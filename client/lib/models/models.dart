class User {
  final String id;
  final String username;
  final String displayName;
  final String? avatarId;

  User({required this.id, required this.username, required this.displayName, this.avatarId});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    username: json['username'],
    displayName: json['display_name'] ?? json['username'],
    avatarId: json['avatar_id'],
  );

  String get atUsername => '@$username';
}

class Channel {
  final String id;
  final String name;
  final String username;
  final String type;
  final String ownerId;
  final String visibility;

  Channel({required this.id, required this.name, this.username = '', required this.type, required this.ownerId, this.visibility = 'public'});

  bool get isChannel => type == 'guild'; // broadcast channel
  bool get isGroup => type == 'group';
  bool get isDm => type == 'dm';

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'],
    name: json['name'] ?? '',
    username: json['username'] ?? '',
    type: json['type'] ?? 'group',
    ownerId: json['owner_id'] ?? '',
    visibility: json['visibility'] ?? 'public',
  );
}

class Member {
  final String id;
  final String username;
  final String displayName;
  final String? avatarId;
  final String role; // owner | admin | member

  Member({required this.id, required this.username, required this.displayName, this.avatarId, this.role = 'member'});

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'],
    username: json['username'] ?? '',
    displayName: json['display_name'] ?? json['username'] ?? '',
    avatarId: json['avatar_id'],
    role: json['role'] ?? 'member',
  );
}

class Message {
  final String id;
  final String channelId;
  final String senderId;
  final String senderUsername;
  final String senderDisplayName;
  final String content;
  final String? fileId;
  final String mimeType;
  final String? replyToId;
  final String status;
  final String createdAt;
  final String? editedAt;
  final List<Reaction> reactions;

  Message({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.senderUsername,
    required this.senderDisplayName,
    required this.content,
    this.fileId,
    this.mimeType = '',
    this.replyToId,
    this.status = 'sent',
    required this.createdAt,
    this.editedAt,
    this.reactions = const [],
  });

  Message copyWith({List<Reaction>? reactions}) => Message(
    id: id, channelId: channelId, senderId: senderId,
    senderUsername: senderUsername, senderDisplayName: senderDisplayName,
    content: content, fileId: fileId, mimeType: mimeType,
    replyToId: replyToId, status: status, createdAt: createdAt,
    editedAt: editedAt, reactions: reactions ?? this.reactions,
  );

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    channelId: json['channel_id'],
    senderId: json['sender_id'],
    senderUsername: json['sender_username'] ?? '',
    senderDisplayName: json['sender_display_name'] ?? json['sender_username'] ?? '',
    content: json['content'] ?? '',
    fileId: json['file_id'],
    mimeType: json['mime_type'] ?? '',
    replyToId: json['reply_to_id'],
    status: json['status'] ?? 'sent',
    createdAt: json['created_at'] ?? '',
    editedAt: json['edited_at'],
    reactions: (json['reactions'] as List?)?.map((r) => Reaction.fromJson(r)).toList() ?? [],
  );
}

class Reaction {
  final String messageId;
  final String userId;
  final String emoji;
  final String? username;
  final String? createdAt;

  Reaction({required this.messageId, required this.userId, required this.emoji, this.username, this.createdAt});

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
    messageId: json['message_id'] ?? '',
    userId: json['user_id'] ?? '',
    emoji: json['emoji'] ?? '',
    username: json['username'],
    createdAt: json['created_at'],
  );
}

class FileInfo {
  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final int width;
  final int height;
  final double duration; // seconds, for audio/video

  FileInfo({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    this.width = 0,
    this.height = 0,
    this.duration = 0,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
    id: json['id'],
    originalName: json['original_name'],
    mimeType: json['mime_type'],
    size: json['size'],
    width: json['width'] ?? 0,
    height: json['height'] ?? 0,
    duration: (json['duration'] ?? 0).toDouble(),
  );
}

class WsMessage {
  final String type;
  final dynamic payload;

  WsMessage({required this.type, this.payload});

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
    type: json['type'] ?? '',
    payload: json['payload'],
  );
}
