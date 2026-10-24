import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class TradesPage extends StatefulWidget {
  const TradesPage({super.key});
  @override
  State<TradesPage> createState() => _TradesPageState();
}

class _TradesPageState extends State<TradesPage> {
  bool openOnly = false;
  int size = 50;

  Widget row(Map t) {
    final open = t['status'] == 'OPEN';
    final buy = t['direction'] == 'BUY';
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Row(children: [
        Pill('${t['direction'] ?? '-'}', buy ? C.up : C.down),
        const SizedBox(width: 10),
        Expanded(child: Text('${t['symbol'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(open ? 'open' : money(t['profit'], sign: true), style: TextStyle(color: open ? C.gold : pnlColor(t['profit']), fontWeight: FontWeight.w700)),
      ]),
      subtitle: Text('stake ${money(t['stake'])}  ·  ${t['kind'] ?? ''}  ·  ${ago(t['openedAt'])}', style: const TextStyle(fontSize: 12, color: C.muted)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entry ${t['entry'] ?? '-'}   SL ${t['sl'] ?? '-'}   TP ${t['tp'] ?? '-'}   score ${t['score'] ?? '-'}', style: const TextStyle(color: C.muted)),
        const SizedBox(height: 6),
        Text('${t['reason'] ?? 'No reasoning stored'}', style: const TextStyle(fontSize: 12)),
        if (!open) Text('Closed ${ago(t['closedAt'])}  sell ${t['sellPrice'] ?? '-'}', style: const TextStyle(color: C.muted, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      key: ValueKey('$openOnly$size'),
      every: const Duration(seconds: 8),
      load: () => openOnly ? s.get('/api/trades/open').then((x) => {'items': x, 'total': (x as List).length}) : s.get('/api/trades', q: {'size': size}),
      builder: (c, d, refresh) {
        final items = d['items'] as List;
        return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Transactions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('History')), ButtonSegment(value: true, label: Text('Open'))],
              selected: {openOnly},
              onSelectionChanged: (v) => setState(() => openOnly = v.first),
            ),
          ]),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: items.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No trades yet', style: TextStyle(color: C.muted))))
                : Column(children: [for (final t in items) ...[row(t as Map), const Divider(height: 1)]]),
          ),
          if (!openOnly && (d['total'] as num) > items.length)
            Center(child: TextButton(onPressed: () => setState(() => size += 50), child: Text('Load more (${d['total']} total)'))),
        ]));
      },
    );
  }
}
