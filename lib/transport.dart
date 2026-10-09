import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// ----------------------------------------------------------------- models

class Peer {
  final String id, name;
  final bool connected;
  Peer(this.id, this.name, this.connected);

  /// Conversation key: the same person always has the same chat,
  /// whichever way (Bluetooth, WiFi, mesh) they are reached.
  String get key => id.startsWith('group:')
      ? id
      : id.startsWith('mesh:')
          ? 'dm:${id.substring(5)}'
          : 'dm:$name';
}

class Msg {
  final String text;
  final bool mine;
  final String? sender; // shown in group chats
  final String? id; // used for delivery / read ticks
  int status; // 1 = sent, 2 = delivered, 3 = read
  final DateTime at;
  Msg(this.text, this.mine,
      {this.sender, this.id, this.status = 1, DateTime? at})
      : at = at ?? DateTime.now();
}

/// What another person shares about themselves.
class PeerProfile {
  final String bio, about;
  final ImageProvider? image;
  PeerProfile(this.bio, this.about, Uint8List? thumb)
      : image = (thumb == null || thumb.isEmpty) ? null : MemoryImage(thumb);
}

// Shared by Bluetooth and WiFi so a conversation is the same on both.
final sharedChats = <String, List<Msg>>{};
final sharedUnread = <String, int>{};
final sharedProfiles = <String, PeerProfile>{};

// ------------------------------------------------------------- transports

abstract class Transport extends ChangeNotifier {
  final chats = sharedChats;
  final unread = sharedUnread;
  final profiles = sharedProfiles;
  String? openId; // key of the chat that is open on screen
  String? error;
  bool needSettings = false;
  bool needLocation = false;
  bool appActive = true; // false while the app is in the background
  void Function(String key, Msg m)? onIncoming; // for notifications
  void Function()? onChanged; // chats changed (for saving)
  bool _dead = false;

  // My own profile, shared with the people I talk to.
  String myBio = '';
  String myAbout = '';
  Uint8List? myThumb;
  int profileVersion = 0;

  Future<bool> start(String me);
  List<Peer> get peers;
  Future<bool> connect(Peer p) async => true;
  void send(Peer p, String text);
  Future<void> stop();

  bool isOnline(String id) => peers.any((p) => p.id == id && p.connected);

  // Mesh relay (Bluetooth only): messages hop through nearby phones.
  bool meshEnabled = false;
  bool get supportsMesh => false;
  List<Peer> get meshPeers => const <Peer>[];
  void setMesh(bool on) {}

  // Group chat (WiFi only). Other transports have no groups.
  Set<String> get joinedGroups => const <String>{};
  List<String> get nearbyGroups => const <String>[];
  void joinGroup(String name) {}
  void leaveGroup(String name) {}

  /// Send a delivery / read confirmation to the person behind [key].
  void ack(String key, String id, int status) {}

  /// My profile changed: tell the others.
  void profileChanged() {}

  void setMyProfile(String bio, String about, Uint8List? thumb) {
    myBio = bio;
    myAbout = about;
    myThumb = thumb;
    profileVersion =
        Object.hash(bio, about, Object.hashAll(thumb ?? const <int>[]));
    profileChanged();
  }

  Map<String, dynamic> profileJson() => {
        'bio': myBio,
        'about': myAbout,
        'av': myThumb == null ? '' : base64Encode(myThumb!),
        'pv': profileVersion,
      };

  void storeProfile(String name, Map m) {
    final av = (m['av'] as String?) ?? '';
    Uint8List? thumb;
    if (av.isNotEmpty) {
      try {
        thumb = base64Decode(av);
      } catch (_) {}
    }
    profiles[name] = PeerProfile(
        (m['bio'] as String?) ?? '', (m['about'] as String?) ?? '', thumb);
    notifyListeners();
  }

  ImageProvider? avatarOf(String name) => profiles[name]?.image;

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  void addMsg(String key, Msg m) {
    (chats[key] ??= []).add(m);
    if (!m.mine) {
      if (openId != key) unread[key] = (unread[key] ?? 0) + 1;
      onIncoming?.call(key, m);
    }
    onChanged?.call();
    notifyListeners();
  }

  /// A message from another phone: keep it and confirm delivery / reading.
  void receive(String key, Msg m) {
    addMsg(key, m);
    final id = m.id;
    if (id == null) return;
    ack(key, id, 2);
    m.status = 2;
    if (appActive && openId == key) {
      ack(key, id, 3);
      m.status = 3;
    }
  }

  /// The person opened the chat: confirm everything they received as read.
  void markRead(String key) {
    for (final m in chats[key] ?? <Msg>[]) {
      if (!m.mine && m.id != null && m.status < 3) {
        ack(key, m.id!, 3);
        m.status = 3;
      }
    }
    onChanged?.call();
  }

  void handleAck(String key, String id, int status) {
    for (final m in chats[key] ?? <Msg>[]) {
      if (m.mine && m.id == id && m.status < status) {
        m.status = status;
        onChanged?.call();
        notifyListeners();
        return;
      }
    }
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
        case 'g':
          final gname = m['gn'] as String;
          if (_groups.contains(gname)) {
            addMsg('group:$gname', Msg(m['x'] as String, false, sender: name));
          }
          break;
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
  }
}

// EOF
