import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class WorkAlerts {
  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID');
  static bool initialized = false;
  static VoidCallback? onNotificationOpen;
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && appId.isNotEmpty;
  static void connect(String userId, VoidCallback onOpen) {
    if (!supported) return;
    onNotificationOpen = onOpen;
    if (!initialized) {
      OneSignal.initialize(appId);
      OneSignal.Notifications.addClickListener((_) => onNotificationOpen?.call());
      initialized = true;
    }
    OneSignal.login(userId);
  }
  static Future<String> enable() async {
    if (!supported) return 'Phone alerts need the configured Android app. Chrome preview uses the incoming work screen.';
    final allowed = await OneSignal.Notifications.requestPermission(true);
    return allowed ? 'Phone notifications enabled. Go online to receive work.' : 'Notifications are blocked. Enable them in phone settings.';
  }
  static Future<void> disconnect() async {
    onNotificationOpen = null;
    if (initialized) await OneSignal.logout();
  }
}
