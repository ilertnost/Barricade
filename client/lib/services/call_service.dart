import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';
import 'ws_service.dart';
import 'platform_call_service.dart';

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

  List<CallLogEntry> get callLog => List.unmodifiable(_callLog);

  CallState _state = CallState.idle;
  String? _channelId;
  bool _muted = false;
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
  bool get videoEnabled => _videoEnabled;
  bool get inCall => _state == CallState.connected || _state == CallState.ringing;
  bool get isDm => _isDm;

  IncomingCallInfo? _incomingCall;
  IncomingCallInfo? get incomingCall => _incomingCall;

  RTCSessionDescription? _pendingOfferSdp;
  String? _pendingCallerId;
  String _pendingCallerDisplayName = '';

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  void onWsMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'webrtc') {
      handleIncomingSignal(msg['payload'] as Map<String, dynamic>);
    }
  }

  Future<void> initLocalMedia({bool video = false}) async {
    _videoEnabled = video;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}}
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<void> _setAudioRoute() async {
    if (_isDm) {
      await Helper.setSpeakerphoneOn(false);
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

    await initLocalMedia(video: video);
    await _setAudioRoute();

    for (final peerId in peerIds) {
      await _connectToPeer(peerId, channelId);
    }
  }

  Future<void> answerIncomingCall() async {
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
        pc.addTrack(track, _localStream!);
      }
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _ws.sendWebRTC(_channelId!, 'answer', jsonEncode(answer.toMap()), callerId);
    await _setAudioRoute();
    _updateParticipants();
  }

  Future<void> declineIncomingCall() async {
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
        pc.addTrack(track, _localStream!);
      }
    }

    final sdp = await pc.createOffer();
    await pc.setLocalDescription(sdp);

    _ws.sendWebRTC(channelId, 'offer', jsonEncode(sdp.toMap()), peerId);
  }

  void prepareIncoming(String fromId, String channelId, String callerName) {
    // Called from FCM push before the actual offer arrives via WebSocket.
    // Sets up minimal state so the UI can show the incoming call immediately.
    if (_state != CallState.idle) return;
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
    notifyListeners();
  }

  Future<void> handleIncomingSignal(Map<String, dynamic> payload) async {
    final channelId = payload['channel_id'] as String? ?? _channelId;
    final type = payload['type'] as String?;
    final fromId = payload['from_id'] as String?;
    if (type == null || fromId == null) return;

    switch (type) {
      case 'offer':
        if (_state != CallState.idle) {
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
        PlatformCallService.showIncomingCall(_pendingCallerDisplayName, fromId);
        notifyListeners();

      case 'answer':
        final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
        final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);
        await _connections[fromId]?.setRemoteDescription(sdp);
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
        await _connections[fromId]?.addCandidate(candidate);

      case 'end_call':
        _playDisconnect();
        _resetAll();
    }
  }

  void _resetAll() {
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

  Future<RTCPeerConnection> _createPeerConnection(String peerId, String channelId) async {
    final pc = await createPeerConnection(_iceConfig);

    pc.onIceCandidate = (candidate) {
      _ws.sendWebRTC(channelId, 'candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }, peerId);
    };

    pc.onTrack = (event) {
      _remoteStreams[peerId] = event.streams[0];
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
    await _connections[userId]?.close();
    _connections.remove(userId);
    _remoteStreams.remove(userId);
    if (_connections.isEmpty) {
      _resetAll();
    } else {
      _updateParticipants();
    }
  }

  Future<void> endCall() async {
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
    Helper.setSpeakerphoneOn(true);
    _ringPlayer.play(AssetSource('sounds/ringback.wav'));
  }

  void _playIncomingRing() {
    Helper.setSpeakerphoneOn(true);
    _ringPlayer.play(AssetSource('sounds/incoming.wav'));
  }

  void _playDisconnect() {
    _tonePlayer.play(AssetSource('sounds/disconnect.wav'));
  }

  void _stopRings() {
    _ringPlayer.stop();
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
    _updateParticipants();
  }

  @override
  void dispose() {
    PlatformCallService.stopCallService();
    _ringPlayer.dispose();
    _tonePlayer.dispose();
    _participantsCtrl.close();
    endCall();
    super.dispose();
  }
}
