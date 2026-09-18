import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class WorkAlerts {
  static Timer? _repeat;
  static final _requests = <String>{};

  static Future<void> startIncomingRequestAlert(String id) async {
    _requests.add(id);
    if (_repeat != null) return;
    _repeat = Timer.periodic(const Duration(seconds: 3), (_) {
      playIncomingRequestAlert();
    });
    await playIncomingRequestAlert();
  }

  static Future<void> stopIncomingRequestAlert([String? id]) async {
    if (id == null) {
      _requests.clear();
    } else {
      _requests.remove(id);
    }
    if (_requests.isNotEmpty) return;
    _repeat?.cancel();
    _repeat = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await const MethodChannel('buklin/work_alerts')
            .invokeMethod<void>('stop');
      } catch (_) {}
    }
  }

  static void retainIncomingRequests(Set<String> ids) {
    _requests.removeWhere((id) => !ids.contains(id));
    if (_requests.isEmpty && _repeat != null) stopIncomingRequestAlert();
  }

  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID');
  static bool initialized = false;
  static VoidCallback? onNotificationOpen;
  static bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      appId.isNotEmpty;

  static Future<void> playIncomingRequestAlert() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await const MethodChannel('buklin/work_alerts')
            .invokeMethod<void>('play');
        return;
      } catch (_) {}
    }
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.vibrate();
    } catch (_) {}
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  static void connect(String userId, VoidCallback onOpen) {
    if (!supported) return;
    onNotificationOpen = onOpen;
    if (!initialized) {
      OneSignal.initialize(appId);
      OneSignal.Notifications.addClickListener((event) {
        onNotificationOpen?.call();
      });
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        if (event.notification.additionalData?['job_id'] != null) {
          // The refreshed job list plays the alert once per new request.
          event.preventDefault();
          onNotificationOpen?.call();
        }
      });
      initialized = true;
    }
    OneSignal.login(userId);
  }

  static Future<String> enable() async {
    if (!supported) {
      return 'Phone alerts need the configured Android app. Chrome preview uses the incoming work screen.';
    }
    final allowed = await OneSignal.Notifications.requestPermission(true);
    return allowed
        ? 'Phone notifications enabled. Go online to receive work.'
        : 'Notifications are blocked. Enable them in phone settings.';
  }

  static Future<void> disconnect() async {
    await stopIncomingRequestAlert();
    onNotificationOpen = null;
    if (initialized) await OneSignal.logout();
  }
}
