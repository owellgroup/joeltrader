import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/candle_chart.dart';
import '../widgets/common.dart';

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});
  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> {
  static const tfs = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1'];
  String symbol = 'frxEURUSD', tf = 'M15', tool = 'none';
  List<Candle> candles = [];
  Map? overlay, analysis, signal;
  final show = <String>{'ema', 'sr', 'ob', 'tl'};
  final drawings = <Drawing>[];
  List symbols = [];
  List<String> favorites = [];
  bool loading = false, analyzing = false, email = true;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    s.get('/api/market/symbols').then((x) { if (mounted) setState(() => symbols = x); }).catchError((_) {});
    s.get('/api/watchlist').then((x) { if (mounted) setState(() => favorites = [for (final w in x) if (w['favorite'] == true) '${w['symbol']}']); }).catchError((_) {});
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => load(silent: true));
  }

  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> load({bool silent = false}) async {
    if (!silent) setState(() { loading = true; error = null; });
    try {
      final r = await context.read<Session>().get('/api/market/analyze', q: {'symbol': symbol, 'tf': tf});
      if (!mounted) return;
      setState(() {
        candles = [for (final m in r['candles']) Candle.from(m)];
        overlay = r['overlay'];
        error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => error = errMsg(e));
    }
    if (mounted && !silent) setState(() => loading = false);
  }

  void pick(String s) {
    setState(() { symbol = s; signal = null; analysis = null; drawings.clear(); });
    load();
  }

  Future<void> analyzeAuto() async {
    setState(() { analyzing = true; error = null; });
    try {
      final r = await context.read<Session>().get('/api/market/analyze', q: {'symbol': symbol, 'tf': 'M5', 'auto': true, 'email': email});
      if (!mounted) return;
      setState(() {
        analysis = r['analysis'];
        signal = r['analysis']['signal'];
        tf = 'M5';
        candles = [for (final m in r['candles']) Candle.from(m)];
        overlay = r['overlay'];
        show.addAll({'sr', 'ob', 'tl', 'fib'});
      });
      toast(context, signal != null ? 'Entry found${email ? ' - emailed to you' : ''}' : 'No clean entry right now');
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
    if (mounted) setState(() => analyzing = false);
  }

  Widget chip(String key, String label) => FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: show.contains(key),
        onSelected: (v) => setState(() => v ? show.add(key) : show.remove(key)),
      );

  Widget toolBtn(String k, IconData i, String tip) => IconButton(
        tooltip: tip,
        isSelected: tool == k,
        style: IconButton.styleFrom(backgroundColor: tool == k ? C.brand.withAlpha(80) : null),
        icon: Icon(i, size: 20),
        onPressed: () => setState(() => tool = tool == k ? 'none' : k),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final isFav = favorites.contains(symbol);
    final wide = MediaQuery.of(context).size.width > 900;
    return Column(children: [
      Container(
        color: C.panel,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Row(children: [
            SizedBox(
              width: wide ? 280 : 190,
              child: Autocomplete<Map>(
                displayStringForOption: (m) => '${m['symbol']}',
                optionsBuilder: (v) {
                  final q = v.text.toLowerCase();
                  if (q.isEmpty) return const Iterable<Map>.empty();
                  return symbols.cast<Map>().where((m) => '${m['symbol']}'.toLowerCase().contains(q) || '${m['name']}'.toLowerCase().contains(q)).take(20);
                },
                optionsViewBuilder: (ctx, onSel, opts) => Align(alignment: Alignment.topLeft, child: Material(
                  color: C.panel2, elevation: 6,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 280, maxWidth: 340), child: ListView(shrinkWrap: true, children: [
                    for (final m in opts) ListTile(dense: true, title: Text('${m['name']}'), subtitle: Text('${m['symbol']} · ${m['market']}'), onTap: () => onSel(m)),
                  ])),
                )),
                fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
                  controller: ctrl, focusNode: focus,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: symbol),
                  onSubmitted: (v) { if (v.trim().isNotEmpty) pick(v.trim()); },
                ),
                onSelected: (m) => pick('${m['symbol']}'),
              ),
            ),
            IconButton(
              tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(isFav ? Icons.star : Icons.star_border, color: C.gold),
              onPressed: () async {
                try {
                  if (isFav) { await s.put('/api/watchlist/$symbol', {'favorite': false}); setState(() => favorites.remove(symbol)); }
                  else { await s.put('/api/watchlist/$symbol', {'favorite': true}); setState(() => favorites.add(symbol)); }
                } catch (e) { toast(context, errMsg(e), error: true); }
              },
            ),
            Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final t in tfs) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                label: Text(t, style: const TextStyle(fontSize: 12)), selected: tf == t,
                onSelected: (_) { setState(() => tf = t); load(); },
              )),
            ]))),
          ]),
          if (favorites.isNotEmpty) SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in favorites) Padding(padding: const EdgeInsets.only(right: 6, top: 4), child: ActionChip(
              label: Text(f.replaceFirst('frx', ''), style: TextStyle(fontSize: 11, color: f == symbol ? C.gold : C.text)), onPressed: () => pick(f),
            )),
          ])),
          const SizedBox(height: 4),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            chip('ema', 'EMA 20/50/200'), const SizedBox(width: 6),
            chip('bb', 'Bollinger'), const SizedBox(width: 6),
            chip('sr', 'Support/Resistance'), const SizedBox(width: 6),
            chip('tl', 'Trendlines'), const SizedBox(width: 6),
            chip('ob', 'Order blocks'), const SizedBox(width: 6),
            chip('fib', 'Fibonacci'),
            const SizedBox(width: 12),
            toolBtn('h', Icons.horizontal_rule, 'Horizontal line'),
            toolBtn('t', Icons.show_chart, 'Trendline (2 taps)'),
            toolBtn('r', Icons.crop_square, 'Rectangle (2 taps)'),
            IconButton(tooltip: 'Clear drawings', icon: const Icon(Icons.delete_sweep_outlined, size: 20), onPressed: () => setState(drawings.clear)),
            const SizedBox(width: 12),
            Checkbox(value: email, onChanged: (v) => setState(() => email = v ?? true)),
            const Text('Email signal', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: analyzing ? null : analyzeAuto,
              icon: analyzing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_graph, size: 18),
              label: Text(analyzing ? 'Analyzing D1 to M5...' : 'Analyze automatically'),
            ),
          ])),
        ]),
      ),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: Container(
            color: C.bg,
            child: error != null
                ? Center(child: Text(error!, style: const TextStyle(color: C.down)))
                : CandleChart(
                    candles: candles, overlay: overlay, signal: signal, show: show, tf: tf, tool: tool, drawings: drawings,
                    onDraw: (d) => setState(() => drawings.add(d)),
                  ),
          )),
          if (loading) const Positioned(top: 8, right: 80, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          if (tool != 'none') Positioned(top: 8, left: 12, child: Pill(tool == 'h' ? 'Tap to place a line' : 'Tap two points', C.gold)),
        ]),
      ),
      if (analysis != null) _AnalysisPanel(symbol: symbol, a: analysis!),
    ]);
  }
}

