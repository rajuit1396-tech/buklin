import 'app_language.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'backend_api.dart';
import 'package:url_launcher/url_launcher.dart';

String? coordinateError(String? value, int bound) {
  final n = double.tryParse(value ?? '');
  return n == null || !n.isFinite || n.abs() > bound
      ? 'Enter a coordinate between -$bound and $bound'
      : null;
}

Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
    throw Exception('Turn on phone location services, then try again.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied)
    permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    throw Exception(
        'Location permission is blocked. Allow it in Buklin app settings, then try again.');
  }
  if (permission == LocationPermission.denied) {
    throw Exception(
        'Location permission is required. Tap again and choose Allow.');
  }
  return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
}

class WorkLocation extends StatefulWidget {
  const WorkLocation(
      {super.key,
      required this.job,
      required this.isOperator,
      required this.connected});
  final Map<String, dynamic> job;
  final bool isOperator, connected;
  @override
  State<WorkLocation> createState() => _WorkLocationState();
}

class _WorkLocationState extends State<WorkLocation> {
  Timer? timer;
  StreamSubscription<Position>? gps;
  Map<String, dynamic>? site, position;
  bool sharing = false, sending = false, starting = false;
  String? error;
  final map = MapController();
  BackendApi get db => BackendApi.instance;
  @override
  void initState() {
    super.initState();
    if (!widget.connected) {
      site = {
        'lat': widget.job['site_lat'],
        'lng': widget.job['site_lng'],
        'address': widget.job['address']
      };
      position = widget.job['demo_position'];
    }
    refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    if (widget.isOperator &&
        widget.job['operator_id'] ==
            (widget.connected ? (db.user?['id']) : 'demo-operator') &&
        ['accepted', 'on_the_way', 'working'].contains(widget.job['status'])) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) start();
      });
    }
  }

  Future<void> refresh() async {
    if (!widget.connected) {
      if (mounted) setState(() => position = widget.job['demo_position']);
      return;
    }
    try {
      final result = await db.call('GET', '/jobs/${widget.job['id']}/location');
      if (mounted)
        setState(() {
          site = Map<String, dynamic>.from(result['site']);
          position = result['position'] == null
              ? null
              : Map<String, dynamic>.from(result['position']);
        });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Location connection interrupted. Retrying.');
    }
  }

  Future<void> send(Position p) async {
    if (sending || !mounted) return;
    sending = true;
    try {
      if (widget.connected) {
        await db.call('PUT', '/jobs/${widget.job['id']}/location',
            {'lat': p.latitude, 'lng': p.longitude});
      } else {
        widget.job['demo_position'] = {
          'lat': p.latitude,
          'lng': p.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String()
        };
      }
      await refresh();
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Location update failed. Check your connection.');
    } finally {
      sending = false;
    }
  }

  Future<void> start() async {
    if (starting || sharing) return;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      final p = await currentPosition();
      if (!mounted) return;
      await gps?.cancel();
      if (!mounted) return;
      await send(p);
      if (!mounted) return;
      final LocationSettings settings = !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'Buklin work location',
                  notificationText: 'Sharing your location with your customer',
                  enableWakeLock: true))
          : const LocationSettings(
              accuracy: LocationAccuracy.high, distanceFilter: 0);
      gps = Geolocator.getPositionStream(locationSettings: settings)
          .listen(send, cancelOnError: true, onDone: () {
        if (mounted) setState(() => sharing = false);
      }, onError: (_) {
        if (mounted)
          setState(() {
            error = 'GPS stopped. Check permissions and restart sharing.';
            sharing = false;
          });
      });
      setState(() => sharing = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    gps?.cancel();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = site;
    final p = position;
    final hasSite = s?['lat'] != null && s?['lng'] != null;
    final target = hasSite
        ? LatLng((s!['lat'] as num).toDouble(), (s['lng'] as num).toDouble())
        : null;
    final operatorPoint = p == null
        ? null
        : LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    final updated = DateTime.tryParse(p?['updated_at'] ?? '');
    final stale =
        updated == null || DateTime.now().difference(updated).inSeconds > 30;
    final arrived = !stale &&
        target != null &&
        operatorPoint != null &&
        Geolocator.distanceBetween(target.latitude, target.longitude,
                operatorPoint.latitude, operatorPoint.longitude) <=
            100;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),
      if (error != null)
        AppText(error!, style: const TextStyle(color: Colors.red)),
      if (operatorPoint != null)
        AppText(arrived
            ? 'Arrived at the work site'
            : 'Arrival not confirmed • A recent location within 100 metres is required'),
      if (!hasSite) const AppText('Waiting for the work location…'),
      if (target != null) ...[
        if (s?['address'] != null)
          AppText('Work site: {address}', values: {'address': s!['address']}),
        SizedBox(
            height: 250,
            child: FlutterMap(
                mapController: map,
                options: MapOptions(
                    initialCenter: operatorPoint ?? target, initialZoom: 14),
                children: [
                  TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.buklin'),
                  MarkerLayer(markers: [
                    Marker(
                        point: target,
                        child: Tooltip(
                            message: tr(context, 'Work site'),
                            child: const Icon(Icons.location_on,
                                color: Colors.deepOrange, size: 38))),
                    if (operatorPoint != null)
                      Marker(
                          point: operatorPoint,
                          child: Tooltip(
                              message: tr(context, 'Operator'),
                              child: const Icon(Icons.local_shipping,
                                  color: Colors.blue, size: 32))),
                  ]),
                  RichAttributionWidget(attributions: [
                    TextSourceAttribution('OpenStreetMap contributors',
                        onTap: () => launchUrl(Uri.parse(
                            'https://www.openstreetmap.org/copyright')))
                  ]),
                ])),
        const AppText('Orange: work site • Blue: operator'),
        if (operatorPoint != null)
          TextButton(
              onPressed: () => map.move(operatorPoint, 15),
              child: const AppText('Center on operator')),
        if (widget.isOperator)
          TextButton.icon(
              onPressed: () async {
                final uri = Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  'destination': '${target.latitude},${target.longitude}',
                  'travelmode': 'driving'
                });
                if (!await launchUrl(uri,
                        mode: LaunchMode.externalApplication) &&
                    mounted)
                  setState(() => error = 'Could not open navigation.');
              },
              icon: const Icon(Icons.navigation),
              label: const AppText('Navigate to work site')),
      ],
      AppText(
          p == null
              ? 'Waiting for operator to share location.'
              : stale
                  ? 'Last known location (not live) • {time}'
                  : 'Location recently updated • {time}',
          values: {'time': updated?.toLocal()}),
      if (widget.isOperator) ...[
        const AppText(
            'Location sharing starts automatically after acceptance. Allow location access so your customer can follow you. Sharing stops when this job screen closes or the job completes.'),
        if (sharing)
          const AppText('Live location sharing is active')
        else
          TextButton(
              onPressed: starting ? null : start,
              child: AppText(
                  starting ? 'Getting GPS…' : 'Retry live location sharing')),
      ],
    ]);
  }
}
