import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class AdminsPage extends StatelessWidget {
  const AdminsPage({super.key});

  Future<void> create(BuildContext context, VoidCallback done) async {
    final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Add admin'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 10),
        TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 10),
        TextField(controller: pass, decoration: const InputDecoration(labelText: 'Temporary password (min 8)')),
        const SizedBox(height: 8),
        const Text('They must change it at first login. Each admin only ever sees their own accounts and data.', style: TextStyle(color: C.muted, fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Create'))],
    ));
    if (ok != true) return;
    try {
      await context.read<Session>().post('/api/admins', {'name': name.text, 'email': email.text, 'password': pass.text});
      done();
    } catch (e) { if (context.mounted) toast(context, errMsg(e), error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      every: const Duration(minutes: 1),
      load: () => s.get('/api/admins'),
      builder: (c, list, refresh) => page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Administrators', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          FilledButton.icon(onPressed: () => create(context, refresh), icon: const Icon(Icons.person_add_alt), label: const Text('Add admin')),
        ]),
        const SizedBox(height: 12),
        Panel(padding: EdgeInsets.zero, child: Column(children: [
          for (final u in (list as List)) ...[
            ListTile(
              leading: CircleAvatar(backgroundColor: C.brand.withAlpha(60), child: Text('${u['name'] ?? u['email']}'.substring(0, 1).toUpperCase())),
              title: Text('${u['name']}'),
              subtitle: Text('${u['email']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Pill('${u['role']}', u['role'] == 'SUPER_ADMIN' ? C.gold : C.brand),
                const SizedBox(width: 8),
                if (s.isSuper && u['role'] != 'SUPER_ADMIN') ...[
                  Switch(value: u['enabled'] == true, onChanged: (v) async {
                    try { await s.patch('/api/admins/${u['id']}/enabled', {'enabled': v}); refresh(); } catch (e) { toast(context, errMsg(e), error: true); }
                  }),
                  IconButton(icon: const Icon(Icons.delete_outline, color: C.down), onPressed: () async {
                    if (!await confirm(context, 'Delete admin?', 'This permanently deletes ${u['email']} and all their linked accounts, trades and signals.', ok: 'Delete')) return;
                    try { await s.delete('/api/admins/${u['id']}'); refresh(); } catch (e) { toast(context, errMsg(e), error: true); }
                  }),
                ],
              ]),
            ),
            const Divider(height: 1),
          ],
        ])),
      ])),
    );
  }
}
