import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/strings.dart';

class VoiceRecorder extends StatefulWidget {
  final void Function(File file, String filename, int durationMs) onSend;

  const VoiceRecorder({super.key, required this.onSend});

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _playing = false;
  String? _audioPath;
  int _durationMs = 0;
  late AnimationController _animCtrl;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() => _recording = true);
      _animCtrl.repeat(reverse: true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _animCtrl.stop();
    if (path != null) {
      await _player.play(DeviceFileSource(path));
      final dur = await _player.getDuration();
      await _player.stop();
      setState(() {
        _recording = false;
        _audioPath = path;
        _durationMs = dur?.inMilliseconds ?? 0;
      });
    } else {
      setState(() => _recording = false);
    }
  }

  void _send() {
    if (_audioPath != null) {
      final file = File(_audioPath!);
      widget.onSend(file, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a', _durationMs);
      setState(() {
        _audioPath = null;
        _durationMs = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recording)
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, child) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1 + _animCtrl.value * 0.3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.red, size: 12),
                    const SizedBox(width: 8),
                    Text('Recording...', style: TextStyle(color: Colors.red[300])),
                  ],
                ),
              ),
            )
          else if (_audioPath != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                  onPressed: () async {
                    if (_playing) {
                      await _player.stop();
                      setState(() => _playing = false);
                    } else {
                      await _player.play(DeviceFileSource(_audioPath!));
                      _player.onPlayerComplete.listen((_) {
                        if (mounted) setState(() => _playing = false);
                      });
                      setState(() => _playing = true);
                    }
                  },
                ),
                Text('${(_durationMs / 1000).toStringAsFixed(1)}s'),
                const SizedBox(width: 8),
                FilledButton(onPressed: _send, child: Text(Strings.t('chat.send'))),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => setState(() {
                    _audioPath = null;
                    _durationMs = 0;
                  }),
                  child: Text(Strings.t('common.cancel')),
                ),
              ],
            )
          else
            Text(Strings.t('chat.voice.hint')),
          const SizedBox(height: 16),
          GestureDetector(
            onTapDown: (_) => _startRecording(),
            onTapUp: (_) => _stopRecording(),
            onTapCancel: () => _stopRecording(),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: _recording ? Colors.red : Theme.of(context).colorScheme.primary,
              child: Icon(
                _recording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
