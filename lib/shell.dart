import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat.dart';
import 'transport.dart';
import 'ui.dart';

part 'shell_parts.dart';

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

  void _setTab(int i) => setState(() => _tab = i);

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
}

// EOF
