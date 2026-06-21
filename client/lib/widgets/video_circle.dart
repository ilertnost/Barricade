import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

/// Telegram-style video circle ("кружок"): hold to record a short, low-size
/// round clip. Rewritten to fix the start/stop race (which produced runaway
/// "huge empty" files), add a duration cap with countdown, and make tap-to-focus
/// best-effort with a visible indicator.
class VideoCircle extends StatefulWidget {
  final void Function(File file, String filename) onSend;

  const VideoCircle({super.key, required this.onSend});

  @override
  State<VideoCircle> createState() => _VideoCircleState();
}

class _VideoCircleState extends State<VideoCircle> {
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  bool _recording = false;
  bool _switching = false;
  bool _flashOn = false;
  int _camIdx = 0;
  int _frontIdx = -1;
  int _backIdx = -1;
  String? _error;

  // Guards against the start/stop race: a quick tap could call stop before
  // start finished, leaving the camera recording forever.
  Future<void>? _startFuture;
  bool _sending = false;

  Timer? _ticker;
  int _elapsedMs = 0;
  Offset? _focusPoint;

  static const double _size = 250;
  static const int _maxMs = 60000; // cap clips at 60s

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      debugPrint('VideoCircle: cameras=${_cameras.length} '
          '${_cameras.map((c) => c.lensDirection.name).toList()}');
      if (_cameras.isEmpty) return _setError('Камеры не найдены');
      // Pick only the FIRST back and FIRST front lens — auxiliary back lenses
      // (macro/depth) often can't be opened as a normal camera.
      _backIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _frontIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _camIdx = _frontIdx >= 0 ? _frontIdx : (_backIdx >= 0 ? _backIdx : 0);
      await _initCamera(_cameras[_camIdx]);
    } catch (e) {
      _setError('$e');
    }
  }

  void _setError(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  Future<void> _initCamera(CameraDescription cam) async {
    _error = null;
    // medium (~480p) keeps circle files small; circles don't need 1080p.
    _ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: true);
    try {
      await _ctrl!.initialize();
      try {
        await _ctrl!.setFocusMode(FocusMode.auto);
      } catch (_) {/* some front cameras don't support focus modes */}
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      _setError('$e');
    }
  }

  bool get _canSwitch => _frontIdx >= 0 && _backIdx >= 0;

  void _switchCam() async {
    if (!_canSwitch || _switching) return;
    setState(() => _switching = true);
    final wasRecording = _recording;
    try {
      // If recording, stop current clip and discard it.
      if (wasRecording) {
        _ticker?.cancel();
        try {
          await _ctrl?.stopVideoRecording();
        } catch (_) {}
      }
      await _ctrl?.dispose();
      _ctrl = null;
      _camIdx = _camIdx == _frontIdx ? _backIdx : _frontIdx;
      await _initCamera(_cameras[_camIdx]);
      // Auto-restart recording after switch.
      if (wasRecording) {
        await _ctrl!.startVideoRecording();
        setState(() {
          _elapsedMs = 0;
        });
        _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (!mounted) return;
          setState(() => _elapsedMs += 100);
          if (_elapsedMs >= _maxMs) _stopAndSend();
        });
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _toggleFlash() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    try {
      setState(() => _flashOn = !_flashOn);
      await _ctrl!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      _setError('$e');
    }
  }

  void _onTapFocus(TapDownDetails d) async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    final p = Offset((d.localPosition.dx / _size).clamp(0, 1), (d.localPosition.dy / _size).clamp(0, 1));
    setState(() => _focusPoint = d.localPosition);
    try {
      await _ctrl!.setExposurePoint(p);
      await _ctrl!.setFocusPoint(p);
    } catch (_) {/* unsupported on this camera — best effort */}
    // Hide the focus ring after a moment.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  Future<void> _startRecording() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _recording) return;
    final start = () async {
      await _ctrl!.startVideoRecording();
    }();
    _startFuture = start;
    try {
      await start;
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsedMs = 0;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => _elapsedMs += 100);
        if (_elapsedMs >= _maxMs) _stopAndSend();
      });
    } catch (e) {
      _setError('$e');
    }
  }

  Future<void> _stopAndSend() async {
    // Wait for a possibly-still-running start before stopping (race guard).
    if (_startFuture != null) {
      try {
        await _startFuture;
      } catch (_) {}
    }
    if (_ctrl == null || !_recording || _sending) return;
    _sending = true;
    _ticker?.cancel();
    final tooShort = _elapsedMs < 600; // ignore accidental taps
    try {
      final xfile = await _ctrl!.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      if (tooShort) {
        _sending = false;
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/circle_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(xfile.path).copy(path);
      widget.onSend(File(path), 'circle.mp4');
    } catch (e) {
      debugPrint('VideoCircle stop error: $e');
      if (mounted) setState(() => _recording = false);
    } finally {
      _sending = false;
    }
  }

  String get _timeLabel {
    final s = _elapsedMs ~/ 1000;
    return '0:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return SizedBox(
        height: 320,
        child: Center(
          child: _error != null
              ? Padding(padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center))
              : const CircularProgressIndicator(),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_canSwitch)
              IconButton(
                icon: const Icon(Icons.flip_camera_android),
                onPressed: _switching ? null : _switchCam,
              ),
            IconButton(
              icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleFlash,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipOval(
          child: GestureDetector(
            onTapDown: _onTapFocus,
            child: SizedBox(
              width: _size,
              height: _size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _switching
                      ? Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()))
                      : CameraPreview(_ctrl!),
                  if (_recording)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                              const SizedBox(width: 6),
                              Text(_timeLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 22,
                      top: _focusPoint!.dy - 22,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.yellowAccent, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Hold-to-record via long press — far more reliable than tapDown/tapUp.
        GestureDetector(
          onLongPressStart: (_) => _startRecording(),
          onLongPressEnd: (_) => _stopAndSend(),
          onLongPressCancel: () => _stopAndSend(),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recording ? Colors.red : cs.primary,
              boxShadow: _recording
                  ? [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 4)]
                  : null,
            ),
            child: Icon(_recording ? Icons.stop : Icons.videocam, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _recording ? 'Отпустите, чтобы отправить' : 'Удерживайте для записи',
          style: TextStyle(color: cs.outline, fontSize: 12),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
