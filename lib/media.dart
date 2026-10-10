import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import 'transport.dart';

String fmtSize(int b) => b >= 1048576
    ? '${(b / 1048576).toStringAsFixed(1)} MB'
    : '${(b / 1024).ceil()} KB';

/// Photo or video inside a chat bubble.
class MediaBubble extends StatelessWidget {
  final Msg m;
  const MediaBubble(this.m, {super.key});

  Widget _box(Widget child) => Container(
      width: 220,
      height: 160,
      color: const Color(0x33000000),
      alignment: Alignment.center,
      child: child);

  @override
  Widget build(BuildContext context) {
    final busy = m.progress < 1 && !m.failed;
    final ready = m.file != null && !m.failed && !busy;
    Widget content;
    if (m.kind == 'image' && ready) {
      content = Image.file(File(m.file!),
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _box(const Icon(Icons.broken_image, size: 40)));
    } else if (busy) {
      content = _box(Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(value: m.progress > 0 ? m.progress : null),
        const SizedBox(height: 8),
        Text('${(m.progress * 100).round()}%',
            style: const TextStyle(fontSize: 12)),
      ]));
    } else {
      content = _box(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            m.failed
                ? Icons.error_outline
                : (m.kind == 'video' ? Icons.play_circle_fill : Icons.image),
            size: 44),
        const SizedBox(height: 6),
        Text(
            m.failed
                ? 'Could not load'
                : '${m.kind == 'video' ? 'Video' : 'Photo'} • ${fmtSize(m.size)}',
            style: const TextStyle(fontSize: 12)),
      ]));
    }
    return GestureDetector(
      onTap: ready
          ? () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => MediaScreen(m)))
          : null,
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: content),
    );
  }
}

/// Full screen view of a photo / video with Save and Share.
class MediaScreen extends StatelessWidget {
  final Msg m;
  const MediaScreen(this.m, {super.key});

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (m.kind == 'video') {
        await Gal.putVideo(m.file!, album: 'BitMee');
      } else {
        await Gal.putImage(m.file!, album: 'BitMee');
      }
      messenger.showSnackBar(
          const SnackBar(content: Text('Saved to your gallery (album: BitMee)')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save. Allow photo / storage permission and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = m.kind == 'video';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, actions: [
        IconButton(
            tooltip: 'Save to gallery',
            icon: const Icon(Icons.download),
            onPressed: () => _save(context)),
        IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: () => Share.shareXFiles([XFile(m.file!)])),
      ]),
      body: video
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.videocam, size: 80, color: Colors.white54),
              const SizedBox(height: 16),
              Text('Video • ${fmtSize(m.size)}',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text('Save it to your gallery to play it',
                  style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: () => _save(context),
                  icon: const Icon(Icons.download),
                  label: const Text('Save to gallery')),
            ]))
          : InteractiveViewer(child: Center(child: Image.file(File(m.file!)))),
    );
  }
}

// EOF
