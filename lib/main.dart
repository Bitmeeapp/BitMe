import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BitmeApp());

const kAccent = Color(0xFF3A5BFF);

class BitmeApp extends StatelessWidget {
  const BitmeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bitme',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: kAccent,
            useMaterial3: true,
            brightness: Brightness.dark),
        home: const Boot(),
      );
}

// ---------------------------------------------------------------- models

class Peer {
  final String id, name;
  final bool connected;
  Peer(this.id, this.name, this.connected);
}

class Msg {
  final String text;
  final bool mine;
  Msg(this.text, this.mine);
}

// ------------------------------------------------------------- transports

abstract class Transport extends ChangeNotifier {
  final chats = <String, List<Msg>>{};
  String? error;
  bool _dead = false;

  Future<bool> start(String me);
  List<Peer> get peers;
  Future<bool> connect(Peer p) async => true;
  void send(Peer p, String text);
  void stop();

  void addMsg(String id, Msg m) {
    (chats[id] ??= []).add(m);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_dead) super.notifyListeners();
  }

  @override
  void dispose() {
    _dead = true;
    stop();
    super.dispose();
  }
}

/// Bluetooth (Google Nearby Connections, Android)
class BtTransport extends Transport {
  static const _svc = 'com.bitme.chat';
  final _found = <String, String>{};
  final _links = <String, String>{};
  final _pending = <String, Completer<bool>>{};
  String _me = '';

  @override
  List<Peer> get peers {
    final ids = {..._found.keys, ..._links.keys};
    return ids
        .map((i) => Peer(i, _links[i] ?? _found[i] ?? i, _links.containsKey(i)))
        .toList();
  }

  @override
  Future<bool> start(String me) async {
    _me = me;
    try {
      await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ].request();
      await Nearby().startAdvertising(me, Strategy.P2P_CLUSTER,
          onConnectionInitiated: _init,
          onConnectionResult: _result,
          onDisconnected: _disc,
          serviceId: _svc);
      await Nearby().startDiscovery(me, Strategy.P2P_CLUSTER,
          onEndpointFound: (id, name, _) {
            _found[id] = name;
            notifyListeners();
          },
          onEndpointLost: (id) {
            _found.remove(id);
            notifyListeners();
          },
          serviceId: _svc);
      return true;
    } catch (e) {
      error = 'Bluetooth start nahi hua: $e';
      notifyListeners();
      return false;
    }
  }

  void _init(String id, ConnectionInfo info) {
    _found[id] = info.endpointName;
    Nearby().acceptConnection(id, onPayLoadRecieved: (eid, p) {
      if (p.type == PayloadType.BYTES && p.bytes != null) {
        addMsg(eid, Msg(utf8.decode(p.bytes!), false));
      }
    }, onPayloadTransferUpdate: (a, b) {});
  }

  void _result(String id, Status s) {
    final ok = s == Status.CONNECTED;
    if (ok) {
      _links[id] = _found[id] ?? id;
    } else {
      _links.remove(id);
    }
    _pending.remove(id)?.complete(ok);
    notifyListeners();
  }

  void _disc(String id) {
    _links.remove(id);
    notifyListeners();
  }

  @override
  Future<bool> connect(Peer p) async {
    if (p.connected) return true;
    final c = Completer<bool>();
    _pending[p.id] = c;
    try {
      await Nearby().requestConnection(_me, p.id,
          onConnectionInitiated: _init,
          onConnectionResult: _result,
          onDisconnected: _disc);
    } catch (_) {
      _pending.remove(p.id);
      return false;
    }
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () => false);
  }

  @override
  void send(Peer p, String text) {
    addMsg(p.id, Msg(text, true));
    Nearby().sendBytesPayload(p.id, Uint8List.fromList(utf8.encode(text)));
  }

  @override
  void stop() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
  }
}

/// Same WiFi (UDP broadcast for discovery, UDP unicast for messages)
class WifiTransport extends Transport {
  static const _port = 45454;
  final _uid = Random().nextInt(1 << 30).toString();
  String _me = '';
  RawDatagramSocket? _sock;
  Timer? _timer;
  final _names = <String, String>{};
  final _ips = <String, InternetAddress>{};
  final _seen = <String, DateTime>{};

  @override
  List<Peer> get peers =>
      _names.entries.map((e) => Peer(e.key, e.value, true)).toList();

