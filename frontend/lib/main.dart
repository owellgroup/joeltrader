import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api.dart';
import 'core/theme.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  session.init();
  runApp(ChangeNotifierProvider.value(value: session, child: const JoelTraderApp()));
}

class JoelTraderApp extends StatelessWidget {
  const JoelTraderApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    Widget home;
    if (!s.ready) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!s.loggedIn) {
      home = const LoginScreen();
    } else if (s.user!['mustChangePassword'] == true) {
      home = const ForcePasswordScreen();
    } else {
      home = const Shell();
    }
    return MaterialApp(title: 'joelTrader', debugShowCheckedModeBanner: false, theme: buildTheme(), home: home);
  }
}
