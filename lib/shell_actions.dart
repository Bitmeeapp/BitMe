part of 'shell.dart';

extension _ShellActions on _ShellState {
  Widget _groupTile(String name) {
    final id = 'group:$name';
    final joined = t.joinedGroups.contains(name);
    final msgs = t.chats[id] ?? [];
    final last = msgs.isEmpty ? null : msgs.last;
    final un = t.unread[id] ?? 0;
    final sub = last != null
        ? '${last.mine ? 'You' : (last.sender ?? '')}: ${last.text}'
        : (joined ? 'Group • say hi' : 'Group nearby • tap to join');
    return InkWell(
      onTap: () {
        if (!joined) {
          t.joinGroup(name);
          _saveGroups();
        }
        _openGroup(name);
      },
      onLongPress: joined ? () => _leaveGroup(name) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(name: name, group: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: un > 0 ? Colors.lightBlueAccent : Colors.white60)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(last == null ? '' : fmtTime(last.at),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            if (un > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration:
                    const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                child: Text('$un',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  void _openGroup(String name) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ChatScreen(t: t, peer: Peer('group:$name', name, true))));
  }

  Future<void> _newGroup() async {
    if (_mode != Mode.wifi) await _setMode(Mode.wifi);
    if (!mounted) return;
    final n = await askText(context, 'Create or join group',
        hint: 'Group name', ok: 'Continue');
    if (n == null || n.isEmpty) return;
    t.joinGroup(n);
    _saveGroups();
    _openGroup(n);
  }

  Future<void> _leaveGroup(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Leave "$name"?'),
        content: const Text('Group messages will be removed from this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) {
      t.leaveGroup(name);
      _saveGroups();
    }
  }

  Future<void> _sendSms() async {
    final phoneCtl = TextEditingController();
    final msg = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send SMS'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Uses your SIM network, no internet needed. Normal SMS charges may apply. Replies arrive in your SMS app.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 12),
          TextField(
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Phone number')),
          TextField(
              controller: msg,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Message')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    final n = phoneCtl.text.trim();
    final m = msg.text.trim();
    if (n.isEmpty || m.isEmpty) {
      _snack('Enter a number and a message');
      return;
    }
    final launched = await launchUrl(
        Uri.parse('sms:$n?body=${Uri.encodeComponent(m)}'),
        mode: LaunchMode.externalApplication);
    if (!launched && mounted) _snack('Could not open the SMS app');
  }

  Future<void> _editProfile() async {
    _sk.currentState?.closeEndDrawer();
    final nameC = TextEditingController(text: _me);
    final bioC = TextEditingController(text: _bio);
    final aboutC = TextEditingController(text: _about);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: const Text('Edit profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameC,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Username')),
          TextField(
              controller: bioC,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Bio (short)', hintText: 'One line about you')),
          TextField(
              controller: aboutC,
              maxLength: 300,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                  labelText: 'About (long description)',
                  alignLabelWithHint: true)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameC.text.trim();
    final bio = bioC.text.trim();
    final about = aboutC.text.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('bio', bio);
    await p.setString('about', about);
    final renamed = name.isNotEmpty && name != _me;
    if (renamed) await p.setString('username', name);
    if (!mounted) return;
    _setProfile(bio, about, renamed ? name : null);
  }

  Future<void> _initNotifications() async {
    try {
      await _notifier.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon')));
      await Permission.notification.request();
    } catch (_) {}
  }

  void _notify(String key, Msg m) {
    if (!_background) return;
    final isGroup = key.startsWith('group:');
    final name = key.substring(isGroup ? 6 : 3);
    final title = isGroup ? '${m.sender ?? 'Someone'} • $name' : name;
    _notifier
        .show(
            key.hashCode & 0x7fffffff,
            title,
            m.text,
            const NotificationDetails(
                android: AndroidNotificationDetails('bitme_messages', 'Messages',
                    channelDescription: 'New message alerts',
                    importance: Importance.high,
                    priority: Priority.high)))
        .catchError((_) {});
  }

  /// Tell both transports what my profile looks like (shared with others).
  void _syncProfile() {
    for (final tr in [_bt, _wifi]) {
      tr.setMyProfile(_bio, _about, _thumb);
    }
  }

  Future<void> _saveGroups() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('groups', _wifi.joinedGroups.toList());
  }

  void _avatarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickAvatar();
            },
          ),
          if (_avatar != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () {
                Navigator.pop(context);
                _removeAvatar();
              },
            ),
        ]),
      ),
    );
  }

  void _plusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Add username'),
            subtitle: const Text('Chat with one person'),
            onTap: () {
              Navigator.pop(context);
              _addUsername();
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('Create or join group'),
            subtitle: const Text('Group chat over WiFi'),
            onTap: () {
              Navigator.pop(context);
              _newGroup();
            },
          ),
          ListTile(
            leading: const Icon(Icons.sms),
            title: const Text('Send SMS'),
            subtitle: const Text('Uses SIM network, no internet'),
            onTap: () {
              Navigator.pop(context);
              _sendSms();
            },
          ),
        ]),
      ),
    );
  }
}

// EOF
