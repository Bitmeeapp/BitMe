part of 'bt_transport.dart';

extension _BtMedia on BtTransport {
  /// A file is announced: prepare to receive its pieces.
  void _startIncoming(String eid, Map h) {
    final kind = h['kind'] as String;
    final size = h['size'] as int;
    final key = 'dm:${_nameOf(eid)}';
    final msg = Msg(mediaLabel(kind), false,
        id: h['i'] as String?, kind: kind, size: size, progress: 0);
    addMsg(key, msg);
    if (size > kMaxMedia || (h['n'] as int) <= 0) {
      msg.failed = true;
      notifyListeners();
      return;
    }
    final fid = h['i'] as String;
    final inc = _In(eid, key, msg, h['n'] as int);
    _incoming[fid] = inc;
    inc.ready = () async {
      final dir = await mediaDir();
      final fname = (h['name'] as String).replaceAll('/', '_');
      inc.path = '${dir.path}/${newId()}_$fname';
      inc.raf = await File(inc.path).open(mode: FileMode.write);
    }();
  }

  /// Piece of a file: [1][idLength][id][4 bytes: number][data]
  void _onChunk(Uint8List b) {
    final idLen = b[1];
    final fid = String.fromCharCodes(b.sublist(2, 2 + idLen));
    final inc = _incoming[fid];
    if (inc == null) return;
    final seq = ByteData.sublistView(b, 2 + idLen, 6 + idLen).getUint32(0);
    final data = Uint8List.sublistView(b, 6 + idLen);
    inc.chain = inc.chain.then((_) async {
      try {
        await inc.ready;
        final raf = inc.raf!;
        await raf.setPosition(seq * BtTransport._chunk);
        await raf.writeFrom(data);
        inc.got++;
        inc.msg.progress = inc.got / inc.total;
        if (inc.got % 10 == 0) notifyListeners();
        if (inc.got >= inc.total) {
          await raf.close();
          _incoming.remove(fid);
          mediaDone(inc.key, inc.msg, inc.path);
        }
      } catch (_) {
        inc.msg.failed = true;
        _incoming.remove(fid);
        notifyListeners();
      }
    });
  }

  Future<void> _pump(String eid, File f, String fid, int total, Msg m) async {
    final idBytes = ascii.encode(fid);
    final raf = await f.open();
    try {
      for (var seq = 0; seq < total; seq++) {
        if (!_links.containsKey(eid)) {
          m.failed = true;
          break;
        }
        final data = await raf.read(BtTransport._chunk);
        final head = 2 + idBytes.length;
        final frame = Uint8List(head + 4 + data.length);
        frame[0] = 1;
        frame[1] = idBytes.length;
        frame.setRange(2, head, idBytes);
        ByteData.sublistView(frame, head, head + 4).setUint32(0, seq);
        frame.setRange(head + 4, frame.length, data);
        await Nearby().sendBytesPayload(eid, frame);
        m.progress = (seq + 1) / total;
        if (seq % 10 == 0) notifyListeners();
      }
    } catch (_) {
      m.failed = true;
    }
    await raf.close();
    notifyListeners();
    onChanged?.call();
  }
}

/// A photo / video that is arriving.
class _In {
  final String eid, key;
  final Msg msg;
  final int total;
  int got = 0;
  String path = '';
  RandomAccessFile? raf;
  Future<void>? ready;
  Future<void> chain = Future.value();
  _In(this.eid, this.key, this.msg, this.total);
}

// EOF
