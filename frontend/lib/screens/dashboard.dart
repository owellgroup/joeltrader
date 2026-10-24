import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'performance.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      every: const Duration(seconds: 5),
      load: () => s.get('/api/dashboard'),
      builder: (c, d, refresh) {
        final bot = d['bot'] as Map;
        final p = d['performance30d'] as Map;
        final today = d['today'] as Map;
        final baskets = (bot['baskets'] ?? []) as List;
        final quotes = (d['quotes'] ?? []) as List;
        final bal = bot['balance'] ?? d['lastBalance'];
        return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Welcome, ${s.user?['name'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            Pill(bot['running'] == true ? 'BOT RUNNING' : 'BOT STOPPED', bot['running'] == true ? C.up : C.muted),
            if (bot['accountType'] != null) ...[const SizedBox(width: 8), Pill('${bot['accountType']}', bot['accountType'] == 'REAL' ? C.gold : C.brand)],
          ]),
          const SizedBox(height: 16),
          Grid([
            Stat('Balance', bal == null ? '-' : '${money(bal)} ${bot['currency'] ?? ''}'),
            Stat('Today P/L', money(today['netProfit'], sign: true), color: pnlColor(today['netProfit']), sub: '${today['trades']} closed trades'),
            Stat('30-day net', money(p['netProfit'], sign: true), color: pnlColor(p['netProfit'])),
            Stat('Win rate (30d)', '${p['winRate']}%', sub: 'PF ${p['profitFactor'] ?? '∞'}'),
            Stat('Open baskets', '${baskets.length}', sub: '${bot['phase'] ?? ''}'),
          ], minWidth: 180),
          const SizedBox(height: 16),
          Grid([
            Panel(title: 'Equity curve (30d)', child: EquityChart(p['equityCurve'])),
            Panel(title: 'Live positions', child: baskets.isEmpty
                ? const Padding(padding: EdgeInsets.all(12), child: Text('No open positions. The bot is scanning for a clean entry.', style: TextStyle(color: C.muted)))
                : Column(children: [
                    for (final b in baskets)
                      ListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        leading: Pill('${b['direction']}', b['direction'] == 'BUY' ? C.up : C.down),
                        title: Text('${b['symbol']}  ·  ${b['contracts']} contracts'),
                        subtitle: Text('stake ${money(b['stake'])}  ·  ${b['kind']}  ·  score ${b['score']}'),
                        trailing: Text(money(b['pnl'], sign: true), style: TextStyle(color: pnlColor(b['pnl']), fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                  ])),
          ], minWidth: 460),
          const SizedBox(height: 16),
          Panel(title: 'Live market quotes', child: quotes.isEmpty
              ? const Text('Waiting for ticks...', style: TextStyle(color: C.muted))
              : Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final q in quotes)
                    Container(
                      width: 170, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${q['symbol']}'.replaceFirst('frx', ''), style: const TextStyle(color: C.muted, fontSize: 12)),
                        Text(q['price'] == null ? '-' : '${q['price']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text('${n(q['change_pct']) >= 0 ? '+' : ''}${q['change_pct']}%', style: TextStyle(color: pnlColor(q['change_pct']), fontSize: 12)),
                      ]),
                    ),
                ])),
          const SizedBox(height: 16),
          Grid([
            Panel(title: 'Latest signals', child: (d['recentSignals'] as List).isEmpty
                ? const Text('No signals yet. Open Charts and press "Analyze automatically", or enable signal alerts in Signals.', style: TextStyle(color: C.muted))
                : Column(children: [
                    for (final x in d['recentSignals'])
                      ListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        leading: Pill('${x['direction']}', x['direction'] == 'BUY' ? C.up : C.down),
                        title: Text('${x['symbol']}  @ ${x['entry']}'),
                        subtitle: Text('SL ${x['sl']}  TP ${x['tp1']}  ·  ${ago(x['createdAt'])}'),
                        trailing: Text('${x['score']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ])),
            Panel(title: 'Bot activity', child: SizedBox(
              height: 180,
              child: ListView(children: [
                for (final l in ((bot['logs'] ?? []) as List).reversed.take(15))
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${ago(l['t'])}  ${l['msg']}', style: TextStyle(fontSize: 12, color: l['level'] == 'error' ? C.down : l['level'] == 'warn' ? C.gold : C.muted))),
              ]),
            )),
          ], minWidth: 460),
        ]));
      },
    );
  }
}
