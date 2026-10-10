import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'transport.dart';

part 'bt_media.dart';

/// Bluetooth (Google Nearby Connections, Android) with optional mesh relay.
///
/// Mesh relay: every phone announces its username to its neighbours. Messages
/// for someone who is not a direct neighbour are flooded through the network
/// (each phone passes them on, max [_ttl] hops, duplicates are dropped).
class BtTransport extends Transport {
  static const _svc = 'com.bitme.chat';
  static const _ttl = 6;
  static const _chunk = 30000; // bytes of a file per message (limit is 32 KB)

  final _found = <String, String>{}; // endpointId -> name (seen nearby)
  final _links = <String, String>{}; // endpointId -> name (connected)
  final _pending = <String, Completer<bool>>{};
  final _mesh = <String, DateTime>{}; // name -> last announcement
  final _wanted = <String>{}; // people we were connected to: reconnect on our own
  final _foundAt = <String, DateTime>{}; // when an endpoint was first seen
  final _fails = <String, int>{}; // failed automatic connection attempts
  final _incoming = <String, _In>{}; // files being received
  final _seenList = <String>[];
  final _seenSet = <String>{};
  final _rnd = Random();
  Timer? _timer;
  String _me = '';

  @override
  List<Peer> get peers {
    final ids = {..._found.keys, ..._links.keys};
    return ids
        .map((i) => Peer(i, _links[i] ?? _found[i] ?? i, _links.containsKey(i)))
        .toList();
  }

  @override
  bool get supportsMesh => true;

  @override
  List<Peer> get meshPeers =>
      _mesh.keys.map((n) => Peer('mesh:$n', n, true)).toList();

  @override
  void setMesh(bool on) {
    meshEnabled = on;
    if (!on) _mesh.clear();
    notifyListeners();
    if (on) _tick();
  }

  @override
  bool isOnline(String id) => id.startsWith('mesh:')
      ? _mesh.containsKey(id.substring(5))
      : super.isOnline(id);

