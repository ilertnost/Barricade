import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';
import 'ws_service.dart';
import 'platform_call_service.dart';
import 'mute_service.dart';

class IncomingCallInfo {
  final String fromId;
  final String channelId;
  final String fromDisplayName;
  IncomingCallInfo({
    required this.fromId,
    required this.channelId,
    required this.fromDisplayName,
  });
}

class CallParticipant {
  final String userId;
  final String displayName;
  final bool hasVideo;
  final bool isMuted;
  final MediaStream? stream;
  final double volume;

  CallParticipant({
    required this.userId,
    required this.displayName,
    this.hasVideo = false,
    this.isMuted = false,
    this.stream,
    this.volume = 1.0,
  });
}

enum CallState { idle, ringing, connected }

class CallLogEntry {
  final String peerId;
  final String peerName;
  final DateTime timestamp;
  final bool isIncoming;
  final bool answered;
  final int durationSec;

  CallLogEntry({
    required this.peerId,
    required this.peerName,
    required this.timestamp,
    required this.isIncoming,
    required this.answered,
    this.durationSec = 0,
  });
}

class CallService extends ChangeNotifier {
  final WsService _ws;
  final AudioPlayer _ringPlayer = AudioPlayer();
  final AudioPlayer _tonePlayer = AudioPlayer();
  final List<CallLogEntry> _callLog = [];

  CallService(this._ws) {
    _ws.addListener(onWsMessage);
    _ringPlayer.setReleaseMode(ReleaseMode.loop);
    _ringPlayer.setVolume(1.0);
  }

  bool _isMuted(String? channelId) {
    if (channelId == null) return false;
    return MuteService.isMuted(channelId);
  }

  List<CallLogEntry> get callLog => List.unmodifiable(_callLog);

  CallState _state = CallState.idle;
  String? _channelId;
  bool _muted = false;
  bool _deafened = false;
  bool _videoEnabled = false;
  bool _isDm = false;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, double> _volumes = {};
  final List<CallParticipant> _participants = [];
  int _callStartTimestamp = 0;
  String? _callPeerId;
  String _callPeerName = '';
  bool _callIsIncoming = false;

  final _participantsCtrl = StreamController<List<CallParticipant>>.broadcast();
  Stream<List<CallParticipant>> get participantStream => _participantsCtrl.stream;
  List<CallParticipant> get participants => List.unmodifiable(_participants);
  CallState get state => _state;
  String? get channelId => _channelId;
  String? get callPeerId => _callPeerId;
  String get callPeerName => _callPeerName;
  bool get muted => _muted;
  bool get deafened => _deafened;
  bool get videoEnabled => _videoEnabled;
  bool get inCall => _state == CallState.connected || _state == CallState.ringing;
  bool get isDm => _isDm;
  bool get isSharingScreen => _isSharingScreen;
  bool get isPeerSharing => _sharingPeerId != null;
  String? get sharingPeerId => _sharingPeerId;
  MediaStream? get screenStream => _screenStream;

  IncomingCallInfo? _incomingCall;
  IncomingCallInfo? get incomingCall => _incomingCall;

  bool _inVoiceRoom = false;
  String? _voiceChannelId;
  final Set<String> _voiceParticipants = {};
  final Map<String, RTCPeerConnection> _voiceConnections = {};
  final Map<String, RTCVideoRenderer> _voiceRenderers = {};
  final _voiceParticipantCtrl = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get voiceParticipantStream => _voiceParticipantCtrl.stream;
  Set<String> get voiceParticipants => Set.unmodifiable(_voiceParticipants);
  bool get inVoiceRoom => _inVoiceRoom;
  String? get voiceChannelId => _voiceChannelId;

  // Screen sharing
  MediaStream? _screenStream;
  bool _isSharingScreen = false;
  String? _sharingPeerId;
  final Map<String, RTCRtpSender> _videoSenders = {};
  final Map<String, MediaStream> _screenShareStreams = {};
  Map<String, MediaStream> get screenShareStreams => Map.unmodifiable(_screenShareStreams);

  RTCSessionDescription? _pendingOfferSdp;
  String? _pendingCallerId;
  String _pendingCallerDisplayName = '';
  Timer? _callTimeout;

