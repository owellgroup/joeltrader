import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import 'common.dart';

class Candle {
  final int t;
  final double o, h, l, c;
  Candle(this.t, this.o, this.h, this.l, this.c);
  factory Candle.from(Map m) => Candle((m['time'] as num).toInt(), n(m['open']), n(m['high']), n(m['low']), n(m['close']));
}

/// A drawing made by the user. Points are stored as (epoch seconds, price) so they stay put when new candles arrive.
class Drawing {
  final String kind; // h = horizontal line, t = trendline, r = rectangle
  final List<Offset> pts; // dx = time, dy = price
  Drawing(this.kind, this.pts);
}

class Geo {
  final Size size;
  final List<Candle> c;
  final double barW, offset;
  late final double plotW, plotH, lastVis, minP, maxP, step;
  static const axisW = 68.0, axisH = 22.0;

  Geo(this.size, this.c, this.barW, this.offset, List<double> extra) {
    plotW = size.width - axisW;
    plotH = size.height - axisH;
    lastVis = (c.length - 1) - offset + 3;
    step = c.length > 1 ? (c.last.t - c.first.t) / (c.length - 1) : 60;
    var lo = double.infinity, hi = -double.infinity;
    final a = math.max(0, (lastVis - plotW / barW).floor()), b = math.min(c.length - 1, lastVis.ceil());
    for (var i = a; i <= b; i++) {
      lo = math.min(lo, c[i].l);
      hi = math.max(hi, c[i].h);
    }
    for (final e in extra) {
      if (e.isFinite && hi.isFinite && e > lo - (hi - lo) * 1.5 && e < hi + (hi - lo) * 1.5) {
        lo = math.min(lo, e);
        hi = math.max(hi, e);
      }
    }
    if (!lo.isFinite || hi <= lo) { lo = (lo.isFinite ? lo : 0) - 1; hi = lo + 2; }
    final pad = (hi - lo) * 0.07;
    minP = lo - pad;
    maxP = hi + pad;
  }

  double x(double idx) => plotW - (lastVis - idx) * barW;
  double y(double p) => plotH - (p - minP) / (maxP - minP) * plotH;
  double priceAt(double py) => minP + (plotH - py) / plotH * (maxP - minP);
  double idxAtX(double px) => lastVis - (plotW - px) / barW;

  double idxOfTime(double t) {
    if (c.isEmpty) return 0;
    if (t >= c.last.t) return c.length - 1 + (t - c.last.t) / step;
    if (t <= c.first.t) return (t - c.first.t) / step;
    var lo = 0, hi = c.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) >> 1;
      if (c[m].t <= t) { lo = m; } else { hi = m; }
    }
    return lo + (t - c[lo].t) / math.max(1, c[hi].t - c[lo].t);
  }

  double timeAtIdx(double i) {
    if (i >= c.length - 1) return c.last.t + (i - (c.length - 1)) * step;
    if (i <= 0) return c.first.t + i * step;
    final lo = i.floor();
    return c[lo].t + (i - lo) * (c[lo + 1].t - c[lo].t);
  }
}

class ChartPainter extends CustomPainter {
  final List<Candle> c;
  final Map? ov;
  final Map? sig;
  final Set<String> show;
  final List<Drawing> drawings;
  final Drawing? pending;
  final double barW, offset;
  final Offset? cross;
  final String tf;
  ChartPainter(this.c, this.ov, this.sig, this.show, this.drawings, this.pending, this.barW, this.offset, this.cross, this.tf);

