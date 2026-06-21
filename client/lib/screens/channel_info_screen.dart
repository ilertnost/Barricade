import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/strings.dart';
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
  String _peerName = '';

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
    if (mounted) {
      setState(() { _members = members; _loading = false; });
      if (_channel.isDm) _loadPeerInfo();
    }
  }

  Future<void> _loadPeerInfo() async {
    final peer = _members.where((m) => m.id != _myId).firstOrNull;
    if (peer != null && mounted) {
      setState(() {
        _peerName = peer.displayName.isNotEmpty ? peer.displayName : peer.username;
      });
    }
  }

  String get _typeLabel => _channel.isChannel ? Strings.t('channel.channel') : _channel.isGroup ? Strings.t('channel.group') : Strings.t('channel.dm');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(Strings.t('info.info')),
          actions: [
            if (_isOwner && !widget.channel.isDm)
              IconButton(icon: const Icon(Icons.edit), tooltip: Strings.t('common.edit'), onPressed: _editSettings),
            if (!_isOwner && !widget.channel.isDm)
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Leave',
                onPressed: () => _leaveChannel(context),
              ),
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
                    name: _channel.isDm ? (_peerName.isNotEmpty ? _peerName : _channel.name) : _channel.name,
                    radius: 40,
                    fallbackIcon: !_channel.isDm
                        ? (_channel.isChannel ? Icons.campaign : Icons.group)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(_channel.isDm ? (_peerName.isNotEmpty ? _peerName : _channel.name) : _channel.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  if (!_channel.isDm && _channel.username.isNotEmpty)
                    Text('@${_channel.username}', style: TextStyle(color: cs.primary)),
                  const SizedBox(height: 2),
                  Text(Strings.t('info.member_count').replaceFirst('{type}', _typeLabel).replaceFirst('{count}', '${_members.length}'),
                      style: TextStyle(color: cs.outline, fontSize: 13)),
                  if (_channel.visibility == 'private')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock, size: 13, color: cs.outline),
                        const SizedBox(width: 4),
                        Text(Strings.t('channel.private'), style: TextStyle(color: cs.outline, fontSize: 12)),
                      ]),
                    ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              tabs: [
                Tab(text: Strings.t('info.media')),
                Tab(text: Strings.t('info.files')),
                Tab(text: Strings.t('info.music')),
                Tab(text: Strings.t('info.links')),
                Tab(text: Strings.t('info.members')),
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
        floatingActionButton: _canManage && !widget.channel.isDm
            ? FloatingActionButton.extended(
                onPressed: _addMember,
                icon: const Icon(Icons.person_add),
                label: Text(Strings.t('common.add')),
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
        final roleLabel = m.role == 'owner' ? Strings.t('info.owner') : m.role == 'admin' ? Strings.t('info.admin') : null;
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
                title: Text(Strings.t('info.make_admin')),
                onTap: () { Navigator.pop(ctx); _setRole(m, 'admin'); },
              ),
            if (_isOwner && m.role == 'admin')
              ListTile(
                leading: const Icon(Icons.remove_moderator),
                title: Text(Strings.t('info.remove_admin')),
                onTap: () { Navigator.pop(ctx); _setRole(m, 'member'); },
              ),
            ListTile(
              leading: Icon(Icons.person_remove, color: Theme.of(ctx).colorScheme.error),
              title: Text(Strings.t('info.remove_from_chat'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
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
      SnackBar(content: Text(ok ? Strings.t('info.added').replaceFirst('{name}', user.displayName) : Strings.t('info.add_failed'))),
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
          title: Text(Strings.t('channel.settings')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Strings.t('channel.name'))),
              const SizedBox(height: 10),
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'username', prefixText: '@')),
              const SizedBox(height: 10),
              DropdownButtonFormField(
                initialValue: visibility,
                decoration: InputDecoration(labelText: Strings.t('channel.visibility')),
                items: [
                  DropdownMenuItem(value: 'public', child: Text(Strings.t('channel.public'))),
                  DropdownMenuItem(value: 'private', child: Text(Strings.t('channel.private'))),
                ],
                onChanged: (v) => setLocal(() => visibility = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.t('common.save'))),
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

  Future<void> _leaveChannel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('channel.delete_confirm').replaceFirst('{name}', _channel.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.t('common.delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ApiService.removeMember(_channel.id, _myId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to leave')));
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
    if (_items.isEmpty) return _EmptyTab(Strings.t('info.no_media'));
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
    if (_items.isEmpty) return _EmptyTab(Strings.t('info.no_files'));
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
      title: Text(_info?.originalName ?? Strings.t('chat.file'), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    if (_items.isEmpty) return _EmptyTab(Strings.t('info.no_music'));
    // Oldest → newest queue.
    final ordered = _items.reversed.toList();
    final tracks = ordered.map((m) => AudioTrack(
      fileId: m.fileId!,
      title: m.content.isNotEmpty ? m.content : Strings.t('chat.audio'),
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
          title: Text(m.content.isNotEmpty ? m.content : Strings.t('chat.audio')),
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
    if (_links.isEmpty) return _EmptyTab(Strings.t('info.no_links'));
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
    if (query.isEmpty) return Center(child: Text(Strings.t('common.type_name')));
    return FutureBuilder<List<User>>(
      future: ApiService.getUsers(query: query),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!;
        if (users.isEmpty) return Center(child: Text(Strings.t('common.not_found')));
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
