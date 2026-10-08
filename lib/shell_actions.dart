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
        if (!joined) t.joinGroup(name);
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
    if (ok == true) t.leaveGroup(name);
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