  List<double> _levels() {
    if (sig == null) return [];
    return [n(sig!['entry']), n(sig!['sl']), n(sig!['tp1']), n(sig!['tp2'])];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (c.length < 2) return;
    final g = Geo(size, c, barW, offset, _levels());
    final paint = Paint();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, g.plotW, g.plotH));

    // grid
    paint..color = C.line.withAlpha(120)..strokeWidth = 0.5;
    for (var i = 0; i <= 6; i++) {
      final y = g.plotH / 6 * i;
      canvas.drawLine(Offset(0, y), Offset(g.plotW, y), paint);
    }

    // zones from analysis
    if (ov != null) {
      if (show.contains('ob')) {
        for (final o in (ov!['order_blocks'] as List)) {
          final x1 = g.x(g.idxOfTime(n(o['t'])));
          final r = Rect.fromLTRB(x1, g.y(n(o['high'])), g.plotW, g.y(n(o['low'])));
          final bull = o['type'] == 'bullish';
          canvas.drawRect(r, Paint()..color = (bull ? C.up : C.down).withAlpha(45));
          canvas.drawRect(r, Paint()..color = (bull ? C.up : C.down).withAlpha(120)..style = PaintingStyle.stroke);
          _text(canvas, bull ? 'Bullish OB' : 'Bearish OB', Offset(math.max(x1, 4) + 4, r.top + 2), 10, (bull ? C.up : C.down));
        }
      }
      if (show.contains('sr')) {
        for (final s in (ov!['sr'] as List)) {
          final y = g.y(n(s['price']));
          _dashed(canvas, Offset(0, y), Offset(g.plotW, y), (s['type'] == 'support' ? C.up : C.down).withAlpha(170));
          _text(canvas, '${s['type'] == 'support' ? 'S' : 'R'} x${s['touches']}', Offset(4, y - 12), 10, C.muted);
        }
      }
      if (show.contains('fib') && ov!['fib'] != null) {
        final f = ov!['fib'] as Map;
        final x1 = g.x(math.min(g.idxOfTime(n(f['t_hi'])), g.idxOfTime(n(f['t_lo']))));
        (f['levels'] as Map).forEach((k, v) {
          final y = g.y(n(v));
          canvas.drawLine(Offset(math.max(0, x1), y), Offset(g.plotW, y), Paint()..color = C.gold.withAlpha(110)..strokeWidth = 0.8);
          _text(canvas, 'Fib $k', Offset(g.plotW - 54, y - 11), 9, C.gold);
        });
      }
      if (show.contains('tl')) {
        for (final t in (ov!['trendlines'] as List)) {
          final i1 = g.idxOfTime(n(t['t1']));
          final slope = n(t['slope_per_bar']);
          final p1 = n(t['p1']);
          final i2 = g.lastVis;
          final broken = t['broken'] == true;
          _dashed(canvas, Offset(g.x(i1), g.y(p1)), Offset(g.x(i2), g.y(p1 + slope * (i2 - i1))), (broken ? C.muted : Colors.cyanAccent).withAlpha(220));
        }
      }
    }

    // indicators
    final ind = ov?['indicators'] as Map?;
    if (ind != null) {
      if (show.contains('ema')) {
        _series(canvas, g, ind['ema20'], Colors.orangeAccent);
        _series(canvas, g, ind['ema50'], Colors.lightBlueAccent);
        _series(canvas, g, ind['ema200'], Colors.purpleAccent);
      }
      if (show.contains('bb')) {
        _series(canvas, g, ind['bb_upper'], C.muted);
        _series(canvas, g, ind['bb_mid'], C.muted.withAlpha(120));
        _series(canvas, g, ind['bb_lower'], C.muted);
      }
    }

    // candles
    final a = math.max(0, g.idxAtX(0).floor()), b = math.min(c.length - 1, g.lastVis.ceil());
    final bw = math.max(1.0, barW * 0.7);
    for (var i = a; i <= b; i++) {
      final k = c[i];
      final up = k.c >= k.o;
      final col = up ? C.up : C.down;
      final x = g.x(i.toDouble());
      paint..color = col..strokeWidth = 1;
      canvas.drawLine(Offset(x, g.y(k.h)), Offset(x, g.y(k.l)), paint);
      final top = g.y(math.max(k.o, k.c)), bot = g.y(math.min(k.o, k.c));
      canvas.drawRect(Rect.fromLTRB(x - bw / 2, top, x + bw / 2, math.max(bot, top + 1)), paint..style = PaintingStyle.fill);
    }

    // signal levels
    if (sig != null) {
      final x0 = g.x((c.length - 1).toDouble());
      void zone(double p1, double p2, Color col) =>
          canvas.drawRect(Rect.fromLTRB(x0, math.min(g.y(p1), g.y(p2)), g.plotW, math.max(g.y(p1), g.y(p2))), Paint()..color = col.withAlpha(45));
      zone(n(sig!['entry']), n(sig!['sl']), C.down);
      zone(n(sig!['entry']), n(sig!['tp1']), C.up);
      void line(String label, double p, Color col) {
        final y = g.y(p);
        canvas.drawLine(Offset(0, y), Offset(g.plotW, y), Paint()..color = col..strokeWidth = 1.4);
        _text(canvas, '$label ${_fmt(p)}', Offset(8, y - 13), 11, col, bold: true);
      }
      line('ENTRY', n(sig!['entry']), C.brand);
      line('SL', n(sig!['sl']), C.down);
      line('TP1', n(sig!['tp1']), C.up);
      line('TP2', n(sig!['tp2']), C.up.withAlpha(180));
    }

    // user drawings
    for (final d in [...drawings, if (pending != null) pending!]) {
      final p = Paint()..color = C.gold..strokeWidth = 1.5..style = PaintingStyle.stroke;
      Offset pt(Offset o) => Offset(g.x(g.idxOfTime(o.dx)), g.y(o.dy));
      if (d.kind == 'h') {
        canvas.drawLine(Offset(0, g.y(d.pts[0].dy)), Offset(g.plotW, g.y(d.pts[0].dy)), p);
      } else if (d.pts.length == 2 && d.kind == 't') {
        final a1 = pt(d.pts[0]), a2 = pt(d.pts[1]);
        final k = a2.dx == a1.dx ? 0.0 : (a2.dy - a1.dy) / (a2.dx - a1.dx);
        canvas.drawLine(a1, Offset(g.plotW + 400, a1.dy + k * (g.plotW + 400 - a1.dx)), p);
      } else if (d.pts.length == 2 && d.kind == 'r') {
        canvas.drawRect(Rect.fromPoints(pt(d.pts[0]), pt(d.pts[1])), p);
        canvas.drawRect(Rect.fromPoints(pt(d.pts[0]), pt(d.pts[1])), Paint()..color = C.gold.withAlpha(25));
      }
    }

    // crosshair
    if (cross != null && cross!.dx < g.plotW && cross!.dy < g.plotH) {
      final p = Paint()..color = C.muted..strokeWidth = 0.6;
      canvas.drawLine(Offset(cross!.dx, 0), Offset(cross!.dx, g.plotH), p);
      canvas.drawLine(Offset(0, cross!.dy), Offset(g.plotW, cross!.dy), p);
      final i = g.idxAtX(cross!.dx).round();
      if (i >= 0 && i < c.length) {
        final k = c[i];
        _text(canvas, '${DateFormat('dd MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(k.t * 1000))}  O ${_fmt(k.o)}  H ${_fmt(k.h)}  L ${_fmt(k.l)}  C ${_fmt(k.c)}', const Offset(8, 4), 11, C.text);
      }
    }
    canvas.restore();

    // price axis
    canvas.drawRect(Rect.fromLTWH(g.plotW, 0, Geo.axisW, size.height), Paint()..color = C.panel);
    for (var i = 0; i <= 6; i++) {
      final y = g.plotH / 6 * i;
      _text(canvas, _fmt(g.priceAt(y)), Offset(g.plotW + 4, y - 6), 10, C.muted);
    }
    final last = c.last;
    final ly = g.y(last.c);
    canvas.drawRect(Rect.fromLTWH(g.plotW, ly - 9, Geo.axisW, 18), Paint()..color = last.c >= last.o ? C.up : C.down);
    _text(canvas, _fmt(last.c), Offset(g.plotW + 4, ly - 6), 10, Colors.white, bold: true);
    if (cross != null && cross!.dy < g.plotH) {
      canvas.drawRect(Rect.fromLTWH(g.plotW, cross!.dy - 9, Geo.axisW, 18), Paint()..color = C.panel2);
      _text(canvas, _fmt(g.priceAt(cross!.dy)), Offset(g.plotW + 4, cross!.dy - 6), 10, C.text);
    }
    // time axis
    canvas.drawRect(Rect.fromLTWH(0, g.plotH, size.width, Geo.axisH), Paint()..color = C.panel);
    final fmt = (tf == 'D1') ? DateFormat('dd MMM') : DateFormat('dd HH:mm');
    final every = math.max(1, (110 / barW).round());
    for (var i = (a ~/ every) * every; i <= b; i += every) {
      if (i < 0) continue;
      _text(canvas, fmt.format(DateTime.fromMillisecondsSinceEpoch(c[i].t * 1000)), Offset(g.x(i.toDouble()) - 22, g.plotH + 5), 9, C.muted);
    }
  }

  String _fmt(double v) => v.abs() >= 100 ? v.toStringAsFixed(2) : v.abs() >= 1 ? v.toStringAsFixed(4) : v.toStringAsFixed(5);

  void _series(Canvas canvas, Geo g, dynamic data, Color col) {
    if (data == null) return;
    final list = data as List;
    final path = Path();
    var started = false;
    final a = math.max(0, g.idxAtX(0).floor()), b = math.min(list.length - 1, g.lastVis.ceil());
    for (var i = a; i <= b; i++) {
      final v = list[i];
      if (v == null) { started = false; continue; }
      final o = Offset(g.x(i.toDouble()), g.y(n(v)));
      if (!started) { path.moveTo(o.dx, o.dy); started = true; } else { path.lineTo(o.dx, o.dy); }
    }
    canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.1);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color col) {
    final p = Paint()..color = col..strokeWidth = 1;
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (double d = 0; d < len; d += 9) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 5, len), p);
    }
  }

  void _text(Canvas canvas, String s, Offset o, double size, Color col, {bool bold = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)), textDirection: ui_td)..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant ChartPainter o) => true;
}