  void _startCallTimeout() {
    _callTimeout?.cancel();
    _callTimeout = Timer(const Duration(seconds: 20), () {
      if (!_callIsIncoming && _state == CallState.ringing) {
        // Caller: unanswered for 20s — auto-cancel
        _state = CallState.idle;
        _stopRings();
        PlatformCallService.cancelIncomingNotification();
        PlatformCallService.stopCallService();
        if (_channelId != null && _callPeerId != null) {
          _ws.sendWebRTC(_channelId!, 'end_call', {}, _callPeerId!);
        }
        _logCall(_callPeerId ?? '', _callPeerName, false, false);
        _cleanupConnections();
        notifyListeners();
      } else if (_callIsIncoming && _state == CallState.ringing) {
        // Callee: didn't answer for 20s — auto-decline
        declineIncomingCall();
      }
    });
  }

  void _cancelTimeout() {
    _callTimeout?.cancel();
    _callTimeout = null;
  }

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  void onWsMessage(Map<String, dynamic> msg) {
    final t = msg['type'] as String?;
    debugPrint('VOICE_WS: type="$t" inVoice=$_inVoiceRoom participants=${_voiceParticipants.length}');
    switch (t) {
      case 'webrtc':
        handleIncomingSignal(msg['payload'] as Map<String, dynamic>);
      case 'voice_room_participants':
        _handleVoiceRoomParticipants(msg['payload'] as Map<String, dynamic>);
      case 'voice_room_user_joined':
        _handleVoiceRoomUserJoined(msg['payload'] as Map<String, dynamic>);
      case 'voice_room_user_left':
        _handleVoiceRoomUserLeft(msg['payload'] as Map<String, dynamic>);
    }
  }

