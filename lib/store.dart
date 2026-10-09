import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import 'transport.dart';

/// Keeps chats on the phone so they are still there after the app is closed.
class ChatStore {
  static Timer? _timer;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('chats_v1');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map;
      data.forEach((k, v) {
        final old = (v as List).map((e) {
          final l = e as List;
          return Msg(l[0] as String, l[1] == 1,
              sender: l[3] as String?,
              id: l[4] as String?,
              status: l[5] as int,
              at: DateTime.fromMillisecondsSinceEpoch(l[2] as int));
        }).toList();
        final key = k as String;
        sharedChats[key] = [...old, ...(sharedChats[key] ?? <Msg>[])];
      });
    } catch (_) {}
  }

  static void saveSoon() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _save);
  }

  static Future<void> _save() async {
    final out = <String, dynamic>{};
    sharedChats.forEach((k, v) {
      if (v.isEmpty) return;
      final tail = v.length > 200 ? v.sublist(v.length - 200) : v;
      out[k] = tail
          .map((m) => [
                m.text,
                m.mine ? 1 : 0,
                m.at.millisecondsSinceEpoch,
                m.sender,
                m.id,
                m.status,
              ])
          .toList();
    });
    final p = await SharedPreferences.getInstance();
    await p.setString('chats_v1', jsonEncode(out));
  }
}

/// Small 64x64 square copy of the profile picture. This is what is sent to
/// other phones (the full picture is too big for a Bluetooth/UDP message).
Future<Uint8List> makeThumb(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final s = (img.width < img.height ? img.width : img.height).toDouble();
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH((img.width - s) / 2, (img.height - s) / 2, s, s),
      ui.Rect.fromLTWH(0, 0, 64, 64),
      ui.Paint()..filterQuality = ui.FilterQuality.medium);
  final out = await rec.endRecording().toImage(64, 64);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// EOF
