import 'package:buklin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class CustomerGps extends GeolocatorPlatform {
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    requests++;
    return Position(
        latitude: 24.5,
        longitude: 46.7,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);
  }
}

void main() {
  testWidgets('search automatically captures customer GPS location',
      (tester) async {
    final original = GeolocatorPlatform.instance;
    final gps = CustomerGps();
    GeolocatorPlatform.instance = gps;
    addTearDown(() => GeolocatorPlatform.instance = original);
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: WorkApp()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next: loading vehicle'), 300);
    await tester.tap(find.text('Next: loading vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trailer'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount you want to give'), '250');
    await tester.tap(find.text('Next: work location'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Store number'), '007');
    await tester.scrollUntilVisible(find.text('Search for an operator'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Search for an operator'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gps.requests, 1);
    expect(find.text('Your work order'), findsOneWidget);
    expect(find.textContaining('Pinned work site: 24.5, 46.7'), findsOneWidget);
  });
}
