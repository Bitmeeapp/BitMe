import 'dart:async';

import 'dart:convert';

import 'dart:io';

import 'dart:math';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:nearby_connections/nearby_connections.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:share_plus/share_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const BitmeApp());

// ---------------------------------------------------------------- config

const kBuild = int.fromEnvironment('BUILD', defaultValue: 0);

const kRepo = 'Bitmeeapp/BitMe'; // GitHub repo (update + share link)

const kShareLink = 'https://github.com/$kRepo';

const kBg = Color(0xFF07070D);

const kCard = Color(0xFF16171F);

const kBubble = Color(0xFF1E2029);

const kBlue = Color(0xFF2E6BFF);

const kPurple = Color(0xFF9B3BFF); const kGreen = Color(0xFF19C37D);

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

} class GradientButton extends StatelessWidget {

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

 child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.bold)),

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

 if (!m.mine && openId != id) unread[id] = (unread[id] ?? 0) + 1; notifyListeners();

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

 if (!await Permission.location.isGranted) {

 error = 'Bluetooth ke liye Location permission zaroori hai.\n\n'

 'Settings kholo → Permissions → Location → Allow karo, phir wapas aakar 

"Dobara try karo" dabao.';

 needSettings = true;

 notifyListeners();

 return false;

 }

 if (!await Permission.location.serviceStatus.isEnabled) {

 error = 'Phone ki Location (GPS) ON karo, phir "Dobara try karo" dabao.';

 notifyListeners(); return false;

 }

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

 try { await Nearby().requestConnection(_me, p.id,

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

 _found.clear();

 _links.clear();

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

 return true; } catch (e) {

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

 @override void stop() {

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

 Navigator.pushReplacement( context, MaterialPageRoute(builder: (_) => Shell(me: n)));

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

 child: Padding(

 padding: const EdgeInsets.all(28),

 child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

 ClipRRect(

 borderRadius: BorderRadius.circular(28),

 child: Image.asset('assets/icon.png', width: 120)),

 const SizedBox(height: 22),

 const Text('Bitme',

 style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),

 const SizedBox(height: 8),

 const Text('Connect • Chat • Share • Be You',

 style: TextStyle(color: Colors.white70)),

 const SizedBox(height: 40),

 TextField(

 controller: _c,

 maxLength: 20,

 textInputAction: TextInputAction.done,

 onSubmitted: (_) => _save(),

 decoration: InputDecoration(

 hintText: 'Apna username likho',

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

 );

}

enum Mode { bluetooth, wifi }

class Shell extends StatefulWidget {

 final String me;

 const Shell({super.key, required this.me});

 @override State<Shell> createState() => _ShellState();

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

 void _restart() {

 t.stop();

 t.error = null;

 t.needSettings = false;

 t.refresh();

 t.start(_me);

 }

 void _setMode(Mode m) {

 if (m == _mode) return;

 t.stop();

 setState(() => _mode = m);

 t.error = null;

 t.needSettings = false;

 t.start(_me);

 }

 Future<void> _open(Peer p) async {

 if (!p.connected) {

 _snack('${p.name} se connect ho raha hai...');

 final ok = await t.connect(p);

 if (!ok) return _snack('Connect nahi hua, dobara try karo');

 }

 if (!mounted) return;

 Navigator.push(

 context, MaterialPageRoute(

 builder: (_) => ChatScreen(t: t, peer: Peer(p.id, p.name, true))));

 }

 Future<void> _addUsername() async {

 final name = await askText(context, 'Username add karo',

 hint: 'dusre ka username', ok: 'Add');

 if (name == null || name.isEmpty) return;

 final hit = t.peers.where((p) => p.name.toLowerCase() == name.toLowerCase());

 if (hit.isEmpty) {

 _snack('"$name" nahi mila. Dusre phone par Bitme khula hona chahiye.');

 } else {

 _open(hit.first);

 }

 }

 Future<void> _rename() async {

 _sk.currentState?.closeEndDrawer();

 final n = await askText(context, 'Username badlo', initial: _me);

 if (n == null || n.isEmpty || n == _me) return;

 final p = await SharedPreferences.getInstance();

 await p.setString('username', n);

 setState(() => _me = n);

 _restart();

 }

 Future<void> _checkUpdate() async {

 _sk.currentState?.closeEndDrawer();

 _snack('Update check ho raha hai...');

 try {

 final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);

 final req = await c

 .getUrl(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'));

 req.headers.set('User-Agent', 'Bitme');

 final res = await req.close();

 if (res.statusCode == 404) {

 c.close();

 return _snack('Abhi koi update nahi hai');

 }

 if (res.statusCode != 200) throw Exception('status ${res.statusCode}');

 final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;

 c.close();

 final n =

 int.tryParse((j['tag_name'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ?? 

0;

 if (!mounted) return;

 if (n <= kBuild) return _snack('Aap latest version par ho ');

 final assets = (j['assets'] as List?) ?? [];

 final url = assets.isNotEmpty

 ? assets.first['browser_download_url'] as String

 : j['html_url'] as String;

 final go = await showDialog<bool>(

 context: context,

 builder: (_) => AlertDialog(

 title: const Text('Naya update aaya hai'),

 content: Text('Bitme build $n available hai. Download karna hai?'), actions: [

 TextButton(

 onPressed: () => Navigator.pop(context, false),

 child: const Text('Baad me')),

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

 if (mounted) _snack('Update check nahi hua. Internet check karo.');

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

 borderSide: BorderSide.none), ),

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

 Text('Nearby phones dhoond raha hai...\nDusre phone par bhi Bitme 

kholo.',

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

 borderRadius: BorderRadius.circular(22)), child: Row(mainAxisSize: MainAxisSize.min, children: [

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

 : (p.connected ? 'Connected • message bhejo' : 'Tap karke connect karo');

 retur
