import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'media.dart';
import 'transport.dart';
import 'ui.dart';

class ChatScreen extends StatefulWidget {
  final Transport t;
  final Peer peer;
  const ChatScreen({super.key, required this.t, required this.peer});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();

  String get _key => widget.peer.key;
  bool get _isGroup => widget.peer.id.startsWith('group:');

  @override
  void initState() {
    super.initState();
    widget.t.openId = _key;
    widget.t.unread.remove(_key);
    widget.t.markRead(_key);
  }

  void _attachMenu() {
    if (_isGroup) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Photos and videos can only be sent in a one-to-one chat')));
      return;
    }
    void choose(ImageSource s, bool video) {
      Navigator.pop(context);
      _pick(s, video);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => choose(ImageSource.camera, false)),
          ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record a video'),
              onTap: () => choose(ImageSource.camera, true)),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo from gallery'),
              onTap: () => choose(ImageSource.gallery, false)),
          ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Video from gallery'),
              onTap: () => choose(ImageSource.gallery, true)),
        ]),
      ),
    );
  }

  Future<void> _pick(ImageSource source, bool video) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final x = video
          ? await picker.pickVideo(
              source: source, maxDuration: const Duration(seconds: 60))
          : await picker.pickImage(
              source: source, maxWidth: 1600, imageQuality: 85);
      if (x == null) return;
      if (!widget.t.isOnline(widget.peer.id)) {
        messenger.showSnackBar(
            SnackBar(content: Text('${widget.peer.name} is offline')));
        return;
      }
      final err = await widget.t
          .sendMedia(widget.peer, x.path, video ? 'video' : 'image');
      if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not open the camera / gallery')));
    }
  }

  void _showProfile() {
    if (_isGroup) return;
    final prof = widget.t.profiles[widget.peer.name];
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: widget.peer.name, size: 96, image: prof?.image),
            const SizedBox(height: 12),
            Text(widget.peer.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text((prof?.bio ?? '').isEmpty ? 'No bio yet' : prof!.bio,
                style: const TextStyle(color: Colors.white70)),
            if ((prof?.about ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(prof!.about, style: const TextStyle(height: 1.4))),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.t.openId = null;
    _c.dispose();
    super.dispose();
  }

  void _send() {
    final s = _c.text.trim();
    if (s.isEmpty) return;
    if (!widget.t.isOnline(widget.peer.id)) {
      if (_isGroup) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.peer.name} is offline')));
        return;
      }
      // The person is away: keep the message and send it when they are back.
      widget.t.queue(widget.peer, s);
      _c.clear();
      return;
    }
    widget.t.send(widget.peer, s);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'profile') _showProfile();
                if (v == 'clear') {
                  for (final m in widget.t.chats[_key] ?? <Msg>[]) {
                    final f = m.file;
                    if (f != null) {
                      try {
                        File(f).deleteSync();
                      } catch (_) {}
                    }
                  }
                  widget.t.chats.remove(_key);
                  widget.t.outbox.remove(_key);
                  widget.t.onChanged?.call();
                  widget.t.refresh();
                }
              },
              itemBuilder: (_) => [
                if (!_isGroup)
                  const PopupMenuItem(value: 'profile', child: Text('View profile')),
                const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
              ],
            ),
          ],
          title: ListenableBuilder(
            listenable: widget.t,
            builder: (_, __) {
              final on = widget.t.isOnline(widget.peer.id);
              final isGroup = widget.peer.id.startsWith('group:');
              final isMesh = widget.peer.id.startsWith('mesh:');
              return GestureDetector(
                  onTap: _showProfile,
                  child: Row(children: [
                Avatar(
                    name: widget.peer.name,
                    size: 40,
                    group: isGroup,
                    image: isGroup ? null : widget.t.avatarOf(widget.peer.name)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  if (isGroup)
                    const Text('Group chat • WiFi',
                        style: TextStyle(fontSize: 12, color: Colors.white60))
                  else
                    Row(children: [
                      Icon(Icons.circle, size: 9, color: on ? kGreen : Colors.grey),
                      const SizedBox(width: 5),
                      Text(on ? (isMesh ? 'Via mesh' : 'Online') : 'Offline',
                          style: const TextStyle(fontSize: 12, color: Colors.white60)),
                    ]),
                ])),
              ]));
            },
          ),
        ),
        body: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.t,
              builder: (_, __) {
                final msgs = (widget.t.chats[_key] ?? []).reversed.toList();
                final maxW = MediaQuery.of(context).size.width * .72;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final bubble = Container(
                      constraints: BoxConstraints(maxWidth: maxW),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      decoration: BoxDecoration(
                        gradient: m.mine ? kGradient : null,
                        color: m.mine ? null : kBubble,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!m.mine && m.sender != null)
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(m.sender!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.lightBlueAccent)),
                                  )),
                            if (m.kind != null)
                              MediaBubble(m)
                            else
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(m.text, style: const TextStyle(fontSize: 16))),
                            const SizedBox(height: 3),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(fmtTime(m.at),
                                  style: const TextStyle(fontSize: 11, color: Colors.white60)),
                              if (m.mine) ...[
                                const SizedBox(width: 4),
                                Icon(m.status == 0 ? Icons.schedule : (m.status >= 2 ? Icons.done_all : Icons.done),
                                    size: 14,
                                    color: m.status >= 3
                                        ? Colors.cyanAccent
                                        : Colors.white70),
                              ],
                            ]),
                          ]),
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment:
                            m.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!m.mine) ...[
                            Avatar(
                                name: m.sender ?? widget.peer.name,
                                size: 30,
                                image: widget.t.avatarOf(m.sender ?? widget.peer.name)),
                            const SizedBox(width: 8),
                          ],
                          bubble,
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(children: [
                IconButton(
                    tooltip: 'Photo / video',
                    icon: const Icon(Icons.attach_file),
                    onPressed: _attachMenu),
                Expanded(
                  child: TextField(
                    controller: _c,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: kCard,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration:
                        const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
}

// EOF
