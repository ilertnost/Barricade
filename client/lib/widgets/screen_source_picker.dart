import 'package:flutter/material.dart';

/// Confirmation dialog before screen sharing.
/// Source selection is handled by the native xdg-desktop-portal
/// (KDE/GNOME) via getDisplayMedia() — only one dialog shown.
class ScreenShareConfirmDialog extends StatelessWidget {
  const ScreenShareConfirmDialog({super.key});

  /// Show dialog and return true if user confirmed.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const ScreenShareConfirmDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.screen_share, color: cs.primary, size: 32),
      title: const Text('Демонстрация экрана'),
      content: const Text('Начать демонстрацию экрана?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Начать'),
        ),
      ],
    );
  }
}
