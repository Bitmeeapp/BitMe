import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'transport.dart';

void main() => runApp(const BitmeApp());

// ---------------------------------------------------------------- config
const kBuild = int.fromEnvironment('BUILD', defaultValue: 0);
const kRepo = 'Bitmeeapp/BitMe'; // GitHub repo (used for update check + share link)
const kShareLink = 'https://github.com/$kRepo';

const kBg = Color(0xFF07070D);
const kCard = Color(0xFF16171F);
const kBubble = Color(0xFF1E2029);
const kBlue = Color(0xFF2E6BFF);
const kPurple = Color(0xFF9B3BFF);
const kGreen = Color(0xFF19C37D);
const kGradient = LinearGradient(
    colors: [kBlue, kPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight);

class BitmeApp extends StatelessWidget {
  const BitmeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bitme',
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

// ---------------------------------------------------------------- helpers

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

Future<String?> askText(BuildContext c, String title,
    {String initial = '', String hint = '', String ok = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const GradientButton({super.key, required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        decoration: BoxDecoration(
            gradient: kGradient, borderRadius: BorderRadius.circular(27)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(27),
            onTap: onTap,
            child: Center(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))),
          ),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool online;
  const Avatar({super.key, required this.name, this.size = 52, this.online = false});

  static const _cols = [
    Color(0xFF2E6BFF),
    Color(0xFF9B3BFF),
    Color(0xFFE040A0),
    Color(0xFF00A884),
    Color(0xFFFF8A3D),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final c = _cols[seed % _cols.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [c, c.withValues(alpha: .6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.bold)),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * .26,
              height: size * .26,
              decoration: BoxDecoration(
                  color: kGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: kBg, width: 2)),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- screens

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
                const Text('Bitme',
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

enum Mode { bluetooth, wifi }

class Shell extends StatefulWidget {
  final String me;
  const Shell({super.key, required this.me});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _sk = GlobalKey<ScaffoldState>();
  final _bt = BtTransport();
  final _wifi = WifiTransport();
  Mode _mode = Mode.bluetooth;
  int _tab = 0;
  String _q = '';
  late String _me = widget.me;

  Transport get t => _mode == Mode.bluetooth ? _bt : _wifi;

  @override
  void initState() {
    super.initState();
    t.start(_me);
  }

  @override
  void dispose() {
    _bt.dispose();
    _wifi.dispose();
    super.dispose();
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s)));

  Future<void> _restart() async {
    await t.stop();
    t.error = null;
    t.needSettings = false;
    t.refresh();
    t.start(_me);
  }

  bool _switching = false;

  Future<void> _setMode(Mode m) async {
    if (m == _mode || _switching) return;
    _switching = true;
    await t.stop();
    if (!mounted) return;
    setState(() => _mode = m);
    t.error = null;
    t.needSettings = false;
    t.start(_me);
    _switching = false;
  }

  Future<void> _open(Peer p) async {
    if (!p.connected) {
      _snack('Connecting to ${p.name}...');
      final ok = await t.connect(p);
      if (!ok) return _snack('Could not connect. Please try again.');
    }
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(t: t, peer: Peer(p.id, p.name, true))));
  }

  Future<void> _addUsername() async {
    final name = await askText(context, 'Add username',
        hint: "Friend's username", ok: 'Add');
    if (name == null || name.isEmpty) return;
    final hit = t.peers.where((p) => p.name.toLowerCase() == name.toLowerCase());
    if (hit.isEmpty) {
      _snack('"$name" not found. Bitme must be open on the other phone.');
    } else {
      _open(hit.first);
    }
  }

  Future<void> _rename() async {
    _sk.currentState?.closeEndDrawer();
    final n = await askText(context, 'Change username', initial: _me);
    if (n == null || n.isEmpty || n == _me) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('username', n);
    setState(() => _me = n);
    _restart();
  }

  Future<void> _checkUpdate() async {
    _sk.currentState?.closeEndDrawer();
    _snack('Checking for updates...');
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await c
          .getUrl(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'));
      req.headers.set('User-Agent', 'Bitme');
      final res = await req.close();
      if (!mounted) return;
      if (res.statusCode == 404) {
        c.close();
        return _snack('No updates available yet');
      }
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      c.close();
      final n =
          int.tryParse((j['tag_name'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (!mounted) return;
      if (n <= kBuild) return _snack("You're on the latest version ✅");
      final assets = (j['assets'] as List?) ?? [];
      final url = assets.isNotEmpty
          ? assets.first['browser_download_url'] as String
          : j['html_url'] as String;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Update available'),
          content: Text('Bitme version 1.0.$n is available. Download it now?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download')),
          ],
        ),
      );
      if (go == true) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) _snack('Could not check for updates. Please check your internet.');
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _sk,
        endDrawer: _drawer(),
        body: SafeArea(child: _tab == 0 ? _messages() : _profile()),
        bottomNavigationBar: _nav(),
      );

  Widget _menuBtn() => IconButton(
      icon: const Icon(Icons.menu, size: 28),
      onPressed: () => _sk.currentState?.openEndDrawer());

  Widget _messages() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
        child: Row(children: [
          const Text('Messages',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const Spacer(),
          _menuBtn(),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Search chats...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: kCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(children: [
          _chip('Bluetooth', Icons.bluetooth, Mode.bluetooth),
          const SizedBox(width: 10),
          _chip('WiFi', Icons.wifi, Mode.wifi),
        ]),
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: t,
          builder: (_, __) {
            if (t.error != null) return _errorView();
            final ps = t.peers
                .where((p) => p.name.toLowerCase().contains(_q.toLowerCase()))
                .toList();
            ps.sort((a, b) {
              final la = t.chats[a.id]?.last.at;
              final lb = t.chats[b.id]?.last.at;
              if (la != null && lb != null) return lb.compareTo(la);
              if (la != null) return -1;
              if (lb != null) return 1;
              return a.name.compareTo(b.name);
            });
            if (ps.isEmpty) {
              return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Looking for nearby phones...\nOpen Bitme on the other phone too.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
              ]));
            }
            return ListView.builder(
                itemCount: ps.length, itemBuilder: (_, i) => _tile(ps[i]));
          },
        ),
      ),
    ]);
  }

  Widget _chip(String label, IconData icon, Mode m) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
            gradient: sel ? kGradient : null,
            color: sel ? null : kCard,
            borderRadius: BorderRadius.circular(22)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _tile(Peer p) {
    final last = (t.chats[p.id] ?? []).isEmpty ? null : t.chats[p.id]!.last;
    final un = t.unread[p.id] ?? 0;
    final sub = last != null
        ? '${last.mine ? 'You: ' : ''}${last.text}'
        : (p.connected ? 'Connected • say hi' : 'Tap to connect');
    return InkWell(
      onTap: () => _open(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(name: p.name, online: p.connected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: un > 0 ? Colors.lightBlueAccent : Colors.white60)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(last == null ? '' : fmtTime(last.at),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            if (un > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration:
                    const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                child: Text('$un',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _errorView() => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t.error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (t.needSettings)
              FilledButton.tonal(
                  onPressed: openAppSettings, child: const Text('Open Settings')),
            const SizedBox(height: 8),
            FilledButton(onPressed: _restart, child: const Text('Try again')),
          ])));

  Widget _profile() => ListenableBuilder(
        listenable: Listenable.merge([_bt, _wifi]),
        builder: (_, __) {
          var sent = 0, got = 0;
          for (final tr in [_bt, _wifi]) {
            for (final l in tr.chats.values) {
              for (final m in l) {
                m.mine ? sent++ : got++;
              }
            }
          }
          final dev = t.peers.where((p) => p.connected).length;
          Widget stat(String n, String l) => Expanded(
                child: Column(children: [
                  Text(n,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(l, style: const TextStyle(color: Colors.white60)),
                ]),
              );
          return ListView(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                height: 150,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF1B1055), Color(0xFF5B21B6), Color(0xFF0E2A6B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
              ),
              Positioned(top: 4, right: 8, child: _menuBtn()),
              Positioned(
                left: 20,
                bottom: -45,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                      child: Avatar(name: _me, size: 84)),
                ),
              ),
            ]),
            const SizedBox(height: 58),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_me, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                Text('@${_me.toLowerCase().replaceAll(' ', '_')}',
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 10),
                const Text('Bitme user ⚡\nChat without internet 💬'),
                const SizedBox(height: 22),
                Row(children: [
                  stat('$sent', 'Sent'),
                  stat('$got', 'Received'),
                  stat('$dev', 'Connected'),
                ]),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          backgroundColor: kCard,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onPressed: _rename,
                      child: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                      style: IconButton.styleFrom(backgroundColor: kCard),
                      onPressed: () => _sk.currentState?.openEndDrawer(),
                      icon: const Icon(Icons.settings_outlined)),
                ]),
              ]),
            ),
          ]);
        },
      );

  Widget _nav() {
    Widget item(IconData i, String l, int idx) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _tab = idx),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(i, color: _tab == idx ? kPurple : Colors.white54),
                const SizedBox(height: 2),
                Text(l,
                    style: TextStyle(
                        fontSize: 12, color: _tab == idx ? kPurple : Colors.white54)),
              ]),
            ),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
          color: kBg, border: Border(top: BorderSide(color: Color(0xFF1C1D26)))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          item(Icons.chat_bubble, 'Messages', 0),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _addUsername,
                child: Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 30),
                ),
              ),
            ),
          ),
          item(Icons.person, 'Profile', 1),
        ]),
      ),
    );
  }

  Widget _drawer() => Drawer(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon.png', width: 72)),
                const SizedBox(height: 12),
                const Text('Bitme',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(_me),
              subtitle: const Text('My username'),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: _rename,
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share app'),
              onTap: () {
                _sk.currentState?.closeEndDrawer();
                Share.share('Bitme: chat without internet, over Bluetooth or WiFi. Download: $kShareLink');
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Update app'),
              onTap: _checkUpdate,
            ),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
              title: const Text('Donate'),
              onTap: () {
                _sk.currentState?.closeEndDrawer();
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DonateScreen()));
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Version 1.0.$kBuild',
                  style: const TextStyle(color: Colors.white38)),
            ),
          ]),
        ),
      );
}

