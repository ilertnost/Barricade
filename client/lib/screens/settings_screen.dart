import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/strings.dart';
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../services/theme_controller.dart';
import '../services/locale_controller.dart';
import '../services/quick_reaction_controller.dart';
import '../widgets/media_utils.dart';
import '../widgets/chat_settings.dart';
import '../main.dart' show AppState;
import 'chat_screen.dart';

/// Standalone settings screen (route `/settings`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Strings.t('settings.title'))),
      body: const SettingsBody(),
    );
  }
}

/// Settings content without its own Scaffold/AppBar, so it can be embedded as a
/// bottom-nav tab or used inside [SettingsScreen].
class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key});

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  User? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ApiService.getMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _editUsername() async {
    final ctrl = TextEditingController(text: _me?.username ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('auth.username')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'username',
            hintText: Strings.t('user.min_3_chars'),
            prefixText: '@',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(Strings.t('common.save'))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await ApiService.updateProfile(username: result);
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update username: $e')),
          );
        }
      }
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _me?.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('user.profile')),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(labelText: Strings.t('user.display_name')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: Text(Strings.t('common.save'))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await ApiService.updateProfile(displayName: result);
      _load();
    }
  }

  Future<void> _pickAvatar() async {
    final result = await MediaUtils.pickFromGallery();
    if (result == null || !mounted) return;
    try {
      final resp = await ApiService.uploadFile(result.file.path, result.filename);
      final fileId = resp['id'] as String?;
      if (fileId != null && mounted) {
        await ApiService.updateProfile(avatarId: fileId);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки аватарки: $e')));
      }
    }
  }

  void _logout() {
    context.read<WsService>().disconnect();
    context.read<AppState>().setLoggedIn(false);
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    return ListView(
      children: [
        // ── Аккаунт ──
        _SectionHeader(Strings.t('settings.account')),
        if (_me != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: _me!.avatarId != null
                      ? NetworkImage(ApiService.getFileUrl(_me!.avatarId!))
                      : null,
                  child: _me!.avatarId == null
                      ? Text(_me!.username[0].toUpperCase(), style: const TextStyle(fontSize: 32))
                      : null,
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.camera_alt, size: 18,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(_me!.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
          Center(child: Text(_me!.atUsername,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey))),
          const SizedBox(height: 4),
        ],
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(Strings.t('user.display_name')),
          subtitle: Text(Strings.t('user.display_name_hint')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editProfile,
        ),
        ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text(Strings.t('auth.username')),
          subtitle: Text('@${_me?.username ?? ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editUsername,
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(Strings.t('auth.change_password')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showChangePassword(),
        ),

        const Divider(),

        // ── Оформление ──
        _SectionHeader(Strings.t('theme.title')),
        const _ThemeModeTile(),
        const _AccentColorTile(),
        const _LanguageTile(),
        const _QuickReactionTile(),

        const Divider(),

        // ── Приватность ──
        const _PrivacySection(),

        const Divider(),

        // ── Настройки чатов ──
        _SectionHeader(Strings.t('chat_settings.title')),
        const ChatSettingsSection(),

        const Divider(),

        // ── Уведомления ──
        _SectionHeader(Strings.t('settings.notifications')),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(Strings.t('settings.notifications')),
          subtitle: Text(Strings.t('settings.notifications_hint')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showNotificationSettings(),
        ),

        const Divider(),

        // ── Разработчику ──
        _SectionHeader(Strings.t('settings.dev_menu')),
        ListTile(
          leading: const Icon(Icons.developer_mode),
          title: Text(Strings.t('settings.dev_menu')),
          subtitle: Text(Strings.t('settings.dev_menu_hint')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openDeveloperMenu,
        ),

        const Divider(),

        // ── Информация ──
        _SectionHeader(Strings.t('settings.info')),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(Strings.t('settings.server')),
          subtitle: Text(Config.serverUrl),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(Strings.t('settings.version')),
          subtitle: const Text('1.0.0'),
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: Text(Strings.t('settings.blocked_users')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showBlockedUsers(),
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: Text(Strings.t('settings.search_users')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showUserSearch(),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(Strings.t('settings.logout')),
          onTap: _logout,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _openDeveloperMenu() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _DeveloperMenuPage()));
  }

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('settings.notifications')),
        content: const Text('Настройки уведомлений появятся в следующем обновлении.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('common.ok'))),
        ],
      ),
    );
  }

  Future<void> _showChangePassword() async {
    final oldPwd = TextEditingController();
    final newPwd = TextEditingController();
    final confirmPwd = TextEditingController();
    String? error;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(Strings.t('auth.change_password')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPwd,
                decoration: InputDecoration(
                  labelText: Strings.t('auth.old_password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPwd,
                decoration: InputDecoration(
                  labelText: Strings.t('auth.new_password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPwd,
                decoration: InputDecoration(
                  labelText: Strings.t('auth.confirm_password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(Strings.t('common.cancel')),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (newPwd.text != confirmPwd.text) {
                        setDialogState(() => error = 'Пароли не совпадают');
                        return;
                      }
                      if (newPwd.text.length < 4) {
                        setDialogState(() => error = 'Пароль должен быть минимум 4 символа');
                        return;
                      }
                      setDialogState(() { error = null; loading = true; });
                      try {
                        final result = await ApiService.changePassword(oldPwd.text, newPwd.text);
                        if (result.containsKey('error')) {
                          setDialogState(() { error = result['error']; loading = false; });
                        } else {
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(Strings.t('auth.password_changed'))),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() { error = Strings.t('auth.connection_failed'); loading = false; });
                      }
                    },
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    oldPwd.dispose();
    newPwd.dispose();
    confirmPwd.dispose();
  }

  void _showUserSearch() {
    showSearch(context: context, delegate: UserSearchDialog());
  }

  void _showBlockedUsers() {
    showDialog(
      context: context,
      builder: (ctx) => _BlockedUsersDialog(),
    );
  }
}

class _QuickReactionTile extends StatelessWidget {
  const _QuickReactionTile();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<QuickReactionController>();
    return ListTile(
      leading: const Icon(Icons.add_reaction_outlined),
      title: Text(Strings.t('chat.quick_reaction')),
      subtitle: Text(Strings.t('chat.quick_reaction_hint')),
      trailing: PopupMenuButton<String>(
        icon: Text(ctrl.emoji, style: const TextStyle(fontSize: 24)),
        onSelected: (e) => ctrl.setEmoji(e),
        itemBuilder: (_) => QuickReactionController.emojis.map((e) => PopupMenuItem(
          value: e,
          child: Text(e, style: const TextStyle(fontSize: 24)),
        )).toList(),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LocaleController>();
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(Strings.t('language.title')),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'ru', label: Text('RU')),
          ButtonSegment(value: 'en', label: Text('EN')),
        ],
        selected: {ctrl.locale.languageCode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => ctrl.setLocale(Locale(s.first)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ThemeController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.brightness_6),
          const SizedBox(width: 16),
          Expanded(child: Text(Strings.t('theme.theme'))),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.smartphone), tooltip: Strings.t('theme.system')),
                  ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), tooltip: Strings.t('theme.light')),
                  ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), tooltip: Strings.t('theme.dark')),
                ],
                selected: {ctrl.mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => ctrl.setMode(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentColorTile extends StatelessWidget {
  const _AccentColorTile();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ThemeController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined),
              const SizedBox(width: 16),
              Text(Strings.t('theme.accent')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final opt in kAccentOptions)
                _AccentDot(
                  option: opt,
                  selected: (opt.seed == null && ctrl.useSystemAccent) ||
                      (opt.seed != null && !ctrl.useSystemAccent && opt.seed!.toARGB32() == ctrl.seed?.toARGB32()),
                  onTap: () => ctrl.setSeed(opt.seed),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;
  const _AccentDot({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSystem = option.seed == null;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: option.label,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSystem ? cs.primaryContainer : option.seed,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: isSystem
              ? Icon(Icons.auto_awesome, size: 18, color: cs.onPrimaryContainer)
              : (selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null),
        ),
      ),
    );
  }
}

