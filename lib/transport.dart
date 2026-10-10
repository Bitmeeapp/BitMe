import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

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
  // Photo / video (kind is null for plain text messages)
  final String? kind; // 'image' or 'video'
  String? file; // path on this phone once the file is available
  final int size; // bytes
  double progress; // 0..1 while a file is being sent / received
  bool failed;
  Msg(this.text, this.mine,
      {this.sender,
      this.id,
      this.status = 1,
      DateTime? at,
      this.kind,
      this.file,
      this.size = 0,
      this.progress = 1,
      this.failed = false})
      : at = at ?? DateTime.now();
}

/// Biggest photo / video that can be sent (30 MB).
const kMaxMedia = 30 * 1024 * 1024;

String mediaLabel(String kind) => kind == 'video' ? '🎥 Video' : '📷 Photo';

/// Folder where BitMee keeps the photos and videos of your chats.
Future<Directory> mediaDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/media');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
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
// Messages written while the other phone was away (key -> waiting messages).
final sharedOutbox = <String, List<Msg>>{};

// ------------------------------------------------------------- transports

abstract class Transport extends ChangeNotifier {
  final chats = sharedChats;
  final unread = sharedUnread;
  final profiles = sharedProfiles;
  final outbox = sharedOutbox;
  String? openId; // key of the chat that is open on screen
  String? error;
  bool needSettings = false;
  bool needLocation = false;
  bool appActive = true; // false while the app is in the background
  String? statusText; // e.g. "Connecting to Sam (try 2/3)..."
  String? hint; // e.g. "No WiFi connection found"
  bool needBluetooth = false;
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

  /// The other phone is away: keep the message, send it when they are back.
  void queue(Peer p, String text) {
    final m = Msg(text, true, id: newId(), status: 0);
    addMsg(p.key, m);
    (outbox[p.key] ??= []).add(m);
  }

  /// Send one waiting message to [name] (they are reachable now).
  void deliverQueued(String name, Msg m) {}

  void flushOutbox(String name) {
    final q = outbox.remove('dm:$name');
    if (q == null || q.isEmpty) return;
    for (final m in q) {
      deliverQueued(name, m);
      if (m.status == 0) m.status = 1;
    }
    onChanged?.call();
    notifyListeners();
  }

  /// Search again for phones (also refreshes a stale list).
  Future<void> refreshRadio() async {}

  /// Send a photo or video. Returns an error text, or null when it started.
  Future<String?> sendMedia(Peer p, String path, String kind) async =>
      'Photos and videos are not supported here';

  /// Copy a picked file into BitMee's own folder.
  Future<File> stageFile(String path) async {
    final dir = await mediaDir();
    final name = path.split('/').last;
    return File(path).copy('${dir.path}/${newId()}_$name');
  }

  /// A file finished arriving: keep its path and confirm delivery.
  void mediaDone(String key, Msg m, String filePath) {
    m.file = filePath;
    m.progress = 1;
    final id = m.id;
    if (id != null) {
      ack(key, id, 2);
      m.status = 2;
      if (appActive && openId == key) {
        ack(key, id, 3);
        m.status = 3;
      }
    }
    onChanged?.call();
    notifyListeners();
  }

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

// EOF
