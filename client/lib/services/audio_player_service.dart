import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../config.dart';
import 'api_service.dart';

/// One playable audio item in the chat-wide queue.
class AudioTrack {
  final String fileId;
  final String title;
  final String artist;
  final Duration? duration;

  AudioTrack({
    required this.fileId,
    required this.title,
    this.artist = '',
    this.duration,
  });
}

/// App-global audio player. Builds a queue from a channel's audio messages and
/// plays through them (Telegram-style), with repeat (off/all/one), shuffle,
/// seek, speed and background playback (via just_audio_background).
class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<AudioTrack> _queue = [];

  AudioPlayerService() {
    // Re-broadcast the state changes the UI cares about.
    _player.currentIndexStream.listen((_) => notifyListeners());
    _player.playerStateStream.listen((_) => notifyListeners());
    _player.loopModeStream.listen((_) => notifyListeners());
    _player.shuffleModeEnabledStream.listen((_) => notifyListeners());
  }

  AudioPlayer get player => _player;

  // ---- Streams for fine-grained UI (seek bars) ----
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  // ---- Snapshot getters ----
  bool get isPlaying => _player.playing;
  LoopMode get loopMode => _player.loopMode;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  double get speed => _player.speed;
  bool get hasQueue => _queue.isNotEmpty;

  AudioTrack? get currentTrack {
    final i = _player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  /// fileId of the track currently loaded in the player (playing or paused),
  /// so message bubbles can highlight themselves.
  String? get currentFileId => currentTrack?.fileId;

  AudioSource _sourceFor(AudioTrack t) {
    final uri = Uri.parse('${Config.serverUrl}/api/files/${t.fileId}');
    final token = ApiService.token;
    // LockCachingAudioSource streams via HTTP Range and caches to disk —
    // pairs with the server's new ServeContent Range support.
    return LockCachingAudioSource(
      uri,
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      tag: MediaItem(
        id: t.fileId,
        title: t.title,
        artist: t.artist.isEmpty ? 'Barricade' : t.artist,
        duration: t.duration,
      ),
    );
  }

  /// Replace the queue with [tracks] and start at [startIndex].
  Future<void> playQueue(List<AudioTrack> tracks, int startIndex) async {
    _queue = tracks;
    notifyListeners();
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: tracks.map(_sourceFor).toList()),
        initialIndex: startIndex.clamp(0, tracks.length - 1),
      );
      await _player.play();
    } catch (_) {
      // Surface nothing here; UI just won't enter the playing state.
    }
  }

  /// Toggle play/pause for the track that's already loaded.
  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Play [track] from [queue]; if it's already the current track, just toggle.
  Future<void> playOrToggle(List<AudioTrack> queue, int index) async {
    final target = queue[index];
    if (currentFileId == target.fileId) {
      await toggle();
    } else {
      await playQueue(queue, index);
    }
  }

  Future<void> next() => _player.seekToNext();
  Future<void> previous() => _player.seekToPrevious();
  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> cycleLoopMode() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    final nextMode = order[(order.indexOf(_player.loopMode) + 1) % order.length];
    return _player.setLoopMode(nextMode);
  }

  Future<void> toggleShuffle() async {
    final enable = !_player.shuffleModeEnabled;
    if (enable) await _player.shuffle();
    await _player.setShuffleModeEnabled(enable);
  }

  Future<void> setSpeed(double s) => _player.setSpeed(s);

  Future<void> stop() async {
    await _player.stop();
    _queue = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
