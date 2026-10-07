import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'transport.dart';

void main() => runApp(const BitmeApp());

const kBg = Color(0xFF07070D);
const kCard = Color(0xFF16171F);
const kBubble = Color(0xFF1E2029);
const kBlue = Color(0xFF2E6BFF);

class BitmeApp extends StatelessWidget {
  const BitmeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitme',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: Brightness.dark),
      ),
      home: const BootScreen(),
    );
  }
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String? username;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        username = prefs.getString('username');
        loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return username == null ? const WelcomeScreen() : ShellScreen(me: username!);
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final controller = TextEditingController();

  Future<void> saveName() async {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ShellScreen(me: name)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.offline_bolt_rounded, size: 80, color: kBlue),
              const SizedBox(height: 16),
              const Text('Bitme', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Apna naam likho',
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kBlue),
                  onPressed: saveName,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum Mode { bluetooth, wifi }

class ShellScreen extends StatefulWidget {
  final String me;
  const ShellScreen({super.key, required this.me});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final BtTransport _bt = BtTransport();
  final WifiTransport _wifi = WifiTransport();
  Mode _mode = Mode.bluetooth;

  Transport get t => _mode == Mode.bluetooth ? _bt : _wifi;

  @override
  void initState() {
    super.initState();
    t.start(widget.me);
  }

  @override
  void dispose() {
    _bt.dispose();
    _wifi.dispose();
    super.dispose();
  }

  void _setMode(Mode m) {
    if (m == _mode) return;
    t.stop();
    setState(() => _mode = m);
    t.start(widget.me);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bitme - ${widget.me}'),
        backgroundColor: kCard,
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth, color: _mode == Mode.bluetooth ? kBlue : Colors.grey),
            onPressed: () => _setMode(Mode.bluetooth),
          ),
          IconButton(
            icon: Icon(Icons.wifi, color: _mode == Mode.wifi ? kBlue : Colors.grey),
            onPressed: () => _setMode(Mode.wifi),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: t,
        builder: (context, _) {
          if (t.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t.error!, textAlign: TextAlign.center),
              ),
            );
          }

          final peers = t.peers;
          if (peers.isEmpty) {
            return const Center(
              child: Text('Searching nearby devices...\nDusre phone par bhi app open karein.', textAlign: TextAlign.center),
            );
          }

          return ListView.builder(
            itemCount: peers.length,
            itemBuilder: (context, index) {
              final peer = peers[index];
              return ListTile(
                title: Text(peer.name),
                subtitle: Text(peer.connected ? 'Connected' : 'Tap to connect'),
                onTap: () async {
                  if (!peer.connected) await t.connect(peer);
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(t: t, peer: peer)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Transport t;
  final Peer peer;
  const ChatScreen({super.key, required this.t, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();

  void send() {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    widget.t.send(widget.peer, text);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.peer.name), backgroundColor: kCard),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.t,
              builder: (context, _) {
                final msgs = widget.t.chats[widget.peer.id] ?? [];
                return ListView.builder(
                  itemCount: msgs.length,
                  itemBuilder: (context, index) {
                    final msg = msgs[index];
                    return Align(
                      alignment: msg.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: msg.mine ? kBlue : kBubble,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg.text),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'Type message...'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
