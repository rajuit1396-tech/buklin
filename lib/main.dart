import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'backend_api.dart';
import 'package:flutter/services.dart';
import 'work_location.dart';
import 'site_picker.dart';
import 'work_alerts.dart';
import 'admin_panel.dart';
import 'admin_login.dart';

const services = ['5-finger excavator grapple', 'Pickup van', 'Big truck'];
const serviceImages = ['assets/grapple.png', 'assets/pickup.png', 'assets/truck.png'];
const live = backendUrl != '';

String? amountError(String? value) {
  final text = value?.trim() ?? '';
  if (!RegExp(r'^(?:[3-9][0-9]|[1-9][0-9]{2})$').hasMatch(text)) {
    return 'Enter 30–999 Riyal';
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  if (live) await BackendApi.instance.restoreSession();
  runApp(MaterialApp(title: 'Buklin', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEA640D)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F1),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF24282B), foregroundColor: Colors.white, minimumSize: const Size(48, 52)))),
    home: WorkApp(preferences: preferences)));
}

class WorkApp extends StatefulWidget {
  const WorkApp({super.key, this.preferences});
  final SharedPreferences? preferences;
  @override
  State<WorkApp> createState() => _WorkAppState();
}

class _WorkAppState extends State<WorkApp> with WidgetsBindingObserver {
  String get stateKey => live ? 'work-$backendUrl-${db.user?['id'] ?? 'guest'}' : 'work-demo';
  Future<void> pendingSave = Future.value();
  bool restoring = true;
  List<TextEditingController> get draftFields => [offeredAmount, storeNumber, address, details, latitude, longitude];
  void saveState() {
    if (restoring || widget.preferences == null) return;
    final key = stateKey;
    final snapshot = jsonEncode({'page': page, 'selected': selected, 'loading': loadingVehicle,
      'operator': operator, 'online': online, 'jobs': jobs, 'balance': balance,
      'blocked': blockedUntil?.toIso8601String(), 'hidden': hidden.toList(),
      'demoBlocks': demoBlocks.map((k,v) => MapEntry(k.toString(), v.toIso8601String())),
      'fields': draftFields.map((c) => c.text).toList()});
    pendingSave = pendingSave.then((_) async { await widget.preferences!.setString(key, snapshot); })
      .catchError((Object _) { });
  }
  void restoreWork() {
    final raw = widget.preferences?.getString(stateKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      page = (data['page'] as int).clamp(0, 2);
      selected = (data['selected'] as int).clamp(0, services.length - 1);
      loadingVehicle = data['loading'];
      operator = live ? (db.user?['role'] == 'operator') : data['operator'] == true;
      online = data['online'] == true;
      jobs = (data['jobs'] as List).map((j) => Map<String,dynamic>.from(j)).toList();
      balance = data['balance'] as int;
      blockedUntil = DateTime.tryParse(data['blocked'] ?? '');
      hidden.addAll(List<String>.from(data['hidden']));
      (data['demoBlocks'] as Map).forEach((k,v) => demoBlocks[k == 'true'] = DateTime.parse(v));
      final fields = List<String>.from(data['fields']);
      for (var i = 0; i < draftFields.length; i++) { draftFields[i].text = fields[i]; }
    } catch (_) { message = 'Saved screen could not be restored. Your online work will be refreshed.'; }
  }
  @override
  void setState(VoidCallback fn) { super.setState(fn); saveState(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    saveState();
    if (state == AppLifecycleState.resumed && live && signedIn) connect();
  }
  final address = TextEditingController(), details = TextEditingController();
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  final amountForm = GlobalKey<FormState>();
  final offeredAmount = TextEditingController();
  final latitude = TextEditingController(), longitude = TextEditingController();
  static const loadingVehicles = ['Dyna', 'Trailer', 'Inside store'];
  final storeNumber = TextEditingController();
  String? loadingVehicle;
  int page = 0;
  final scroll = ScrollController();
  void goToPage(int value) {
    setState(() => page = value);
    if (scroll.hasClients) scroll.jumpTo(0);
  }
  void returnHomeAfterWork() {
    setState(() {
      page = 0;
      selected = 0;
      loadingVehicle = null;
      for (final controller in [offeredAmount, storeNumber, address, details, latitude, longitude]) {
        controller.clear();
      }
      message = 'Work completed.';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }
  final hidden = <String>{};
  List<Map<String, dynamic>> jobs = [];
  int selected = 0;
  int balance = 0;
  int get availableBalance => live ? balance
    : balance - 4 * jobs.where((j) => j['status'] == 'completed').length;
  DateTime? blockedUntil;
  final demoBlocks = <bool, DateTime>{};
  DateTime? get restrictionEnd => live ? blockedUntil : demoBlocks[operator];
  bool get restricted => restrictionEnd?.isAfter(DateTime.now()) ?? false;
  bool operator = false, online = false, busy = false, refreshing = false;
  String? message;
  Timer? poll;
  StreamSubscription<dynamic>? channel;
  BackendApi get db => BackendApi.instance;
  bool get signedIn => !live || db.user != null;
  String get userId => live ? db.user!['id'] as String : 'demo-customer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreWork();
    restoring = false;
    for (final controller in draftFields) { controller.addListener(saveState); }
    if (live && signedIn) connect();
  }
  void connect() {
    if (db.user?['role'] == 'admin') return;
    operator = db.user?['role'] == 'operator';
    WorkAlerts.connect(userId, refresh);
    channel?.cancel();
    channel = db.listen(refresh);
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    refresh();
  }
  Future<void> refresh() async {
    if (!live || !signedIn || refreshing) return;
    refreshing = true;
    final session = db.token;
    try {
      final result = await db.call('GET', '/jobs');
      if (mounted && db.token == session) {
        final updatedJobs = List<Map<String,dynamic>>.from(result['jobs']);
        final completed = updatedJobs.any((next) => next['status'] == 'completed' &&
          jobs.any((previous) => previous['id'] == next['id'] &&
            ['accepted', 'on_the_way', 'working'].contains(previous['status'])));
        setState(() {
          if (operator) online = result['online'] == true;
          jobs = updatedJobs;
          balance = (result['balance'] as num?)?.toInt() ?? 0;
          blockedUntil = DateTime.tryParse(result['blocked_until']?.toString() ?? '');
        });
        if (completed) returnHomeAfterWork();
      }
    } on ApiException catch (e) {
      if (mounted && e.statusCode == 401 && db.token == session) {
        await BackendApi.storage.delete(key: db.sessionKey);
        db.closeEvents();
        poll?.cancel();
        if (mounted) setState(() { db.token = null; db.user = null; message = 'Please sign in again to restore your work.'; });
      } else if (mounted) {
        setState(() => message = e.message);
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Connection interrupted. Retrying; shown requests may be out of date.');
    } finally { refreshing = false; }
  }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { await action(); }
    on ApiException catch (e) { if (mounted) setState(() => message = e.message); }
    catch (_) { if (mounted) setState(() => message = 'Could not finish. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> request() async {
    if (restricted) throw const ApiException('New requests are temporarily paused after cancellation.');
    if (!form.currentState!.validate()) return;
    if (loadingVehicle == null || amountError(offeredAmount.text) != null) {
      goToPage(1);
      return;
    }
    if (coordinateError(latitude.text, 90) != null || coordinateError(longitude.text, 180) != null) {
      setState(() => message = 'Choose your work location on the map first.');
      return;
    }
    address.text = 'Pinned work site: ${latitude.text}, ${longitude.text}';
    details.text = '${services[selected]} with loading vehicle: $loadingVehicle';
    final row = <String, dynamic>{'customer_id': userId, 'service': services[selected],
      'loading_vehicle': loadingVehicle, 'store_number': storeNumber.text,
      'offered_amount': double.parse(offeredAmount.text.trim()),
      'site_lat': double.parse(latitude.text), 'site_lng': double.parse(longitude.text),
      'address': address.text.trim(), 'details': details.text.trim()};
    if (live) {
      await db.call('POST', '/jobs', {
        'equipment': services[selected], 'loading': loadingVehicle, 'store_number': storeNumber.text,
        'offered_amount': offeredAmount.text.trim(),
        'site_address': address.text.trim(), 'work_details': details.text.trim(),
        'lat': double.parse(latitude.text), 'lng': double.parse(longitude.text)});
      await refresh();
    }
    else { setState(() => jobs.insert(0, {...row,
      'id': DateTime.now().microsecondsSinceEpoch.toString(), 'status': 'requested'})); }
  }
  Future<void> change(Map<String, dynamic> job, String action, {String? otp}) async {
    if (action == 'accept' && restricted) throw const ApiException('Work acceptance is temporarily paused after cancellation.');
    if (action == 'cancel') {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Cancel this work?'),
        content: Text(operator ? 'You will be unable to accept new work for 5 hours.'
          : 'You will be unable to make new requests for 3 days.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep work')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel work'))]));
      if (confirmed != true || !mounted) return;
    }
    if (action == 'start' || action == 'complete') {
      final p = await currentPosition();
      if (live) {
        await db.call('PUT', '/jobs/${job['id']}/location', {'lat': p.latitude, 'lng': p.longitude});
      } else {
        final metres = Geolocator.distanceBetween(p.latitude, p.longitude,
          (job['site_lat'] as num).toDouble(), (job['site_lng'] as num).toDouble());
        if (metres > 100) throw const ApiException('Arrive within 100 metres of the work site first');
        if (action == 'start' && otp != job['start_otp']) throw const ApiException('Incorrect four-digit customer OTP');
      }
    }
    if (live) {
      await db.call('POST', '/jobs/${job['id']}/action', {'action': action, if (otp != null) 'otp': otp});
      await refresh();
    } else {
      setState(() {
        if (action == 'decline') { hidden.add(job['id'].toString()); return; }
        if (action == 'cancel') {
          if (!['requested', 'accepted', 'on_the_way'].contains(job['status'])) {
            throw const ApiException('Work cannot be cancelled after starting.');
          }
          demoBlocks[operator] = DateTime.now().add(Duration(hours: operator ? 5 : 72));
          poll ??= Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted) setState(() {});
          });
          if (operator) online = false;
          job.remove('start_otp');
        }
        if (action == 'complete' && job['status'] != 'working') {
          throw const ApiException('Only work in progress can be completed');
        }
        job['status'] = {'accept': 'accepted', 'travel': 'on_the_way', 'start': 'working',
          'complete': 'completed', 'cancel': 'cancelled'}[action];
        if (action == 'accept') {
          job['operator_id'] = 'demo-operator';
          job['start_otp'] = Random.secure().nextInt(10000).toString().padLeft(4, '0');
        }
        if (action == 'start') job.remove('start_otp');
      });
      if (action == 'complete') returnHomeAfterWork();
    }
  }
  Future<void> startWithOtp(Map<String,dynamic> job) async {
    final controller = TextEditingController();
    final codeForm = GlobalKey<FormState>();
    final code = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Enter customer OTP'),
      content: Form(key: codeForm, child: TextFormField(controller: controller,
        autofocus: true, keyboardType: TextInputType.number, maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        decoration: const InputDecoration(labelText: '4-digit OTP', helperText: 'Ask the customer after arriving at the site'),
        validator: (s) => RegExp(r'^[0-9]{4}$').hasMatch(s ?? '') ? null : 'Enter all 4 digits')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (codeForm.currentState!.validate()) Navigator.pop(context, controller.text); },
          child: const Text('Verify and start'))]));
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (code != null && mounted) await change(job, 'start', otp: code);
  }
  @override
  void dispose() {
    saveState();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in draftFields) { controller.removeListener(saveState); }
    scroll.dispose();
    if (live) db.closeEvents();
    poll?.cancel(); channel?.cancel();
    for (final c in [address, details, email, password, latitude, longitude, storeNumber, offeredAmount]) { c.dispose(); }
    super.dispose();
  }
  Widget heading(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)));
  Widget button(String text, Future<void> Function() action) => FilledButton(
    onPressed: busy ? null : () => perform(action), child: Text(text));

  @override
  Widget build(BuildContext context) {
    if (live && signedIn && db.user?['role'] == 'admin') {
      return AdminPanel(onSignOut: () async {
        await db.logout();
        if (mounted) setState(() {});
      });
    }
    final active = jobs.where((j) => !['completed', 'cancelled'].contains(j['status'])).toList();
    return Scaffold(appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: signedIn && !operator && active.isEmpty && !restricted
        ? IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
            onPressed: busy || page == 0 ? null : () => goToPage(page - 1))
        : null,
      title: const Text('BUKLIN',
      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)), actions: [
      if (live && signedIn) IconButton(tooltip: 'Sign out', onPressed: busy ? null : () => perform(() async {
        if (operator) await db.call('PUT', '/availability', {'available': false});
        poll?.cancel(); await channel?.cancel();
        await db.logout();
        await WorkAlerts.disconnect();
        if (mounted) setState(() { jobs.clear(); hidden.clear(); online = false; page = 0; balance = 0; blockedUntil = null; });
      }), icon: const Icon(Icons.logout))]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
          if (!live) Container(padding: const EdgeInsets.all(12), color: const Color(0xFFFFE6CD),
            child: const Text('LOCAL DEMO • Requests stay on this device. Switch roles to try accepting work.')),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message!, style: const TextStyle(color: Color(0xFF9E3400)))),
          if (!signedIn) ...login() else ...[
            if (!live) Padding(padding: const EdgeInsets.only(top: 16), child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Customer')),
                ButtonSegment(value: true, label: Text('Operator'))], selected: {operator},
              onSelectionChanged: busy ? null : (s) => setState(() => operator = s.first))),
            if (!live) TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AdminLogin())),
              icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('Admin panel')),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your balance: $availableBalance Riyal',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(availableBalance < 0 ? '${-availableBalance} Riyal to pay' : 'Available money'),
                const Text('4 Riyal is deducted when each job is completed.'),
              ]))),
            if (restricted) Padding(padding: const EdgeInsets.all(16),
              child: Text('Work paused after cancellation. You can ${operator ? 'accept work' : 'make new requests'} again after ${restrictionEnd!.toLocal()}.')),
            if (operator) ...operatorView(active) else if (!restricted) ...customerView(active),
            if (jobs.any((j) => ['completed', 'cancelled'].contains(j['status']))) ...[
              heading('Recent work'), ...jobs.where((j) => ['completed', 'cancelled'].contains(j['status'])).map(jobCard)],
          ], const SizedBox(height: 24),
        ])))));
  }
  List<Widget> login() => [
    Image.asset('assets/buklin-logo.png', height: 180), heading('Work on demand.'),
    const Text('Request equipment. Connect with an operator. Get the job done.'), const SizedBox(height: 24),
    TextField(controller: email, decoration: const InputDecoration(labelText: 'Username or email')),
    const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
    const SizedBox(height: 16), button('Sign in', () async {
      await db.login(email.text.trim(), password.text);
      password.clear(); restoreWork(); connect();
    }),
    TextButton(onPressed: busy ? null : () => perform(() async {
      await db.login(email.text.trim(), password.text, register: true);
      password.clear(); restoreWork(); connect();
    }), child: const Text('Create customer account')),
    const Text('Operators sign in with an approved operator account.'),
  ];
  List<Widget> customerView(List<Map<String, dynamic>> active) => [
    if (active.isEmpty) ...[
      heading(['Choose your work vehicle', 'Choose loading vehicle', 'Where is the work?'][page]),
      Text('Step ${page + 1} of 3'),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: (page + 1) / 3),
    ],
    if (active.isEmpty && page == 0) ...[
    const SizedBox(height: 20),
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
      color: const Color(0xFF24282B), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/buklin-logo.png', width: 90, height: 90)),
        const SizedBox(height: 16), const Text('HEAVY WORK. MADE EASY.', style: TextStyle(color: Color(0xFFFF994F), letterSpacing: 1.5)),
        const SizedBox(height: 12), const Text('The right machine.\nRight when you need it.',
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))])),
      heading('What do you need?'),
      ...List.generate(services.length, (i) => Card(elevation: 0,
        color: selected == i ? const Color(0xFFFFE6CD) : Colors.white,
        child: ListTile(contentPadding: const EdgeInsets.all(16),
          leading: ClipRRect(borderRadius: BorderRadius.circular(10),
            child: Image.asset(serviceImages[i], width: 64, height: 56,
              fit: BoxFit.contain, excludeFromSemantics: true)),
          title: Text(services[i], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(['Material handling & site cleanup', 'Small loads & local deliveries', 'Heavy loads & bulk transport'][i]),
          trailing: Icon(selected == i ? Icons.check_circle : Icons.circle_outlined),
          onTap: busy ? null : () => setState(() => selected = i)))),
      const SizedBox(height: 16),
      button('Next: loading vehicle', () async => goToPage(1)),
    ],
    if (active.isEmpty && page == 1) ...[
      const SizedBox(height: 16),
      const Text('Select where the material will be loaded.'),
      ...loadingVehicles.map((name) => Card(elevation: 0,
        color: loadingVehicle == name ? const Color(0xFFFFE6CD) : Colors.white,
        child: ListTile(title: Text(name),
          trailing: Icon(loadingVehicle == name ? Icons.check_circle : Icons.circle_outlined),
          onTap: busy ? null : () => setState(() => loadingVehicle = name)))),
      const SizedBox(height: 16),
      Form(key: amountForm, child: TextFormField(
        controller: offeredAmount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3, maxLengthEnforcement: MaxLengthEnforcement.enforced)],
        maxLength: 3,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: const InputDecoration(labelText: 'Amount you want to give',
          hintText: '250', suffixText: 'Riyal', helperText: 'Required • 30–999 Riyal'),
        validator: amountError,
      )),
      const SizedBox(height: 12),
      FilledButton(onPressed: loadingVehicle == null || busy ? null : () {
        if (amountForm.currentState!.validate()) goToPage(2);
      },
        child: const Text('Next: work location')),
    ],
    if (active.isNotEmpty) ...[heading('Your work order'), ...active.map(jobCard)],
    if (active.isEmpty && page == 2) ...[
      Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('${services[selected]} • $loadingVehicle')),
      Form(key: form, child: TextFormField(
        controller: storeNumber,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        maxLength: 3,
        decoration: const InputDecoration(labelText: 'Store number', hintText: 'e.g. 007',
          helperText: 'Required • Exactly 3 digits'),
        validator: (value) => RegExp(r'^[0-9]{3}$').hasMatch(value ?? '')
          ? null : 'Enter exactly 3 digits',
      )),
      const SizedBox(height: 12),
      SitePicker(
        initialLatitude: double.tryParse(latitude.text),
        initialLongitude: double.tryParse(longitude.text),
        onChanged: (point) {
          latitude.text = point.latitude.toString();
          longitude.text = point.longitude.toString();
        },
      ),
      const SizedBox(height: 16), button('Search for an operator', request),
    ],
  ];
  List<Widget> operatorView(List<Map<String, dynamic>> active) {
    final mine = active.where((j) => j['operator_id'] == (live ? userId : 'demo-operator')).toList();
    final offers = active.where((j) => j['status'] == 'requested' && !hidden.contains(j['id'].toString())).toList();
    return [heading('Ready for your next job?'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(mine.isNotEmpty
        ? 'Busy • new requests paused' : online ? 'Online • receiving requests' : 'You are offline'),
        subtitle: Text(mine.isNotEmpty ? 'Finish your current work to receive new requests.'
          : 'Receive new work orders when you are available.'), value: online,
        onChanged: busy || restricted ? null : (v) => perform(() async {
          if (live) await db.call('PUT', '/availability', {'available': v});
          setState(() => online = v);
        })),
      TextButton.icon(onPressed: busy ? null : () => perform(() async {
        final result = await WorkAlerts.enable();
        if (mounted) setState(() => message = result);
      }), icon: const Icon(Icons.notifications_active_outlined), label: const Text('Enable phone work alerts')),
      if (mine.isNotEmpty) ...[heading('Your active work'), ...mine.map(jobCard)]
      else if (online && !restricted) ...[heading('Incoming requests'),
        if (offers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No requests yet. New work will appear here.')),
        ...offers.map(jobCard)]
      else const Padding(padding: EdgeInsets.all(24), child: Text('Go online when you are available to accept work.'))];
  }
  Widget jobCard(Map<String, dynamic> j) {
    const loadingImages = {
      'Dyna': 'assets/loading-dyna.png',
      'Trailer': 'assets/loading-trailer.png',
      'Inside store': 'assets/loading-store.png',
    };
    final loadingImage = operator ? loadingImages[j['loading_vehicle']] : null;
    final status = j['status'] as String;
    final showPrivateDetails = !operator ||
      (j['operator_id'] == (live ? userId : 'demo-operator') && status != 'requested');
    final labels = {'requested': 'Waiting for an operator', 'accepted': 'Operator accepted',
      'on_the_way': 'Operator on the way', 'working': 'Work in progress', 'completed': 'Work completed', 'cancelled': 'Request cancelled'};
    return Card(margin: const EdgeInsets.only(bottom: 16), color: Colors.white, elevation: 0,
      child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(labels[status] ?? status, style: const TextStyle(color: Color(0xFFBC4F00), fontWeight: FontWeight.bold)),
        const SizedBox(height: 12), Text(j['service'], style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        if (showPrivateDetails && j['store_number'] != null) Text('Store number: ${j['store_number']}'),
        if (!operator && ['accepted', 'on_the_way'].contains(status) && j['start_otp'] != null)
          Container(margin: const EdgeInsets.symmetric(vertical: 16), padding: const EdgeInsets.all(16),
            color: const Color(0xFFFFE6CD), child: Column(children: [
              const Text('Start-work OTP'),
              SelectableText(j['start_otp'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8)),
              const Text('Share this code with your operator after they arrive.') ])),
        if (j['loading_vehicle'] != null)
          Row(children: [
            if (loadingImage != null) ...[
              Image.asset(loadingImage, width: 88, height: 72, fit: BoxFit.contain,
                excludeFromSemantics: true),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text('Loading vehicle: ${j['loading_vehicle']}')),
          ]),
        if (j['offered_amount'] != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Customer offer: ${num.parse(j['offered_amount'].toString()).toStringAsFixed(0)} Riyal',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        if (!operator && status == 'requested') const Padding(padding: EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [LinearProgressIndicator(), SizedBox(height: 12),
            Text('Searching for an available operator… You can cancel while waiting.') ])),
        if (showPrivateDetails) ...[const SizedBox(height: 8), Text(j['address'])],
        const SizedBox(height: 8), Text(j['details']),
        if (j['operator_id'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Assigned operator: ${j['operator_id']}')),
        if (['accepted', 'on_the_way', 'working'].contains(status)) WorkLocation(
          key: ValueKey('${j['id']}-$operator'), job: j, isOperator: operator, connected: live),
        const SizedBox(height: 16),
        if (['requested', 'accepted', 'on_the_way'].contains(status) &&
            (!operator || j['operator_id'] == (live ? userId : 'demo-operator')))
          button('Cancel work', () => change(j, 'cancel')),
        if (operator && online && status == 'requested') ...[
          button('Accept work', () => change(j, 'accept')),
          TextButton(onPressed: busy ? null : () => perform(() => change(j, 'decline')), child: const Text('Decline'))],
        if (operator && j['operator_id'] == (live ? userId : 'demo-operator')) ...[
          if (status == 'accepted') button('Go to work', () => change(j, 'travel')),
          if (['accepted','on_the_way','working'].contains(status))
            const Text('New requests are paused during this job. Starting and finishing require arrival within 100 metres.'),
          if (status == 'on_the_way') button('Start work with OTP', () => startWithOtp(j)),
          if (status == 'working') button('Finished work', () => change(j, 'complete'))],
      ])));
  }
}
