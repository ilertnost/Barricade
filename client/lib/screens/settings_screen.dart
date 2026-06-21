import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../services/theme_controller.dart';
import '../services/locale_controller.dart';
import '../services/quick_reaction_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    return ListView(
        children: [
          if (_me != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _editProfile,
              child: Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: _me!.avatarId != null
                      ? NetworkImage(ApiService.getFileUrl(_me!.avatarId!))
                      : null,
                  child: _me!.avatarId == null
                      ? Text(_me!.username[0].toUpperCase(), style: const TextStyle(fontSize: 32))
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _editProfile,
              child: Center(child: Text(_me!.displayName, style: Theme.of(context).textTheme.headlineSmall)),
            ),
            Center(
              child: Text(
                _me!.atUsername,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(Strings.t('user.display_name')),
            subtitle: Text(Strings.t('user.display_name_hint')),
            onTap: _editProfile,
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(Strings.t('auth.username')),
            subtitle: Text('@${_me?.username ?? ''}'),
            onTap: _editUsername,
          ),
          const Divider(),
          const _QuickReactionTile(),
          const Divider(),
          const _LanguageTile(),
          const Divider(),
          const _PrivacySection(),
          const Divider(),
          _SectionHeader(Strings.t('theme.title')),
          const _ThemeModeTile(),
          const _AccentColorTile(),
          const Divider(),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(Strings.t('auth.change_password')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangePassword(),
          ),
          const Divider(),
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
            onTap: () {
              context.read<WsService>().disconnect();
              context.read<AppState>().setLoggedIn(false);
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
        ],
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
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.smartphone), tooltip: Strings.t('theme.system')),
              ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), tooltip: Strings.t('theme.light')),
              ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), tooltip: Strings.t('theme.dark')),
            ],
            selected: {ctrl.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => ctrl.setMode(s.first),
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
