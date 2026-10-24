import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LogoBadge extends StatelessWidget {
  final double height;
  const LogoBadge({super.key, this.height = 44});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Image.asset('assets/logo.png', height: height),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false, hide = true;
  String? error;

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      await context.read<Session>().login(email.text.trim(), pass.text);
    } catch (e) {
      setState(() => error = errMsg(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Panel(
                padding: const EdgeInsets.all(28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: LogoBadge(height: 56)),
                  const SizedBox(height: 20),
                  const Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const Text('Admin access only. Accounts are created by an administrator.', style: TextStyle(color: C.muted, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: hide,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide))),
                  ),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: C.down))),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: busy ? null : submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Signing in...' : 'Sign in'))),
                ]),
              ),
            ),
          ),
        ),
      );
}

class ForcePasswordScreen extends StatefulWidget {
  const ForcePasswordScreen({super.key});
  @override
  State<ForcePasswordScreen> createState() => _ForcePasswordScreenState();
}

class _ForcePasswordScreenState extends State<ForcePasswordScreen> {
  final cur = TextEditingController(), nw = TextEditingController();
  String? error;

  Future<void> save() async {
    try {
      final s = context.read<Session>();
      await s.post('/api/auth/change-password', {'currentPassword': cur.text, 'newPassword': nw.text});
      await s.reloadUser();
    } catch (e) {
      setState(() => error = errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Panel(title: 'Choose a new password', child: Column(children: [
              const Text('For your security you must replace the temporary password before continuing.', style: TextStyle(color: C.muted)),
              const SizedBox(height: 12),
              TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 12),
              TextField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 8 characters)')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: C.down))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: save, child: const Text('Save and continue'))),
              TextButton(onPressed: () => context.read<Session>().logout(), child: const Text('Sign out')),
            ])),
          ),
        ),
      );
}
