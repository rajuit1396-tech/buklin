import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'work_location.dart';

class SitePicker extends StatefulWidget {
  const SitePicker({super.key, this.initialLatitude, this.initialLongitude, required this.onChanged});
  final double? initialLatitude, initialLongitude;
  final ValueChanged<LatLng> onChanged;
  @override
  State<SitePicker> createState() => _SitePickerState();
}

class _SitePickerState extends State<SitePicker> {
  final controller = MapController();
  LatLng? chosen;
  bool locating = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      chosen = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }
  void choose(LatLng point) {
    setState(() { chosen = point; error = null; });
    widget.onChanged(point);
  }
  Future<void> locate() async {
    setState(() { locating = true; error = null; });
    try {
      final position = await currentPosition();
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      controller.move(point, 17);
      choose(point);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not get GPS. Allow location access, or drag the map to your work site.');
    } finally { if (mounted) setState(() => locating = false); }
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('Drag the map to place the pin at your work site.'),
    const SizedBox(height: 12),
    ClipRRect(borderRadius: BorderRadius.circular(20), child: SizedBox(
      height: 380, child: Stack(alignment: Alignment.center, children: [
        FlutterMap(mapController: controller, options: MapOptions(
          initialCenter: chosen ?? const LatLng(20, 0), initialZoom: chosen == null ? 2 : 16,
          onPositionChanged: (camera, gesture) { if (gesture) choose(camera.center); },
          onTap: (_, point) { controller.move(point, controller.camera.zoom); choose(point); },
        ), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.buklin'),
          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors',
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))]),
        ]),
        const IgnorePointer(child: Padding(padding: EdgeInsets.only(bottom: 42),
          child: Icon(Icons.location_pin, color: Colors.deepOrange, size: 48))),
      ]))),
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: locating ? null : locate,
      icon: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.my_location),
      label: Text(locating ? 'Finding your location…' : 'Use my exact location')),
    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
    Text(chosen == null ? 'Choose a location to continue.' : 'Work-site pin selected. Drag to adjust.'),
  ]);
}
