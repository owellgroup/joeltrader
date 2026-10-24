import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SignalsPage extends StatefulWidget {
  const SignalsPage({super.key});
  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  final sym = TextEditingController();
  int tick = 0;

  Widget signalCard(Map x) => Panel(
        title: '${x['symbol']}',
        actions: [Pill('${x['direction']}', x['direction'] == 'BUY' ? C.up : C.down), const SizedBox(width: 8), Text('${x['score']}/100', style: const TextStyle(fontWeight: FontWeight.w700))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 18, children: [
            Text('Entry ${x['entry']}'),
            Text('SL ${x['sl']}', style: const TextStyle(color: C.down)),
            Text('TP1 ${x['tp1']}', style: const TextStyle(color: C.up)),
            Text('TP2 ${x['tp2']}', style: const TextStyle(color: C.up)),
            Text('R:R ${x['rr']}'),
          ]),
          const SizedBox(height: 8),
          Text('${x['reasons'] ?? ''}', style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text('${x['source']} · ${ago(x['createdAt'])}', style: const TextStyle(color: C.muted, fontSize: 11)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Signals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const Text('Signals are for you to trade manually. They are never executed by the bot.', style: TextStyle(color: C.muted)),
      const SizedBox(height: 16),
      Grid([
        Panel(title: 'Email me clean setups', child: AsyncPoll<dynamic>(
          key: ValueKey(tick),
          every: const Duration(minutes: 5),
          load: () => s.get('/api/watchlist'),
          builder: (c, list, refresh) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The engine scans these symbols every few minutes (D1 to M5) and emails a signal when a clean entry forms.', style: TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: sym, decoration: const InputDecoration(hintText: 'Symbol e.g. frxEURUSD, frxXAUUSD, R_100'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: () async {
                if (sym.text.trim().isEmpty) return;
                try { await s.put('/api/watchlist/${sym.text.trim()}', {'favorite': true, 'signals': true}); sym.clear(); refresh(); } catch (e) { toast(context, errMsg(e), error: true); }
              }, child: const Text('Add')),
            ]),
            for (final w in (list as List))
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: Text('${w['symbol']}'),
                leading: Switch(value: w['signals'] == true, onChanged: (v) async { await s.put('/api/watchlist/${w['symbol']}', {'signals': v}); refresh(); }),
                trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () async { await s.delete('/api/watchlist/${w['symbol']}'); refresh(); }),
              ),
          ]),
        )),
        Panel(title: 'Analyze now', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('For the chart view with the full analysis drawn on it, use the Charts page.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 8),
          _QuickAnalyze(onDone: () => setState(() => tick++)),
        ])),
      ], minWidth: 420),
      const SizedBox(height: 16),
      AsyncPoll<dynamic>(
        key: ValueKey('h$tick'),
        every: const Duration(seconds: 30),
        load: () => s.get('/api/signals'),
        builder: (c, list, r) => (list as List).isEmpty
            ? const Panel(child: Text('No signals yet.', style: TextStyle(color: C.muted)))
            : Grid([for (final x in list) signalCard(x as Map)], minWidth: 420),
      ),
    ]));
  }
}

class _QuickAnalyze extends StatefulWidget {
  final VoidCallback onDone;
  const _QuickAnalyze({required this.onDone});
  @override
  State<_QuickAnalyze> createState() => _QuickAnalyzeState();
}

class _QuickAnalyzeState extends State<_QuickAnalyze> {
  final c = TextEditingController(text: 'frxEURUSD');
  bool busy = false;
  String? result;

  Future<void> run() async {
    setState(() { busy = true; result = null; });
    try {
      final r = await context.read<Session>().get('/api/market/analyze', q: {'symbol': c.text.trim(), 'auto': true, 'email': true});
      final a = r['analysis'];
      result = a['signal'] != null ? '${a['signal']['direction']} signal found and emailed. See the list below.' : 'No clean entry now: ${a['note']}';
      widget.onDone();
    } catch (e) { result = errMsg(e); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(controller: c)),
          const SizedBox(width: 8),
          FilledButton(onPressed: busy ? null : run, child: Text(busy ? 'Analyzing...' : 'Analyze')),
        ]),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(result!)),
      ]);
}
