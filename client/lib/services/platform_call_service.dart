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

  static Future<void> showIncomingCall(String callerName, String callerId) async {
    try {
      await _channel.invokeMethod('showIncomingCall', {
        'callerName': callerName,
        'callerId': callerId,
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
}
