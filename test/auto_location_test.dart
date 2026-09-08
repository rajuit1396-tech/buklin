import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:buklin/work_location.dart';

class FakeGps extends GeolocatorPlatform {
  int requests = 0;
  final updates = StreamController<Position>();
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    requests++;
    return Position(latitude: 24.5, longitude: 46.7, timestamp: DateTime.now(),
      accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0,
      speed: 0, speedAccuracy: 0);
  }
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => updates.stream;
}

void main() {
  testWidgets('accepted operator automatically publishes GPS and cancels on close', (tester) async {
    final original = GeolocatorPlatform.instance;
    final gps = FakeGps();
    GeolocatorPlatform.instance = gps;
    addTearDown(() async { GeolocatorPlatform.instance = original; await gps.updates.close(); });
    final job = <String,dynamic>{'id':'demo','operator_id':'demo-operator','status':'accepted'};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkLocation(job:job,isOperator:true,connected:false))));
    await tester.pump();
    await tester.pump();
    expect(gps.requests, 1);
    expect(job['demo_position']['lat'], 24.5);
    expect(find.text('Stop location sharing'), findsNothing);
    expect(find.text('Live location sharing is active'), findsOneWidget);
    expect(gps.updates.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(gps.updates.hasListener, isFalse);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkLocation(job:job,isOperator:false,connected:false))));
    await tester.pump();
    expect(gps.requests, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