class _AnalysisPanel extends StatelessWidget {
  final String symbol;
  final Map a;
  const _AnalysisPanel({required this.symbol, required this.a});
  @override
  Widget build(BuildContext context) {
    final sig = a['signal'] as Map?;
    final bias = Map<String, dynamic>.from(a['bias'] as Map);
    Color bc(String v) => v == 'bullish' ? C.up : v == 'bearish' ? C.down : C.muted;
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      width: double.infinity,
      color: C.panel,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Top-down bias', style: TextStyle(color: C.muted)),
          for (final e in bias.entries) Pill('${e.key} ${e.value}', bc('${e.value}')),
        ]),
        const SizedBox(height: 8),
        if (sig == null)
          Text('No clean entry on $symbol right now. ${a['note'] ?? ''} (best setup score ${a['best_score']}/100)', style: const TextStyle(color: C.gold))
        else ...[
          Wrap(spacing: 16, runSpacing: 4, children: [
            Pill('${sig['direction']}', sig['direction'] == 'BUY' ? C.up : C.down),
            Text('Entry ${sig['entry']?.toStringAsFixed(5)}'),
            Text('SL ${sig['sl']?.toStringAsFixed(5)}', style: const TextStyle(color: C.down)),
            Text('TP1 ${sig['tp1']?.toStringAsFixed(5)}', style: const TextStyle(color: C.up)),
            Text('TP2 ${sig['tp2']?.toStringAsFixed(5)}', style: const TextStyle(color: C.up)),
            Text('R:R ${sig['rr']}'),
            Text('Score ${sig['score']}/100', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          for (final r in (sig['reasons'] as List)) Text('• $r', style: const TextStyle(fontSize: 12, color: C.muted)),
        ],
      ])),
    );
  }
}
