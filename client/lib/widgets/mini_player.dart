import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';

/// Persistent control bar shown while audio is loaded. Bind it once near the
/// bottom of a screen; it hides itself when nothing is queued.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerService>();
    if (!audio.hasQueue) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final track = audio.currentTrack;

    return Material(
      color: cs.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar driven by the player's position stream.
          StreamBuilder<Duration>(
            stream: audio.positionStream,
            builder: (context, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: audio.durationStream,
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? track?.duration ?? Duration.zero;
                  final maxMs = dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds;
                  final value = pos.inMilliseconds.clamp(0, maxMs).toDouble();
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          min: 0,
                          max: maxMs.toDouble(),
                          value: value,
                          onChanged: (v) => audio.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos), style: Theme.of(context).textTheme.bodySmall),
                            Text(_fmt(dur), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Icon(Icons.music_note, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(track?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium),
                      if ((track?.artist ?? '').isNotEmpty)
                        Text(track!.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
                    ],
                  ),
                ),
                // Shuffle
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Перемешать',
                  icon: Icon(Icons.shuffle,
                      color: audio.shuffleEnabled ? cs.primary : cs.outline),
                  onPressed: audio.toggleShuffle,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Предыдущий',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: audio.previous,
                ),
                IconButton(
                  tooltip: audio.isPlaying ? 'Пауза' : 'Играть',
                  icon: Icon(audio.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 34, color: cs.primary),
                  onPressed: audio.toggle,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Следующий',
                  icon: const Icon(Icons.skip_next),
                  onPressed: audio.next,
                ),
                // Repeat off / all / one
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Повтор',
                  icon: Icon(
                    audio.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                    color: audio.loopMode == LoopMode.off ? cs.outline : cs.primary,
                  ),
                  onPressed: audio.cycleLoopMode,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close),
                  onPressed: audio.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
