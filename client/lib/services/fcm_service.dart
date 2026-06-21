import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'ws_service.dart';
import 'call_service.dart';
import 'platform_call_service.dart';

class FcmService {
  final WsService _ws;
  final CallService _call;

  FcmService(this._ws, this._call);

  static Future<void> init() async {
    if (Platform.isAndroid) {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
      );
      messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<String?> getToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      return token;
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  Future<bool> registerToken(String token) async {
    try {
      await ApiService.post('/api/fcm/register', {'token': token});
      return true;
    } catch (e) {
      debugPrint('FCM register error: $e');
      return false;
    }
  }

  void setupListeners() {
    final messaging = FirebaseMessaging.instance;

    // App was killed and opened from notification
    messaging.getInitialMessage().then((msg) {
      if (msg != null) handleMessage(msg.data);
    });

    // App was in background and notification was tapped
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      handleMessage(msg.data);
    });

    // App is in foreground and push arrives
    FirebaseMessaging.onMessage.listen((msg) {
      handleMessage(msg.data);
    });
  }

  void handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type != 'call_offer') return;

    final fromId = data['from_id'] as String?;
    final channelId = data['channel_id'] as String?;
    final callerName = data['caller_name'] as String? ?? '';

    if (fromId == null || channelId == null) return;

    // FCM push arrived — show incoming call notification via platform channel.
    // The WebSocket may reconnect later and deliver the full offer.
    PlatformCallService.showIncomingCall(callerName, fromId);

    // Also notify CallService so it can prepare state.
    _call.prepareIncoming(fromId, channelId, callerName);
  }
}
