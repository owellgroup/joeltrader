import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});
  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final extra = <String>{};
  final add = TextEditingController();
  bool highOnly = true;

  Color impact(String? i) => i == 'High' ? C.down : i == 'Medium' ? C.gold : C.muted;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Markets & News', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      SizedBox(
        height: 380,
        child: AsyncPoll<dynamic>(
          key: ValueKey(extra.join(',')),
          every: const Duration(seconds: 3),
          load: () => s.get('/api/market/quotes', q: {'extra': extra.join(',')}),
          builder: (c, q, r) => Panel(
            title: 'Live quotes',
            actions: [
              SizedBox(width: 150, child: TextField(controller: add, decoration: const InputDecoration(hintText: 'Add symbol e.g. frxEURJPY'), onSubmitted: (v) {
                if (v.trim().isNotEmpty) setState(() { extra.add(v.trim()); add.clear(); });
              })),
            ],
            child: Expanded(child: ListView(children: [
              for (final x in (q as List))
                ListTile(
                  dense: true,
                  title: Text('${x['symbol']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(x['price'] == null ? '-' : '${x['price']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(width: 70, child: Text('${n(x['change_pct']) >= 0 ? '+' : ''}${x['change_pct']}%', textAlign: TextAlign.right, style: TextStyle(color: pnlColor(x['change_pct']), fontSize: 12))),
                  ]),
                ),
            ])),
          ),
        ),
      ),
      const SizedBox(height: 16),
      AsyncPoll<dynamic>(
        every: const Duration(minutes: 5),
        load: () => s.get('/api/market/calendar'),
        builder: (c, list, r) {
          final evs = (list as List).where((e) => !highOnly || e['impact'] == 'High').toList();
          String? lastDay;
          return Panel(
            title: 'Economic calendar & high-impact news (this week)',
            actions: [
              const Text('High impact only', style: TextStyle(fontSize: 12, color: C.muted)),
              Switch(value: highOnly, onChanged: (v) => setState(() => highOnly = v)),
            ],
            child: evs.isEmpty
                ? const Text('No events (calendar feed unavailable or nothing scheduled).', style: TextStyle(color: C.muted))
                : Column(children: [
                    for (final e in evs) Builder(builder: (_) {
                      final t = DateTime.parse(e['time']).toLocal();
                      final day = DateFormat('EEEE d MMM').format(t);
                      final head = day != lastDay;
                      lastDay = day;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (head) Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(day, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700))),
                        ListTile(
                          dense: true, contentPadding: EdgeInsets.zero,
                          leading: SizedBox(width: 90, child: Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: impact(e['impact']), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(DateFormat('HH:mm').format(t)),
                          ])),
                          title: Text('${e['currency']}  ${e['title']}'),
                          subtitle: Text('Forecast ${e['forecast'] ?? '-'}   Previous ${e['previous'] ?? '-'}', style: const TextStyle(fontSize: 11)),
                          trailing: Pill('${e['impact']}', impact(e['impact'])),
                        ),
                      ]);
                    }),
                  ]),
          );
        },
      ),
      const SizedBox(height: 8),
      const Text('The bot closes trades and stays out of affected symbols around high-impact releases. Times shown in your local time zone.', style: TextStyle(color: C.muted, fontSize: 12)),
    ]));
  }
}
