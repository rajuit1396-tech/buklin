import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_login.dart';
import 'site_picker.dart';
import 'work_location.dart';

void main() => runApp(const BuklinApp());

String? amountError(String? value) {
  if (value == null || !RegExp(r'^[1-9][0-9]{1,2}$').hasMatch(value)) {
    return 'Enter a whole amount from 30 to 999';
  }
  final number = int.parse(value);
  return number < 30 || number > 999
      ? 'Enter a whole amount from 30 to 999'
      : null;
}

class BuklinApp extends StatelessWidget {
  const BuklinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Buklin',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      scaffoldBackgroundColor: const Color(0xfff4f7f5),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
      ),
      useMaterial3: true,
    ),
    home: const WorkApp(),
  );
}

class WorkApp extends StatefulWidget {
  const WorkApp({super.key, this.preferences});
  final SharedPreferences? preferences;
  @override
  State<WorkApp> createState() => _WorkAppState();
}

class _WorkAppState extends State<WorkApp> {
  static const equipment = [
    ('5-finger excavator grapple', Icons.front_loader),
    ('Pickup van', Icons.local_shipping_outlined),
    ('Big truck', Icons.fire_truck_outlined),
  ];
  static const loadingOptions = ['Dyna', 'Trailer', 'Inside store'];
  final amount = TextEditingController(), store = TextEditingController();
  final form = GlobalKey<FormState>();
  SharedPreferences? prefs;
  int page = 0, selected = 0;
  String? loading;
  double? latitude, longitude;
  List<Map<String, dynamic>> jobs = [];
  bool showAmountError = false;

  @override
  void initState() {
    super.initState();
    amount.addListener(_save);
    store.addListener(_save);
    _restore();
  }

  Future<void> _restore() async {
    prefs = widget.preferences ?? await SharedPreferences.getInstance();
    final raw = prefs!.getString('work-demo');
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        page = (data['page'] as num?)?.toInt().clamp(0, 2) ?? 0;
        selected = (data['selected'] as num?)?.toInt().clamp(0, 2) ?? 0;
        loading = data['loading'] as String?;
        latitude = (data['site_lat'] as num?)?.toDouble();
        longitude = (data['site_lng'] as num?)?.toDouble();
        jobs =
            (data['jobs'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final fields =
            (data['fields'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (fields.isNotEmpty) amount.text = fields[0];
        if (fields.length > 1) store.text = fields[1];
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (prefs == null) return;
    await prefs!.setString(
      'work-demo',
      jsonEncode({
        'page': page,
        'selected': selected,
        'loading': loading,
        'operator': false,
        'online': false,
        'balance': 0,
        'blocked': null,
        'hidden': [],
        'demoBlocks': {},
        'fields': [amount.text, store.text, '', '', '', ''],
        'site_lat': latitude,
        'site_lng': longitude,
        'jobs': jobs,
      }),
    );
  }

  void _go(int value) {
    setState(() => page = value);
    _save();
  }

  @override
  void dispose() {
    amount.removeListener(_save);
    store.removeListener(_save);
    amount.dispose();
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? active;
    for (final job in jobs) {
      if (!['completed', 'cancelled'].contains(job['status'])) {
        active = job;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(
        leading: page > 0 && active == null
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => _go(page - 1),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: const Row(
          children: [
            Icon(Icons.construction),
            SizedBox(width: 9),
            Text(
              'BUKLIN',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AdminLogin())),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Admin panel'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: active != null
          ? _activeJob(active)
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _progress(),
                        const SizedBox(height: 22),
                        if (page == 0) _equipmentPage(),
                        if (page == 1) _loadingPage(),
                        if (page == 2) _locationPage(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _progress() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Step ${page + 1} of 3',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: (page + 1) / 3,
        minHeight: 7,
        borderRadius: BorderRadius.circular(8),
      ),
    ],
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.black54),
        ),
      ],
    ),
  );
  Widget _equipmentPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'What equipment do you need?',
        'Choose the machine or vehicle for this job.',
      ),
      ...List.generate(
        equipment.length,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              selected: selected == index,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              leading: Icon(equipment[index].$2, size: 34),
              title: Text(
                equipment[index].$1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: selected == index
                  ? const Icon(Icons.check_circle)
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                setState(() => selected = index);
                _save();
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _go(1),
        icon: const Icon(Icons.arrow_forward),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('Next: loading vehicle'),
        ),
      ),
    ],
  );
  Widget _loadingPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'How will it be loaded?',
        'Select one loading option and enter your offer.',
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: loadingOptions
            .map(
              (value) => ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Text(value),
                ),
                selected: loading == value,
                onSelected: (_) {
                  setState(() => loading = value);
                  _save();
                },
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 24),
      TextFormField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        decoration: InputDecoration(
          labelText: 'Amount you want to give',
          errorText: showAmountError ? 'Enter 30–999 Riyal' : null,
          suffixText: 'Riyal',
          prefixIcon: const Icon(Icons.payments_outlined),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: loading == null ? null : _continueToLocation,
        icon: const Icon(Icons.arrow_forward),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('Next: work location'),
        ),
      ),
    ],
  );
  void _continueToLocation() {
    if (amountError(amount.text) != null) {
      setState(() => showAmountError = true);
      return;
    }
    showAmountError = false;
    _go(2);
  }

  Widget _locationPage() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Where is the work?',
          '${equipment[selected].$1} • ${loading ?? ''}',
        ),
        TextFormField(
          controller: store,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(
            labelText: 'Store number',
            hintText: '007',
            prefixIcon: Icon(Icons.store_outlined),
          ),
          validator: (value) => RegExp(r'^\d{3}$').hasMatch(value ?? '')
              ? null
              : 'Enter exactly 3 digits',
        ),
        const SizedBox(height: 20),
        SitePicker(
          initialLatitude: latitude,
          initialLongitude: longitude,
          onChanged: (point) {
            latitude = point.latitude;
            longitude = point.longitude;
            _save();
          },
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.search),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Search for an operator'),
          ),
        ),
      ],
    ),
  );
  void _search() {
    final valid = form.currentState!.validate(),
        offerProblem = amountError(amount.text);
    if (!valid ||
        offerProblem != null ||
        latitude == null ||
        longitude == null) {
      final message =
          offerProblem ??
          (latitude == null ? 'Choose the work location on the map.' : null);
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    setState(
      () => jobs = [
        {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'status': 'waiting',
          'service': equipment[selected].$1,
          'loading_vehicle': loading,
          'offer': int.parse(amount.text),
          'store_number': store.text,
          'site_lat': latitude,
          'site_lng': longitude,
          'address': 'Selected work site',
        },
      ],
    );
    _save();
  }

  Widget _activeJob(Map<String, dynamic> job) {
    final working = job['status'] == 'working';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              working ? Icons.engineering : Icons.manage_search,
              size: 62,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              working ? 'Work in progress' : 'Searching for an operator',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${job['service'] ?? 'Equipment'} • ${job['loading_vehicle'] ?? ''}',
              textAlign: TextAlign.center,
            ),
            if (working || ['accepted', 'on_the_way'].contains(job['status']))
              WorkLocation(job: job, isOperator: false, connected: false),
            const SizedBox(height: 24),
            if (job['status'] == 'waiting')
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    jobs = [];
                    page = 2;
                  });
                  _save();
                },
                child: const Text('Cancel request'),
              ),
          ],
        ),
      ),
    );
  }
}
