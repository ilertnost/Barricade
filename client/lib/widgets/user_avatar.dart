import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Circular avatar showing the user's photo if available, otherwise initials on
/// a deterministic color derived from the name (Discord/Telegram style).
class UserAvatar extends StatelessWidget {
  final String name;
  final String? avatarId;
  final double radius;
  final IconData? fallbackIcon;

  const UserAvatar({
    super.key,
    required this.name,
    this.avatarId,
    this.radius = 22,
    this.fallbackIcon,
  });

  // A small palette of pleasant, saturated hues keyed off the name hash.
  static const _palette = [
    Color(0xFF5865F2), // blurple
    Color(0xFF229ED9), // tg blue
    Color(0xFFEB459E), // pink
    Color(0xFF57F287), // green
    Color(0xFFFEE75C), // yellow
    Color(0xFFED4245), // red
    Color(0xFF9B59B6), // purple
    Color(0xFFE67E22), // orange
    Color(0xFF1ABC9C), // teal
  ];

  Color get _color {
    if (name.isEmpty) return _palette[0];
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (avatarId != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(ApiService.getFileUrl(avatarId!)),
        backgroundColor: _color,
      );
    }
    final color = _color;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: fallbackIcon != null
          ? Icon(fallbackIcon, color: Colors.white, size: radius)
          : Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
