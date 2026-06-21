import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickReactionController extends ChangeNotifier {
  static const _key = 'quick_reaction_emoji';
  static const _default = '👍';
  static const List<String> emojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '🔥', '🎉', '🙏', '👎'];

  String _emoji = _default;
  String get emoji => _emoji;

  void load() {
    SharedPreferences.getInstance().then((p) {
      _emoji = p.getString(_key) ?? _default;
      notifyListeners();
    });
  }

  Future<void> setEmoji(String e) async {
    _emoji = e;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, e);
  }
}
