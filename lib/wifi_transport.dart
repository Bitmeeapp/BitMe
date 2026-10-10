import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'transport.dart';

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
  final _peerPv = <String, int>{};
  final _askedAt = <String, DateTime>{};
  final _servers = <ServerSocket>[];

  Map<String, dynamic> _hi() =>
      {'t': 'hi', 'g': _groups.toList(), 'pv': profileVersion};

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
      onChanged?.call();
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
  void profileChanged() => _hello();

  @override
  Future<bool> start(String me) async {
    _me = me;
    try {
      _timer?.cancel();
      await _bind();
      _checkWifi();
      _hello();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_sock == null) {
          // the network changed or the socket closed: open it again
          try {
            await _bind();
          } catch (_) {}
        }
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

  Future<void> _bind() async {
    _sock?.close();
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port,
        reuseAddress: true);
    s.broadcastEnabled = true;
    s.listen(_onEvent, onError: (_) => _sock = null, onDone: () => _sock = null);
    _sock = s;
  }

  /// Warn when the phone is not on a WiFi network (or hotspot).
  Future<void> _checkWifi() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final onWifi = ifs.any((i) =>
          RegExp(r'wlan|swlan|ap\d|wifi|eth', caseSensitive: false).hasMatch(i.name));
      final h = onWifi
          ? null
          : 'No WiFi connection found.\nConnect both phones to the same WiFi, or turn on a hotspot on one phone and connect the other phone to it.';
      if (h != hint) {
        hint = h;
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  Future<void> refreshRadio() async {
    _names.clear();
    _ips.clear();
    _seen.clear();
    notifyListeners();
    await _checkWifi();
    _hello();
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

  void _askProfile(String u, InternetAddress a) {
    final last = _askedAt[u];
    if (last != null && DateTime.now().difference(last).inSeconds < 5) return;
    _askedAt[u] = DateTime.now();
    _tx(a, {'t': 'pq'});
  }

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final d = _sock?.receive();
    if (d == null) return;
    try {
      final m = jsonDecode(utf8.decode(d.data)) as Map;
      final u = m['u'] as String;
      if (u == _uid) return;
      final name = m['n'] as String;
      final isNew = !_names.containsKey(u);
      _names[u] = name;
      _ips[u] = d.address;
      _seen[u] = DateTime.now();
      var changed = isNew;
      switch (m['t']) {
        case 'hi':
          final gl = ((m['g'] as List?) ?? []).map((x) => x.toString()).toList();
          if ((_peerGroups[u] ?? []).join('|') != gl.join('|')) changed = true;
          _peerGroups[u] = gl;
          final hpv = m['pv'];
          if (hpv is int && hpv != 0 && _peerPv[u] != hpv) _askProfile(u, d.address);
          break;
        case 'pq':
          _tx(d.address, {'t': 'p', ...profileJson()});
          break;
        case 'p':
          storeProfile(name, m);
          final ppv = m['pv'];
          if (ppv is int) _peerPv[u] = ppv;
          break;
        case 'm':
          receive('dm:$name', Msg(m['x'] as String, false, id: m['i'] as String?));
          break;
        case 'a':
          handleAck('dm:$name', m['i'] as String, m['s'] as int);
          break;
        case 'fh':
          _download(name, d.address, m);
          break;
        case 'g':
          final gname = m['gn'] as String;
          if (_groups.contains(gname)) {
            addMsg('group:$gname', Msg(m['x'] as String, false, sender: name));
          }
          break;
      }
      if (isNew) {
        _tx(d.address, _hi());
        flushOutbox(name); // messages written while they were away
      }
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

  /// Receive a photo / video from [name]: the sender serves the file on a
  /// temporary TCP port and we read it from there.
  Future<void> _download(String name, InternetAddress addr, Map h) async {
    final kind = h['kind'] as String;
    final size = h['size'] as int;
    final key = 'dm:$name';
    final msg = Msg(mediaLabel(kind), false,
        id: h['i'] as String?, kind: kind, size: size, progress: 0);
    addMsg(key, msg);
    if (size > kMaxMedia) {
      msg.failed = true;
      notifyListeners();
      return;
    }
    try {
      final dir = await mediaDir();
      final fname = (h['name'] as String).replaceAll('/', '_');
      final file = File('${dir.path}/${newId()}_$fname');
      final sink = file.openWrite();
      final s = await Socket.connect(addr, h['port'] as int,
          timeout: const Duration(seconds: 10));
      var got = 0;
      var last = DateTime.now();
      await for (final chunk in s) {
        sink.add(chunk);
        got += chunk.length;
        msg.progress = size == 0 ? 1 : got / size;
        if (DateTime.now().difference(last).inMilliseconds > 300) {
          last = DateTime.now();
          notifyListeners();
        }
      }
      await sink.close();
      if (got < size) {
        msg.failed = true;
        notifyListeners();
      } else {
        mediaDone(key, msg, file.path);
      }
    } catch (_) {
      msg.failed = true;
      notifyListeners();
    }
    onChanged?.call();
  }

  @override
  Future<String?> sendMedia(Peer p, String path, String kind) async {
    if (p.id.startsWith('group:') ||
        p.id.startsWith('mesh:') ||
        p.id.startsWith('offline:')) {
      return 'Photos and videos can only be sent in a direct chat';
    }
    final ip = _ips[p.id];
    if (ip == null) return '${p.name} is offline';
    final size = await File(path).length();
    if (size > kMaxMedia) return 'File is too big (max 30 MB)';
    final f = await stageFile(path);
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _servers.add(server);
    server.listen((Socket s) async {
      try {
        await s.addStream(f.openRead());
        await s.close();
      } catch (_) {
        s.destroy();
      }
    });
    Timer(const Duration(minutes: 10), () {
      server.close();
      _servers.remove(server);
    });
    final m = Msg(mediaLabel(kind), true,
        id: newId(), kind: kind, file: f.path, size: size);
    addMsg(p.key, m);
    _tx(ip, {
      't': 'fh',
      'i': m.id,
      'kind': kind,
      'name': f.path.split('/').last,
      'size': size,
      'port': server.port,
    });
    return null;
  }

  @override
  void deliverQueued(String name, Msg m) {
    for (final e in _names.entries) {
      if (e.value == name) {
        final ip = _ips[e.key];
        if (ip != null) _tx(ip, {'t': 'm', 'i': m.id, 'x': m.text});
        return;
      }
    }
  }

  @override
  void ack(String key, String id, int status) {
    if (!key.startsWith('dm:')) return;
    final name = key.substring(3);
    for (final e in _names.entries) {
      if (e.value == name) {
        final ip = _ips[e.key];
        if (ip != null) _tx(ip, {'t': 'a', 'i': id, 's': status});
        return;
      }
    }
  }

  @override
  void send(Peer p, String text) {
    if (p.id.startsWith('group:')) {
      addMsg(p.key, Msg(text, true));
      final gn = p.id.substring(6);
      for (final ip in _ips.values) {
        _tx(ip, {'t': 'g', 'gn': gn, 'x': text});
      }
      return;
    }
    final m = Msg(text, true, id: newId());
    addMsg(p.key, m);
    final ip = _ips[p.id];
    if (ip != null) _tx(ip, {'t': 'm', 'i': m.id, 'x': text});
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
    _peerPv.clear();
    _askedAt.clear();
    for (final s in _servers) {
      s.close();
    }
    _servers.clear();
  }
}

// EOF