class UserSearchDialog extends SearchDelegate<User> {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null!));
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Future<void> _openDmOrCreateChannel(BuildContext context, User target) async {
    final me = await ApiService.getMe();
    if (target.id == me.id) return;
    try {
      final channels = await ApiService.getChannels();
      final existing = await ApiService.findExistingDm(channels, target.id);
      if (existing != null) {
        if (context.mounted) {
          close(context, target);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              channel: existing,
            ),
          ));
        }
        return;
      }
    } catch (_) {}

    try {
      final ch = await ApiService.createChannel(
        target.displayName.isNotEmpty ? target.displayName : target.username,
        'dm',
        [target.id],
      );
      if (context.mounted) {
        close(context, target);
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(channel: ch),
        ));
      }
    } catch (_) {}
  }

  Widget _buildList(BuildContext context) {
    if (query.isEmpty) {
      return Center(child: Text(Strings.t('common.type_to_search')));
    }
    return FutureBuilder<List<User>>(
      future: ApiService.getUsers(query: query),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!;
        if (users.isEmpty) return Center(child: Text(Strings.t('common.no_users')));
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, i) {
            final user = users[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatarId != null
                    ? NetworkImage(ApiService.getFileUrl(user.avatarId!))
                    : null,
                child: user.avatarId == null
                    ? Text(user.username[0].toUpperCase())
                    : null,
              ),
              title: Text(user.displayName),
              subtitle: Text(user.atUsername),
              onTap: () => _openDmOrCreateChannel(context, user),
              onLongPress: () async {
                final blocked = await ApiService.isBlockedBy(user.id);
                final action = blocked
                    ? Strings.t('settings.unblock')
                    : Strings.t('settings.block');
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(action),
                    content: Text(blocked
                        ? '${Strings.t('settings.unblock')} @${user.username}?'
                        : Strings.t('settings.block_confirm').replaceFirst('{name}', user.username)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('common.cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  if (blocked) {
                    await ApiService.unblockUser(user.id);
                  } else {
                    await ApiService.blockUser(user.id);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(blocked
                          ? '${user.username} ${Strings.t('settings.unblock').toLowerCase()}'
                          : '${user.username} ${Strings.t('settings.block').toLowerCase()}')),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }
}

class _BlockedUsersDialog extends StatefulWidget {
  @override
  State<_BlockedUsersDialog> createState() => _BlockedUsersDialogState();
}

class _BlockedUsersDialogState extends State<_BlockedUsersDialog> {
  List<User>? _users;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await ApiService.getBlacklist();
    if (mounted) setState(() { _users = users; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('settings.blocked_users')),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _users!.isEmpty
                ? Center(child: Text(Strings.t('settings.blocked_empty')))
                : ListView.builder(
                    itemCount: _users!.length,
                    itemBuilder: (_, i) {
                      final u = _users![i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: u.avatarId != null
                              ? NetworkImage(ApiService.getFileUrl(u.avatarId!))
                              : null,
                          child: u.avatarId == null ? Text(u.username[0].toUpperCase()) : null,
                        ),
                        title: Text(u.displayName),
                        subtitle: Text(u.atUsername),
                        trailing: TextButton(
                          onPressed: () async {
                            await ApiService.unblockUser(u.id);
                            _load();
                          },
                          child: Text(Strings.t('settings.unblock')),
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Strings.t('common.cancel')),
        ),
      ],
    );
  }
}

class _PrivacySection extends StatefulWidget {
  const _PrivacySection();
  @override
  State<_PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<_PrivacySection> {
  String _lastSeenMode = 'everyone';
  bool _readReceipts = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastSeenMode = prefs.getString('privacy_last_seen') ?? 'everyone';
        _readReceipts = prefs.getBool('privacy_read_receipts') ?? true;
      });
    }
  }

  Future<void> _setLastSeen(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_last_seen', mode);
    setState(() => _lastSeenMode = mode);
  }

  Future<void> _toggleReadReceipts(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_read_receipts', val);
    setState(() => _readReceipts = val);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(Strings.t('settings.privacy')),
        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: Text(Strings.t('settings.privacy_last_seen')),
          subtitle: Text(Strings.t('settings.privacy_last_seen_hint')),
        ),
        RadioListTile<String>(
          title: Text(Strings.t('settings.privacy_everyone')),
          value: 'everyone',
          groupValue: _lastSeenMode,
          onChanged: (v) => _setLastSeen(v!),
        ),
        RadioListTile<String>(
          title: Text(Strings.t('settings.privacy_recently')),
          value: 'recently',
          groupValue: _lastSeenMode,
          onChanged: (v) => _setLastSeen(v!),
        ),
        RadioListTile<String>(
          title: Text(Strings.t('settings.privacy_nobody')),
          value: 'nobody',
          groupValue: _lastSeenMode,
          onChanged: (v) => _setLastSeen(v!),
        ),
        SwitchListTile(
          title: Text(Strings.t('settings.privacy_read_receipts')),
          subtitle: Text(Strings.t('settings.privacy_read_receipts_hint')),
          value: _readReceipts,
          onChanged: _toggleReadReceipts,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Меню разработчика
// ─────────────────────────────────────────────────────────────────────────────

class _DeveloperMenuPage extends StatefulWidget {
  const _DeveloperMenuPage();
  @override
  State<_DeveloperMenuPage> createState() => _DeveloperMenuPageState();
}

class _DeveloperMenuPageState extends State<_DeveloperMenuPage> {
  String _renderer = 'auto'; // auto / impeller / vulkan

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _renderer = prefs.getString('dev_renderer') ?? 'auto';
      });
    }
  }

  Future<void> _setRenderer(String? val) async {
    if (val == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dev_renderer', val);
    setState(() => _renderer = val);
    if (mounted) _showRestartDialog();
  }

  void _showRestartDialog() {
    final isDesktop = !Platform.isAndroid;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перезапустите приложение'),
        content: Text(isDesktop
            ? 'Изменение движка рендеринга вступит в силу после перезапуска.\n\n'
              'Desktop: запустите с флагом --enable-impeller или --enable-vulkan:\n'
              '  flutter run --enable-vulkan'
            : 'Изменение движка рендеринга вступит в силу после перезапуска приложения.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _importContacts(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final text = String.fromCharCodes(bytes);

      final contacts = _parseVCard(text);
      if (contacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не найдено контактов в файле')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Найдено ${contacts.length} контактов. Ищу совпадения…')),
        );
      }

      // Search each contact on the server and show matches.
      final matches = <_NameUserMatch>[];
      for (final name in contacts) {
        try {
          final users = await ApiService.getUsers(query: name);
          if (users.isNotEmpty) {
            matches.add(_NameUserMatch(name: name, users: users));
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Совпадения не найдены. Контакты не добавлены.')),
        );
        return;
      }

      // Show dialog with matches to select which to add.
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => _ImportContactsDialog(matches: matches),
      );

      if (selected == null || selected.isEmpty) return;

      int added = 0;
      for (final match in matches) {
        for (final user in match.users) {
          if (selected.contains(user.id)) {
            try {
              await ApiService.addContact(user.id, displayName: match.name);
              added++;
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено контактов: $added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    }
  }

  /// Simple vCard 2.1/3.0/4.0 parser returning list of full names.
  List<String> _parseVCard(String text) {
    final names = <String>[];
    final lines = text.split(RegExp(r'\r?\n'));
    String? currentFn;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase().startsWith('FN:')) {
        currentFn = trimmed.substring(3).trim();
      } else if (trimmed.toUpperCase().startsWith('END:VCARD')) {
        if (currentFn != null && currentFn.isNotEmpty) {
          names.add(currentFn);
        }
        currentFn = null;
      }
    }
    return names.toSet().toList(); // deduplicate
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Меню разработчика')),
      body: ListView(
        children: [
          const _SectionHeader('Движок рендеринга'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Выберите бэкенд рендеринга Flutter (требует перезапуска)',
                style: TextStyle(fontSize: 13, color: cs.outline)),
          ),
          RadioListTile<String>(
            title: const Text('Skia (по умолчанию)'),
            value: 'auto',
            groupValue: _renderer,
            onChanged: _setRenderer,
          ),
          RadioListTile<String>(
            title: const Text('Impeller (OpenGL/Vulkan)'),
            subtitle: const Text('Новый движок, меньше шансов на CPU'),
            value: 'impeller',
            groupValue: _renderer,
            onChanged: _setRenderer,
          ),
          RadioListTile<String>(
            title: const Text('Vulkan (Impeller)'),
            subtitle: const Text('Vulkan-бэкенд Impeller (экспериментально)'),
            value: 'vulkan',
            groupValue: _renderer,
            onChanged: _setRenderer,
          ),
          const Divider(),
          const _SectionHeader('Эффекты и отладка'),
          ListTile(
            leading: const Icon(Icons.web),
            title: const Text('WebView Debug'),
            subtitle: Text(Platform.isAndroid
                ? 'Включить отладку WebView'
                : 'Desktop WebView не используется'),
            trailing: Text(Platform.isAndroid ? 'Android' : 'N/A',
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera2 API'),
            subtitle: Text(Platform.isAndroid
                ? 'Использовать Camera2 API'
                : 'Desktop: системная камера'),
            trailing: Text(Platform.isAndroid ? 'Android' : 'Desktop',
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ),
          ListTile(
            leading: const Icon(Icons.contacts),
            title: const Text('Импорт контактов'),
            subtitle: const Text('Из vCard / CSV файла'),
            trailing: const Icon(Icons.upload_file),
            onTap: () => _importContacts(context),
          ),
          const Divider(),
          const _SectionHeader('О приложении'),
          ListTile(
            leading: const Icon(Icons.abc),
            title: const Text('Flutter'),
            subtitle: Text(_flutterVersion()),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('Текущий рендерер'),
            subtitle: Text(_renderer == 'vulkan'
                ? 'Vulkan (запрос)'
                : _renderer == 'impeller'
                    ? 'Impeller (запрос)'
                    : 'Skia / системный'),
          ),
        ],
      ),
    );
  }

  String _flutterVersion() {
    try {
      return const String.fromEnvironment('FLUTTER_VERSION', defaultValue: '3.44.0');
    } catch (_) {
      return '—';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Вспомогательные типы
// ─────────────────────────────────────────────────────────────────────────────

class _NameUserMatch {
  final String name;
  final List<User> users;
  const _NameUserMatch({required this.name, required this.users});
}

class _ImportContactsDialog extends StatefulWidget {
  final List<_NameUserMatch> matches;
  const _ImportContactsDialog({required this.matches});

  @override
  State<_ImportContactsDialog> createState() => _ImportContactsDialogState();
}

class _ImportContactsDialogState extends State<_ImportContactsDialog> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    // Pre-select all matches by default.
    for (final m in widget.matches) {
      for (final u in m.users) {
        _selected.add(u.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Найдено совпадений: ${widget.matches.length}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          children: [
            const Text('Выберите, кого добавить в контакты:'),
            const SizedBox(height: 8),
            ...widget.matches.map((m) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(m.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                ...m.users.map((u) => CheckboxListTile(
                  dense: true,
                  title: Text(u.displayName),
                  subtitle: Text(u.atUsername),
                  value: _selected.contains(u.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(u.id);
                      } else {
                        _selected.remove(u.id);
                      }
                    });
                  },
                )),
              ],
            )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toSet()),
          child: Text('Добавить (${_selected.length})'),
        ),
      ],
    );
  }
}