  // ------------------------------------------------------------- start/stop

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
            'Tap "Open app settings" → Permissions → Location → Allow. BitMee will retry when you come back.';
        needSettings = true;
        notifyListeners();
        return false;
      }
      if (!await Permission.location.serviceStatus.isEnabled) {
        error = 'Location is turned off.\n\n'
            'Bluetooth search needs Location ON. Tap "Turn on Location", switch it on and come back. BitMee will retry automatically.';
        needLocation = true;
        notifyListeners();
        return false;
      }
      await _startAdvertising();
      await _startDiscovery();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
      return true;
    } catch (e) {
      final m = e.toString();
      if (m.contains('MISSING_PERMISSION')) {
        error = 'A required permission is missing.\n\n'
            'Open app settings and allow Location and Nearby devices, then come back.';
        needSettings = true;
        needLocation = m.contains('LOCATION');
      } else if (m.contains('8007') || m.contains('BLUETOOTH_ERROR')) {
        error = 'Bluetooth is turned off.\n\n'
            'Turn Bluetooth on and come back. BitMee will retry automatically.';
        needBluetooth = true;
      } else {
        error = 'Could not start Bluetooth: $e';
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> _startAdvertising() =>
      Nearby().startAdvertising(_me, Strategy.P2P_CLUSTER,
          onConnectionInitiated: _init,
          onConnectionResult: _result,
          onDisconnected: _disc,
          serviceId: _svc);

  @override
  Future<void> refreshRadio() async {
    if (_me.isEmpty) return;
    try {
      await Nearby().stopAdvertising();
    } catch (_) {}
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    _found.removeWhere((id, _) => !_links.containsKey(id));
    notifyListeners();
    try {
      await _startAdvertising();
      await _startDiscovery();
    } catch (_) {}
  }

  Future<void> _startDiscovery() => Nearby().startDiscovery(
      _me, Strategy.P2P_CLUSTER,
      onEndpointFound: (id, name, _) {
        _found[id] = name;
        _foundAt.putIfAbsent(id, () => DateTime.now());
        notifyListeners();
      },
      onEndpointLost: (id) {
        _found.remove(id);
        _foundAt.remove(id);
        notifyListeners();
      },
      serviceId: _svc);

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _foundAt.clear();
    _fails.clear();
    _found.clear();
    _links.clear();
    _mesh.clear();
    _pending.clear();
    _incoming.clear();
    statusText = null;
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
    } catch (_) {}
  }

  // ------------------------------------------------------------ connections

  void _init(String id, ConnectionInfo info) {
    _found[id] = info.endpointName;
    Nearby().acceptConnection(id,
        onPayLoadRecieved: _onPayload, onPayloadTransferUpdate: (a, b) {});
  }

  void _result(String id, Status s) {
    final ok = s == Status.CONNECTED;
    if (ok) {
      final name = _found[id] ?? id;
      _links[id] = name;
      _mesh.remove(name); // now a direct neighbour
      _wanted.add(name);
      _sendProfile(id);
      flushOutbox(name); // messages written while they were away
      if (statusText != null && statusText!.contains(name)) statusText = null;
    } else {
      _links.remove(id);
    }
    _pending.remove(id)?.complete(ok);
    notifyListeners();
    if (ok && meshEnabled) _tick();
  }

  void _disc(String id) {
    final name = _links.remove(id);
    for (final e in _incoming.entries.toList()) {
      if (e.value.eid == id) {
        e.value.msg.failed = true;
        _incoming.remove(e.key);
      }
    }
    notifyListeners();
    if (name != null && _timer != null) _scheduleReconnect(name);
  }

  /// The link dropped: scan again at once and reconnect without waiting.
  void _scheduleReconnect(String name) {
    final label = 'Reconnecting to $name...';
    statusText = label;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (_timer == null || _links.containsValue(name)) return;
      await refreshRadio(); // the other phone may have a new id now
      _tick();
    });
    Future.delayed(const Duration(seconds: 30), () {
      if (statusText == label) {
        statusText = null;
        notifyListeners();
      }
    });
  }

  @override
  void deliverQueued(String name, Msg m) {
    for (final e in _links.entries) {
      if (e.value == name) {
        _sendTo(e.key, {'k': 'm', 'i': m.id, 'x': m.text});
        return;
      }
    }
  }

  @override
  Future<bool> connect(Peer p) async {
    if (p.connected) return true;
    for (var attempt = 0; attempt < 3; attempt++) {
      statusText = 'Connecting to ${p.name} (try ${attempt + 1}/3)...';
      notifyListeners();
      final c = Completer<bool>();
      _pending[p.id] = c;
      // Searching while connecting keeps the radio busy; pause it.
      try {
        await Nearby().stopDiscovery();
      } catch (_) {}
      var ok = false;
      try {
        await Nearby().requestConnection(_me, p.id,
            onConnectionInitiated: _init,
            onConnectionResult: _result,
            onDisconnected: _disc);
        ok = await c.future
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      } catch (e) {
        if (e.toString().contains('8003')) {
          // already connected to this phone
          _links[p.id] = _found[p.id] ?? p.name;
          ok = true;
        }
      }
      _pending.remove(p.id);
      if (ok) {
        statusText = null;
        try {
          await _startDiscovery();
        } catch (_) {}
        notifyListeners();
        return true;
      }
      try {
        await Nearby().disconnectFromEndpoint(p.id);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    statusText = null;
    notifyListeners();
    try {
      await _startDiscovery();
    } catch (_) {}
    return false;
  }

  /// Mesh mode: connect by ourselves. Only the phone whose name sorts first
  /// starts the connection, so two phones do not call each other at once.
  Future<void> _autoConnect(String id) async {
    if (_links.containsKey(id) || _pending.containsKey(id)) return;
    final c = Completer<bool>();
    _pending[id] = c;
    var ok = false;
    try {
      await Nearby().requestConnection(_me, id,
          onConnectionInitiated: _init,
          onConnectionResult: _result,
          onDisconnected: _disc);
      ok = await c.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    } catch (_) {}
    _pending.remove(id);
    if (ok) {
      _fails.remove(id);
      return;
    }
    final n = (_fails[id] ?? 0) + 1;
    _fails[id] = n;
    try {
      await Nearby().disconnectFromEndpoint(id);
    } catch (_) {}
    if (n >= 2) {
      _fails.remove(id);
      await refreshRadio(); // the saved id is probably old
    }
  }

  // ------------------------------------------------------------------- mesh

  String _newId() => '$_me-${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1 << 20)}';

  bool _markSeen(String id) {
    if (!_seenSet.add(id)) return false;
    _seenList.add(id);
    if (_seenList.length > 600) _seenSet.remove(_seenList.removeAt(0));
    return true;
  }

  void _sendTo(String endpointId, Map<String, dynamic> m) {
    Nearby()
        .sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(m))))
        .catchError((_) {});
  }

  void _flood(Map<String, dynamic> m, {String? except}) {
    for (final id in _links.keys.toList()) {
      if (id != except) _sendTo(id, m);
    }
  }

  void _tick() {
    if (_me.isEmpty) return;
    final t0 = DateTime.now();
    for (final e in _found.entries.toList()) {
      final id = e.key;
      final name = e.value;
      if (_links.containsKey(id) || _pending.containsKey(id)) continue;
      final known = meshEnabled ||
          _wanted.contains(name) ||
          sharedChats.containsKey('dm:$name'); // someone we talked to before
      if (!known) continue;
      // The phone with the smaller name calls first. The other one joins in
      // after 10 seconds, so it still works if the first phone is asleep.
      final waited = t0.difference(_foundAt[id] ?? t0).inSeconds;
      if (_me.compareTo(name) < 0 || waited >= 10) _autoConnect(id);
    }
    if (!meshEnabled) return;
    final id = _newId();
    _markSeen(id);
    _flood({'k': 'ann', 'id': id, 'from': _me, 'ttl': _ttl});
    final now = DateTime.now();
    final old = _mesh.entries
        .where((e) => now.difference(e.value).inSeconds > 30)
        .map((e) => e.key)
        .toList();
    for (final k in old) {
      _mesh.remove(k);
    }
    if (old.isNotEmpty) notifyListeners();
  }

  String _nameOf(String endpointId) => _links[endpointId] ?? _found[endpointId] ?? endpointId;

  String _keyFor(String name) => 'dm:$name';

  void _sendProfile(String endpointId) =>
      _sendTo(endpointId, {'k': 'p', 'n': _me, ...profileJson()});

  @override
  void profileChanged() {
    for (final id in _links.keys.toList()) {
      _sendProfile(id);
    }
  }

  @override
  void ack(String key, String id, int status) {
    if (!key.startsWith('dm:')) return;
    final name = key.substring(3);
    for (final e in _links.entries) {
      if (e.value == name) {
        _sendTo(e.key, {'k': 'a', 'i': id, 's': status});
        return;
      }
    }
  }

  void _onPayload(String eid, Payload p) {
    if (p.type != PayloadType.BYTES || p.bytes == null) return;
    final bytes = p.bytes!;
    if (bytes.isNotEmpty && bytes[0] == 1) {
      _onChunk(bytes); // a piece of a photo / video
      return;
    }
    final raw = utf8.decode(bytes);
    Map? m;
    try {
      final d = jsonDecode(raw);
      if (d is Map) m = d;
    } catch (_) {}
    if (m == null) {
      addMsg('dm:${_nameOf(eid)}', Msg(raw, false)); // plain text from an older version
      return;
    }
    switch (m['k']) {
      case 'm':
        receive('dm:${_nameOf(eid)}',
            Msg(m['x'] as String, false, id: m['i'] as String?));
        break;
      case 'a':
        handleAck('dm:${_nameOf(eid)}', m['i'] as String, m['s'] as int);
        break;
      case 'p':
        storeProfile((m['n'] as String?) ?? _nameOf(eid), m);
        break;
      case 'fh':
        _startIncoming(eid, m);
        break;
      case 'ann':
        _onAnnounce(eid, m);
        break;
      case 'r':
        _onRelay(eid, m);
        break;
    }
  }

  void _noteMesh(String name) {
    if (name == _me || _links.containsValue(name)) return;
    final isNew = !_mesh.containsKey(name);
    _mesh[name] = DateTime.now();
    if (isNew) notifyListeners();
  }

  void _onAnnounce(String eid, Map m) {
    if (!_markSeen(m['id'] as String)) return;
    _noteMesh(m['from'] as String);
    final ttl = (m['ttl'] as int) - 1;
    if (ttl > 0 && meshEnabled) {
      _flood({'k': 'ann', 'id': m['id'], 'from': m['from'], 'ttl': ttl}, except: eid);
    }
  }

  void _onRelay(String eid, Map m) {
    if (!_markSeen(m['id'] as String)) return;
    final from = m['from'] as String;
    final to = m['to'] as String;
    if (to == _me) {
      _noteMesh(from);
      addMsg(_keyFor(from), Msg(m['x'] as String, false));
      return;
    }
    final ttl = (m['ttl'] as int) - 1;
    if (ttl > 0 && meshEnabled) {
      _flood({
        'k': 'r',
        'id': m['id'],
        'from': from,
        'to': to,
        'x': m['x'],
        'ttl': ttl,
      }, except: eid);
    }
  }

  // ------------------------------------------------------- photos & videos

  @override
  Future<String?> sendMedia(Peer p, String path, String kind) async {
    if (!_links.containsKey(p.id)) {
      return '${p.name} is not directly connected';
    }
    final size = await File(path).length();
    if (size > kMaxMedia) return 'File is too big (max 30 MB)';
    final f = await stageFile(path);
    final fid = newId();
    final total = (size + _chunk - 1) ~/ _chunk;
    final m = Msg(mediaLabel(kind), true,
        id: fid, kind: kind, file: f.path, size: size, progress: 0);
    addMsg(p.key, m);
    _sendTo(p.id, {
      'k': 'fh',
      'i': fid,
      'kind': kind,
      'name': f.path.split('/').last,
      'size': size,
      'n': total,
    });
    _pump(p.id, f, fid, total, m);
    return null;
  }

  // ------------------------------------------------------------------- send

  @override
  void send(Peer p, String text) {
    final msg = Msg(text, true, id: newId());
    addMsg(p.key, msg);
    if (p.id.startsWith('mesh:')) {
      final id = _newId();
      _markSeen(id);
      _flood({
        'k': 'r',
        'id': id,
        'from': _me,
        'to': p.id.substring(5),
        'x': text,
        'ttl': _ttl,
      });
    } else {
      _sendTo(p.id, {'k': 'm', 'i': msg.id, 'x': text});
    }
  }
}

// EOF
