import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'backend_api.dart';
import 'dart:math';

const adminMachines = ['5-finger excavator grapple', 'Pickup van', 'Big truck'];
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, this.demo = false, this.onSignOut});
  final bool demo;
  final Future<void> Function()? onSignOut;
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}
class _AdminPanelState extends State<AdminPanel> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  final username = TextEditingController(), password = TextEditingController();
  final search = TextEditingController();
  String role = 'operator';
  String? machine, message;
  bool busy = false, showPassword = false;
  List<Map<String,dynamic>> users = [];
  BackendApi get api => BackendApi.instance;
  @override
  void initState() { super.initState(); if (!widget.demo) load(); }
  Future<void> load() async {
    setState(() => busy = true);
    try {
      final result = await api.call('GET', '/admin/users?search=${Uri.encodeQueryComponent(search.text.trim())}');
      if (mounted) setState(() => users = List<Map<String,dynamic>>.from(result['users']));
    } on ApiException catch(e) { if (mounted) setState(() => message = e.message); }
    catch (_) { if (mounted) setState(() => message = 'Could not load accounts. Try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> create() async {
    if (!form.currentState!.validate()) return;
    setState(() { busy = true; message = null; });
    try {
      final body = <String,dynamic>{'name':name.text.trim(),'phone':phone.text.trim(),
        'username':username.text.trim().toLowerCase(),'password':password.text,
        'role':role,'service':role == 'operator' ? machine : null};
      if (widget.demo) {
        if (users.any((u) => u['username'] == body['username'])) throw const ApiException('Username already exists');
        body.remove('password');
        setState(() => users.insert(0, body));
      } else {
        await api.call('POST', '/admin/users', body);
        await load();
      }
      if (!mounted) return;
      final savedUsername = username.text.trim();
      for (final controller in [name,phone,username,password]) { controller.clear(); }
      setState(() { showPassword = false;
        message = widget.demo ? 'Preview account added. It cannot sign in and is not saved to the server.'
          : 'Account $savedUsername created. They can sign in with their username and password.';
      });
    } on ApiException catch(e) { if (mounted) setState(() => message = e.message); }
    catch (_) { if (mounted) setState(() => message = 'Could not create the account. Please try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> adjustBalance(Map<String,dynamic> user) async {
    final amount = TextEditingController(), reason = TextEditingController();
    final key = GlobalKey<FormState>();
    bool credit = true;
    final approved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text('Balance: ${user['name'] ?? user['username']}'),
        content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current balance: ${user['balance'] ?? 0} Riyal'),
          SwitchListTile(title: Text(credit ? 'Add money / payment' : 'Deduct money'), value: credit,
            onChanged: (value) => update(() => credit = value)),
          TextFormField(controller: amount, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 7,
            decoration: const InputDecoration(labelText: 'Amount in Riyal'),
            validator: (s) { final value = int.tryParse(s ?? '') ?? 0;
              return value < 1 || value > 1000000 ? 'Enter 1–1000000 Riyal' : null; }),
          TextFormField(controller: reason, maxLength: 300, decoration: const InputDecoration(labelText: 'Reason / payment reference'),
            validator: (s) => (s?.trim().length ?? 0) < 3 ? 'Enter a reason' : null),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Apply'))])));
    if (approved == true && mounted) {
      final value = int.parse(amount.text) * (credit ? 1 : -1);
      final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      final id = '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
      await manage(() async {
        if (widget.demo) {
          user['balance'] = (user['balance'] ?? 0) + value;
          (user['entries'] ??= <Map<String,dynamic>>[]).insert(0, {'amount': value, 'reason': reason.text.trim()});
        } else {
          await api.call('POST', '/admin/users/${user['id']}/balance', {'id': id, 'amount': value, 'reason': reason.text.trim()});
        }
      });
    }
    // Let the closing dialog finish using its controllers.
    Future.delayed(const Duration(seconds: 1), () { amount.dispose(); reason.dispose(); });
  }
  Future<void> manage(Future<void> Function() action) async {
    setState(() { busy = true; message = null; });
    try { await action(); if (!widget.demo && mounted) await load(); }
    on ApiException catch(e) { if (mounted) setState(() => message = e.message); }
    catch (_) { if (mounted) setState(() => message = 'Could not update account. Refresh to check the result.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> history(Map<String,dynamic> user) async {
    await manage(() async {
      final entries = widget.demo ? (user['entries'] ?? []) as List
        : (await api.call('GET', '/admin/users/${user['id']}/balance'))['entries'] as List;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Balance history'), content: SizedBox(width: 450,
          child: entries.isEmpty ? const Text('No balance changes yet.') : ListView(shrinkWrap: true,
            children: entries.map<Widget>((e) => ListTile(title: Text('${e['amount']} Riyal'),
              subtitle: Text('${e['reason']}\n${e['created_at'] ?? ''}'))).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
    });
  }
  @override
  void dispose() { for (final c in [name,phone,username,password,search]) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Buklin Admin'), actions: [
      if (widget.onSignOut != null) IconButton(tooltip:'Sign out', icon:const Icon(Icons.logout),
        onPressed: busy ? null : () async {
          setState(() => busy = true);
          try { await widget.onSignOut!(); }
          catch (_) { if (mounted) setState(() { busy = false; message = 'Could not sign out. Try again.'; }); }
        }),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth:700),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        if (widget.demo) const Card(child: Padding(padding: EdgeInsets.all(12),
          child: Text('ADMIN PREVIEW • Accounts exist only on this screen. Use an admin login with the live backend to save real accounts.'))),
        if (busy) const LinearProgressIndicator(),
        if (message != null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!)),
        const Text('Register an account',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
        const SizedBox(height:16),
        SegmentedButton<String>(segments:const [
          ButtonSegment(value:'operator',label:Text('Operator'),icon:Icon(Icons.engineering)),
          ButtonSegment(value:'customer',label:Text('Customer'),icon:Icon(Icons.person_outline))],
          selected:{role}, onSelectionChanged:busy ? null : (s)=>setState(() {role=s.first;machine=null;})),
        const SizedBox(height:20),
        Form(key:form, child:Column(children:[
          TextFormField(controller:name,enabled:!busy,maxLength:100,
            decoration:const InputDecoration(labelText:'Full name'),
            validator:(s)=>(s?.trim().length ?? 0)<2?'Enter a full name':null),
          TextFormField(controller:phone,enabled:!busy,keyboardType:TextInputType.phone,maxLength:16,
            decoration:const InputDecoration(labelText:'Phone number',hintText:'+966501234567'),
            validator:(s)=>RegExp(r'^\+?[0-9]{7,15}$').hasMatch(s?.trim() ?? '')?null:'Enter 7–15 digits, optionally starting with +'),
          TextFormField(controller:username,enabled:!busy,maxLength:40,
            inputFormatters:[FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]'))],
            decoration:const InputDecoration(labelText:'Username',helperText:'3–40 letters, numbers or underscores'),
            validator:(s)=>RegExp(r'^[a-zA-Z0-9_]{3,40}$').hasMatch(s?.trim() ?? '')?null:'Enter at least 3 characters'),
          TextFormField(controller:password,enabled:!busy,obscureText:!showPassword,maxLength:128,
            enableSuggestions:false,autocorrect:false,
            decoration:InputDecoration(labelText:'Password',helperText:'At least 10 characters',
              suffixIcon:IconButton(tooltip:showPassword?'Hide password':'Show password',
                onPressed:()=>setState(()=>showPassword=!showPassword),icon:Icon(showPassword?Icons.visibility_off:Icons.visibility))),
            validator:(s)=>(s?.length ?? 0)<10?'Use at least 10 characters':null),
          if(role=='operator') DropdownButtonFormField<String>(key:ValueKey(role),initialValue:machine,
            isExpanded:true,decoration:const InputDecoration(labelText:'Assigned machine'),
            items:adminMachines.map((m)=>DropdownMenuItem(value:m,child:Text(m))).toList(),
            onChanged:busy?null:(m)=>setState(()=>machine=m),validator:(m)=>m==null?'Select one machine':null),
          const SizedBox(height:20),
          SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:create,
            child:Text(role=='operator'?'Create operator':'Create customer'))),
        ])),
        const SizedBox(height:32),
        const Text('Registered accounts',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        if (!widget.demo) Padding(padding:const EdgeInsets.symmetric(vertical:16),child:TextField(controller:search,
          onSubmitted:busy?null:(_)=>load(),decoration:InputDecoration(labelText:'Search name, phone or username',
            suffixIcon:IconButton(onPressed:busy?null:load,icon:const Icon(Icons.search))))),
        if(users.isEmpty) const Padding(padding:EdgeInsets.all(16),child:Text('No accounts to display.')),
        ...users.map((u)=>Card(child:Column(children: [ListTile(
          leading:Icon(u['role']=='operator'?Icons.engineering:Icons.person_outline),
          title:Text(u['name'] ?? u['username'] ?? u['email'] ?? 'Account'),
          subtitle:Text('${u['role']} • ${u['username'] ?? u['email'] ?? ''}\n${u['phone'] ?? ''}'
            '${u['role']=='operator'?'\nMachine: ${u['service']}':''}\nBalance: ${u['balance'] ?? 0} Riyal'),isThreeLine:true),
          if (u['blocked_until'] != null) Padding(padding: const EdgeInsets.all(8), child: Text('Restricted until ${u['blocked_until']}')),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: busy ? null : () => adjustBalance(u), child: const Text('Manage balance')),
            TextButton(onPressed: busy ? null : () => history(u), child: const Text('Balance history')),
            if (u['blocked_until'] != null) TextButton(onPressed: busy ? null : () => manage(() async {
              if (widget.demo) { u['blocked_until'] = null; }
              else { await api.call('POST', '/admin/users/${u['id']}/clear-restriction'); }
            }), child: const Text('Clear restriction')),
          ]),
        ]))),
      ])))),
  );
}
