import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../services/api_service.dart';

class WsService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;

  bool get isConnected => _channel != null;

  void connect() {
    final token = ApiService.token;
    if (token == null) return;

    _channel = WebSocketChannel.connect(
      Uri.parse('${Config.wsUrl}?token=$token'),
    );

    _channel!.stream.listen(
      (data) {
        if (onMessage != null) {
          onMessage!(jsonDecode(data as String));
        }
      },
      onError: (err) => null,
      onDone: () {
        _channel = null;
        Future.delayed(Duration(seconds: 3), connect);
      },
    );
  }

  void send(String type, dynamic payload) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': type,
      'payload': payload,
    }));
  }

  void sendMessage(String channelId, String content, {String? fileId, String? replyToId}) {
    send('send_message', {
      'channel_id': channelId,
      'content': content,
      if (fileId != null) 'file_id': fileId,
      if (replyToId != null) 'reply_to_id': replyToId,
    });
  }

  void createChannel(String name, String type, List<String> memberIds) {
    send('create_channel', {
      'name': name,
      'type': type,
      'member_ids': memberIds,
    });
  }

  void joinChannel(String channelId) {
    send('join_channel', {'channel_id': channelId});
  }

  void editMessage(String messageId, String content) {
    send('edit_message', {
      'message_id': messageId,
      'content': content,
    });
  }

  void deleteMessage(String messageId) {
    send('delete_message', {'message_id': messageId});
  }

  void sendTyping(String channelId) {
    send('typing', {'channel_id': channelId});
  }

  void addReaction(String messageId, String emoji) {
    send('reaction_add', {'message_id': messageId, 'emoji': emoji});
  }

  void removeReaction(String messageId, String emoji) {
    send('reaction_remove', {'message_id': messageId, 'emoji': emoji});
  }

  void updateVoiceState(String channelId, {bool muted = false, bool deafened = false}) {
    send('voice_state_update', {
      'channel_id': channelId,
      'muted': muted,
      'deafened': deafened,
    });
  }

  void sendWebRTC(String channelId, String type, dynamic data, String targetId) {
    send('webrtc', {
      'channel_id': channelId,
      'type': type,
      'data': data,
      'target_id': targetId,
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
