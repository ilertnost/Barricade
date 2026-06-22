import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';

class ChatSettingsSection extends StatefulWidget {
  const ChatSettingsSection({super.key});
  @override
  State<ChatSettingsSection> createState() => _ChatSettingsSectionState();
}

class _ChatSettingsSectionState extends State<ChatSettingsSection> {
  String _autoDownload = 'wifi';
  String _historyKeep = 'forever';
  bool _notifications = true;

  static const _prefAutoDownload = 'chat_auto_download';
  static const _prefHistoryKeep = 'chat_history_keep';
  static const _prefNotifications = 'chat_notifications';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _autoDownload = p.getString(_prefAutoDownload) ?? 'wifi';
      _historyKeep = p.getString(_prefHistoryKeep) ?? 'forever';
      _notifications = p.getBool(_prefNotifications) ?? true;
    });
  }

  Future<void> _setAutoDownload(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefAutoDownload, v);
    if (mounted) setState(() => _autoDownload = v);
  }

  Future<void> _setHistoryKeep(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefHistoryKeep, v);
    if (mounted) setState(() => _historyKeep = v);
  }

  Future<void> _toggleNotifications(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefNotifications, v);
    if (mounted) setState(() => _notifications = v);
  }

  Future<void> _clearCache() async {
    // TODO: implement actual cache clearing
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Strings.t('chat_settings.cleared'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(Strings.t('chat_settings.auto_download')),
          subtitle: Text(Strings.t('chat_settings.auto_download_hint')),
          trailing: DropdownButton<String>(
            value: _autoDownload,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: 'never', child: Text(Strings.t('chat_settings.auto_download_never'))),
              DropdownMenuItem(value: 'wifi', child: Text(Strings.t('chat_settings.auto_download_wifi'))),
              DropdownMenuItem(value: 'always', child: Text(Strings.t('chat_settings.auto_download_always'))),
            ],
            onChanged: (v) => _setAutoDownload(v!),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(Strings.t('chat_settings.history_keep')),
          subtitle: Text(Strings.t('chat_settings.history_keep_hint')),
          trailing: DropdownButton<String>(
            value: _historyKeep,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: 'forever', child: Text(Strings.t('chat_settings.history_forever'))),
              DropdownMenuItem(value: 'month', child: Text(Strings.t('chat_settings.history_month'))),
              DropdownMenuItem(value: 'week', child: Text(Strings.t('chat_settings.history_week'))),
              DropdownMenuItem(value: 'day', child: Text(Strings.t('chat_settings.history_day'))),
            ],
            onChanged: (v) => _setHistoryKeep(v!),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(Strings.t('chat_settings.notifications')),
          subtitle: Text(Strings.t('chat_settings.notifications_hint')),
          value: _notifications,
          onChanged: _toggleNotifications,
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(Strings.t('chat_settings.clear_cache')),
          subtitle: Text(Strings.t('chat_settings.clear_cache_hint')),
          onTap: _clearCache,
        ),
      ],
    );
  }
}
