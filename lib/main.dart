import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const BitmeApp());

// ---------------------------------------------------------------- config

const kBuild = int.fromEnvironment('BUILD', defaultValue: 0);
const kRepo = 'Bitmeeapp/BitMe'; // GitHub repo

const kBg = Color(0xFF07070D);
const kCard = Color(0xFF16171F);
const kBubble = Color(0xFF1E2029);
const kBlue = Color(0xFF2E6BFF);
const kPurple = Color(0xFF9B3BFF);
const kGreen = Color(0xFF19C37D);

const kGradient = LinearGradient(
  colors: [kBlue, kPurple],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

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
          colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: Brightness.dark),
          appBarTheme: const AppBarTheme(backgroundColor: kBg, surfaceTintColor: Colors.transparent),
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
  return '$h:$m${d.hour >= 12 ? 'PM' : 'AM'}';
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String hint = '', String ok = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
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
        decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(27)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(27),
            onTap: onTap,
            child: Center(
              child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
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
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [c, c.withValues(alpha: .6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.bold)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * .26,
                height: size * .26,
                decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: kBg, width: 2)),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- models

class Peer {
  final String id, name;
  final bool connected;
  Peer(this.id, this.name, this.connected);
}

class Msg {
  final String text;
  final bool mine;
  final DateTime at = DateTime.now();
  Msg(this.text, this.mine);
}

// ------------------------------------------------------------- transports

abstract class Transport extends ChangeNotifier {
  final chats = <String, List<Msg>>{};
  final unread = <String, int>{};
  String? openId;
  String? error;
  bool needSettings = false;
  bool _dead = false;

  Future<bool> start(String me);
  List<Peer> get peers;
  Future<bool> connect(Peer p) async => true;
  void send(Peer p, String text);
  void stop();

  bool isOnline(String id) => peers.any((p) => p.id == id && p.connected);

  void addMsg(String id, Msg m) {
    (chats[id] ??= []).add(m);
    if (!m.mine && openId != id) unread[id] = (unread[id] ?? 0) + 1;
    notifyListeners();
  }

  void refresh() => notifyListeners();

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
    return ids.map((i) => Peer(i, _links[i] ?? _found[i] ?? i, _links.containsKey(i))).toList();
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

      if (!await Permission.location.isGranted) {
        error = 'Bluetooth ke liye Location permission zaroori hai.\n\nSettings kholo → Permissions → Location → Allow karo.';
        needSettings = true;
        notifyListeners();
        return false;
      }

      if (!await Permission.location.serviceStatus.isEnabled) {
        error = 'Phone ki Location (GPS) ON karo, phir "Dobara try karo" dabao.';
        notifyListeners();
        return false;
      }

      await Nearby().startAdvertising(
        me,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _init,
        onConnectionResult: _result,
        onDisconnected: _disc,
        serviceId: _svc,
      );

      await Nearby().startDiscovery(
        me,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, _) {
          _found[id] = name;
          notifyListeners();
        },
        onEndpointLost: (id) {
          _found.remove(id);
          notifyListeners();
        },
        serviceId: _svc,
      );

      return true;
    } catch (e) {
      error = 'Bluetooth start nahi hua: $e';
      notifyListeners();
      return false;
    }
  }

  void _init(String id, ConnectionInfo info) {
    _found[id] = info.endpointName;
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (eid, p) {
        if (p.type == PayloadType.BYTES && p.bytes != null) {
          addMsg(eid, Msg(utf8.decode(p.bytes!), false));
        }
      },
      onPayloadTransferUpdate: (a, b) {},
    );
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
      await Nearby().requestConnection(
        _me,
        p.id,
        onConnectionInitiated: _init,
        onConnectionResult: _result,
        onDisconnected: _disc,
      );
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
    _found.clear();
    _links.clear();
  }
}

/// Same WiFi (UDP broadcast)
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
  List<Peer> get peers => _names.entries.map((e) => Peer(e.key, e.value, true)).toList();

  @override
  Future<bool> start(String me) async {
    _me = me;
    try {
      _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port, reuseAddress: true);
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
    final old = _seen.entries.where((e) => DateTime.now().difference(e.value).inSeconds > 12).map((e) => e.key).toList();
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
    _sock = null;
    _names.clear();
    _ips.clear();
    _seen.clear();
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
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Shell(me: n)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -.45), radius: 1.0, colors: [Color(0xFF241466), kBg]),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(28)),
                        child: const Icon(Icons.offline_bolt_rounded, size: 64, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Bitme', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                  const SizedBox(height:
                                 