  @override
  Future<bool> start(String me) async {
    _me = me;
    try {
      _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port,
          reuseAddress: true);
      _sock!.broadcastEnabled = true;
      _sock!.listen(_onEvent);
      _hello();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        _hello();
        _prune();
      });
      return true;
    } catch (e) {
      error = 'WiFi start nahi hua: $e';
      notifyListeners();
      return false;
    }
  }

  void _tx(InternetAddress a, Map<String, dynamic> m) {
    m['u'] = _uid;
    m['n'] = _me;
    _sock?.send(utf8.encode(jsonEncode(m)), a, _port);
  }

  void _hello() => _tx(InternetAddress('255.255.255.255'), {'t': 'hi'});

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final d = _sock?.receive();
    if (d == null) return;
    try {
      final m = jsonDecode(utf8.decode(d.data)) as Map;
      final u = m['u'] as String;
      if (u == _uid) return;
      final isNew = !_names.containsKey(u);
      _names[u] = m['n'] as String;
      _ips[u] = d.address;
      _seen[u] = DateTime.now();
      if (m['t'] == 'm') addMsg(u, Msg(m['x'] as String, false));
      if (isNew) {
        _tx(d.address, {'t': 'hi'});
        notifyListeners();
      }
    } catch (_) {}
  }

  void _prune() {
    final old = _seen.entries
        .where((e) => DateTime.now().difference(e.value).inSeconds > 12)
        .map((e) => e.key)
        .toList();
    for (final u in old) {
      _seen.remove(u);
      _names.remove(u);
      _ips.remove(u);
    }
    if (old.isNotEmpty) notifyListeners();
  }

  @override
  void send(Peer p, String text) {
    addMsg(p.id, Msg(text, true));
    final ip = _ips[p.id];
    if (ip != null) _tx(ip, {'t': 'm', 'x': text});
  }

  @override
  void stop() {
    _timer?.cancel();
    _sock?.close();
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
    return _name == null ? const SetupScreen() : HomeScreen(me: _name!);
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _c = TextEditingController();

  Future<void> _save() async {
    final n = _c.text.trim();
    if (n.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('username', n);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => HomeScreen(me: n)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/icon.png', width: 110)),
              const SizedBox(height: 20),
              const Text('Bitme',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
              const Text('Bina internet ke chat'),
              const SizedBox(height: 32),
              TextField(
                controller: _c,
                maxLength: 20,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                    labelText: 'Apna username', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _save, child: const Text('Shuru karo'))),
            ]),
          ),
        ),
      );
}

enum Mode { bluetooth, wifi }

class HomeScreen extends StatelessWidget {
  final String me;
  const HomeScreen({super.key, required this.me});

  Widget _card(BuildContext c, IconData i, String t, String s, Mode m) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Icon(i, size: 36, color: kAccent),
          title: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              c, MaterialPageRoute(builder: (_) => PeersScreen(me: me, mode: m))),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bitme')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Hi, $me 👋', style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          _card(context, Icons.bluetooth, 'Bluetooth se chat',
              'Paas ke phone se, bina WiFi ke', Mode.bluetooth),
          _card(context, Icons.wifi, 'WiFi se chat',
              'Same WiFi par jude phones se', Mode.wifi),
        ]),
      );
}

class PeersScreen extends StatefulWidget {
  final String me;
  final Mode mode;
  const PeersScreen({super.key, required this.me, required this.mode});
  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  late final Transport t =
      widget.mode == Mode.bluetooth ? BtTransport() : WifiTransport();

  @override
  void initState() {
    super.initState();
    t.start(widget.me);
  }

  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _open(Peer p) async {
    if (!p.connected) {
      _snack('${p.name} se connect ho raha hai...');
      final ok = await t.connect(p);
      if (!ok) return _snack('Connect nahi hua, dobara try karo');
    }
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ChatScreen(t: t, peer: Peer(p.id, p.name, true))));
  }

  Future<void> _addUsername() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Username add karo'),
        content: TextField(
            controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'dusre ka username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final hit = t.peers.where((p) => p.name.toLowerCase() == name.toLowerCase());
    if (hit.isEmpty) {
      _snack('"$name" nahi mila. Dusre phone par Bitme khula hona chahiye.');
    } else {
      _open(hit.first);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.mode == Mode.bluetooth ? 'Bluetooth' : 'WiFi')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _addUsername,
            icon: const Icon(Icons.person_add),
            label: const Text('Username add karo')),
        body: ListenableBuilder(
          listenable: t,
          builder: (_, __) {
            if (t.error != null) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.error!)));
            }
            final ps = t.peers;
            if (ps.isEmpty) {
              return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Nearby phones dhoond raha hai...\nDusre phone par bhi Bitme kholo.',
                    textAlign: TextAlign.center),
              ]));
            }
            return ListView(
                children: ps
                    .map((p) => ListTile(
                          leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                          title: Text(p.name),
                          subtitle: Text(p.connected ? 'Connected' : 'Tap karke connect karo'),
                          trailing: const Icon(Icons.chat_bubble_outline),
                          onTap: () => _open(p),
                        ))
                    .toList());
          },
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

  void _send() {
    final s = _c.text.trim();
    if (s.isEmpty) return;
    widget.t.send(widget.peer, s);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.peer.name)),
        body: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.t,
              builder: (_, __) {
                final msgs = (widget.t.chats[widget.peer.id] ?? []).reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    return Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                        decoration: BoxDecoration(
                          color: m.mine ? kAccent : const Color(0xFF2B2D3A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(m.text, style: const TextStyle(fontSize: 16)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                        hintText: 'Message likho',
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
                  ),
                ),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ]),
      );
}
