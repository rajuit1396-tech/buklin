import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const services = ['5-finger excavator grapple', 'Pickup van', 'Big truck'];
const serviceIcons = [Icons.precision_manufacturing, Icons.airport_shuttle, Icons.local_shipping];
const endpoint = String.fromEnvironment('SUPABASE_URL');
const apiKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const live = endpoint != '' && apiKey != '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  if (live) {
    try { await Supabase.initialize(url: endpoint, anonKey: apiKey); }
    catch (_) { error = 'Connection setup failed. Check configuration and restart.'; }
  }
  runApp(MaterialApp(title: 'Buklin', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEA640D)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F1),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF24282B), foregroundColor: Colors.white, minimumSize: const Size(48, 52)))),
    home: error == null ? const WorkApp() : Scaffold(body: Center(child: Text(error)))));
}

class WorkApp extends StatefulWidget {
  const WorkApp({super.key});
  @override
  State<WorkApp> createState() => _WorkAppState();
}

class _WorkAppState extends State<WorkApp> {
  final address = TextEditingController(), details = TextEditingController();
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  final hidden = <String>{};
  List<Map<String, dynamic>> jobs = [];
  int selected = 0;
  bool operator = false, online = false, busy = false, refreshing = false;
  String? message;
  Timer? poll;
  RealtimeChannel? channel;
  SupabaseClient get db => Supabase.instance.client;
  bool get signedIn => !live || db.auth.currentUser != null;
  String get userId => live ? db.auth.currentUser!.id : 'demo-customer';

