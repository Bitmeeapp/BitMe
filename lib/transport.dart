import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

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
  Future<void> stop();

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
        error = 'Location permission is required for Bluetooth.\n\n'
            'Open Settings → Permissions → Location → Allow, then come back and tap "Try again".';
        needSettings = true;
        notifyListeners();
        return false;
      }
      if (!await Permission.location.serviceStatus.isEnabled) {
        error = 'Turn on your phone\'s Location (GPS), then tap "Try again".';
        notifyListeners();
        return false;
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
      error = 'Could not start Bluetooth: $e';
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
    Nearby()
        .sendBytesPayload(p.id, Uint8List.fromList(utf8.encode(text)))
        .catchError((_) {});
  }

  @override
  Future<void> stop() async {
    _found.clear();
    _links.clear();
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
    } catch (_) {}
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
      _timer?.cancel();
      _sock?.close();
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
      error = 'Could not start WiFi: $e';
      notifyListeners();
      return false;
    }
  }

  void _tx(InternetAddress a, Map<String, dynamic> m) {
    m['u'] = _uid;
    m['n'] = _me;
    _sock?.send(utf8.encode(jsonEncode(m)), a, _port);
  }

  Future<void> _hello() async {
    _tx(InternetAddress('255.255.255.255'), {'t': 'hi'});
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          final p = a.address.split('.');
          if (p.length == 4 && !a.isLoopback) {
            _tx(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'), {'t': 'hi'});
          }
        }
      }
    } catch (_) {}
  }

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
  Future<void> stop() async {
    _timer?.cancel();
    _sock?.close();
    _sock = null;
    _names.clear();
    _ips.clear();
    _seen.clear();
  }
}
