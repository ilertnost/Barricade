import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../services/call_service.dart';
import '../services/locale_controller.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'incoming_call_screen.dart';
import '../widgets/voice_room_panel.dart';

/// App shell: bottom NavigationBar with Чаты / Контакты / Настройки.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  User? _me;
  OverlayEntry? _callBanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<CallService>().addListener(_onCallStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final call = context.read<CallService>();
      if (call.state == CallState.ringing && call.incomingCall != null) {
        _showCallBanner();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callBanner?.remove();
    context.read<CallService>().removeListener(_onCallStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = context.read<WsService>();
        if (!ws.isConnected) ws.connect();

        final call = context.read<CallService>();
        if (call.state == CallState.connected && call.channelId != null && call.callPeerId != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(
            channelId: call.channelId!,
            peerIds: [call.callPeerId!],
          )));
        } else if (call.state == CallState.ringing && call.incomingCall != null) {
          _hideCallBanner();
          _showCallBanner();
        }
      });
    }
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final call = context.read<CallService>();
    if (call.state == CallState.ringing && call.incomingCall != null) {
      _showCallBanner();
    } else {
      _hideCallBanner();
    }
  }

  void _showCallBanner() {
    _callBanner?.remove();
    _callBanner = OverlayEntry(
      builder: (_) => const IncomingCallFullscreen(),
    );
    Overlay.of(context).insert(_callBanner!);
  }

  void _hideCallBanner() {
    _callBanner?.remove();
    _callBanner = null;
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiService.getMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  void _goToSettings() => setState(() => _index = 3);

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _ChatsTab(me: _me, onProfileTap: _goToSettings),
                _ContactsTab(),
                _CallLogTab(),
                SettingsScreen(),
              ],
            ),
          ),
          // Voice room bar — visible from any tab when connected
          Consumer<CallService>(
            builder: (_, call, __) {
              if (!call.inVoiceRoom || call.voiceChannelId == null) {
                return const SizedBox.shrink();
              }
              final cs = Theme.of(context).colorScheme;
              return GestureDetector(
                onTap: () => showVoiceRoomPanel(context, channelName: 'Голосовой канал'),
                child: Container(
                  width: double.infinity,
                  color: Colors.green.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.headset, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          call.voiceParticipants.isEmpty
                              ? 'В голосовом канале'
                              : 'В голосовом канале (${call.voiceParticipants.length})',
                          style: TextStyle(fontSize: 13, color: Colors.green.shade700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => call.leaveVoiceRoom(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Выйти', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_up, size: 18, color: cs.outline),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: Strings.t('common.chats')),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Strings.t('common.contacts')),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'Звонки'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Strings.t('settings.title')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Чаты
// ─────────────────────────────────────────────────────────────────────────────

class _ChatsTab extends StatefulWidget {
  final User? me;
  final VoidCallback onProfileTap;
  const _ChatsTab({required this.me, required this.onProfileTap});

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  List<Channel> _channels = [];
  bool _loading = true;
  final Map<String, String> _dmPeerNames = {};
  final Map<String, String> _dmPeerUsernames = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, DateTime> _lastActivity = {};
  String? _openChatId;
  bool _wsBound = false;

  @override
  void initState() {
    super.initState();
    _bindWs();
    _load();
  }

  @override
  void dispose() {
    context.read<WsService>().removeListener(_handleWsMessage);
    super.dispose();
  }

  void _bindWs() {
    if (_wsBound) return;
    _wsBound = true;
    context.read<WsService>().addListener(_handleWsMessage);
  }

  void _handleWsMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'] as String?;
    final payload = data['payload'];
    if (type == 'channel_created' && payload != null) {
      final ch = Channel.fromJson(payload);
      if (!_channels.any((c) => c.id == ch.id)) {
        setState(() => _channels.insert(0, ch));
        context.read<WsService>().joinChannel(ch.id);
      }
    } else if (type == 'channel_deleted' && payload != null) {
      final chId = payload['channel_id'] as String?;
      if (chId != null) setState(() => _channels.removeWhere((c) => c.id == chId));
    } else if (type == 'new_message' && payload != null) {
      final msg = Message.fromJson(payload);
      final chId = msg.channelId;
      if (chId != _openChatId) {
        _unreadCounts[chId] = (_unreadCounts[chId] ?? 0) + 1;
      }
      _lastActivity[chId] = DateTime.now();
      setState(() {
        _channels.sort((a, b) => (_lastActivity[b.id] ?? DateTime(2000))
            .compareTo(_lastActivity[a.id] ?? DateTime(2000)));
      });
    }
  }

  Future<void> _load() async {
    try {
      final channels = await ApiService.getChannels();
      if (mounted) {
        setState(() {
          _channels = channels;
          _loading = false;
        });
        for (final ch in channels) {
          context.read<WsService>().joinChannel(ch.id);
        }
        _resolveDmNames();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveDmNames() async {
    for (final ch in _channels) {
      if (ch.type != 'dm') continue;
      try {
        final members = await ApiService.getMembers(ch.id);
        final peer = members.where((m) => m.id != ApiService.currentUserId).firstOrNull;
        if (peer != null) {
          _dmPeerNames[ch.id] = peer.displayName.isNotEmpty ? peer.displayName : peer.username;
          _dmPeerUsernames[ch.id] = peer.username;
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _openChat(Channel ch) async {
    setState(() => _openChatId = ch.id);
    _unreadCounts.remove(ch.id);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(channel: ch)));
    // ChatScreen took over the WS handler — restore ours and refresh.
    _bindWs();
    _load();
    setState(() => _openChatId = null);
  }

  void _createChannel() {
    showDialog(
      context: context,
      builder: (ctx) => _CreateChannelDialog(
        onCreated: (ch) {
          if (!_channels.any((c) => c.id == ch.id)) _channels.insert(0, ch);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _deleteChannel(Channel ch) async {
    try {
      await ApiService.deleteChannel(ch.id);
      setState(() => _channels.removeWhere((c) => c.id == ch.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t('channel.delete_failed').replaceFirst('{error}', '$e'))));
        _load();
      }
    }
  }

  Future<bool> _confirmDelete(Channel ch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('common.delete')),
        content: Text(Strings.t('channel.delete_confirm').replaceFirst('{name}', ch.name.isEmpty ? 'this chat' : ch.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('common.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(Strings.t('common.delete')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  IconData _iconFor(Channel ch) =>
      ch.type == 'dm' ? Icons.person : ch.type == 'group' ? Icons.group : Icons.tag;

  String _subtitleFor(Channel ch) =>
      ch.type == 'dm' ? Strings.t('channel.dm') : ch.type == 'group' ? Strings.t('channel.group') : Strings.t('channel.channel');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: widget.onProfileTap,
            child: UserAvatar(
              name: widget.me?.displayName ?? widget.me?.username ?? '?',
              avatarId: widget.me?.avatarId,
              radius: 18,
            ),
          ),
        ),
        title: const Text('Barricade'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: GlobalSearchDelegate()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createChannel,
        child: const Icon(Icons.edit),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _channels.isEmpty
              ? _EmptyState(
                  icon: Icons.forum_outlined,
                  text: Strings.t('common.no_channels'),
                  hint: 'Нажмите + чтобы создать чат',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _channels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final ch = _channels[i];
                      final isDm = ch.type == 'dm';
                      final canDelete = isDm || widget.me?.id == ch.ownerId;
                      final name = isDm
                          ? (_dmPeerNames[ch.id] ?? ch.name)
                          : (ch.name.isEmpty ? 'Чат ${ch.id.substring(0, 6)}' : ch.name);
                      return Dismissible(
                        key: ValueKey(ch.id),
                        direction: canDelete ? DismissDirection.endToStart : DismissDirection.none,
                        background: Container(
                          color: cs.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(Icons.delete, color: cs.onErrorContainer),
                        ),
                        confirmDismiss: (_) => _confirmDelete(ch).then((ok) {
                          if (ok) _deleteChannel(ch);
                          return ok;
                        }),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: UserAvatar(
                            name: name,
                            radius: 24,
                            fallbackIcon: ch.type == 'dm' ? null : _iconFor(ch),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_subtitleFor(ch), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_unreadCounts.containsKey(ch.id) && _unreadCounts[ch.id]! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_unreadCounts[ch.id]}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              if (ch.type != 'dm' && ch.visibility == 'private')
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.lock, size: 16, color: cs.outline),
                                ),
                            ],
                          ),
                          onTap: () => _openChat(ch),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Контакты
// ─────────────────────────────────────────────────────────────────────────────

class _ContactsTab extends StatefulWidget {
  const _ContactsTab();

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab> {
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await ApiService.getContacts();
      if (mounted) setState(() { _contacts = contacts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Channel> _resolveDmChannel(String peerId, String displayName) async {
    final channels = await ApiService.getChannels();
    final existing = await ApiService.findExistingDm(channels, peerId);
    if (existing != null) return existing;
    return await ApiService.createChannel(displayName, 'dm', [peerId]);
  }

  Future<void> _openDm(String peerId, String displayName) async {
    try {
      final ch = await _resolveDmChannel(peerId, displayName);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(channel: ch)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка открытия чата: $e')));
      }
    }
  }

  Future<void> _callUser(String peerId, String displayName) async {
    try {
      final ch = await _resolveDmChannel(peerId, displayName);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(channelId: ch.id, peerIds: [peerId], video: false)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  String _formatLastSeen(String lastSeen) {
    final dt = DateTime.tryParse(lastSeen);
    if (dt == null) return '';
    final now = DateTime.now().toUtc();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return Strings.t('user.online_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${Strings.t('user.min_ago')}';
    if (diff.inHours < 24) return '${diff.inHours} ${Strings.t('user.hours_ago')}';
    return '${diff.inDays} ${Strings.t('user.days_ago')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Strings.t('common.contacts'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? _EmptyState(icon: Icons.people_outline, text: Strings.t('common.no_users'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _contacts.length,
                    itemBuilder: (_, i) {
                      final c = _contacts[i];
                      final id = c['contact_id'] as String;
                      final name = c['display_name'] as String? ?? '';
                      final username = c['username'] as String? ?? '';
                      final avatarId = c['avatar_id'] as String?;
                      final online = c['online'] as bool? ?? false;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: Stack(
                          children: [
                            UserAvatar(name: name, avatarId: avatarId, radius: 24),
                            if (online)
                              Positioned(
                                right: 0, bottom: 0,
                                child: Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.call_outlined, size: 18),
                              onPressed: () => _callUser(id, name),
                              tooltip: 'Позвонить',
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline, size: 18),
                              onPressed: () => _openDm(id, name),
                              tooltip: 'Написать',
                            ),
                          ],
                        ),
                        onTap: () => _openDm(id, name),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Недавние звонки
// ─────────────────────────────────────────────────────────────────────────────

class _CallLogTab extends StatefulWidget {
  const _CallLogTab();

  @override
  State<_CallLogTab> createState() => _CallLogTabState();
}

class _CallLogTabState extends State<_CallLogTab> {
  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final log = call.callLog;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Недавние звонки')),
      body: log.isEmpty
          ? _EmptyState(
              icon: Icons.history,
              text: 'Нет истории звонков',
              hint: 'Позвоните кому-нибудь из контактов',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: log.length,
              itemBuilder: (_, i) {
                final entry = log[i];
                final icon = entry.isIncoming
                    ? (entry.answered ? Icons.call_received : Icons.call_missed)
                    : Icons.call_made;
                final color = entry.answered
                    ? null
                    : cs.error;
                return ListTile(
                  leading: Icon(icon, color: color, size: 24),
                  title: Text(entry.peerName, style: TextStyle(color: color)),
                  subtitle: Text(
                    '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}'
                    '${entry.durationSec > 0 ? ' · ${entry.durationSec}с' : ''}',
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  const _EmptyState({required this.icon, required this.text, this.hint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: cs.outline, fontSize: 16)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(color: cs.outline, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Глобальный поиск (шапка «Чаты»)
// ─────────────────────────────────────────────────────────────────────────────

class GlobalSearchDelegate extends SearchDelegate<void> {
  List<User> _users = [];
  List<Channel> _channels = [];
  bool _searched = false;

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Future<void> _search() async {
    if (query.isEmpty) return;
    try {
      final data = await ApiService.searchAll(query);
      _users = (data['users'] as List).map((e) => User.fromJson(e)).toList();
      _channels = (data['channels'] as List).map((e) => Channel.fromJson(e)).toList();
      _searched = true;
    } catch (_) {}
  }

  Widget _buildList(BuildContext context) {
    if (query.isEmpty) return Center(child: Text(Strings.t('common.type_to_search')));
    if (!_searched) _search();
    if (!_searched && _users.isEmpty) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: [
        if (_channels.isNotEmpty) ...[
          _searchHeader(context, Strings.t('common.chats')),
          ..._channels.map((ch) => ListTile(
                leading: UserAvatar(name: ch.name, radius: 22,
                    fallbackIcon: ch.type == 'guild' ? Icons.campaign : Icons.group),
                title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  ch.username.isNotEmpty ? '@${ch.username}' : null,
                  ch.type == 'guild' ? Strings.t('channel.channel') : Strings.t('channel.group'),
                ].whereType<String>().join(' · ')),
                onTap: () async {
                  // Public → join then open; private (member) → just open.
                  final joined = await ApiService.joinChannel(ch.id);
                  if (context.mounted) {
                    close(context, null);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(channel: joined ?? ch)));
                  }
                },
              )),
        ],
        if (_users.isNotEmpty) ...[
          _searchHeader(context, Strings.t('common.contacts')),
          ..._users.map((u) => ListTile(
                leading: UserAvatar(name: u.displayName, avatarId: u.avatarId, radius: 22),
                title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(u.atUsername, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  close(context, null);
                  _openDmOrCreateChannel(context, u);
                },
              )),
        ],
        if (_searched && _users.isEmpty && _channels.isEmpty)
          Center(child: Padding(padding: EdgeInsets.all(32), child: Text(Strings.t('common.nothing_found')))),
      ],
    );
  }

  Widget _searchHeader(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );

  Future<void> _openDmOrCreateChannel(BuildContext context, User target) async {
    try {
      final me = await ApiService.getMe();
      if (target.id == me.id) return;
      final channels = await ApiService.getChannels();
      final existing = await ApiService.findExistingDm(channels, target.id);
      if (existing != null) {
        if (context.mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(channel: existing)));
        }
        return;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка поиска чата: $e')));
      }
    }
    try {
      final ch = await ApiService.createChannel(
          target.displayName.isNotEmpty ? target.displayName : target.username, 'dm', [target.id]);
      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(channel: ch)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания чата: $e')));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Диалог создания чата
// ─────────────────────────────────────────────────────────────────────────────

class _CreateChannelDialog extends StatefulWidget {
  final Function(Channel) onCreated;
  const _CreateChannelDialog({required this.onCreated});

  @override
  State<_CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<_CreateChannelDialog> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _type = 'group';
  String _visibility = 'public';
  List<User> _searchResults = [];
  final List<String> _selectedIds = [];
  bool _searching = false;
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    _searchTimer?.cancel();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      debugPrint('[_CreateChannelDialog] searching for: $q');
      try {
        final users = await ApiService.getUsers(query: q);
        debugPrint('[_CreateChannelDialog] found ${users.length} users for: $q');
        if (mounted) {
          setState(() => _searchResults = users);
          debugPrint('[_CreateChannelDialog] searchResults set to ${users.length} items');
        }
      } catch (e) {
        debugPrint('[_CreateChannelDialog] search error: $e');
        if (mounted) setState(() => _searchResults = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Strings.t('channel.new_chat')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'group', label: Text(Strings.t('channel.group')), icon: Icon(Icons.group)),
                ButtonSegment(value: 'guild', label: Text(Strings.t('channel.channel')), icon: Icon(Icons.campaign)),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: Strings.t('channel.name')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: Strings.t('channel.username_search'),
                hintText: Strings.t('channel.optional'),
                prefixText: '@',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField(
              isExpanded: true,
              initialValue: _visibility,
              decoration: InputDecoration(labelText: Strings.t('channel.visibility')),
              items: [
                DropdownMenuItem(value: 'public', child: Text(Strings.t('channel.public_search'))),
                DropdownMenuItem(value: 'private', child: Text(Strings.t('channel.private_invite'))),
              ],
              onChanged: (v) => setState(() => _visibility = v!),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(Strings.t('channel.add_participants'), style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(hintText: Strings.t('channel.search_users_placeholder'), prefixIcon: Icon(Icons.search)),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_selectedIds.isNotEmpty)
              Wrap(
                spacing: 6,
                children: _selectedIds.map((id) {
                  final u = _searchResults.where((x) => x.id == id);
                  return Chip(
                    label: Text(u.isNotEmpty ? u.first.username : id.substring(0, 6), style: const TextStyle(fontSize: 12)),
                    onDeleted: () => setState(() => _selectedIds.remove(id)),
                  );
                }).toList(),
              ),
            if (_searching)
              const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_searchResults.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: _searchResults.map((u) => CheckboxListTile(
                  dense: true,
                  title: Text(u.displayName),
                  subtitle: Text(u.atUsername),
                  value: _selectedIds.contains(u.id),
                  onChanged: (v) => setState(() {
                    if (v == true) _selectedIds.add(u.id);
                    else _selectedIds.remove(u.id);
                  }),
                )).toList(),
              )
            else if (_searchCtrl.text.isNotEmpty)
              const SizedBox(height: 48, child: Center(child: Text('Пользователи не найдены'))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(Strings.t('common.cancel'))),
        FilledButton(
          onPressed: () async {
            if (_nameCtrl.text.isEmpty) return;
            try {
              final ch = await ApiService.createChannel(
                _nameCtrl.text,
                _type,
                _selectedIds,
                username: _usernameCtrl.text.trim().toLowerCase(),
                visibility: _visibility,
              );
              if (context.mounted) {
                final nav = Navigator.of(context, rootNavigator: true);
                widget.onCreated(ch);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => ChatScreen(channel: ch)));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          child: Text(Strings.t('common.create')),
        ),
      ],
    );
  }
}
