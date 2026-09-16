import 'package:flutter/material.dart';
import 'backend_api.dart';
import 'admin_panel.dart';

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final username = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, authenticated = false;
  String? error;
  Future<void> signIn() async {
    if (!form.currentState!.validate()) return;
    if (backendUrl.isEmpty) {
      setState(() => error = 'Admin login is unavailable until the backend is connected.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await BackendApi.instance.login(username.text.trim(), password.text, adminOnly: true);
      if (mounted) setState(() { password.clear(); authenticated = true; });
    } on ApiException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Could not sign in. Please try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { username.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (authenticated) return AdminPanel(onSignOut: () async {
      await BackendApi.instance.logout();
      if (mounted) setState(() => authenticated = false);
    });
    return Scaffold(appBar: AppBar(title: const Text('Admin login')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: username, enabled: !busy,
              decoration: const InputDecoration(labelText: 'Username or email'),
              validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter your admin username or email' : null),
            const SizedBox(height: 16),
            TextFormField(controller: password, enabled: !busy, obscureText: true,
              autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) => (value?.isEmpty ?? true) ? 'Enter your password' : null,
              onFieldSubmitted: busy ? null : (_) => signIn()),
            if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!)),
            const SizedBox(height: 20),
            FilledButton(onPressed: busy ? null : signIn, child: Text(busy ? 'Signing in…' : 'Sign in')),
          ]))))));
  }
}