class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Donate')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Text('Bitme is free ❤️',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('If you like the app, you can support it.\nScan the QR code to donate.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(16)),
                // To change the QR, replace assets/donate_qr.png (same file name)
                child: Image.asset('assets/donate_qr.png',
                    width: 260,
                    height: 260,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 260,
                        height: 260,
                        child: Center(
                            child: Text('QR coming soon',
                                style: TextStyle(color: Colors.black))))),
              ),
              const SizedBox(height: 16),
              const Text('Thank you 🙏'),
            ]),
          ),
        ),
      );
}

class ChatScreen extends StatefulWidget {
  final Transport t;
  final Peer peer;
  const ChatScreen({super.key, required this.t, required this.peer});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.t.openId = widget.peer.id;
    widget.t.unread.remove(widget.peer.id);
  }

  @override
  void dispose() {
    widget.t.openId = null;
    _c.dispose();
    super.dispose();
  }

  void _send() {
    final s = _c.text.trim();
    if (s.isEmpty) return;
    if (!widget.t.isOnline(widget.peer.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.peer.name} is offline')));
      return;
    }
    widget.t.send(widget.peer, s);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: ListenableBuilder(
            listenable: widget.t,
            builder: (_, __) {
              final on = widget.t.isOnline(widget.peer.id);
              return Row(children: [
                Avatar(name: widget.peer.name, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Row(children: [
                    Icon(Icons.circle, size: 9, color: on ? kGreen : Colors.grey),
                    const SizedBox(width: 5),
                    Text(on ? 'Online' : 'Offline',
                        style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  ]),
                ])),
              ]);
            },
          ),
        ),
        body: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.t,
              builder: (_, __) {
                final msgs = (widget.t.chats[widget.peer.id] ?? []).reversed.toList();
                final maxW = MediaQuery.of(context).size.width * .72;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final bubble = Container(
                      constraints: BoxConstraints(maxWidth: maxW),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      decoration: BoxDecoration(
                        gradient: m.mine ? kGradient : null,
                        color: m.mine ? null : kBubble,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                                alignment: Alignment.centerLeft,
                                child: Text(m.text, style: const TextStyle(fontSize: 16))),
                            const SizedBox(height: 3),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(fmtTime(m.at),
                                  style: const TextStyle(fontSize: 11, color: Colors.white60)),
                              if (m.mine) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.done, size: 14, color: Colors.white70),
                              ],
                            ]),
                          ]),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment:
                            m.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!m.mine) ...[
                            Avatar(name: widget.peer.name, size: 30),
                            const SizedBox(width: 8),
                          ],
                          bubble,
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: kCard,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration:
                        const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
}
