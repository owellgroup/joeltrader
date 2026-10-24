import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import 'login.dart';
import 'dashboard.dart';
import 'bot.dart';
import 'charts.dart';
import 'signals.dart';
import 'market.dart';
import 'trades.dart';
import 'performance.dart';
import 'accounts.dart';
import 'admins.dart';
import 'settings.dart';

class _Item {
  final String label;
  final IconData icon;
  final Widget Function() build;
  const _Item(this.label, this.icon, this.build);
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  List<_Item> items(bool isSuper) => [
        _Item('Dashboard', Icons.space_dashboard_outlined, () => const DashboardPage()),
        _Item('Auto Trader', Icons.smart_toy_outlined, () => const BotPage()),
        _Item('Charts', Icons.candlestick_chart_outlined, () => const ChartsPage()),
        _Item('Signals', Icons.notifications_active_outlined, () => const SignalsPage()),
        _Item('Markets & News', Icons.public, () => const MarketPage()),
        _Item('Trades', Icons.swap_vert, () => const TradesPage()),
        _Item('Performance', Icons.query_stats, () => const PerformancePage()),
        _Item('Accounts', Icons.account_balance_wallet_outlined, () => const AccountsPage()),
        _Item('Admins', Icons.admin_panel_settings_outlined, () => const AdminsPage()),
        _Item('Settings', Icons.settings_outlined, () => const SettingsPage()),
      ];

  Widget nav(List<_Item> its, {bool closeOnTap = false}) {
    final s = context.watch<Session>();
    return Column(children: [
      const SizedBox(height: 16),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: LogoBadge(height: 40))),
      const SizedBox(height: 12),
      Expanded(
        child: ListView(children: [
          for (var i = 0; i < its.length; i++)
            ListTile(
              dense: true,
              selected: i == index,
              selectedTileColor: C.brand.withAlpha(40),
              selectedColor: Colors.white,
              leading: Icon(its[i].icon, size: 20),
              title: Text(its[i].label),
              onTap: () {
                setState(() => index = i);
                if (closeOnTap) Navigator.of(context).pop();
              },
            ),
        ]),
      ),
      const Divider(height: 1),
      ListTile(
        dense: true,
        title: Text(s.user?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(s.user?['email'] ?? '', style: const TextStyle(fontSize: 11)),
        trailing: IconButton(icon: const Icon(Icons.logout, size: 18), tooltip: 'Sign out', onPressed: () => s.logout()),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final its = items(context.read<Session>().isSuper);
    final wide = MediaQuery.of(context).size.width >= 900;
    if (index >= its.length) index = 0;
    final body = KeyedSubtree(key: ValueKey(index), child: its[index].build());
    if (wide) {
      return Scaffold(
        body: Row(children: [
          Container(width: 240, decoration: const BoxDecoration(color: C.panel, border: Border(right: BorderSide(color: C.line))), child: nav(its)),
          Expanded(child: body),
        ]),
      );
    }
    // Mobile: left drawer with every page + bottom tabs for the four most used pages.
    const tabs = [0, 1, 2, 5];
    final tabIndex = tabs.contains(index) ? tabs.indexOf(index) : 0;
    return Scaffold(
      appBar: AppBar(title: Text(its[index].label), titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.text)),
      drawer: Drawer(child: SafeArea(child: nav(its, closeOnTap: true))),
      body: body,
      bottomNavigationBar: NavigationBar(
        backgroundColor: C.panel,
        selectedIndex: tabIndex,
        indicatorColor: C.brand.withAlpha(80),
        onDestinationSelected: (i) => setState(() => index = tabs[i]),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(its[t].icon), label: its[t].label.split(' ').first)],
      ),
    );
  }
}
