import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class BotPage extends StatefulWidget {
  const BotPage({super.key});
  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  int? accountId;
  bool allowReal = false;
  Map<String, dynamic> cfg = {};
  bool cfgLoaded = false;
  List accounts = [];

  @override
  void initState() {
    super.initState();
    context.read<Session>().get('/api/accounts').then((a) { if (mounted) setState(() => accounts = a); });
  }

  Future<void> start(Map bot) async {
    final s = context.read<Session>();
    final acc = accounts.cast<Map>().where((a) => a['id'] == accountId).toList();
    if (acc.isEmpty) return toast(context, 'Select a Deriv account first', error: true);
    final real = acc.first['accountType'] == 'REAL';
    if (real && !allowReal) return toast(context, 'REAL account: tick "I allow real-money trading" first', error: true);
    if (real && !await confirm(context, 'Trade with REAL money?', 'The bot will place live trades on ${acc.first['accountId']}. You can lose your stake. Continue?', ok: 'Start real trading')) return;
    try {
      await s.post('/api/bot/start', {'accountId': accountId, 'config': cfg, 'allowReal': allowReal});
      toast(context, 'Bot started');
    } catch (e) { toast(context, errMsg(e), error: true); }
  }

  Future<void> stop() async {
    final close = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop trading'),
        content: const Text('Close all open positions now, or stop opening new trades and let open ones finish?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Let open trades finish')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close everything')),
        ],
      ),
    );
    if (close == null) return;
    try { await context.read<Session>().post('/api/bot/stop', {'closeOpen': close}); toast(context, 'Bot stopped'); }
    catch (e) { toast(context, errMsg(e), error: true); }
  }

  Widget slider(String key, String label, double min, double max, {int? div, String unit = ''}) {
    final v = n(cfg[key]).clamp(min, max).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${v.toStringAsFixed(div == null ? 1 : 0)}$unit', style: const TextStyle(fontSize: 12, color: C.muted)),
      Slider(value: v, min: min, max: max, divisions: div, onChanged: (x) => setState(() => cfg[key] = div != null ? x.roundToDouble() : double.parse(x.toStringAsFixed(1)))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return AsyncPoll<dynamic>(
      every: const Duration(seconds: 4),
      load: () => s.get('/api/bot'),
      builder: (c, d, refresh) {
        final bot = Map<String, dynamic>.from(d['state'] as Map);
        final running = d['running'] == true && bot['running'] == true;
        if (!cfgLoaded) {
          cfg = Map<String, dynamic>.from(bot['config'] ?? {})..addAll(Map<String, dynamic>.from(d['config'] ?? {}));
          cfg.remove('allow_real'); cfg.remove('allow_real_saved');
          accountId ??= d['accountId'];
          cfgLoaded = true;
        }
        final baskets = (bot['baskets'] ?? []) as List;
        return page(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Panel(
            child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Pill(running ? 'RUNNING 24/7' : 'STOPPED', running ? C.up : C.muted),
              Text(bot['phase'] ?? '', style: const TextStyle(color: C.muted)),
              if (bot['halted'] != null) Pill('HALTED: ${bot['halted']}', C.gold),
              if (n(bot['cooldownSec']) > 0) Pill('cooldown ${(n(bot['cooldownSec']) / 60).ceil()} min', C.gold),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<int>(
                  value: accounts.any((a) => a['id'] == accountId) ? accountId : null,
                  hint: const Text('Deriv account'),
                  decoration: const InputDecoration(labelText: 'Trade on account'),
                  items: [for (final a in accounts) DropdownMenuItem<int>(value: a['id'], child: Text('${a['label']} (${a['accountType']})'))],
                  onChanged: running ? null : (v) => setState(() => accountId = v),
                ),
              ),
              if (accounts.cast<Map>().any((a) => a['id'] == accountId && a['accountType'] == 'REAL'))
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: allowReal, onChanged: (v) => setState(() => allowReal = v ?? false)),
                  const Text('I allow real-money trading', style: TextStyle(color: C.gold)),
                ]),
              if (!running) FilledButton.icon(onPressed: () => start(bot), icon: const Icon(Icons.play_arrow), label: const Text('Trade now')),
              if (running) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.down), onPressed: stop, icon: const Icon(Icons.stop), label: const Text('Stop trading')),
            ]),
          ),
          if (accounts.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Link a Deriv account first (Accounts page). Start with a demo account.', style: TextStyle(color: C.gold))),
          const SizedBox(height: 16),
          Grid([
            Stat('Balance', bot['balance'] == null ? '-' : '${money(bot['balance'])} ${bot['currency']}'),
            Stat('Day P/L', money(bot['dayPnl'], sign: true), color: pnlColor(bot['dayPnl'])),
            Stat('Open baskets', '${baskets.length}'),
            Stat('Last scan', bot['lastScan'] == null ? '-' : ago(bot['lastScan'])),
          ], minWidth: 170),
          const SizedBox(height: 16),
          Grid([
            Panel(title: 'Open baskets', child: baskets.isEmpty
                ? const Text('None. The bot opens a basket only when an entry scores above the threshold.', style: TextStyle(color: C.muted))
                : Column(children: [for (final b in baskets) ListTile(dense: true, contentPadding: EdgeInsets.zero,
                    leading: Pill('${b['direction']}', b['direction'] == 'BUY' ? C.up : C.down),
                    title: Text('${b['symbol']} · ${b['contracts']} contracts · ${b['kind']}'),
                    subtitle: Text('stake ${money(b['stake'])} · ${(n(b['ageSec']) / 60).floor()} min'),
                    trailing: Text(money(b['pnl'], sign: true), style: TextStyle(color: pnlColor(b['pnl']), fontWeight: FontWeight.w700)))])),
            Panel(title: 'What the scanner sees (top candidates)', child: ((bot['candidates'] ?? []) as List).isEmpty
                ? const Text('No candidates yet.', style: TextStyle(color: C.muted))
                : Column(children: [for (final x in bot['candidates']) ListTile(dense: true, contentPadding: EdgeInsets.zero,
                    title: Text('${x['symbol']}'),
                    subtitle: Text('${x['note'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    trailing: Text('${x['score']} / ${x['threshold']}', style: TextStyle(fontWeight: FontWeight.w700, color: n(x['score']) >= n(x['threshold']) ? C.up : C.muted)))])),
          ], minWidth: 460),
          const SizedBox(height: 16),
          Panel(
            title: 'Risk management & strategy',
            actions: [FilledButton(onPressed: () async {
              try { await s.put('/api/bot/config', cfg); toast(context, 'Settings saved'); } catch (e) { toast(context, errMsg(e), error: true); }
            }, child: const Text('Save'))],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Maximum loss per basket = its total stake. The server caps these values, so they cannot be set to dangerous levels.', style: TextStyle(color: C.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Grid([
                slider('risk_pct', 'Risk per basket (% of balance)', 0.5, 10),
                slider('max_exposure_pct', 'Max total open stake (%)', 1, 30),
                slider('max_bulk', 'Max contracts per basket', 1, 20, div: 19),
                slider('tp_pct', 'Take profit (% of basket stake)', 5, 200, div: 39),
                slider('sl_pct', 'Basket stop (% of basket stake)', 10, 100, div: 18),
                slider('daily_loss_pct', 'Daily loss limit (%)', 1, 25, div: 24),
                slider('max_drawdown_pct', 'Kill switch drawdown (%)', 5, 50, div: 45),
                slider('threshold_forex', 'Entry score needed (forex/gold)', 60, 95, div: 35),
                slider('threshold_synth', 'Entry score needed (synthetics)', 60, 95, div: 35),
              ], minWidth: 300),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Include synthetic indices in the scan'), subtitle: const Text('Volatility 75 (R_75 and 1HZ75V), Boom and Crash are checked on every scan, separate from the forex shortlist.'),
                  value: cfg['include_synthetics'] != false, onChanged: (v) => setState(() => cfg['include_synthetics'] = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Gold NFP news trader'), subtitle: const Text('Analyses gold before US Non-Farm Payrolls, then trades the reaction with a smaller basket. Other symbols stay out of the market around the release.'),
                  value: cfg['news_gold'] == true, onChanged: (v) => setState(() => cfg['news_gold'] = v)),
            ]),
          ),
          const SizedBox(height: 16),
          Panel(title: 'Live log', child: SizedBox(height: 220, child: ListView(children: [
            for (final l in ((bot['logs'] ?? []) as List).reversed)
              Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${ago(l['t'])}  ${l['msg']}', style: TextStyle(fontSize: 12, color: l['level'] == 'error' ? C.down : l['level'] == 'warn' ? C.gold : C.muted))),
          ]))),
        ]));
      },
    );
  }
}