  @override
  void initState() { super.initState(); if (live && signedIn) connect(); }
  void connect() {
    operator = db.auth.currentUser?.appMetadata['role'] == 'operator';
    channel = db.channel('work-feed-${db.auth.currentUser!.id}')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'jobs',
        callback: (_) => refresh()).subscribe();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    refresh();
  }
  Future<void> refresh() async {
    if (!live || !signedIn || refreshing) return;
    refreshing = true;
    try {
      final rows = await db.from('jobs').select().order('created_at', ascending: false);
      final declined = operator ? await db.from('declines').select('job_id') : <Map<String, dynamic>>[];
      if (mounted) setState(() {
        jobs = List<Map<String, dynamic>>.from(rows);
        hidden.addAll(declined.map((r) => r['job_id'].toString()));
      });
    } catch (_) {
      if (mounted) setState(() => message = 'Connection interrupted. Retrying; shown requests may be out of date.');
    } finally { refreshing = false; }
  }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { await action(); }
    on AuthException catch (e) { if (mounted) setState(() => message = e.message); }
    on PostgrestException catch (e) { if (mounted) setState(() => message = e.message); }
    catch (_) { if (mounted) setState(() => message = 'Could not finish. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> request() async {
    if (!form.currentState!.validate()) return;
    final row = <String, dynamic>{'customer_id': userId, 'service': services[selected],
      'address': address.text.trim(), 'details': details.text.trim()};
    if (live) { await db.from('jobs').insert(row); await refresh(); }
    else { setState(() => jobs.insert(0, {...row,
      'id': DateTime.now().microsecondsSinceEpoch.toString(), 'status': 'requested'})); }
  }
  Future<void> change(Map<String, dynamic> job, String action) async {
    if (live) {
      await db.rpc('job_action', params: {'job_id': job['id'], 'action': action});
      await refresh();
    } else {
      setState(() {
        if (action == 'decline') { hidden.add(job['id'].toString()); return; }
        job['status'] = {'accept': 'accepted', 'travel': 'on_the_way', 'start': 'working',
          'complete': 'completed', 'cancel': 'cancelled'}[action];
        if (action == 'accept') job['operator_id'] = 'demo-operator';
      });
    }
  }
  @override
  void dispose() {
    poll?.cancel(); if (channel != null) db.removeChannel(channel!);
    for (final c in [address, details, email, password]) { c.dispose(); }
    super.dispose();
  }
  Widget heading(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)));
  Widget button(String text, Future<void> Function() action) => FilledButton(
    onPressed: busy ? null : () => perform(action), child: Text(text));

  @override
  Widget build(BuildContext context) {
    final active = jobs.where((j) => !['completed', 'cancelled'].contains(j['status'])).toList();
    return Scaffold(appBar: AppBar(title: const Text('BUKLIN',
      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)), actions: [
      if (live && signedIn) IconButton(tooltip: 'Sign out', onPressed: busy ? null : () => perform(() async {
        poll?.cancel(); if (channel != null) await db.removeChannel(channel!);
        await db.auth.signOut();
        if (mounted) setState(() { jobs.clear(); hidden.clear(); online = false; });
      }), icon: const Icon(Icons.logout))]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(padding: const EdgeInsets.all(20), children: [
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
            if (operator) ...operatorView(active) else ...customerView(active),
            if (jobs.any((j) => ['completed', 'cancelled'].contains(j['status']))) ...[
              heading('Recent work'), ...jobs.where((j) => ['completed', 'cancelled'].contains(j['status'])).map(jobCard)],
          ], const SizedBox(height: 24),
        ])))));
  }
  List<Widget> login() => [
    Image.asset('assets/buklin-logo.png', height: 180), heading('Work on demand.'),
    const Text('Request equipment. Connect with an operator. Get the job done.'), const SizedBox(height: 24),
    TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
    const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
    const SizedBox(height: 16), button('Sign in', () async {
      await db.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      password.clear(); connect();
    }),
    TextButton(onPressed: busy ? null : () => perform(() async {
      await db.auth.signUp(email: email.text.trim(), password: password.text);
      if (signedIn) { connect(); } else { setState(() => message = 'Confirm your email, then sign in.'); }
    }), child: const Text('Create customer account')),
    const Text('Operators sign in with an approved operator account.'),
  ];
  List<Widget> customerView(List<Map<String, dynamic>> active) => [
    const SizedBox(height: 20),
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
      color: const Color(0xFF24282B), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/buklin-logo.png', width: 90, height: 90)),
        const SizedBox(height: 16), const Text('HEAVY WORK. MADE EASY.', style: TextStyle(color: Color(0xFFFF994F), letterSpacing: 1.5)),
        const SizedBox(height: 12), const Text('The right machine.\nRight when you need it.',
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))])),
    if (active.isNotEmpty) ...[heading('Your current request'), ...active.map(jobCard)] else ...[
      heading('What do you need?'),
      ...List.generate(services.length, (i) => Card(elevation: 0,
        color: selected == i ? const Color(0xFFFFE6CD) : Colors.white,
        child: ListTile(contentPadding: const EdgeInsets.all(16), leading: Icon(serviceIcons[i], size: 32),
          title: Text(services[i], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(['Material handling & site cleanup', 'Small loads & local deliveries', 'Heavy loads & bulk transport'][i]),
          trailing: Icon(selected == i ? Icons.check_circle : Icons.circle_outlined),
          onTap: busy ? null : () => setState(() => selected = i)))),
      heading('Tell us about the work'),
      Form(key: form, child: Column(children: [
        TextFormField(controller: address, maxLength: 300, decoration: const InputDecoration(labelText: 'Work site / pickup address'),
          validator: (s) => (s?.trim().length ?? 0) < 5 ? 'Enter a complete work address' : null),
        TextFormField(controller: details, maxLength: 1000, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Work details', hintText: 'Material, load size, access and destination if needed'),
          validator: (s) => (s?.trim().length ?? 0) < 10 ? 'Describe the work in at least 10 characters' : null)])),
      const Text('An operator must accept before work is confirmed. Agree on scope and price with your operator.'),
      const SizedBox(height: 16), button('Request work now', request),
    ],
  ];
  List<Widget> operatorView(List<Map<String, dynamic>> active) {
    final mine = active.where((j) => j['operator_id'] == (live ? userId : 'demo-operator')).toList();
    final offers = active.where((j) => j['status'] == 'requested' && !hidden.contains(j['id'].toString())).toList();
    return [heading('Ready for your next job?'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(online ? 'Online • receiving requests' : 'You are offline'),
        subtitle: const Text('Keep this screen open for incoming work.'), value: online,
        onChanged: busy ? null : (v) => setState(() => online = v)),
      if (mine.isNotEmpty) ...[heading('Your active work'), ...mine.map(jobCard)]
      else if (online) ...[heading('Incoming requests'),
        if (offers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No requests yet. New work will appear here.')),
        ...offers.map(jobCard)]
      else const Padding(padding: EdgeInsets.all(24), child: Text('Go online when you are available to accept work.'))];
  }
  Widget jobCard(Map<String, dynamic> j) {
    final status = j['status'] as String;
    final labels = {'requested': 'Waiting for an operator', 'accepted': 'Operator accepted',
      'on_the_way': 'Operator on the way', 'working': 'Work in progress', 'completed': 'Work completed', 'cancelled': 'Request cancelled'};
    return Card(margin: const EdgeInsets.only(bottom: 16), color: Colors.white, elevation: 0,
      child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(labels[status] ?? status, style: const TextStyle(color: Color(0xFFBC4F00), fontWeight: FontWeight.bold)),
        const SizedBox(height: 12), Text(j['service'], style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Text(j['address']), const SizedBox(height: 8), Text(j['details']),
        if (j['operator_id'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Assigned operator: ${j['operator_id']}')),
        const SizedBox(height: 16),
        if (!operator && status == 'requested') button('Cancel request', () => change(j, 'cancel')),
        if (operator && online && status == 'requested') ...[
          button('Accept work', () => change(j, 'accept')),
          TextButton(onPressed: busy ? null : () => perform(() => change(j, 'decline')), child: const Text('Decline'))],
        if (operator && j['operator_id'] == (live ? userId : 'demo-operator')) ...[
          if (status == 'accepted') button('I’m on the way', () => change(j, 'travel')),
          if (status == 'on_the_way') button('Start work', () => change(j, 'start')),
          if (status == 'working') button('Complete work', () => change(j, 'complete'))],
      ])));
  }
}
