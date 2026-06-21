import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:video_player/video_player.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../services/call_service.dart';
import '../services/audio_player_service.dart';
import '../services/locale_controller.dart';
import '../services/quick_reaction_controller.dart';
import '../services/file_saver.dart';
import '../widgets/media_utils.dart';
import '../widgets/user_avatar.dart';
import 'channel_info_screen.dart';
import 'call_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/video_circle.dart';

class ChatScreen extends StatefulWidget {
  final Channel channel;
  final String? filterSenderId;

  const ChatScreen({super.key, required this.channel, this.filterSenderId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  String? _filterSenderId;
  bool _canPost = true;
  bool _peerOnline = false;
  String? _peerLastSeen;
  String _peerName = '';
  String? _peerId;

  @override
  void initState() {
    super.initState();
    _filterSenderId = widget.filterSenderId;
    _loadMessages();
    context.read<WsService>().addListener(_handleWsMessage);
    context.read<WsService>().joinChannel(widget.channel.id);
    context.read<WsService>().sendReadReceipt(widget.channel.id);
    _resolvePostPermission();
    if (widget.channel.type == 'dm') _loadPeerInfo();
  }

  @override
  void dispose() {
    context.read<WsService>().removeListener(_handleWsMessage);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPeerInfo() async {
    try {
      final members = await ApiService.getMembers(widget.channel.id);
      if (!mounted) return;
      final peer = members.where((m) => m.id != ApiService.currentUserId).firstOrNull;
      if (peer != null) {
        _peerId = peer.id;
        final user = await ApiService.getUser(peer.id);
        if (mounted) {
          setState(() {
            _peerName = user.displayName.isNotEmpty ? user.displayName : user.username;
            _peerOnline = user.online;
            _peerLastSeen = user.lastSeen;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _resolvePostPermission() async {
    if (widget.channel.type != 'guild') return;
    final members = await ApiService.getMembers(widget.channel.id);
    final me = members.where((m) => m.id == ApiService.currentUserId);
    final canPost = me.isNotEmpty && (me.first.role == 'owner' || me.first.role == 'admin');
    if (mounted) setState(() => _canPost = canPost);
  }

  void _startCall({bool video = false}) {
    final call = context.read<CallService>();
    if (widget.channel.type == 'dm') {
      if (_peerId == null) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => CallScreen(
          channelId: widget.channel.id,
          peerIds: [_peerId!],
          video: video,
        ),
      ));
    } else {
      // Group/guild: fetch members, call all others
      ApiService.getMembers(widget.channel.id).then((members) {
        final others = members
            .where((m) => m.id != ApiService.currentUserId)
            .map((m) => m.id)
            .toList();
        if (!mounted || others.isEmpty) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => CallScreen(
            channelId: widget.channel.id,
            peerIds: others,
            video: video,
          ),
        ));
      });
    }
  }

  String _formatLastSeen(String? lastSeen) {
    if (lastSeen == null) return '';
    final dt = DateTime.tryParse(lastSeen);
    if (dt == null) return '';
    final now = DateTime.now().toUtc();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return Strings.t('user.online');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${Strings.t('user.min_ago')}';
    if (diff.inHours < 24) return '${diff.inHours} ${Strings.t('user.hours_ago')}';
    return '${diff.inDays} ${Strings.t('user.days_ago')}';
  }

  List<Message> get _displayMessages {
    if (_filterSenderId == null) return _messages;
    return _messages.where((m) => m.senderId == _filterSenderId).toList();
  }

  void _handleWsMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'] as String?;
    final payload = data['payload'];

    if (type == 'new_message' && payload != null) {
      final msg = Message.fromJson(payload);
      if (msg.channelId == widget.channel.id) {
        setState(() => _messages.insert(0, msg));
      }
    } else if (type == 'message_updated' && payload != null) {
      final msg = Message.fromJson(payload);
      if (msg.channelId == widget.channel.id) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) _messages[idx] = msg;
        });
      }
    } else if (type == 'message_deleted' && payload != null) {
      final msgId = payload['message_id'] as String?;
      final chId = payload['channel_id'] as String?;
      if (msgId != null && chId == widget.channel.id) {
        setState(() => _messages.removeWhere((m) => m.id == msgId));
        _loadMessages();
      }
    } else if (type == 'reaction_add' && payload != null) {
      final msgId = payload['message_id'] as String?;
      if (msgId != null) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            final existing = _messages[idx].reactions;
            _messages[idx] = _messages[idx].copyWith(reactions: [
              ...existing,
              Reaction(
                messageId: msgId,
                userId: payload['user_id'] ?? '',
                emoji: payload['emoji'] ?? '',
                username: payload['username'],
              ),
            ]);
          }
        });
      }
    } else if (type == 'reaction_remove' && payload != null) {
      final msgId = payload['message_id'] as String?;
      final userId = payload['user_id'] as String?;
      final emoji = payload['emoji'] as String?;
      if (msgId != null && userId != null && emoji != null) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(reactions:
              _messages[idx].reactions.where((r) =>
                r.userId != userId || r.emoji != emoji
              ).toList(),
            );
          }
        });
      }
    } else if (type == 'message_status_updated' && payload != null) {
      if (payload['channel_id'] == widget.channel.id) {
        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            if (_messages[i].senderId != ApiService.currentUserId) continue;
            _messages[i] = _messages[i].copyWithStatus('read');
          }
        });
      }
    } else if (type == 'user_presence' && payload != null) {
      final userId = payload['user_id'] as String?;
      if (userId != null && userId != ApiService.currentUserId) {
        setState(() {
          _peerOnline = payload['online'] == true;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await ApiService.getMessages(widget.channel.id);
      if (mounted) setState(() { _messages = msgs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sendMessage() {
    if (_msgCtrl.text.trim().isEmpty) return;
    context.read<WsService>().sendMessage(widget.channel.id, _msgCtrl.text.trim());
    _msgCtrl.clear();
  }

  void _sendMedia(MediaResult result) async {
    final fileId = await MediaUtils.uploadAndGetId(result);
    if (fileId != null && mounted) {
      context.read<WsService>().sendMessage(widget.channel.id, '', fileId: fileId);
    }
  }

  void _sendVoiceFile(File file, String filename, int durationMs) {
    final ws = context.read<WsService>();
    Navigator.pop(context);
    ApiService.uploadFile(file.path, filename, durationSec: durationMs / 1000.0).then((resp) {
      final fileId = resp['id'] as String?;
      if (fileId != null && mounted) {
        ws.sendMessage(widget.channel.id, '', fileId: fileId);
      }
    });
  }

  void _sendVideoCircleFile(File file, String filename) {
    final ws = context.read<WsService>();
    Navigator.pop(context);
    ApiService.uploadFile(file.path, filename).then((resp) {
      final fileId = resp['id'] as String?;
      if (fileId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed: no file id')));
        return;
      }
      if (mounted) ws.sendMessage(widget.channel.id, '', fileId: fileId);
    }).catchError((e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    });
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: MediaAttachmentBar(
            onPickPhoto: () {
              Navigator.pop(ctx);
              MediaUtils.pickFromGallery().then((result) {
                if (result != null) _sendMedia(result);
              });
            },
            onPickVideo: () {
              Navigator.pop(ctx);
              MediaUtils.pickVideoFromGallery().then((result) {
                if (result != null) _sendMedia(result);
              });
            },
            onCapturePhoto: () {
              Navigator.pop(ctx);
              MediaUtils.capturePhoto().then((result) {
                if (result != null) _sendMedia(result);
              });
            },
            onRecordVoice: () {
              Navigator.pop(ctx);
              _showVoiceRecorder();
            },
            onOpenVideoCircle: () {
              Navigator.pop(ctx);
              _showVideoCircle();
            },
            onPickFile: () {
              Navigator.pop(ctx);
              MediaUtils.pickAnyFile().then((result) {
                if (result != null) _sendMedia(result);
              });
            },
          ),
        ),
      ),
    );
  }

  void _showVoiceRecorder() {
    showModalBottomSheet(
      context: context,
      builder: (_) => VoiceRecorder(onSend: _sendVoiceFile),
    );
  }

  void _showVideoCircle() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => VideoCircle(onSend: _sendVideoCircleFile),
    );
  }

  void _editMessage(Message msg) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('chat.edit_message')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); ctrl.dispose(); }, child: Text(Strings.t('common.cancel'))),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              context.read<WsService>().editMessage(msg.id, ctrl.text.trim());
              Navigator.pop(ctx);
              ctrl.dispose();
            }
          }, child: Text(Strings.t('common.save'))),
        ],
      ),
    );
  }

  /// All audio messages in the channel, oldest → newest, for the player queue.
  List<Message> get _orderedAudio => _messages.reversed
      .where((m) => m.fileId != null && m.mimeType.startsWith('audio/'))
      .toList();

  /// Build the chat-wide audio queue and play (or toggle) the tapped message.
  void _playAudioMessage(Message msg) {
    final ordered = _orderedAudio;
    final idx = ordered.indexWhere((m) => m.fileId == msg.fileId);
    if (idx < 0) return;
    final tracks = ordered.map((m) {
      final isVoice = m.mimeType.contains('ogg') || m.mimeType.contains('opus');
      return AudioTrack(
        fileId: m.fileId!,
        title: m.content.isNotEmpty
            ? m.content
            : (isVoice ? Strings.t('chat.voice_message') : Strings.t('chat.audio')),
        artist: m.senderDisplayName.isNotEmpty ? m.senderDisplayName : m.senderUsername,
      );
    }).toList();
    context.read<AudioPlayerService>().playOrToggle(tracks, idx);
  }

  // ---- Multi-select ----
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;
  List<Message> get _selectedMessages =>
      _messages.where((m) => _selectedIds.contains(m.id)).toList();
  bool get _anySelectedHasFile => _selectedMessages.any((m) => m.fileId != null);
  bool get _allSelectedOwn =>
      _selectedMessages.isNotEmpty &&
      _selectedMessages.every((m) => m.senderId == ApiService.currentUserId);

  void _toggleSelect(Message m) {
    setState(() {
      if (!_selectedIds.remove(m.id)) _selectedIds.add(m.id);
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _saveSelectedToDownloads() async {
    final files = _selectedMessages.where((m) => m.fileId != null).toList();
    if (files.isEmpty) return;
    final ids = files.map((m) => m.fileId!).toList();
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Strings.t('chat.saving_files').replaceFirst('{count}', '${ids.length}'))),
    );
    var ok = 0;
    String? lastError;
    for (final m in files) {
      final info = await ApiService.getFileInfo(m.fileId!);
      final res = await FileSaver.saveToDownloads(m.fileId!, info);
      if (res.ok) {
        ok++;
      } else {
        lastError = res.message;
      }
    }
    if (mounted) {
      final msg = ok == ids.length
          ? Strings.t('chat.saved_to_downloads').replaceFirst('{ok}', '$ok').replaceFirst('{total}', '${ids.length}')
          : Strings.t('chat.saved_partial').replaceFirst('{ok}', '$ok').replaceFirst('{total}', '${ids.length}').replaceFirst('{error}', lastError ?? '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _deleteSelected() {
    final ws = context.read<WsService>();
    for (final m in _selectedMessages) {
      if (m.senderId == ApiService.currentUserId) ws.deleteMessage(m.id);
    }
    _clearSelection();
  }

  PreferredSizeWidget _selectionAppBar() {
    final single = _selectedIds.length == 1 ? _selectedMessages.first : null;
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Text(Strings.t('chat.selected_count').replaceFirst('{count}', '${_selectedIds.length}')),
      actions: [
        if (single != null && single.senderId == ApiService.currentUserId && single.content.isNotEmpty)
          IconButton(icon: const Icon(Icons.edit), tooltip: Strings.t('common.edit'), onPressed: () {
            final m = single;
            _clearSelection();
            _editMessage(m);
          }),
        if (_anySelectedHasFile)
          IconButton(icon: const Icon(Icons.download), tooltip: Strings.t('common.save_to_downloads'), onPressed: _saveSelectedToDownloads),
        if (_allSelectedOwn)
          IconButton(icon: const Icon(Icons.delete), tooltip: Strings.t('common.delete'), onPressed: _deleteSelected),
      ],
    );
  }

  bool get _isGroup => widget.channel.type != 'dm';

  DateTime? _dayOf(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  String _dateLabel(String iso) {
    final d = _dayOf(iso);
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return Strings.t('chat.date_today');
    if (diff == 1) return Strings.t('chat.date_yesterday');
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  PreferredSizeWidget _chatAppBar() {
    final cs = Theme.of(context).colorScheme;
    final name = widget.channel.type == 'dm'
        ? (_peerName.isNotEmpty ? _peerName : widget.channel.name)
        : (widget.channel.name.isEmpty ? Strings.t('common.chats') : widget.channel.name);
    final typeLabel = widget.channel.type == 'guild'
        ? Strings.t('channel.channel')
        : widget.channel.type == 'dm'
            ? Strings.t('channel.dm')
            : Strings.t('channel.group');
    final subtitle = _filterSenderId != null
        ? Strings.t('channel.filter_by_member')
        : widget.channel.type == 'dm'
            ? (_peerOnline
                ? Strings.t('user.online')
                : _formatLastSeen(_peerLastSeen))
            : typeLabel;
    return AppBar(
      titleSpacing: 4,
      title: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChannelInfoScreen(channel: widget.channel))),
        child: Row(
          children: [
            UserAvatar(
              name: name,
              radius: 18,
              fallbackIcon: widget.channel.type == 'guild'
                  ? Icons.campaign
                  : widget.channel.type == 'group'
                      ? Icons.group
                      : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: cs.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone),
          tooltip: Strings.t('common.call'),
          onPressed: _startCall,
        ),
        if (widget.channel.type != 'dm')
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: Strings.t('common.video_call'),
            onPressed: () => _startCall(video: true),
          ),
        if (_filterSenderId != null)
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: Strings.t('channel.reset_filter'),
            onPressed: () => setState(() => _filterSenderId = null),
          ),
      ],
    );
  }

  Widget _broadcastNotice(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.all(14),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign, size: 18, color: cs.outline),
            const SizedBox(width: 8),
            Text(Strings.t('channel.only_admin_can_post'), style: TextStyle(color: cs.outline)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _showAttachmentSheet,
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: Strings.t('chat.hint'),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    final filtered = _displayMessages;
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: Scaffold(
      appBar: _selectionMode ? _selectionAppBar() : _chatAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true,
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final msg = filtered[i];
                      // In a reversed list, i+1 is the older (visually-above) message.
                      final older = i + 1 < filtered.length ? filtered[i + 1] : null;
                      final isOwn = msg.senderId == ApiService.currentUserId;
                      final newSeries = older == null ||
                          older.senderId != msg.senderId ||
                          _dayOf(older.createdAt) != _dayOf(msg.createdAt);
                      final showDate = older == null || _dayOf(older.createdAt) != _dayOf(msg.createdAt);
                      return Column(
                        key: ValueKey(msg.id),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDate) _DateSeparator(label: _dateLabel(msg.createdAt)),
                          _MessageBubble(
                            msg: msg,
                            isOwn: isOwn,
                            isGroup: _isGroup,
                            showHeader: newSeries,
                            selectionMode: _selectionMode,
                            selected: _selectedIds.contains(msg.id),
                            onLongPress: () => _toggleSelect(msg),
                            onSelectTap: () => _toggleSelect(msg),
                            onPlayAudio: () => _playAudioMessage(msg),
                            onTapSender: !isOwn
                                ? () => setState(() {
                                      _filterSenderId = _filterSenderId == msg.senderId ? null : msg.senderId;
                                    })
                                : null,
                            onTap: () => _showMessageMenu(context, msg),
                            onDoubleTap: () {
                              final quickEmoji = context.read<QuickReactionController>().emoji;
                              final ws = context.read<WsService>();
                              final hasIt = msg.reactions.any((r) =>
                                  r.userId == ApiService.currentUserId && r.emoji == quickEmoji);
                              if (hasIt) {
                                ws.removeReaction(msg.id, quickEmoji);
                              } else {
                                ws.addReaction(msg.id, quickEmoji);
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const MiniPlayer(),
          _canPost ? _buildInputBar(context) : _broadcastNotice(context),
        ],
      ),
    ),
    );
  }

  void _showMessageMenu(BuildContext context, Message msg) {
    final ws = context.read<WsService>();
    final isOwn = msg.senderId == ApiService.currentUserId;
    final hasText = msg.content.isNotEmpty;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // emoji row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final e in QuickReactionController.emojis)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          final hasIt = msg.reactions.any((r) =>
                              r.userId == ApiService.currentUserId && r.emoji == e);
                          if (hasIt) {
                            ws.removeReaction(msg.id, e);
                          } else {
                            ws.addReaction(msg.id, e);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: msg.reactions.any((r) =>
                                r.userId == ApiService.currentUserId && r.emoji == e)
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ),
              if (isOwn && hasText)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(Strings.t('chat.edit_message')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(msg);
                  },
                ),
              if (isOwn)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(Strings.t('common.delete')),
                  onTap: () {
                    Navigator.pop(ctx);
                    ws.deleteMessage(msg.id);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message msg;
  final bool isOwn;
  final bool isGroup;
  final bool showHeader;
  final VoidCallback? onTapSender;
  final VoidCallback? onPlayAudio;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectTap;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const _MessageBubble({
    required this.msg,
    required this.isOwn,
    this.isGroup = false,
    this.showHeader = true,
    this.onTapSender,
    this.onPlayAudio,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelectTap,
    this.onTap,
    this.onDoubleTap,
  });

  Widget _statusIcon(BuildContext context) {
    switch (msg.status) {
      case 'read':
        return Icon(Icons.done_all, size: 14, color: Theme.of(context).colorScheme.primary);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      default:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
    }
  }

  String get _senderName =>
      msg.senderDisplayName.isNotEmpty ? msg.senderDisplayName : msg.senderUsername;

  String get _time => msg.createdAt.length >= 16 ? msg.createdAt.substring(11, 16) : msg.createdAt;

  /// Group reactions by emoji, count them, and note if current user reacted.
  List<_ReactionGroup> get _reactionGroups {
    final map = <String, List<Reaction>>{};
    for (final r in msg.reactions) {
      map.putIfAbsent(r.emoji, () => []).add(r);
    }
    return map.entries.map((e) => _ReactionGroup(
      emoji: e.key,
      count: e.value.length,
      me: e.value.any((r) => r.userId == ApiService.currentUserId),
    )).toList();
  }

  Widget _buildReactionsRow(BuildContext context) {
    final groups = _reactionGroups;
    if (groups.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: groups.map((g) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: g.me ? cs.primaryContainer.withValues(alpha: 0.6) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: g.me ? Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1) : null,
          ),
          child: Text('${g.emoji} ${g.count}', style: TextStyle(fontSize: 13, color: cs.onSurface)),
        )).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bubbleColor = isOwn ? cs.primaryContainer : cs.surfaceContainerHigh;
    final textColor = isOwn ? cs.onPrimaryContainer : cs.onSurface;
    final hasMedia = msg.fileId != null;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isOwn ? 16 : 4),
      bottomRight: Radius.circular(isOwn ? 4 : 16),
    );
    final showAvatarGutter = isGroup && !isOwn;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: hasMedia ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMedia)
            _MediaContent(key: ValueKey(msg.fileId), fileId: msg.fileId!, mimeType: msg.mimeType, onPlayAudio: onPlayAudio),
          if (msg.content.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(hasMedia ? 12 : 0, hasMedia ? 4 : 0, hasMedia ? 12 : 0, 0),
              child: Text(msg.content, style: TextStyle(color: textColor, fontSize: 15.5)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(hasMedia ? 12 : 0, 2, hasMedia ? 12 : 0, hasMedia ? 8 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_time, style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
                if (msg.editedAt != null) ...[
                  const SizedBox(width: 4),
                  Text(Strings.t('chat.edited'), style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
                ],
                if (isOwn) ...[const SizedBox(width: 4), _statusIcon(context)],
              ],
            ),
          ),
          _buildReactionsRow(context),
        ],
      ),
    );

    Widget row;
    if (showAvatarGutter) {
      row = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: showHeader
                ? UserAvatar(name: _senderName, radius: 14)
                : const SizedBox(width: 28),
          ),
          bubble,
        ],
      );
    } else {
      row = bubble;
    }

    final content = Column(
      crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showHeader && isGroup && !isOwn)
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 2, top: 2),
            child: GestureDetector(
              onTap: onTapSender,
              child: Text(_senderName,
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
          ),
        row,
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onTap: selectionMode ? onSelectTap : onTap,
      onDoubleTap: selectionMode ? null : onDoubleTap,
      child: Container(
        color: selected ? cs.primary.withValues(alpha: 0.16) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        // While selecting, swallow inner taps (image fullscreen, audio play).
        child: IgnorePointer(ignoring: selectionMode, child: content),
      ),
    );
  }
}

