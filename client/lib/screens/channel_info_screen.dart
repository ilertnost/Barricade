import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';
import '../services/file_saver.dart';
import '../widgets/user_avatar.dart';

/// Telegram-style chat info: header + tabs (Media / Files / Music / Links /
/// Members), with member management for owner/admin.
class ChannelInfoScreen extends StatefulWidget {
  final Channel channel;
  const ChannelInfoScreen({super.key, required this.channel});

  @override
  State<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends State<ChannelInfoScreen> {
  late Channel _channel;
  List<Member> _members = [];
  bool _loading = true;

  String get _myId => ApiService.currentUserId ?? '';
  String get _myRole {
    final me = _members.where((m) => m.id == _myId);
    return me.isEmpty ? 'member' : me.first.role;
  }

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';
  bool get _isOwner => _myRole == 'owner';

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await ApiService.getMembers(_channel.id);
    if (mounted) setState(() { _members = members; _loading = false; });
  }

  String get _typeLabel => _channel.isChannel ? 'Канал' : _channel.isGroup ? 'Группа' : 'Личные сообщения';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Инфо'),
          actions: [
            if (_isOwner)
              IconButton(icon: const Icon(Icons.edit), tooltip: 'Изменить', onPressed: _editSettings),
          ],
        ),
        body: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  UserAvatar(
                    name: _channel.name,
                    radius: 40,
                    fallbackIcon: _channel.isChannel ? Icons.campaign : Icons.group,
                  ),
                  const SizedBox(height: 10),
                  Text(_channel.name, style: Theme.of(context).textTheme.titleLarge),
                  if (_channel.username.isNotEmpty)
                    Text('@${_channel.username}', style: TextStyle(color: cs.primary)),
                  const SizedBox(height: 2),
                  Text('$_typeLabel · ${_members.length} участн.',
                      style: TextStyle(color: cs.outline, fontSize: 13)),
                  if (_channel.visibility == 'private')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock, size: 13, color: cs.outline),
                        const SizedBox(width: 4),
                        Text('Приватный', style: TextStyle(color: cs.outline, fontSize: 12)),
                      ]),
                    ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              tabs: [
                Tab(text: 'Медиа'),
                Tab(text: 'Файлы'),
                Tab(text: 'Музыка'),
                Tab(text: 'Ссылки'),
                Tab(text: 'Участники'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _MediaGrid(channelId: _channel.id),
                        _FilesTab(channelId: _channel.id),
                        _MusicTab(channelId: _channel.id),
                        _LinksTab(channelId: _channel.id),
                        _membersTab(),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: _canManage
            ? FloatingActionButton.extended(
                onPressed: _addMember,
                icon: const Icon(Icons.person_add),
                label: const Text('Добавить'),
              )
            : null,
      ),
    );
  }

  // ── Members tab ──
  Widget _membersTab() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _members.length,
      itemBuilder: (_, i) {
        final m = _members[i];
        final roleLabel = m.role == 'owner' ? 'Владелец' : m.role == 'admin' ? 'Админ' : null;
        return ListTile(
          leading: UserAvatar(name: m.displayName, avatarId: m.avatarId, radius: 22),
          title: Text(m.displayName),
          subtitle: Text('@${m.username}'),
          trailing: roleLabel != null
              ? Chip(label: Text(roleLabel, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)
              : null,
          onTap: (_canManage && m.id != _myId && m.role != 'owner') ? () => _memberActions(m) : null,
        );
      },
    );
  }

  void _memberActions(Member m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isOwner && m.role == 'member')
              ListTile(
                leading: const Icon(Icons.shield),
                title: const Text('Назначить админом'),
                onTap: () { Navigator.pop(ctx); _setRole(m, 'admin'); },
              ),
            if (_isOwner && m.role == 'admin')
              ListTile(
                leading: const Icon(Icons.remove_moderator),
                title: const Text('Снять админа'),
                onTap: () { Navigator.pop(ctx); _setRole(m, 'member'); },
              ),
            ListTile(
              leading: Icon(Icons.person_remove, color: Theme.of(ctx).colorScheme.error),
              title: Text('Удалить из чата', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () { Navigator.pop(ctx); _removeMember(m); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(Member m, String role) async {
    if (await ApiService.setMemberRole(_channel.id, m.id, role)) _loadMembers();
  }

  Future<void> _removeMember(Member m) async {
    if (await ApiService.removeMember(_channel.id, m.id)) _loadMembers();
  }

  Future<void> _addMember() async {
    final user = await showSearch<User?>(context: context, delegate: _UserPickDelegate());
    if (user == null) return;
    final ok = await ApiService.addMember(_channel.id, user.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Добавлен: ${user.displayName}' : 'Не удалось добавить')),
    );
    if (ok) _loadMembers();
  }

  Future<void> _editSettings() async {
    final nameCtrl = TextEditingController(text: _channel.name);
    final userCtrl = TextEditingController(text: _channel.username);
    var visibility = _channel.visibility;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Настройки чата'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 10),
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'username', prefixText: '@')),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                initialValue: visibility,
                decoration: const InputDecoration(labelText: 'Видимость'),
                items: const [
                  DropdownMenuItem(value: 'public', child: Text('Публичный')),
                  DropdownMenuItem(value: 'private', child: Text('Приватный')),
                ],
                onChanged: (v) => setLocal(() => visibility = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final updated = await ApiService.updateChannelSettings(
        _channel.id,
        name: nameCtrl.text.trim(),
        username: userCtrl.text.trim(),
        visibility: visibility,
      );
      if (mounted) setState(() => _channel = updated);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

// ─── Media grid (images + videos) ───
class _MediaGrid extends StatefulWidget {
  final String channelId;
  const _MediaGrid({required this.channelId});
  @override
  State<_MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<_MediaGrid> {
  List<Message> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ApiService.getChannelMedia(widget.channelId, 'media').then((m) {
      if (mounted) setState(() { _items = m; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const _EmptyTab('Нет медиа');
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final m = _items[i];
        final isVideo = m.mimeType.startsWith('video/');
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => isVideo ? _VideoViewer(fileId: m.fileId!) : _ImageViewer(fileId: m.fileId!))),
          child: Container(
            color: Colors.black12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!isVideo)
                  Image.network(ApiService.getFileUrl(m.fileId!), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey))
                else
                  Container(color: Colors.black26),
                if (isVideo) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 36)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Files tab ───
class _FilesTab extends StatefulWidget {
  final String channelId;
  const _FilesTab({required this.channelId});
  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  List<Message> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ApiService.getChannelMedia(widget.channelId, 'files').then((m) {
      if (mounted) setState(() { _items = m; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const _EmptyTab('Нет файлов');
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) => _FileRow(fileId: _items[i].fileId!),
    );
  }
}

class _FileRow extends StatefulWidget {
  final String fileId;
  const _FileRow({required this.fileId});
  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  FileInfo? _info;
  @override
  void initState() {
    super.initState();
    ApiService.getFileInfo(widget.fileId).then((i) { if (mounted) setState(() => _info = i); });
  }
  String _size(int b) => b < 1024*1024 ? '${(b/1024).toStringAsFixed(0)} KB' : '${(b/1024/1024).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: const Icon(Icons.insert_drive_file)),
      title: Text(_info?.originalName ?? 'Файл', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_info != null ? _size(_info!.size) : '…'),
      onTap: () => FileSaver.openExternally(widget.fileId, _info?.originalName ?? widget.fileId),
      trailing: IconButton(
        icon: const Icon(Icons.download),
        onPressed: () async {
          final r = await FileSaver.saveToDownloads(widget.fileId, _info);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
        },
      ),
    );
  }
}

// ─── Music tab ───
class _MusicTab extends StatefulWidget {
  final String channelId;
  const _MusicTab({required this.channelId});
  @override
  State<_MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<_MusicTab> {
  List<Message> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ApiService.getChannelMedia(widget.channelId, 'music').then((m) {
      if (mounted) setState(() { _items = m; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const _EmptyTab('Нет музыки');
    // Oldest → newest queue.
    final ordered = _items.reversed.toList();
    final tracks = ordered.map((m) => AudioTrack(
      fileId: m.fileId!,
      title: m.content.isNotEmpty ? m.content : 'Аудио',
      artist: m.senderDisplayName,
    )).toList();
    final audio = context.watch<AudioPlayerService>();
    return ListView.builder(
      itemCount: ordered.length,
      itemBuilder: (_, i) {
        final m = ordered[i];
        final isCurrent = audio.currentFileId == m.fileId;
        return ListTile(
          leading: CircleAvatar(
            child: Icon(isCurrent && audio.isPlaying ? Icons.pause : Icons.music_note),
          ),
          title: Text(m.content.isNotEmpty ? m.content : 'Аудио'),
          subtitle: Text(m.senderDisplayName),
          onTap: () => audio.playOrToggle(tracks, i),
        );
      },
    );
  }
}

// ─── Links tab ───
class _LinksTab extends StatefulWidget {
  final String channelId;
  const _LinksTab({required this.channelId});
  @override
  State<_LinksTab> createState() => _LinksTabState();
}

class _LinksTabState extends State<_LinksTab> {
  final _urlRe = RegExp(r'https?://[^\s]+');
  List<String> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ApiService.getChannelMedia(widget.channelId, 'links').then((m) {
      final links = <String>[];
      for (final msg in m) {
        links.addAll(_urlRe.allMatches(msg.content).map((x) => x.group(0)!));
      }
      if (mounted) setState(() { _links = links; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_links.isEmpty) return const _EmptyTab('Нет ссылок');
    return ListView.builder(
      itemCount: _links.length,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.link),
        title: Text(_links[i], maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => launchUrl(Uri.parse(_links[i]), mode: LaunchMode.externalApplication),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final String text;
  const _EmptyTab(this.text);
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)));
}

// ─── Fullscreen viewers ───
class _ImageViewer extends StatelessWidget {
  final String fileId;
  const _ImageViewer({required this.fileId});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(child: InteractiveViewer(child: Image.network(ApiService.getFileUrl(fileId)))),
      );
}

class _VideoViewer extends StatefulWidget {
  final String fileId;
  const _VideoViewer({required this.fileId});
  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(ApiService.getFileUrl(widget.fileId)))
      ..initialize().then((_) { if (mounted) { setState(() {}); _ctrl!..setLooping(true)..play(); } });
  }
  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: _ctrl?.value.isInitialized == true
              ? AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: GestureDetector(
                  onTap: () => setState(() => _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play()),
                  child: VideoPlayer(_ctrl!)))
              : const CircularProgressIndicator(),
        ),
      );
}

// ─── User picker for "add member" ───
class _UserPickDelegate extends SearchDelegate<User?> {
  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _list(context);
  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
  Widget _list(BuildContext context) {
    if (query.isEmpty) return const Center(child: Text('Введите имя'));
    return FutureBuilder<List<User>>(
      future: ApiService.getUsers(query: query),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!;
        if (users.isEmpty) return const Center(child: Text('Не найдено'));
        return ListView(
          children: users.map((u) => ListTile(
            leading: UserAvatar(name: u.displayName, avatarId: u.avatarId, radius: 20),
            title: Text(u.displayName),
            subtitle: Text(u.atUsername),
            onTap: () => close(context, u),
          )).toList(),
        );
      },
    );
  }
}
