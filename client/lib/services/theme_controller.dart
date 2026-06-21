import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent color presets offered in Settings → Оформление.
/// `null` value = "Системный" (use the device's Material You palette on Android 12+).
class AccentOption {
  final String label;
  final Color? seed;
  const AccentOption(this.label, this.seed);
}

const List<AccentOption> kAccentOptions = [
  AccentOption('Системный', null),
  AccentOption('Индиго', Colors.indigo),
  AccentOption('Синий', Color(0xFF5865F2)), // Discord blurple
  AccentOption('Бирюзовый', Color(0xFF229ED9)), // Telegram blue
  AccentOption('Зелёный', Colors.green),
  AccentOption('Фиолетовый', Colors.deepPurple),
  AccentOption('Оранжевый', Colors.deepOrange),
  AccentOption('Розовый', Colors.pink),
];

/// Holds the user's theme preferences (mode + accent seed) and persists them.
class ThemeController extends ChangeNotifier {
  static const _kMode = 'theme_mode';
  static const _kSeed = 'theme_seed'; // stored ARGB int, or absent = system

  ThemeMode _mode = ThemeMode.dark;
  Color? _seed = Colors.indigo;

  ThemeMode get mode => _mode;

  /// User-chosen accent color, or `null` to follow the system palette.
  Color? get seed => _seed;

  /// True when the accent follows the device's Material You palette.
  bool get useSystemAccent => _seed == null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kMode)) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      case 'system':
        _mode = ThemeMode.system;
        break;
    }
    if (prefs.containsKey(_kSeed)) {
      final v = prefs.getInt(_kSeed);
      _seed = v == null ? null : Color(v);
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
  }

  Future<void> setSeed(Color? seed) async {
    _seed = seed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (seed == null) {
      // Sentinel: present key but "system" means follow dynamic palette.
      await prefs.remove(_kSeed);
    } else {
      await prefs.setInt(_kSeed, seed.toARGB32());
    }
  }
}
