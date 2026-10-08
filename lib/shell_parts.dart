part of 'shell.dart';

extension _ShellParts on _ShellState {

  Widget _modeSwitch() {
    Widget seg(String label, IconData icon, Mode m) {
      final sel = _mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setMode(m),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
                gradient: sel ? kGradient : null,
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: sel ? Colors.white : Colors.white60),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : Colors.white60)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration:
              BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            seg('Bluetooth', Icons.bluetooth, Mode.bluetooth),
            seg('WiFi', Icons.wifi, Mode.wifi),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
            _mode == Mode.wifi
                ? 'Phones on the same WiFi • group chat works here'
                : 'Phones within ~10 m • no WiFi needed',
            style: const TextStyle(fontSize: 12, color: Colors.white38)),
      ]),
    );
  }

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
    final num = TextEditingController();
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
              controller: num,
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
    final n = num.text.trim();
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

  Widget _profile() => ListenableBuilder(
        listenable: Listenable.merge([_bt, _wifi]),
        builder: (_, __) {
          var sent = 0, got = 0;
          for (final tr in [_bt, _wifi]) {
            for (final l in tr.chats.values) {
              for (final m in l) {
                m.mine ? sent++ : got++;
              }
            }
          }
          final dev = t.peers.where((p) => p.connected).length;
          Widget stat(String n, String l) => Expanded(
                child: Column(children: [
                  Text(n,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(l, style: const TextStyle(color: Colors.white60)),
                ]),
              );
          return ListView(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                height: 150,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF1B1055), Color(0xFF5B21B6), Color(0xFF0E2A6B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
              ),
              Positioned(top: 4, right: 8, child: _menuBtn()),
              Positioned(
                left: 20,
                bottom: -45,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                      child: Avatar(name: _me, size: 84)),
                ),
              ),
            ]),
            const SizedBox(height: 58),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_me, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                Text('@${_me.toLowerCase().replaceAll(' ', '_')}',
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 10),
                const Text('Bitme user ⚡\nChat without internet 💬'),
                const SizedBox(height: 22),
                Row(children: [
                  stat('$sent', 'Sent'),
                  stat('$got', 'Received'),
                  stat('$dev', 'Connected'),
                ]),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          backgroundColor: kCard,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onPressed: _rename,
                      child: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                      style: IconButton.styleFrom(backgroundColor: kCard),
                      onPressed: () => _sk.currentState?.openEndDrawer(),
                      icon: const Icon(Icons.settings_outlined)),
                ]),
              ]),
            ),
          ]);
        },
      );

  Widget _nav() {
    Widget item(IconData i, String l, int idx) => Expanded(
          child: InkWell(
            onTap: () => _setTab(idx),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(i, color: _tab == idx ? kPurple : Colors.white54),
                const SizedBox(height: 2),
                Text(l,
                    style: TextStyle(
                        fontSize: 12, color: _tab == idx ? kPurple : Colors.white54)),
              ]),
            ),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
          color: kBg, border: Border(top: BorderSide(color: Color(0xFF1C1D26)))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(children: [
          item(Icons.chat_bubble, 'Messages', 0),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _plusMenu,
                child: Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 30),
                ),
              ),
            ),
          ),
          item(Icons.person, 'Profile', 1),
          ]),
        ),
      ),
    );
  }

  Widget _drawer() => Drawer(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon.png', width: 72)),
                const SizedBox(height: 12),
                const Text('Bitme',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(_me),
              subtitle: const Text('My username'),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: _rename,
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share app'),
              onTap: () {
                _sk.currentState?.closeEndDrawer();
                Share.share('Bitme: chat without internet, over Bluetooth or WiFi. Download: $kShareLink');
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.hub),
              title: const Text('Mesh relay'),
              subtitle: const Text('Bluetooth: auto-connect and pass messages through nearby phones'),
              value: _meshOn,
              onChanged: _setMesh,
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Update app'),
              onTap: _checkUpdate,
            ),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.pinkAccent),
              title: const Text('Donate'),
              onTap: () {
                _sk.currentState?.closeEndDrawer();
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DonateScreen()));
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Version 1.0.$kBuild',
                  style: const TextStyle(color: Colors.white38)),
            ),
          ]),
        ),
      );
}

// EOF