const ui_td = TextDirection.ltr;

/// TradingView-style chart: drag to pan, pinch / mouse-wheel to zoom, tap with a drawing tool to draw.
class CandleChart extends StatefulWidget {
  final List<Candle> candles;
  final Map? overlay, signal;
  final Set<String> show;
  final String tf, tool; // tool: none | h | t | r
  final List<Drawing> drawings;
  final void Function(Drawing) onDraw;
  const CandleChart({super.key, required this.candles, this.overlay, this.signal, required this.show, required this.tf,
      required this.tool, required this.drawings, required this.onDraw});
  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  double barW = 8, offset = 0, _startBar = 8, _startOff = 0, _startX = 0;
  Offset? cross;
  Offset? firstPoint; // pending first point (time, price)
  Geo? geo;

  void _reset() { offset = 0; firstPoint = null; }

  @override
  void didUpdateWidget(CandleChart old) {
    super.didUpdateWidget(old);
    if (old.tf != widget.tf || old.tool != widget.tool) firstPoint = null;
    if (old.candles.isNotEmpty && widget.candles.isNotEmpty && old.candles.first.t != widget.candles.first.t && old.tf != widget.tf) _reset();
  }

  Offset _toData(Offset local) {
    final g = geo!;
    return Offset(g.timeAtIdx(g.idxAtX(local.dx)), g.priceAt(local.dy));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.length < 2) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (ctx, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      geo = Geo(size, widget.candles, barW, offset, const []);
      Drawing? pending;
      if (firstPoint != null && cross != null && widget.tool != 'h') {
        pending = Drawing(widget.tool, [firstPoint!, _toData(cross!)]);
      }
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) setState(() => barW = (barW * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(2.0, 40.0));
        },
        child: MouseRegion(
          onHover: (e) => setState(() => cross = e.localPosition),
          onExit: (_) => setState(() => cross = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (widget.tool == 'none') return;
              final p = _toData(d.localPosition);
              if (widget.tool == 'h') { widget.onDraw(Drawing('h', [p])); return; }
              if (firstPoint == null) { setState(() => firstPoint = p); } else { widget.onDraw(Drawing(widget.tool, [firstPoint!, p])); setState(() => firstPoint = null); }
            },
            onLongPressStart: (d) => setState(() => cross = d.localPosition),
            onLongPressMoveUpdate: (d) => setState(() => cross = d.localPosition),
            onLongPressEnd: (_) => setState(() => cross = null),
            onScaleStart: (d) { _startBar = barW; _startOff = offset; _startX = d.localFocalPoint.dx; },
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount >= 2) {
                barW = (_startBar * d.scale).clamp(2.0, 40.0);
              } else {
                offset = (_startOff + (d.localFocalPoint.dx - _startX) / barW).clamp(-3.0, widget.candles.length - 10.0);
              }
            }),
            child: ClipRect(child: CustomPaint(size: size, painter: ChartPainter(widget.candles, widget.overlay, widget.signal, widget.show, widget.drawings, pending, barW, offset, cross, widget.tf))),
          ),
        ),
      );
    });
  }
}
