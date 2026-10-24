import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../core/api.dart';
import '../core/theme.dart';

double n(dynamic x) => x is num ? x.toDouble() : double.tryParse('$x') ?? 0;
String money(dynamic x, {bool sign = false}) {
  final v = n(x);
  return (sign && v > 0 ? '+' : '') + NumberFormat('#,##0.00').format(v);
}
Color pnlColor(dynamic x) => n(x) > 0 ? C.up : n(x) < 0 ? C.down : C.muted;
String ago(String? iso) {
  if (iso == null) return '-';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '-' : DateFormat('dd MMM HH:mm').format(d);
}

void toast(BuildContext c, String m, {bool error = false}) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? C.down : C.panel2));
}

class Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets padding;
  const Panel({super.key, this.title, required this.child, this.actions = const [], this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                ...actions,
              ]),
            ),
          child,
        ]),
      );
}

class Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  final String? sub;
  const Stat(this.label, this.value, {super.key, this.color, this.sub});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color ?? C.text))),
          if (sub != null) Text(sub!, style: const TextStyle(color: C.muted, fontSize: 11)),
        ]),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withAlpha(120))),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// Lays children out in a responsive grid (min tile width).
class Grid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  const Grid(this.children, {super.key, this.minWidth = 220});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, b) {
        final cols = (b.maxWidth / minWidth).floor().clamp(1, 12);
        final w = (b.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [for (final x in children) SizedBox(width: w, child: x)]);
      });
}

/// Loads data now and every [every]; rebuilds with the latest result.
class AsyncPoll<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Duration every;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  const AsyncPoll({super.key, required this.load, required this.builder, this.every = const Duration(seconds: 10)});
  @override
  State<AsyncPoll<T>> createState() => _AsyncPollState<T>();
}

class _AsyncPollState<T> extends State<AsyncPoll<T>> {
  T? data;
  Object? err;
  Timer? t;
  bool busy = false;

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final d = await widget.load();
      if (mounted) setState(() { data = d; err = null; });
    } catch (e) {
      if (mounted) setState(() => err = e);
    }
    busy = false;
  }

  @override
  void initState() {
    super.initState();
    refresh();
    t = Timer.periodic(widget.every, (_) => refresh());
  }

  @override
  void dispose() { t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      if (err != null) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errMsg(err), style: const TextStyle(color: C.down)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: refresh, child: const Text('Retry')),
        ]));
      }
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, data as T, refresh);
  }
}

Future<bool> confirm(BuildContext c, String title, String text, {String ok = 'Confirm'}) async {
  return await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;
}

Widget page(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1400), child: child)));
