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
  final String? sender; // shown in group chats
  final DateTime at = DateTime.now();
  Msg(this.text, this.mine, {this.sender});
}

// ------------------------------------------------------------- transports

abstract class Transport extends ChangeNotifier {
  final chats = <String, List<Msg>>{};
  final unread = <String, int>{};
  String? openId;
  String? error;
  bool needSettings = false;
  bool needLocation = false;
  bool _dead = false;

  Future<bool> start(String me);
  List<Peer> get peers;
  Future<bool> connect(Peer p) async => true;
  void send(Peer p, String text);
  Future<void> stop();

  bool isOnline(String id) => peers.any((p) => p.id == id && p.connected);

  // Group chat (WiFi only). Other transports have no groups.
  Set<String> get joinedGroups => const <String>{};
  List<String> get nearbyGroups => const <String>[];
  void joinGroup(String name) {}
  void leaveGroup(String name) {}

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
            'Tap "Open app settings" → Permissions → Location → Allow. Bitme will retry when you come back.';
        needSettings = true;
        notifyListeners();
        return false;
      }
      if (!await Permission.location.serviceStatus.isEnabled) {
        error = 'Location is turned off.\n\n'
            'Bluetooth search needs Location ON. Tap "Turn on Location", switch it on and come back. Bitme will retry automatically.';
        needLocation = true;
        notifyListeners();
        return false;
      }
      await Nearby().startAdvertising(me, Strategy.P2P_CLUSTER,
          onConnectionInitiated: _init,
          onConnectionResult: _result,
          onDisconnected: _disc,
          serviceId: _svc);
      await _startDiscovery();
      return true;
    } catch (e) {
      final m = e.toString();
      if (m.contains('MISSING_PERMISSION')) {
        error = 'A required permission is missing.\n\n'
            'Open app settings and allow Location and Nearby devices, then come back.';
        needSettings = true;
        needLocation = m.contains('LOCATION');
      } else {
        error = 'Could not start Bluetooth: $e';
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> _startDiscovery() => Nearby().startDiscovery(_me, Strategy.P2P_CLUSTER,
      onEndpointFound: (id, name, _) {
        _found[id] = name;
        notifyListeners();
      },
      onEndpointLost: (id) {
        _found.remove(id);
        notifyListeners();
      },
      serviceId: _svc);

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
    for (var attempt = 0; attempt < 3; attempt++) {
      final c = Completer<bool>();
      _pending[p.id] = c;
      // Searching while connecting makes the radio busy; pause it.
      try {
        await Nearby().stopDiscovery();
      } catch (_) {}
      var ok = false;
      try {
        await Nearby().requestConnection(_me, p.id,
            onConnectionInitiated: _init,
            onConnectionResult: _result,
            onDisconnected: _disc);
        ok = await c.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
      } catch (e) {
        if (e.toString().contains('8003')) {
          // already connected to this phone
          _links[p.id] = _found[p.id] ?? p.name;
          ok = true;
        }
      }
      _pending.remove(p.id);
      if (ok) {
        try {
          await _startDiscovery();
        } catch (_) {}
        notifyListeners();
        return true;
      }
      // clean half-open state, wait a moment, try again
      try {
        await Nearby().disconnectFromEndpoint(p.id);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    try {
      await _startDiscovery();
    } catch (_) {}
    return false;
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
  final _groups = <String>{};
  final _peerGroups = <String, List<String>>{};

  Map<String, dynamic> _hi() => {'t': 'hi', 'g': _groups.toList()};

  @override
  Set<String> get joinedGroups => _groups;

  @override
  List<String> get nearbyGroups {
    final s = <String>{};
    for (final l in _peerGroups.values) {
      s.addAll(l);
    }
    s.removeAll(_groups);
    return s.toList()..sort();
  }

  @override
  void joinGroup(String name) {
    if (_groups.add(name)) {
      _hello();
      notifyListeners();
    }
  }

  @override
  void leaveGroup(String name) {
    if (_groups.remove(name)) {
      chats.remove('group:$name');
      unread.remove('group:$name');
      _hello();
      notifyListeners();
    }
  }

  @override
  bool isOnline(String id) => id.startsWith('group:')
      ? _groups.contains(id.substring(6))
      : super.isOnline(id);

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
    _tx(InternetAddress('255.255.255.255'), _hi());
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          final p = a.address.split('.');
          if (p.length == 4 && !a.isLoopback) {
            _tx(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'), _hi());
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
      var changed = isNew;
      if (m['t'] == 'hi') {
        final g = ((m['g'] as List?) ?? []).map((e) => e.toString()).toList();
        if ((_peerGroups[u] ?? []).join('|') != g.join('|')) changed = true;
        _peerGroups[u] = g;
      }
      if (m['t'] == 'm') addMsg(u, Msg(m['x'] as String, false));
      if (m['t'] == 'g') {
        final gn = m['gn'] as String;
        if (_groups.contains(gn)) {
          addMsg('group:$gn', Msg(m['x'] as String, false, sender: m['n'] as String));
        }
      }
      if (isNew) _tx(d.address, _hi());
      if (changed) notifyListeners();
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
      _peerGroups.remove(u);
    }
    if (old.isNotEmpty) notifyListeners();
  }

  @override
  void send(Peer p, String text) {
    addMsg(p.id, Msg(text, true));
    if (p.id.startsWith('group:')) {
      final gn = p.id.substring(6);
      for (final ip in _ips.values) {
        _tx(ip, {'t': 'g', 'gn': gn, 'x': text});
      }
      return;
    }
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
    _peerGroups.clear();
  }
}

// EOF
