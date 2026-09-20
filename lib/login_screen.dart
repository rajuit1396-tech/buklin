import 'package:flutter/material.dart';
import 'app_language.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen(
      {super.key,
      required this.username,
      required this.password,
      required this.role,
      required this.busy,
      required this.message,
      required this.onRoleChanged,
      required this.onSubmit});
  final TextEditingController username, password;
  final String role;
  final bool busy;
  final String? message;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onSubmit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool hidePassword = true;

  InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: tr(context, label),
      prefixIcon: Icon(icon, size: 21, color: const Color(0xFF78828A)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE1E2))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEA761A), width: 2)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF151B20),
        body: Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF28323B), Color(0xFF101519)])),
            child: SafeArea(
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: ListView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 28),
                            children: [
                              const Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: IconTheme(
                                      data: IconThemeData(color: Colors.white),
                                      child: LanguageSelector())),
                              Image.asset('assets/buklin-logo.png',
                                  height: 176,
                                  fit: BoxFit.contain,
                                  semanticLabel: 'Buklin'),
                              const SizedBox(height: 20),
                              const AppText('HEAVY WORK. MADE EASY.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFFFFA34D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.4)),
                              const SizedBox(height: 26),
                              Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFFAF9F6),
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Color(0x33000000),
                                            blurRadius: 32,
                                            offset: Offset(0, 14))
                                      ]),
                                  child: AutofillGroup(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                        const AppText('Welcome back',
                                            style: TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.8,
                                                color: Color(0xFF1B242C))),
                                        const SizedBox(height: 6),
                                        const AppText(
                                            'Sign in and get your next job moving.',
                                            style: TextStyle(
                                                color: Color(0xFF66717B),
                                                height: 1.5)),
                                        const SizedBox(height: 24),
                                        Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFECEEEB),
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            child: Row(
                                                children: [
                                              'customer',
                                              'operator'
                                            ].map((role) {
                                              final selected =
                                                  widget.role == role;
                                              return Expanded(
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                              horizontal: 2),
                                                      child: Semantics(
                                                          selected: selected,
                                                          child: TextButton(
                                                              onPressed: widget.busy
                                                                  ? null
                                                                  : () => widget
                                                                      .onRoleChanged(
                                                                          role),
                                                              style: TextButton.styleFrom(
                                                                  backgroundColor: selected
                                                                      ? const Color(
                                                                          0xFF25313B)
                                                                      : Colors
                                                                          .transparent,
                                                                  foregroundColor: selected
                                                                      ? Colors
                                                                          .white
                                                                      : const Color(
                                                                          0xFF5D6871),
                                                                  padding: const EdgeInsets.symmetric(
                                                                      vertical:
                                                                          14),
                                                                  shape: RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(12))),
                                                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                                                Icon(
                                                                    role == 'customer'
                                                                        ? Icons
                                                                            .person_outline_rounded
                                                                        : Icons
                                                                            .engineering_outlined,
                                                                    size: 22),
                                                                const SizedBox(
                                                                    height: 5),
                                                                AppText(
                                                                    role == 'customer'
                                                                        ? 'Customer'
                                                                        : 'Operator',
                                                                    style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w700))
                                                              ])))));
                                            }).toList())),
                                        const SizedBox(height: 24),
                                        AppText(
                                            '${widget.role == 'operator' ? 'Operator' : 'Customer'} login',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF25313B))),
                                        const SizedBox(height: 14),
                                        TextField(
                                            controller: widget.username,
                                            enabled: !widget.busy,
                                            autofillHints: const [
                                              AutofillHints.username
                                            ],
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: field(
                                                'Username or email',
                                                Icons.person_outline_rounded)),
                                        const SizedBox(height: 16),
                                        TextField(
                                            controller: widget.password,
                                            enabled: !widget.busy,
                                            obscureText: hidePassword,
                                            autofillHints: const [
                                              AutofillHints.password
                                            ],
                                            textInputAction:
                                                TextInputAction.done,
                                            onSubmitted: (_) {
                                              if (!widget.busy)
                                                widget.onSubmit();
                                            },
                                            decoration: field('Password',
                                                    Icons.lock_outline_rounded)
                                                .copyWith(
                                                    suffixIcon: IconButton(
                                                        tooltip: tr(
                                                            context,
                                                            hidePassword
                                                                ? 'Show password'
                                                                : 'Hide password'),
                                                        onPressed: () => setState(
                                                            () => hidePassword =
                                                                !hidePassword),
                                                        icon: Icon(hidePassword
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined)))),
                                        if (widget.message != null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 16),
                                              child: Semantics(
                                                  liveRegion: true,
                                                  child: AppText(
                                                      widget.message!,
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xFFAD3B18),
                                                          height: 1.4)))),
                                        const SizedBox(height: 24),
                                        FilledButton(
                                            onPressed: widget.busy
                                                ? null
                                                : widget.onSubmit,
                                            style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFFFF8A24),
                                                foregroundColor:
                                                    const Color(0xFF1B242C),
                                                minimumSize:
                                                    const Size.fromHeight(56),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14))),
                                            child: widget.busy
                                                ? const SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                        AppText('Sign in',
                                                            style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                        SizedBox(width: 12),
                                                        Icon(
                                                            Icons
                                                                .arrow_forward_rounded,
                                                            size: 20)
                                                      ])),
                                        const SizedBox(height: 22),
                                        const AppText(
                                            'Need an account? Contact your administrator.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 12,
                                                height: 1.5,
                                                color: Color(0xFF66717B))),
                                      ]))),
                              const SizedBox(height: 24),
                              const AppText('EQUIPMENT  /  TRANSPORT  /  WORK',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFFADB5BC),
                                      fontSize: 10,
                                      letterSpacing: 1.8)),
                            ]))))),
      );
}
