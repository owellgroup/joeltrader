import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class EquityChart extends StatelessWidget {
  final List curve;
  final double height;
  const EquityChart(this.curve, {super.key, this.height = 220});
  @override
  Widget build(BuildContext context) {
    if (curve.isEmpty) return SizedBox(height: height, child: const Center(child: Text('No closed trades yet', style: TextStyle(color: C.muted))));
    final spots = [for (var i = 0; i < curve.length; i++) FlSpot(i.toDouble(), n(curve[i]['equity']))];
    final up = spots.last.y >= 0;
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: C.line, strokeWidth: 0.5)),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(), rightTitles: AxisTitles(), bottomTitles: AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, barWidth: 2, dotData: const FlDotData(show: false),
            color: up ? C.up : C.down,
            belowBarData: BarAreaData(show: true, color: (up ? C.up : C.down).withAlpha(30)),
          ),
        ],
      )),
    );
  }
}

class GroupBars extends StatelessWidget {
  final List rows;
  const GroupBars(this.rows, {super.key});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox(height: 60, child: Center(child: Text('No data', style: TextStyle(color: C.muted))));
    return SizedBox(
      height: 180,
      child: BarChart(BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 26,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= rows.length) return const SizedBox();
              final k = '${rows[i]['key']}'.replaceFirst('frx', '');
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(k.length > 7 ? k.substring(k.length - 5) : k, style: const TextStyle(fontSize: 9, color: C.muted)));
            },
          )),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: n(rows[i]['net']), width: 12, color: n(rows[i]['net']) >= 0 ? C.up : C.down, borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      )),
    );
  }
}

class PerformancePage extends StatefulWidget {
  const PerformancePage({super.key});
  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  int days = 30;
  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      key: ValueKey(days),
      every: const Duration(seconds: 30),
      load: () => s.get('/api/performance', q: {'days': days}),
      builder: (c, p, refresh) => page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Performance analysis', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 30, label: Text('30d')), ButtonSegment(value: 90, label: Text('90d'))],
            selected: {days},
            onSelectionChanged: (v) => setState(() => days = v.first),
          ),
        ]),
        const SizedBox(height: 16),
        Grid([
          Stat('Net profit', money(p['netProfit'], sign: true), color: pnlColor(p['netProfit'])),
          Stat('Win rate', '${p['winRate']}%', sub: '${p['wins']}W / ${p['losses']}L of ${p['trades']}'),
          Stat('Profit factor', p['profitFactor'] == null ? '∞' : '${p['profitFactor']}'),
          Stat('Expectancy / trade', money(p['expectancy'], sign: true), color: pnlColor(p['expectancy'])),
          Stat('Avg win', money(p['avgWin']), color: C.up),
          Stat('Avg loss', money(p['avgLoss']), color: C.down),
          Stat('Max drawdown', money(p['maxDrawdown']), color: C.down),
          Stat('Best / worst', '${money(p['best'])} / ${money(p['worst'])}'),
        ], minWidth: 170),
        const SizedBox(height: 16),
        Panel(title: 'Equity curve (closed trades)', child: EquityChart(p['equityCurve'])),
        const SizedBox(height: 16),
        Grid([
          Panel(title: 'Net P/L by symbol', child: GroupBars(p['bySymbol'])),
          Panel(title: 'Net P/L by day', child: GroupBars(p['byDay'])),
          Panel(title: 'Net P/L by hour (UTC)', child: GroupBars(p['byHour'])),
          Panel(title: 'Auto vs news trades', child: GroupBars(p['byKind'])),
        ], minWidth: 420),
        const SizedBox(height: 16),
        Panel(title: 'Symbol breakdown', child: Table(columnWidths: const {0: FlexColumnWidth(2)}, children: [
          const TableRow(children: [Text('Symbol', style: TextStyle(color: C.muted)), Text('Trades', style: TextStyle(color: C.muted)), Text('Win %', style: TextStyle(color: C.muted)), Text('Net', style: TextStyle(color: C.muted))]),
          for (final r in p['bySymbol'])
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${r['key']}')),
              Text('${r['trades']}'), Text('${r['winRate']}%'),
              Text(money(r['net'], sign: true), style: TextStyle(color: pnlColor(r['net']))),
            ]),
        ])),
      ])),
    );
  }
}