class _ReactionGroup {
  final String emoji;
  final int count;
  final bool me;
  const _ReactionGroup({required this.emoji, required this.count, required this.me});
}

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
      ),
    );
  }
}

class _MediaContent extends StatefulWidget {
  final String fileId;
  final String mimeType;
  final VoidCallback? onPlayAudio;

  const _MediaContent({super.key, required this.fileId, required this.mimeType, this.onPlayAudio});

  @override
  State<_MediaContent> createState() => _MediaContentState();
}

class _MediaContentState extends State<_MediaContent> {
  String _mimeType = '';
  bool _loadingInfo = false;

  @override
  void initState() {
    super.initState();
    _mimeType = widget.mimeType;
    if (_mimeType.isEmpty || _mimeType == 'application/octet-stream') _fetchInfo();
  }

  Future<void> _fetchInfo() async {
    if (_loadingInfo) return;
    setState(() => _loadingInfo = true);
    try {
      final info = await ApiService.getFileInfo(widget.fileId);
      if (mounted && info != null) {
        setState(() {
          _mimeType = info.mimeType;
          _loadingInfo = false;
        });
      } else {
        if (mounted) setState(() => _loadingInfo = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInfo) {
      return Container(height: 60,
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_mimeType.startsWith('image/')) return _ImageContent(fileId: widget.fileId);
    if (_mimeType.startsWith('video/')) return _VideoContent(fileId: widget.fileId);
    if (_mimeType.startsWith('audio/')) {
      return _AudioContent(
        fileId: widget.fileId,
        isVoice: _mimeType.contains('ogg') || _mimeType.contains('opus'),
        onPlay: widget.onPlayAudio,
      );
    }
    return _FileContent(fileId: widget.fileId);
  }
}

class _ImageContent extends StatelessWidget {
  final String fileId;
  const _ImageContent({required this.fileId});

  void _openFullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                ApiService.getFileUrl(fileId),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 64)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.35;
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Image.network(
            ApiService.getFileUrl(fileId),
            fit: BoxFit.scaleDown,
            width: double.infinity,
            height: maxH,
          errorBuilder: (_, __, ___) => Container(
            height: 150, color: Colors.grey[900],
            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              height: maxH, color: Colors.grey[900],
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    );
  }
}

class _VideoContent extends StatefulWidget {
  final String fileId;
  const _VideoContent({required this.fileId});

  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _playing = false;
  bool _isCircle = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(ApiService.getFileUrl(widget.fileId)));
    _ctrl!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      if (_isCircle) {
        // Circles (кружки) autoplay muted on loop, Telegram-style.
        _ctrl!.setLooping(true);
        _ctrl!.setVolume(0);
        _ctrl!.play();
        setState(() => _playing = true);
      }
    }).catchError((_) {});
    _detectCircle();
  }

  Future<void> _detectCircle() async {
    try {
      final info = await ApiService.getFileInfo(widget.fileId);
      final name = info?.originalName ?? '';
      final circle = name.contains('circle') || (info != null && info.width > 0 && info.width == info.height);
      if (mounted && circle) {
        setState(() => _isCircle = true);
        if (_initialized) {
          _ctrl!..setLooping(true)..setVolume(0)..play();
          setState(() => _playing = true);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _buildCircle() {
    const size = 220.0;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _CircleFullscreen(fileId: widget.fileId)),
        ),
        child: ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _ctrl!.value.size.width,
                    height: _ctrl!.value.size.height,
                    child: VideoPlayer(_ctrl!),
                  ),
                ),
                const Positioned(
                  bottom: 12,
                  right: 20,
                  child: Icon(Icons.fullscreen, color: Colors.white70, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.35;
    if (!_initialized) {
      return Container(
        height: _isCircle ? 220 : maxH,
        color: Colors.grey[900],
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_isCircle) return _buildCircle();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: _ctrl!.value.aspectRatio,
              child: VideoPlayer(_ctrl!),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (_playing) { _ctrl!.pause(); } else { _ctrl!.play(); }
              setState(() => _playing = !_playing);
            },
            child: CircleAvatar(
              radius: 24, backgroundColor: Colors.black45,
              child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioContent extends StatefulWidget {
  final String fileId;
  final bool isVoice;
  final VoidCallback? onPlay;
  const _AudioContent({required this.fileId, this.isVoice = false, this.onPlay});

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  FileInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await ApiService.getFileInfo(widget.fileId);
      if (mounted) setState(() => _info = info);
    } catch (_) {}
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Playback state comes from the global player so all bubbles + the
    // mini-player stay in sync.
    final audio = context.watch<AudioPlayerService>();
    final isCurrent = audio.currentFileId == widget.fileId;
    final isPlaying = isCurrent && audio.isPlaying;
    final isBuffering = isCurrent &&
        audio.player.processingState == ProcessingState.loading;

    final title = widget.isVoice
        ? Strings.t('chat.voice_message')
        : (_info?.originalName ?? Strings.t('chat.audio'));
    final totalDur = Duration(seconds: (_info?.duration ?? 0).round());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: isBuffering
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: cs.primary, size: 30),
            onPressed: widget.onPlay,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        color: isCurrent ? cs.primary : null,
                      ),
                ),
                if (isCurrent)
                  StreamBuilder<Duration>(
                    stream: audio.positionStream,
                    builder: (context, snap) {
                      final pos = snap.data ?? Duration.zero;
                      return Text(_fmt(pos),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline));
                    },
                  )
                else if (totalDur > Duration.zero)
                  Text(_fmt(totalDur),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen circle player: enlarged round video with sound, looping, and a
/// close button. Opened by tapping a circle in chat.
class _CircleFullscreen extends StatefulWidget {
  final String fileId;
  const _CircleFullscreen({required this.fileId});

  @override
  State<_CircleFullscreen> createState() => _CircleFullscreenState();
}

class _CircleFullscreenState extends State<_CircleFullscreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(ApiService.getFileUrl(widget.fileId)));
    _ctrl!.initialize().then((_) {
      if (!mounted) return;
      _ctrl!..setLooping(true)..setVolume(1)..play();
      setState(() => _ready = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.of(context).size.width * 0.9;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: !_ready
                  ? const CircularProgressIndicator()
                  : GestureDetector(
                      onTap: () => _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play(),
                      child: ClipOval(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _ctrl!.value.size.width,
                              height: _ctrl!.value.size.height,
                              child: VideoPlayer(_ctrl!),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileContent extends StatefulWidget {
  final String fileId;
  const _FileContent({required this.fileId});

  @override
  State<_FileContent> createState() => _FileContentState();
}

class _FileContentState extends State<_FileContent> {
  FileInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await ApiService.getFileInfo(widget.fileId);
      if (mounted) setState(() => _info = info);
    } catch (_) {}
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description;
      case 'apk':
        return Icons.android;
      case 'exe':
      case 'msi':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _openFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await FileSaver.openExternally(widget.fileId, _info?.originalName ?? widget.fileId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _info?.originalName ?? Strings.t('chat.file');
    final sub = _info != null ? _humanSize(_info!.size) : '…';
    return InkWell(
      onTap: _openFile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primaryContainer,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_iconFor(name), color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
