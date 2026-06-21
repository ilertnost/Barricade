import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/models.dart';

class ApiService {
  static String? _token;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<bool> isLoggedIn() async {
    await init();
    return _token != null;
  }

  static Future<Map<String, String>> headers() async {
    return {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  static Future<Map<String, dynamic>> register(String username, String password, {String? deviceId, String? recoveryPhrase}) async {
    final body = <String, dynamic>{'username': username, 'password': password};
    if (deviceId != null) body['device_id'] = deviceId;
    if (recoveryPhrase != null && recoveryPhrase.isNotEmpty) body['recovery_phrase'] = recoveryPhrase;
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 201) {
      _token = data['token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
    }
    return data;
  }

  static Future<bool> checkDevice(String deviceId) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/auth/check-device'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId}),
    );
    final data = jsonDecode(res.body);
    return data['registered'] == true;
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) {
      _token = body['token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
    }
    return body;
  }

  static Future<Map<String, dynamic>> resetPassword(String username, String recoveryPhrase, String newPassword) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'recovery_phrase': recoveryPhrase,
        'new_password': newPassword,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/auth/change-password'),
      headers: await headers(),
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<User> getMe() async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/users/@me'),
      headers: await headers(),
    );
    return User.fromJson(jsonDecode(res.body));
  }

  static Future<User> getUser(String userId) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/users/$userId'),
      headers: await headers(),
    );
    return User.fromJson(jsonDecode(res.body));
  }

  static Future<List<User>> getUsers({String? query}) async {
    final uri = Uri.parse('${Config.serverUrl}/api/users')
        .replace(queryParameters: query != null ? {'q': query} : null);
    final res = await http.get(uri, headers: await headers());
    final list = jsonDecode(res.body) as List;
    return list.map((e) => User.fromJson(e)).toList();
  }

  static Future<Channel> createChannel(String name, String type, List<String> memberIds,
      {String? username, String visibility = 'public'}) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      'member_ids': memberIds,
      'visibility': visibility,
    };
    if (username != null && username.isNotEmpty) body['username'] = username;
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/channels'),
      headers: await headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) {
      final b = jsonDecode(res.body);
      throw Exception(b['error'] ?? 'failed to create channel');
    }
    return Channel.fromJson(jsonDecode(res.body));
  }

  static Future<List<Member>> getMembers(String channelId) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/members'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body);
    if (list == null) return [];
    return (list as List).map((e) => Member.fromJson(e)).toList();
  }

  static Future<Channel?> findExistingDm(List<Channel> channels, String peerId) async {
    for (final ch in channels.where((c) => c.type == 'dm')) {
      try {
        final members = await getMembers(ch.id);
        if (members.any((m) => m.id == peerId)) return ch;
      } catch (_) {}
    }
    return null;
  }

  static Future<List<Message>> getChannelMedia(String channelId, String kind, {String? before}) async {
    final uri = Uri.parse('${Config.serverUrl}/api/channels/$channelId/media')
        .replace(queryParameters: {'kind': kind, if (before != null) 'before': before});
    final res = await http.get(uri, headers: await headers());
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body);
    if (list == null) return [];
    return (list as List).map((e) => Message.fromJson(e)).toList();
  }

  static Future<Channel?> joinChannel(String channelId) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/join'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return null;
    return Channel.fromJson(jsonDecode(res.body));
  }

  static Future<bool> addMember(String channelId, String userId) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/members'),
      headers: await headers(),
      body: jsonEncode({'user_id': userId}),
    );
    return res.statusCode == 200;
  }

  static Future<bool> removeMember(String channelId, String userId) async {
    final res = await http.delete(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/members/$userId'),
      headers: await headers(),
    );
    return res.statusCode == 200;
  }

  static Future<bool> setMemberRole(String channelId, String userId, String role) async {
    final res = await http.patch(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/members/$userId'),
      headers: await headers(),
      body: jsonEncode({'role': role}),
    );
    return res.statusCode == 200;
  }

  static Future<List<Channel>> getChannels() async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/channels'),
      headers: await headers(),
    );
    final decoded = jsonDecode(res.body);
    if (decoded == null) return [];
    return (decoded as List).map((e) => Channel.fromJson(e)).toList();
  }

  static Future<List<Message>> getMessages(String channelId, {String? before}) async {
    final uri = Uri.parse('${Config.serverUrl}/api/channels/$channelId/messages')
        .replace(queryParameters: before != null ? {'before': before} : null);
    final res = await http.get(uri, headers: await headers());
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Message.fromJson(e)).toList();
  }

  static Future<User> updateProfile({String? username, String? displayName, String? avatarId}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (displayName != null) body['display_name'] = displayName;
    if (avatarId != null) body['avatar_id'] = avatarId;
    final res = await http.patch(
      Uri.parse('${Config.serverUrl}/api/users/@me'),
      headers: await headers(),
      body: jsonEncode(body),
    );
    return User.fromJson(jsonDecode(res.body));
  }

  static Future<Map<String, dynamic>> searchAll(String query) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/search').replace(queryParameters: {'q': query}),
      headers: await headers(),
    );
    return jsonDecode(res.body);
  }

  static Future<void> deleteChannel(String channelId) async {
    final res = await http.delete(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId'),
      headers: await headers(),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'delete failed');
    }
  }

  static Future<Channel> updateChannelSettings(String channelId, {String? visibility, String? name, String? username}) async {
    final body = <String, dynamic>{};
    if (visibility != null) body['visibility'] = visibility;
    if (name != null) body['name'] = name;
    if (username != null) body['username'] = username;
    final res = await http.patch(
      Uri.parse('${Config.serverUrl}/api/channels/$channelId/settings'),
      headers: await headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final b = jsonDecode(res.body);
      throw Exception(b['error'] ?? 'failed');
    }
    return Channel.fromJson(jsonDecode(res.body));
  }

  static Future<Map<String, dynamic>> uploadFile(
    String path,
    String filename, {
    int? width,
    int? height,
    double? durationSec,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.serverUrl}/api/files/upload'),
    );
    req.headers['Authorization'] = 'Bearer $_token';
    // Optional media metadata — computed client-side and stored by the server.
    if (width != null) req.fields['width'] = '$width';
    if (height != null) req.fields['height'] = '$height';
    if (durationSec != null) req.fields['duration'] = '$durationSec';
    req.files.add(await http.MultipartFile.fromPath('file', path, filename: filename));
    final res = await req.send();
    final body = jsonDecode(await res.stream.bytesToString());
    return body;
  }

  static String getFileUrl(String fileId) {
    final url = '${Config.serverUrl}/api/files/$fileId';
    if (_token != null) return '$url?token=$_token';
    return url;
  }

  static Future<FileInfo?> getFileInfo(String fileId) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/files/$fileId/info'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return null;
    return FileInfo.fromJson(jsonDecode(res.body));
  }

  static Future<void> blockUser(String userId) async {
    await http.post(
      Uri.parse('${Config.serverUrl}/api/blacklist/$userId'),
      headers: await headers(),
    );
  }

  static Future<void> unblockUser(String userId) async {
    await http.delete(
      Uri.parse('${Config.serverUrl}/api/blacklist/$userId'),
      headers: await headers(),
    );
  }

  static Future<List<User>> getBlacklist() async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/blacklist'),
      headers: await headers(),
    );
    final list = jsonDecode(res.body) as List;
    return list.map((e) => User.fromJson(e)).toList();
  }

  static Future<bool> isBlockedBy(String userId) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/blacklist/$userId/blocked-by'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body);
    return data['blocked'] == true;
  }

  static Future<List<Map<String, dynamic>>> getContacts() async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/contacts'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return [];
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> addContact(String userId, {String? displayName}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    await http.post(
      Uri.parse('${Config.serverUrl}/api/contacts/$userId'),
      headers: await headers(),
      body: jsonEncode(body),
    );
  }

  static Future<void> removeContact(String userId) async {
    await http.delete(
      Uri.parse('${Config.serverUrl}/api/contacts/$userId'),
      headers: await headers(),
    );
  }

  static Future<bool> isContact(String userId) async {
    final res = await http.get(
      Uri.parse('${Config.serverUrl}/api/contacts/$userId/check'),
      headers: await headers(),
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body);
    return data['contact'] == true;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('${Config.serverUrl}$path'),
      headers: await headers(),
      body: jsonEncode(body),
    );
    return jsonDecode(res.body);
  }

  static String? get token => _token;

  static String? get currentUserId {
    if (_token == null) return null;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final data = jsonDecode(payload);
      return data['user_id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
