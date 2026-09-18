import 'package:buklin/work_alerts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repeats until every pending request is dismissed or removed',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('buklin/work_alerts');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() async {
      await WorkAlerts.stopIncomingRequestAlert();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await WorkAlerts.startIncomingRequestAlert('one');
    await WorkAlerts.startIncomingRequestAlert('two');
    expect(calls, ['play']);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, ['play', 'play']);
    await WorkAlerts.stopIncomingRequestAlert('one');
    await tester.pump(const Duration(seconds: 3));
    expect(calls.last, 'play');
    WorkAlerts.retainIncomingRequests({});
    await tester.pump();
    expect(calls.last, 'stop');
    final count = calls.length;
    await tester.pump(const Duration(seconds: 9));
    expect(calls.length, count);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'Android incoming alerts use native sound and vibration without push configuration',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('buklin/work_alerts');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await WorkAlerts.playIncomingRequestAlert();
    expect(calls, ['play']);
  });
}
