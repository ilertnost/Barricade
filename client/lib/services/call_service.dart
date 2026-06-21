import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_service.dart';
import 'ws_service.dart';

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

enum CallState { idle, ringing, connected, ended }

class CallService extends ChangeNotifier {
  final WsService _ws;

  CallService(this._ws) {
    _ws.addListener(onWsMessage);
  }

  CallState _state = CallState.idle;
  String? _channelId;
  bool _muted = false;
  bool _videoEnabled = true;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _connections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, double> _volumes = {};
  final List<CallParticipant> _participants = [];

  final _participantsCtrl = StreamController<List<CallParticipant>>.broadcast();
  Stream<List<CallParticipant>> get participantStream => _participantsCtrl.stream;
  List<CallParticipant> get participants => List.unmodifiable(_participants);
  CallState get state => _state;
  String? get channelId => _channelId;
  bool get muted => _muted;
  bool get videoEnabled => _videoEnabled;
  bool get inCall => _state == CallState.connected || _state == CallState.ringing;

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

  Future<void> initLocalMedia({bool video = true}) async {
    _videoEnabled = video;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}}
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<void> startCall(String channelId, List<String> peerIds, {bool video = true}) async {
    _channelId = channelId;
    _state = CallState.ringing;
    notifyListeners();

    await initLocalMedia(video: video);

    for (final peerId in peerIds) {
      await _connectToPeer(peerId, channelId);
    }

    _state = CallState.connected;
    notifyListeners();
  }

  Future<void> answerCall(String channelId, String callerId, {bool video = true}) async {
    _channelId = channelId;
    _state = CallState.connected;
    notifyListeners();

    await initLocalMedia(video: video);
    // The caller will send an offer via handleIncomingSignal
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

  Future<void> handleIncomingSignal(Map<String, dynamic> payload) async {
    final channelId = payload['channel_id'] as String? ?? _channelId;
    final type = payload['type'] as String?;
    final fromId = payload['from_id'] as String?;
    if (type == null || fromId == null) return;

    switch (type) {
      case 'offer':
        final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
        final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);

        if (_localStream == null) {
          await initLocalMedia(video: true);
        }

        final pc = await _createPeerConnection(fromId, channelId!);
        _connections[fromId] = pc;
        await pc.setRemoteDescription(sdp);

        if (_localStream != null) {
          for (final track in _localStream!.getTracks()) {
            pc.addTrack(track, _localStream!);
          }
        }

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        _ws.sendWebRTC(channelId, 'answer', jsonEncode(answer.toMap()), fromId);
        _updateParticipants();

      case 'answer':
        final sdpMap = jsonDecode(payload['data'] as String) as Map<String, dynamic>;
        final sdp = RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String);
        await _connections[fromId]?.setRemoteDescription(sdp);

      case 'candidate':
        final cand = (payload['data'] as Map<String, dynamic>?) ?? {};
        final candidate = RTCIceCandidate(
          cand['candidate'] as String? ?? '',
          cand['sdpMid'] as String? ?? '',
          cand['sdpMLineIndex'] as int? ?? 0,
        );
        await _connections[fromId]?.addCandidate(candidate);

      case 'end_call':
        await _cleanupPeer(fromId);
    }
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
    _updateParticipants();
  }

  Future<void> endCall() async {
    if (_channelId != null) {
      for (final e in _connections.entries) {
        _ws.sendWebRTC(_channelId!, 'end_call', {}, e.key);
        await e.value.close();
      }
    }
    _connections.clear();
    _remoteStreams.clear();
    await _localStream?.dispose();
    _localStream = null;
    _volumes.clear();
    _participants.clear();
    if (!_participantsCtrl.isClosed) _participantsCtrl.add([]);
    _state = CallState.ended;
    _channelId = null;
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
    _participantsCtrl.close();
    endCall();
    super.dispose();
  }
}