  Future<void> initLocalMedia({bool video = false}) async {
    _videoEnabled = video;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'optional': [{'googNoiseSuppression': true}],
      },
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      if (!video) {
        for (final t in _localStream!.getVideoTracks()) {
          t.enabled = false;
        }
      }
    } catch (_) {
      // Fall back to audio only if camera fails
      final audioConstraints = <String, dynamic>{
        'audio': true,
        'video': false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(audioConstraints);
    }
  }

  Future<void> _setAudioRoute() async {
    if (_isDm) {
      await _setSpeakerphone(false);
    }
  }

  static Future<void> _setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (e) {
      debugPrint('setSpeakerphone error: $e');
    }
  }

  Future<void> startCall(String channelId, List<String> peerIds, {bool video = false}) async {
    _channelId = channelId;
    _isDm = peerIds.length == 1;
    _state = CallState.ringing;
    _callPeerId = peerIds.first;
    _callPeerName = peerIds.first;
    _callIsIncoming = false;
    _playRingback();
    PlatformCallService.startCallService();
    notifyListeners();
    _startCallTimeout();

    await initLocalMedia(video: video);
    await _setAudioRoute();

    for (final peerId in peerIds) {
      await _connectToPeer(peerId, channelId);
    }
  }

  Future<void> answerIncomingCall() async {
    _cancelTimeout();
    _stopRings();
    PlatformCallService.cancelIncomingNotification();
    final callerId = _pendingCallerId;
    final sdp = _pendingOfferSdp;
    if (callerId == null || sdp == null || _channelId == null) return;

    _incomingCall = null;
    _pendingOfferSdp = null;
    _pendingCallerId = null;

    _state = CallState.connected;
    _callStartTimestamp = DateTime.now().millisecondsSinceEpoch;
    PlatformCallService.startCallService();
    notifyListeners();

    if (_localStream == null) {
      await initLocalMedia(video: false);
    }

    final pc = await _createPeerConnection(callerId, _channelId!);
    _connections[callerId] = pc;
    await pc.setRemoteDescription(sdp);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        final sender = await pc.addTrack(track, _localStream!);
        if (sender != null && track.kind == 'video') {
          _videoSenders[callerId] = sender;
        }
      }
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _ws.sendWebRTC(_channelId!, 'answer', jsonEncode(answer.toMap()), callerId);
    await _setAudioRoute();
    _updateParticipants();
  }

  Future<void> declineIncomingCall() async {
    _cancelTimeout();
    _stopRings();
    PlatformCallService.cancelIncomingNotification();
    final callerId = _pendingCallerId;
    final chId = _channelId;
    if (callerId != null) {
      _logCall(callerId, _pendingCallerDisplayName, true, false);
    }
    _incomingCall = null;
    _pendingOfferSdp = null;
    _pendingCallerId = null;
    _channelId = null;
    _state = CallState.idle;
    PlatformCallService.stopCallService();
    notifyListeners();
    if (callerId != null && chId != null) {
      _ws.sendWebRTC(chId, 'end_call', {}, callerId);
    }
  }

  Future<void> _connectToPeer(String peerId, String channelId) async {
    if (_connections.containsKey(peerId)) return;

    final pc = await _createPeerConnection(peerId, channelId);
    _connections[peerId] = pc;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        final sender = await pc.addTrack(track, _localStream!);
        if (sender != null && track.kind == 'video') {
          _videoSenders[peerId] = sender;
        }
      }
    }

    final sdp = await pc.createOffer();
    await pc.setLocalDescription(sdp);

    _ws.sendWebRTC(channelId, 'offer', jsonEncode(sdp.toMap()), peerId);
  }

  // ── Screen sharing ──
  static String? _savedScreenId;

  /// Call [desktopCapturer.getSources] once per session to populate the
  /// native source cache. On Wayland this shows an xdg-desktop-portal dialog.
  /// After this, [startScreenShare] can capture without a second dialog.
  static Future<void> pickScreenSource() async {
    if (_savedScreenId != null || Platform.isAndroid) return;
    debugPrint('PICK_SOURCE: getSources...');
    try {
      final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
      _savedScreenId = sources.firstOrNull?.id;
      debugPrint('PICK_SOURCE: saved id="${_savedScreenId}"');
    } catch (e) {
      debugPrint('PICK_SOURCE: error: $e');
    }
  }

  Future<void> startScreenShare() async {
    if (_isSharingScreen) return;

    try {
      final video = <String, dynamic>{
        'frameRate': 60.0,
        'width': {'ideal': 1920},
        'height': {'ideal': 1080},
      };
      if (_savedScreenId != null && !Platform.isAndroid) {
        video['deviceId'] = {'exact': _savedScreenId};
      }
      // audio:true captures system/loopback audio so the share has sound.
      // Native side falls back to video-only if loopback isn't available.
      final constraints = <String, dynamic>{'video': video, 'audio': true};
      debugPrint('START_SHARE: constraints=$constraints android=$Platform.isAndroid');
      _screenStream = await navigator.mediaDevices.getDisplayMedia(constraints);
      debugPrint('START_SHARE: OK, tracks=${_screenStream!.getVideoTracks().length}');
    } catch (e, st) {
      debugPrint('SCREEN_SHARE_ERROR: $e\n$st');
      return;
    }

    _isSharingScreen = true;

    final screenTrack = _screenStream!.getVideoTracks().firstOrNull;
    if (screenTrack == null) {
      _isSharingScreen = false;
      _screenStream?.dispose();
      _screenStream = null;
      return;
    }

    // Replace existing video senders (regular calls).
    for (final entry in _connections.entries) {
      final sender = _videoSenders[entry.key];
      if (sender != null) {
        try {
          await sender.replaceTrack(screenTrack);
        } catch (e) {
          debugPrint('replaceTrack error for ${entry.key}: $e');
        }
      }
    }

    // Add screen video track to voice room peers and renegotiate.
    for (final entry in _voiceConnections.entries) {
      final sender = _videoSenders[entry.key];
      if (sender == null) {
        try {
          final videoSender = await entry.value.addTrack(screenTrack, _screenStream!);
          _videoSenders[entry.key] = videoSender;
          final sdp = await entry.value.createOffer();
          await entry.value.setLocalDescription(sdp);
          if (_voiceChannelId != null) {
            _ws.sendWebRTC(_voiceChannelId!, 'offer', jsonEncode(sdp.toMap()), entry.key);
            debugPrint('START_SHARE: renegotiate with ${entry.key}');
          }
        } catch (e) {
          debugPrint('addTrack for ${entry.key}: $e');
        }
      } else {
        try {
          await sender.replaceTrack(screenTrack);
        } catch (e) {
          debugPrint('replaceTrack voice for ${entry.key}: $e');
        }
      }
    }

    // Notify all peers (both DM call and voice room).
    final peers = {..._connections.keys, ..._voiceConnections.keys};
    final chId = _channelId ?? _voiceChannelId;
    for (final peerId in peers) {
      if (chId != null) {
        _ws.sendWebRTC(chId, 'screen_share_change', {'sharing': true}, peerId);
      }
    }

    _updateParticipants();
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    if (!_isSharingScreen) return;

    // Restore camera video track for regular calls.
    final cameraTrack = _localStream?.getVideoTracks().firstOrNull;
    if (cameraTrack != null) {
      for (final entry in _connections.entries) {
        final sender = _videoSenders[entry.key];
        if (sender != null) {
          try {
            await sender.replaceTrack(cameraTrack);
          } catch (e) {
            debugPrint('replaceTrack restore error for ${entry.key}: $e');
          }
        }
      }
    }

    // Remove screen video track from voice room peers and renegotiate.
    for (final entry in _voiceConnections.entries) {
      final sender = _videoSenders[entry.key];
      if (sender != null) {
        try {
          await entry.value.removeTrack(sender);
          _videoSenders.remove(entry.key);
          final sdp = await entry.value.createOffer();
          await entry.value.setLocalDescription(sdp);
          if (_voiceChannelId != null) {
            _ws.sendWebRTC(_voiceChannelId!, 'offer', jsonEncode(sdp.toMap()), entry.key);
            debugPrint('STOP_SHARE: renegotiate with ${entry.key}');
          }
        } catch (e) {
          debugPrint('removeTrack for ${entry.key}: $e');
        }
      }
    }

    // Stop and dispose screen stream.
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;
    _isSharingScreen = false;

    // Notify all peers.
    final peers = {..._connections.keys, ..._voiceConnections.keys};
    final chId = _channelId ?? _voiceChannelId;
    for (final peerId in peers) {
      if (chId != null) {
        _ws.sendWebRTC(chId, 'screen_share_change', {'sharing': false}, peerId);
      }
    }

    _updateParticipants();
    notifyListeners();
  }

  Future<void> toggleScreenShare() async {
    if (_isSharingScreen) {
      await stopScreenShare();
    } else {
      await startScreenShare();
    }
  }

  Future<void> joinVoiceRoom(String channelId) async {
    if (_inVoiceRoom) return;
    debugPrint('VOICE_JOIN: channel=$channelId');
    _voiceChannelId = channelId;
    _inVoiceRoom = true;
    if (_localStream == null) {
      try {
        await initLocalMedia(video: false);
      } catch (e) {
        debugPrint('joinVoiceRoom initLocalMedia error: $e');
      }
    }
    await _setSpeakerphone(true);
    _ws.voiceRoomJoin(channelId);
    notifyListeners();
  }

  Future<void> leaveVoiceRoom() async {
    if (!_inVoiceRoom) return;
    debugPrint('VOICE_LEAVE: channel=$_voiceChannelId');
    if (_isSharingScreen) await stopScreenShare();
    if (_voiceChannelId != null) {
      _ws.voiceRoomLeave(_voiceChannelId!);
    }
    _cleanupVoiceRoom();
    notifyListeners();
  }

  void _cleanupVoiceRoom() {
    for (final e in _voiceConnections.entries) {
      e.value.close();
      _videoSenders.remove(e.key);
    }
    _voiceConnections.clear();
    for (final e in _voiceRenderers.entries) {
      e.value.dispose();
    }
    _voiceRenderers.clear();
    for (final uid in _voiceParticipants) {
      _remoteStreams.remove(uid);
    }
    _voiceParticipants.clear();
    _volumes.clear();
    _screenShareStreams.clear();
    _voiceChannelId = null;
    _inVoiceRoom = false;
    if (!inCall) {
      _localStream?.dispose();
      _localStream = null;
    }
  }

  void _handleVoiceRoomParticipants(Map<String, dynamic> payload) {
    final participants = List<String>.from(payload['participants'] as List? ?? []);
    debugPrint('VOICE_PARTICIPANTS: got ${participants.length} participants: $participants');
    _voiceParticipants.addAll(participants);
    _voiceParticipantCtrl.add(Set.from(_voiceParticipants));
    notifyListeners();
    for (final peerId in participants) {
      debugPrint('VOICE_PARTICIPANTS: connecting to $peerId');
      _connectVoicePeer(peerId).catchError((e) {
        debugPrint('_connectVoicePeer error for $peerId: $e');
      });
    }
  }

  void _handleVoiceRoomUserJoined(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    debugPrint('VOICE_USER_JOINED: userId=$userId inVoice=$_inVoiceRoom');
    if (userId == null || !_inVoiceRoom) return;
    _voiceParticipants.add(userId);
    debugPrint('VOICE_USER_JOINED: participants now=${_voiceParticipants.length}');
    _voiceParticipantCtrl.add(Set.from(_voiceParticipants));
    // If currently sharing screen, notify new joiner.
    if (_isSharingScreen && _voiceChannelId != null) {
      _ws.sendWebRTC(_voiceChannelId!, 'screen_share_change', {'sharing': true}, userId);
    }
    notifyListeners();
    // Don't create an offer here — the joiner creates offers to all
    // existing participants via _handleVoiceRoomParticipants.
    // We wait for the incoming offer from the new joiner.
  }

  void _handleVoiceRoomUserLeft(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    debugPrint('VOICE_USER_LEFT: userId=$userId');
    if (userId == null) return;
    _voiceParticipants.remove(userId);
    debugPrint('VOICE_USER_LEFT: participants now=${_voiceParticipants.length}');
    _voiceParticipantCtrl.add(Set.from(_voiceParticipants));
    if (_voiceConnections.containsKey(userId)) {
      _voiceConnections[userId]!.close();
      _voiceConnections.remove(userId);
    }
    _videoSenders.remove(userId);
    if (_voiceRenderers.containsKey(userId)) {
      _voiceRenderers[userId]!.dispose();
      _voiceRenderers.remove(userId);
    }
    notifyListeners();
  }

  Future<void> _ensureVoiceRenderer(String peerId, MediaStream stream) async {
    if (_voiceRenderers.containsKey(peerId)) return;
    // On Linux audio plays natively without RTCVideoRenderer.
    if (!Platform.isAndroid) return;
    final r = RTCVideoRenderer();
    _voiceRenderers[peerId] = r;
    await r.initialize();
    r.srcObject = stream;
  }

  Future<void> _connectVoicePeer(String peerId) async {
    debugPrint('VOICE_CONNECT: peer=$peerId hasExisting=${_voiceConnections.containsKey(peerId)} channel=$_voiceChannelId');
    if (_voiceConnections.containsKey(peerId)) return;
    if (_voiceChannelId == null) return;
    if (_localStream == null) {
      debugPrint('VOICE_CONNECT: initLocalMedia for $peerId');
      await initLocalMedia(video: false);
    }

    final pc = await _createPeerConnection(
      peerId,
      _voiceChannelId!,
      onRemoteStream: (stream) => _ensureVoiceRenderer(peerId, stream),
    );
    _voiceConnections[peerId] = pc;
    debugPrint('VOICE_CONNECT: PC created for $peerId');

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        final sender = await pc.addTrack(track, _localStream!);
        if (sender != null && track.kind == 'video') {
          _videoSenders[peerId] = sender;
        }
      }
    }

    final sdp = await pc.createOffer();
    await pc.setLocalDescription(sdp);
    debugPrint('VOICE_CONNECT: sending offer to $peerId');
    _ws.sendWebRTC(_voiceChannelId!, 'offer', jsonEncode(sdp.toMap()), peerId);
  }

  void prepareIncoming(String fromId, String channelId, String callerName) {
    // Called from FCM push before the actual offer arrives via WebSocket.
    // Sets up minimal state so the UI can show the incoming call immediately.
    if (_state != CallState.idle) return;
    if (_isMuted(channelId)) return;
    _channelId = channelId;
    _pendingCallerId = fromId;
    _pendingCallerDisplayName = callerName;
    _callPeerId = fromId;
    _callPeerName = callerName;
    _callIsIncoming = true;
    _isDm = true;
    _state = CallState.ringing;
    _incomingCall = IncomingCallInfo(
      fromId: fromId,
      channelId: channelId,
      fromDisplayName: callerName,
    );
    _playIncomingRing();
    _startCallTimeout();
    notifyListeners();
  }

  Future<void> handleIncomingSignal(Map<String, dynamic> payload) async {
    final channelId = payload['channel_id'] as String? ?? _channelId;
    final type = payload['type'] as String?;
    final fromId = payload['from_id'] as String?;
    if (type == null || fromId == null) return;

    switch (type) {
      case 'offer':
        debugPrint('VOICE_OFFER: inVoice=$_inVoiceRoom channel=$_voiceChannelId offerChannel=$channelId from=$fromId');
        if (_inVoiceRoom && _voiceChannelId == channelId) {
          debugPrint('VOICE_OFFER: accepting voice room offer from $fromId');
          try {
            final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
            final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);

            // Check for re-negotiation on existing connection (e.g. screen share).
            final existingPc = _voiceConnections[fromId];
            if (existingPc != null) {
              debugPrint('VOICE_OFFER: renegotiation for existing PC $fromId');
              await existingPc.setRemoteDescription(sdp);
              final answer = await existingPc.createAnswer();
              await existingPc.setLocalDescription(answer);
              _ws.sendWebRTC(_voiceChannelId!, 'answer', jsonEncode(answer.toMap()), fromId);
              return;
            }

            if (_localStream == null) {
              try {
                await initLocalMedia(video: false);
              } catch (e) {
                debugPrint('voice room offer initLocalMedia error: $e');
              }
            }
            final pc = await _createPeerConnection(
              fromId,
              _voiceChannelId!,
              onRemoteStream: (stream) => _ensureVoiceRenderer(fromId, stream),
            );
            _voiceConnections[fromId] = pc;
            debugPrint('VOICE_OFFER: PC created for $fromId');
            await pc.setRemoteDescription(sdp);
        if (_localStream != null) {
          for (final track in _localStream!.getTracks()) {
            final sender = await pc.addTrack(track, _localStream!);
            if (sender != null && track.kind == 'video') {
              _videoSenders[fromId] = sender;
            }
          }
        }
        // If currently sharing screen, add video track for new joiner.
        if (_isSharingScreen && _screenStream != null) {
          final screenTrack = _screenStream!.getVideoTracks().firstOrNull;
          if (screenTrack != null) {
            try {
              final sender = await pc.addTrack(screenTrack, _screenStream!);
              _videoSenders[fromId] = sender;
              debugPrint('VOICE_OFFER: added screen track for new joiner $fromId');
            } catch (e) {
              debugPrint('VOICE_OFFER: addTrack screen for $fromId: $e');
            }
          }
        }
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            debugPrint('VOICE_OFFER: sending answer to $fromId');
            _ws.sendWebRTC(_voiceChannelId!, 'answer', jsonEncode(answer.toMap()), fromId);
          } catch (e) {
            debugPrint('voice room offer handling error: $e');
          }
          return;
        }
        // If already ringing from FCM prepareIncoming for the same caller,
        // just update the SDP and continue.
        if (_state == CallState.ringing && _pendingCallerId == fromId) {
          final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
          _pendingOfferSdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);
          return;
        }
        if (_state != CallState.idle) {
          if (channelId != null) _ws.sendWebRTC(channelId, 'end_call', {}, fromId);
          return;
        }

        if (_isMuted(channelId)) {
          if (channelId != null) _ws.sendWebRTC(channelId, 'end_call', {}, fromId);
          return;
        }

        final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
        final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);

        _channelId = channelId;
        _isDm = true;
        _pendingOfferSdp = sdp;
        _pendingCallerId = fromId;

        _pendingCallerDisplayName = fromId;
        try {
          final user = await ApiService.getUser(fromId);
          _pendingCallerDisplayName = user.displayName.isNotEmpty ? user.displayName : user.username;
        } catch (_) {}

        _incomingCall = IncomingCallInfo(
          fromId: fromId,
          channelId: channelId!,
          fromDisplayName: _pendingCallerDisplayName,
        );
        _state = CallState.ringing;
        _callPeerId = fromId;
        _callPeerName = _pendingCallerDisplayName;
        _callIsIncoming = true;
        _playIncomingRing();
        PlatformCallService.showIncomingCall(_pendingCallerDisplayName, fromId, channelId: channelId ?? '');
        _startCallTimeout();
        notifyListeners();

      case 'answer':
        final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
        final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);
        final pc = _connections[fromId] ?? _voiceConnections[fromId];
        debugPrint('VOICE_ANSWER: from=$fromId pc=${pc != null} inVoice=$_inVoiceRoom');
        await pc?.setRemoteDescription(sdp);
        if (_state == CallState.ringing) {
          _state = CallState.connected;
          _callStartTimestamp = DateTime.now().millisecondsSinceEpoch;
          _stopRings();
          notifyListeners();
        }

      case 'candidate':
        final cand = (payload['data'] as Map<String, dynamic>?) ?? {};
        final candidate = RTCIceCandidate(
          cand['candidate'] as String? ?? '',
          cand['sdpMid'] as String? ?? '',
          cand['sdpMLineIndex'] as int? ?? 0,
        );
        final pc = _connections[fromId] ?? _voiceConnections[fromId];
        debugPrint('VOICE_CANDIDATE: from=$fromId pc=${pc != null} inVoice=$_inVoiceRoom');
        await pc?.addCandidate(candidate);

      case 'screen_share_change':
        final sharing = (payload['data'] as Map<String, dynamic>?)?['sharing'] as bool? ?? false;
        if (sharing) {
          _sharingPeerId = fromId;
        } else {
          _sharingPeerId = null;
        }
        notifyListeners();

      case 'end_call':
        _playDisconnect();
        _resetAll();
    }
  }

  void _resetAll() {
    _cancelTimeout();
    PlatformCallService.cancelIncomingNotification();
    PlatformCallService.stopCallService();
    if (_callPeerId != null && _callStartTimestamp > 0) {
      _logCall(_callPeerId!, _callPeerName, _callIsIncoming, true);
    } else if (_callPeerId != null) {
      _logCall(_callPeerId!, _callPeerName, _callIsIncoming, false);
    }
    _callPeerId = null;
    _callPeerName = '';
    _callIsIncoming = false;
    _callStartTimestamp = 0;
    _state = CallState.idle;
    _channelId = null;
    _incomingCall = null;
    _pendingOfferSdp = null;
    _pendingCallerId = null;
    _pendingCallerDisplayName = '';
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;
    _isSharingScreen = false;
    _sharingPeerId = null;
    _videoSenders.clear();
    _screenShareStreams.clear();
    for (final e in _connections.entries) {
      e.value.close();
    }
    _connections.clear();
    _remoteStreams.clear();
    _volumes.clear();
    _localStream?.dispose();
    _localStream = null;
    _participants.clear();
    _participantsCtrl.add([]);
    notifyListeners();
  }

  void _cleanupConnections() {
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;
    _isSharingScreen = false;
    _sharingPeerId = null;
    _videoSenders.clear();
    _screenShareStreams.clear();
    for (final e in _connections.entries) {
      e.value.close();
    }
    _connections.clear();
    _remoteStreams.clear();
    _volumes.clear();
    _localStream?.dispose();
    _localStream = null;
    _participants.clear();
    _participantsCtrl.add([]);
  }

  Future<RTCPeerConnection> _createPeerConnection(
    String peerId,
    String channelId, {
    void Function(MediaStream stream)? onRemoteStream,
  }) async {
    final pc = await createPeerConnection(_iceConfig);

    pc.onIceCandidate = (candidate) {
      _ws.sendWebRTC(channelId, 'candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }, peerId);
    };

    pc.onTrack = (event) {
      final stream = event.streams[0];
      if (event.track.kind == 'video' && _voiceConnections.containsKey(peerId)) {
        _screenShareStreams[peerId] = stream;
      } else {
        _remoteStreams[peerId] = stream;
        if (onRemoteStream != null) {
          onRemoteStream(stream);
        }
      }
      _updateParticipants();
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanupPeer(peerId);
      }
    };

    return pc;
  }

  void _updateParticipants() {
    final list = <CallParticipant>[];
    list.add(CallParticipant(
      userId: ApiService.currentUserId ?? '',
      displayName: 'Me',
      hasVideo: _videoEnabled,
      isMuted: _muted,
      stream: _localStream,
    ));
    for (final e in _connections.entries) {
      list.add(CallParticipant(
        userId: e.key,
        displayName: e.key,
        hasVideo: _remoteStreams.containsKey(e.key),
        stream: _remoteStreams[e.key],
        volume: _volumes[e.key] ?? 1.0,
      ));
    }
    _participants
      ..clear()
      ..addAll(list);
    if (!_participantsCtrl.isClosed) _participantsCtrl.add(List.from(list));
    notifyListeners();
  }

  Future<void> _cleanupPeer(String userId) async {
    if (_connections.containsKey(userId)) {
      await _connections[userId]?.close();
      _connections.remove(userId);
      _remoteStreams.remove(userId);
      _videoSenders.remove(userId);
      if (_connections.isEmpty) {
        _resetAll();
      }
      _updateParticipants();
    } else if (_voiceConnections.containsKey(userId)) {
      await _voiceConnections[userId]?.close();
      _voiceConnections.remove(userId);
      _videoSenders.remove(userId);
      if (_voiceRenderers.containsKey(userId)) {
        _voiceRenderers[userId]!.dispose();
        _voiceRenderers.remove(userId);
      }
      // Do NOT remove from _voiceParticipants here — that's handled by
      // _handleVoiceRoomUserLeft when the user explicitly leaves the room.
      // Removing on ICE disconnect makes participants flicker out of the UI.
    }
  }

  Future<void> endCall() async {
    if (_isSharingScreen) {
      _screenStream?.getTracks().forEach((t) => t.stop());
      _screenStream?.dispose();
      _screenStream = null;
      _isSharingScreen = false;
      _sharingPeerId = null;
    }
    if (_channelId != null) {
      for (final e in _connections.entries) {
        _ws.sendWebRTC(_channelId!, 'end_call', {}, e.key);
        await e.value.close();
      }
    }
    _playDisconnect();
    _resetAll();
  }

  void _playRingback() {
    _setSpeakerphone(true);
    _ringPlayer.play(AssetSource('sounds/ringback.wav'));
  }

  void _playIncomingRing() {
    _setSpeakerphone(true);
    PlatformCallService.playRingtone();
  }

  void _playDisconnect() {
    _tonePlayer.play(AssetSource('sounds/disconnect.wav'));
  }

  void _stopRings() {
    _ringPlayer.stop();
    PlatformCallService.stopRingtone();
  }

  void _logCall(String peerId, String peerName, bool isIncoming, bool answered) {
    final durationSec = _callStartTimestamp > 0
        ? (DateTime.now().millisecondsSinceEpoch - _callStartTimestamp) ~/ 1000
        : 0;
    _callLog.insert(0, CallLogEntry(
      peerId: peerId,
      peerName: peerName,
      timestamp: DateTime.now(),
      isIncoming: isIncoming,
      answered: answered,
      durationSec: durationSec,
    ));
    _callStartTimestamp = 0;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_muted);
    _updateParticipants();
  }

  Future<void> toggleDeafen() async {
    _deafened = !_deafened;
    if (_deafened) {
      _muted = true;
      _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
      await _setSpeakerphone(false);
    } else {
      _muted = false;
      _localStream?.getAudioTracks().forEach((t) => t.enabled = true);
    }
    _updateParticipants();
  }

  Future<void> toggleVideo() async {
    _videoEnabled = !_videoEnabled;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _videoEnabled);
    _updateParticipants();
  }

  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) await Helper.switchCamera(videoTrack);
  }

  void setVolume(String userId, double volume) {
    _volumes[userId] = volume;
    _applyVolume(userId, volume);
    _updateParticipants();
  }

  Future<void> _applyVolume(String userId, double volume) async {
    if (_voiceRenderers.containsKey(userId)) {
      try {
        await _voiceRenderers[userId]!.setVolume(volume);
      } catch (e) {
        debugPrint('renderer setVolume error: $e');
      }
      return;
    }
    final stream = _remoteStreams[userId];
    if (stream == null) return;
    final track = stream.getAudioTracks().firstOrNull;
    if (track == null) return;
    try {
      await Helper.setVolume(volume, track);
    } catch (e) {
      debugPrint('Helper.setVolume error: $e');
    }
  }

  @override
  void dispose() {
    PlatformCallService.stopCallService();
    _ringPlayer.dispose();
    _tonePlayer.dispose();
    _participantsCtrl.close();
    _voiceParticipantCtrl.close();
    _screenStream?.dispose();
    _screenStream = null;
    if (_inVoiceRoom) leaveVoiceRoom();
    endCall();
    super.dispose();
  }
}
