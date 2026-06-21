import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../services/theme_controller.dart';
import '../services/locale_controller.dart';
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
        title: const Text('Имя пользователя'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'username',
            hintText: 'минимум 3 символа',
            prefixText: '@',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Сохранить')),
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
        title: const Text('Профиль'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Отображаемое имя'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: const Text('Сохранить')),
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
            title: const Text('Отображаемое имя'),
            subtitle: const Text('Как вас видят другие'),
            onTap: _editProfile,
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('Имя пользователя'),
            subtitle: Text('@${_me?.username ?? ''}'),
            onTap: _editUsername,
          ),
          const Divider(),
          const _LanguageTile(),
          const Divider(),
          const _SectionHeader('Оформление'),
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
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LocaleController>();
    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text('Язык / Language'),
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
          const Expanded(child: Text('Тема')),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.smartphone), tooltip: 'Система'),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), tooltip: 'Светлая'),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), tooltip: 'Тёмная'),
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
            children: const [
              Icon(Icons.palette_outlined),
              SizedBox(width: 16),
              Text('Акцент'),
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
      final existing = channels.where((ch) =>
        ch.type == 'dm' && (ch.name.contains(me.id) || ch.name.contains(target.id)));
      if (existing.isNotEmpty) {
        if (context.mounted) {
          close(context, target);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              channel: existing.first,
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
          itemBuilder: (_, i) => ListTile(
            leading: CircleAvatar(
              backgroundImage: users[i].avatarId != null
                  ? NetworkImage(ApiService.getFileUrl(users[i].avatarId!))
                  : null,
              child: users[i].avatarId == null
                  ? Text(users[i].username[0].toUpperCase())
                  : null,
            ),
            title: Text(users[i].displayName),
            subtitle: Text(users[i].atUsername),
            onTap: () => _openDmOrCreateChannel(context, users[i]),
          ),
        );
      },
    );
  }
}
