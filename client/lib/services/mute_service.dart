import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MuteService {
  static SharedPreferences? _prefs;
  static final Set<String> _mutedChannelIds = {};

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString('muted_channels') ?? '[]';
    _mutedChannelIds.addAll((jsonDecode(raw) as List).cast<String>());
  }

  static bool isMuted(String channelId) => _mutedChannelIds.contains(channelId);

  static Future<void> toggleMute(String channelId) async {
    if (_mutedChannelIds.contains(channelId)) {
      _mutedChannelIds.remove(channelId);
    } else {
      _mutedChannelIds.add(channelId);
    }
    await _save();
  }

  static Future<void> mute(String channelId) async {
    _mutedChannelIds.add(channelId);
    await _save();
  }

  static Future<void> unmute(String channelId) async {
    _mutedChannelIds.remove(channelId);
    await _save();
  }

  static Future<void> _save() async {
    await _prefs?.setString('muted_channels', jsonEncode(_mutedChannelIds.toList()));
  }
}
