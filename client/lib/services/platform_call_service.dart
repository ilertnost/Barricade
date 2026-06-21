import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformCallService {
  static const _channel = MethodChannel('barricade/call');

  static Future<void> startCallService() async {
    try {
      await _channel.invokeMethod('startCallService');
    } catch (e) {
      debugPrint('startCallService error: $e');
    }
  }

  static Future<void> stopCallService() async {
    try {
      await _channel.invokeMethod('stopCallService');
    } catch (e) {
      debugPrint('stopCallService error: $e');
    }
  }

  static Future<void> showIncomingCall(String callerName, String callerId, {String channelId = ''}) async {
    try {
      await _channel.invokeMethod('showIncomingCall', {
        'callerName': callerName,
        'callerId': callerId,
        'channelId': channelId,
      });
    } catch (e) {
      debugPrint('showIncomingCall error: $e');
    }
  }

  static Future<void> cancelIncomingNotification() async {
    try {
      await _channel.invokeMethod('cancelIncomingNotification');
    } catch (e) {
      debugPrint('cancelIncomingNotification error: $e');
    }
  }

  static Future<Map<String, dynamic>> getLaunchData() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getLaunchData');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('getLaunchData error: $e');
      return {};
    }
  }

  static Future<void> playRingtone() async {
    try {
      await _channel.invokeMethod('playRingtone');
    } catch (e) {
      debugPrint('playRingtone error: $e');
    }
  }

  static Future<void> stopRingtone() async {
    try {
      await _channel.invokeMethod('stopRingtone');
    } catch (e) {
      debugPrint('stopRingtone error: $e');
    }
  }
}
