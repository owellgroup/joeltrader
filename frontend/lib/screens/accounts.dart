import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  Future<void> link(BuildContext context, VoidCallback done) async {
    final s = context.read<Session>();
    final label = TextEditingController(), appId = TextEditingController(), token = TextEditingController();
    List found = [];
    String? err;
    bool busy = false;
    await showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
        title: const Text('Link a Deriv account'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create a Personal Access Token (scope: trade) in your Deriv developer dashboard and paste it with your App ID. Tokens are stored encrypted.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Label (optional)')),
          const SizedBox(height: 10),
          TextField(controller: appId, decoration: const InputDecoration(labelText: 'Deriv App ID')),
          const SizedBox(height: 10),
          TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Personal Access Token')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: C.down))),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy ? null : () async {
              set(() { busy = true; err = null; });
              try { found = await s.post('/api/accounts/discover', {'token': token.text, 'appId': appId.text}); if (found.isEmpty) err = 'No accounts found for this token'; }
              catch (e) { err = errMsg(e); }
              set(() => busy = false);
            },
            child: Text(busy ? 'Checking...' : 'Find my accounts'),
          ),
          for (final a in found)
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${a['accountId']}'),
              subtitle: Text('${a['accountType']}  ·  ${a['balance'] ?? '-'} ${a['currency'] ?? ''}'),
              trailing: FilledButton(
                onPressed: () async {
                  try {
                    await s.post('/api/accounts', {'label': label.text, 'token': token.text, 'appId': appId.text, 'accountId': a['accountId']});
                    if (dctx.mounted) Navigator.pop(dctx);
                    done();
                  } catch (e) { set(() => err = errMsg(e)); }
                },
                child: const Text('Link'),
              ),
            ),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Close'))],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      every: const Duration(minutes: 5),
      load: () => s.get('/api/accounts'),
      builder: (c, list, refresh) => page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Deriv accounts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          FilledButton.icon(onPressed: () => link(context, refresh), icon: const Icon(Icons.add_link), label: const Text('Link account')),
        ]),
        const SizedBox(height: 4),
        const Text('Only you can see and use the accounts you link. Start with a DEMO account.', style: TextStyle(color: C.muted)),
        const SizedBox(height: 16),
        if ((list as List).isEmpty) const Panel(child: Text('No accounts linked yet.', style: TextStyle(color: C.muted))),
        Grid([
          for (final a in list)
            Panel(
              title: '${a['label']}',
              actions: [Pill('${a['accountType']}', a['accountType'] == 'REAL' ? C.gold : C.brand)],
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['accountId']}  ·  ${a['currency'] ?? ''}', style: const TextStyle(color: C.muted)),
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton(onPressed: () async {
                    try {
                      final r = await s.get('/api/accounts/${a['id']}/refresh');
                      if (!context.mounted) return;
                      showDialog(context: context, builder: (_) => AlertDialog(
                        title: Text('${a['label']} balances'),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${money(r['balance'])} ${r['currency'] ?? ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                          const Divider(),
                          for (final x in (r['allAccounts'] as List)) ListTile(dense: true, title: Text('${x['accountId']}'), subtitle: Text('${x['accountType']}'), trailing: Text('${money(x['balance'])} ${x['currency']}')),
                        ]),
                      ));
                    } catch (e) { toast(context, errMsg(e), error: true); }
                  }, child: const Text('Balance')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () async {
                    final t = TextEditingController();
                    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                      title: const Text('Update token'),
                      content: TextField(controller: t, obscureText: true, decoration: const InputDecoration(labelText: 'New Personal Access Token')),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))],
                    ));
                    if (ok == true) { try { await s.put('/api/accounts/${a['id']}', {'token': t.text}); toast(context, 'Token updated'); } catch (e) { toast(context, errMsg(e), error: true); } }
                  }, child: const Text('Token')),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.delete_outline, color: C.down), onPressed: () async {
                    if (!await confirm(context, 'Remove account?', 'This unlinks ${a['accountId']} from joelTrader. Your Deriv account is not affected.')) return;
                    try { await s.delete('/api/accounts/${a['id']}'); refresh(); } catch (e) { toast(context, errMsg(e), error: true); }
                  }),
                ]),
              ]),
            ),
        ], minWidth: 340),
      ])),
    );
  }
}
