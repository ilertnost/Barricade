import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String channelId;
  final List<String> peerIds;
  final bool video;

  const CallScreen({
    super.key,
    required this.channelId,
    required this.peerIds,
    this.video = true,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<List<CallParticipant>>? _sub;
  bool _fullscreen = false;
  final Map<String, RTCVideoRenderer> _renderers = {};
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final call = context.read<CallService>();
    _sub = call.participantStream.listen((_) {
      if (mounted) setState(() {});
    });
    call.addListener(_onCallStateChanged);
    if (call.state == CallState.ringing) {
      call.answerIncomingCall();
    } else if (call.state != CallState.connected) {
      call.startCall(widget.channelId, widget.peerIds, video: widget.video);
    }
  }

  @override
  void dispose() {
    context.read<CallService>().removeListener(_onCallStateChanged);
    _sub?.cancel();
    _focusNode.dispose();
    for (final r in _renderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final call = context.read<CallService>();
    if (call.state == CallState.idle) {
      call.removeListener(_onCallStateChanged);
      Navigator.of(context).pop();
    }
  }

  RTCVideoRenderer _rendererFor(String userId, MediaStream? stream) {
    if (_renderers.containsKey(userId)) return _renderers[userId]!;
    final r = RTCVideoRenderer();
    _renderers[userId] = r;
    r.initialize().then((_) {
      r.srcObject = stream;
      if (mounted) setState(() {});
    });
    return r;
  }

  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  void _exitFullscreen() {
    if (_fullscreen) setState(() => _fullscreen = false);
  }

  Future<void> _onScreenShareTap(CallService call) async {
    if (call.isSharingScreen) {
      await call.stopScreenShare();
      if (mounted) setState(() {});
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Демонстрация экрана'),
        content: const Text('Начать демонстрацию экрана?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Начать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await call.startScreenShare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
      return;
    }
    if (mounted && !call.isSharingScreen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось начать демонстрацию экрана. Возможно, система не поддерживает захват экрана.')),
      );
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _exitFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();

    Widget body;
    if (call.isPeerSharing || call.isSharingScreen || _fullscreen) {
      body = _buildScreenShareView(call);
    } else {
      body = Column(
        children: [
          Expanded(child: _buildVideoGrid(call)),
          _buildControls(call),
        ],
      );
    }

    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen || call.isPeerSharing
          ? null
          : AppBar(
              backgroundColor: Colors.black87,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => call.endCall(),
              ),
              title: Text(
                widget.peerIds.length > 1
                    ? '${Strings.t("channel.group")} (${call.participants.length - 1})'
                    : call.participants.length > 1
                        ? call.participants[1].displayName
                        : Strings.t("common.calling"),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: _toggleFullscreen,
                ),
                IconButton(
                  icon: const Icon(Icons.picture_in_picture, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
      body: SafeArea(child: body),
    );

    if (!Platform.isAndroid) {
      return KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildScreenShareView(CallService call) {
    // Determine which stream to show:
    // - If local user is sharing, show the screen capture stream.
    // - If a remote peer is sharing, show that peer's video (replaceTrack).
    final isLocalSharing = call.isSharingScreen;
    final remoteSharerId = call.sharingPeerId;

    MediaStream? videoStream;
    String sharerName;
    if (isLocalSharing) {
      videoStream = call.screenStream;
      sharerName = 'Вы';
    } else if (remoteSharerId != null) {
      final participant = call.participants.where((p) => p.userId == remoteSharerId).firstOrNull;
      sharerName = participant?.displayName ?? remoteSharerId;
      videoStream = participant?.stream;
    } else {
      sharerName = '';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Main video
        if (videoStream != null)
          RTCVideoView(
            _rendererFor('_screen_share', videoStream),
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          )
        else
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        // Top banner
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black54,
            child: Row(
              children: [
                const Icon(Icons.screen_share, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLocalSharing
                        ? 'Демонстрация экрана'
                        : '$sharerName демонстрирует экран',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                if (!_fullscreen)
                  IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                    onPressed: _toggleFullscreen,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        // Bottom controls
        if (!_fullscreen)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildScreenShareControls(call, isLocalSharing),
          ),
        // Close button (Android — exit fullscreen)
        if (!Platform.isAndroid && _fullscreen)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: _exitFullscreen,
            ),
          ),
      ],
    );
  }

  Widget _buildScreenShareControls(CallService call, bool isLocalSharing) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.only(bottom: 32, top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(
            icon: call.muted ? Icons.mic_off : Icons.mic,
            color: call.muted ? Colors.red : Colors.white,
            onTap: call.toggleMute,
          ),
          if (isLocalSharing)
            _CtrlBtn(
              icon: Icons.stop_screen_share,
              color: Colors.red,
              onTap: () => call.toggleScreenShare(),
            ),
          _CtrlBtn(
            icon: Icons.call_end,
            color: Colors.red,
            onTap: () => call.endCall(),
          ),
          _CtrlBtn(
            icon: Icons.fullscreen_exit,
            color: Colors.white,
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(CallService call) {
    final tiles = <Widget>[];
    for (final p in call.participants) {
      Widget tile;
      if (p.stream != null) {
        final renderer = _rendererFor(p.userId, p.stream);
        tile = RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
      } else {
        tile = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: _fullscreen ? 40 : 24,
                backgroundColor: Colors.white24,
                child: Text(
                  p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: _fullscreen ? 36 : 20, color: Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(p.displayName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        );
      }
      tiles.add(Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(_fullscreen ? 0 : 8),
        ),
        child: tile is RTCVideoView ? ClipRRect(
          borderRadius: BorderRadius.circular(_fullscreen ? 0 : 8),
          child: tile,
        ) : tile,
      ));
    }
    if (tiles.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final cols = tiles.length <= 2 ? 1 : 2;
        final rows = (tiles.length + cols - 1) ~/ cols;
        return GridView.count(
          crossAxisCount: cols,
          childAspectRatio: constraints.maxWidth / (constraints.maxHeight / rows),
          children: tiles,
        );
      },
    );
  }

  Widget _buildControls(CallService call) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.only(bottom: 32, top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(
            icon: call.muted ? Icons.mic_off : Icons.mic,
            color: call.muted ? Colors.red : Colors.white,
            onTap: call.toggleMute,
          ),
          _CtrlBtn(
            icon: call.videoEnabled ? Icons.videocam : Icons.videocam_off,
            color: call.videoEnabled ? Colors.white : Colors.red,
            onTap: call.toggleVideo,
          ),
          _CtrlBtn(
            icon: call.isSharingScreen ? Icons.stop_screen_share : Icons.screen_share,
            color: call.isSharingScreen ? Colors.green : Colors.white,
            onTap: () => _onScreenShareTap(call),
          ),
          _CtrlBtn(
            icon: Icons.call_end,
            color: Colors.red,
            onTap: () => call.endCall(),
          ),
          _CtrlBtn(
            icon: Icons.flip_camera_android,
            color: Colors.white,
            onTap: call.switchCamera,
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: color.withOpacity(0.2),
      child: IconButton(icon: Icon(icon, color: color), onPressed: onTap),
    );
  }
}
