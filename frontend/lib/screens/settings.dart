import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final cur = TextEditingController(), nw = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Grid([
        Panel(title: 'Profile', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.user?['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('${s.user?['email']}', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 8),
          Pill('${s.user?['role']}', C.brand),
          const SizedBox(height: 12),
          Text('Server: $apiUrl', style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => s.logout(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ])),
        Panel(title: 'Change password', child: Column(children: [
          TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 10),
          TextField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 8)')),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () async {
            try { await s.post('/api/auth/change-password', {'currentPassword': cur.text, 'newPassword': nw.text}); cur.clear(); nw.clear(); toast(context, 'Password changed'); }
            catch (e) { toast(context, errMsg(e), error: true); }
          }, child: const Text('Update'))),
        ])),
        Panel(title: 'Email reports', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('A daily report is emailed automatically at the end of each day. Signals, closed baskets and halts are emailed as they happen.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final d in [1, 7, 30])
              OutlinedButton(onPressed: () async {
                try { await s.post('/api/reports/send-now', null, {'days': d}); toast(context, 'Report sent to ${s.user?['email']}'); }
                catch (e) { toast(context, errMsg(e), error: true); }
              }, child: Text('Send ${d}d report')),
          ]),
        ])),
        const Panel(title: 'Risk notice', child: Text(
          'Trading is risky and you can lose your entire stake. Setup scores measure how many analysis signals agree; they are not a probability of winning and nothing here guarantees profit. Test on a demo account for several weeks before using real money.',
          style: TextStyle(color: C.muted, fontSize: 12),
        )),
      ], minWidth: 380),
    ]));
  }
}
