import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell.dart';
import 'ui.dart';

void main() => runApp(const BitmeApp());

class BitmeApp extends StatelessWidget {
  const BitmeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BitMee',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme:
              ColorScheme.fromSeed(seedColor: kBlue, brightness: Brightness.dark),
          appBarTheme: const AppBarTheme(
              backgroundColor: kBg, surfaceTintColor: Colors.transparent),
          drawerTheme: const DrawerThemeData(backgroundColor: kCard),
          dialogTheme: const DialogThemeData(backgroundColor: kCard),
        ),
        home: const Boot(),
      );
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  String? _name;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _name = p.getString('username');
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold();
    return _name == null ? const WelcomeScreen() : Shell(me: _name!);
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _c = TextEditingController();

  Future<void> _save() async {
    final n = _c.text.trim();
    if (n.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('username', n);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => Shell(me: n)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(0, -.45),
                  radius: 1.0,
                  colors: [Color(0xFF241466), kBg])),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon.png', width: 120)),
                const SizedBox(height: 22),
                const Text('BitMee',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Connect  •  Chat  •  Share  •  Be You',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 40),
                TextField(
                  controller: _c,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: 'Choose your username',
                    counterText: '',
                    filled: true,
                    fillColor: kCard,
                    prefixIcon: const Icon(Icons.alternate_email),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(27),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                GradientButton(text: 'Get Started', onTap: _save),
              ]),
            ),
            ),
          ),
        ),
      );
}

// EOF
