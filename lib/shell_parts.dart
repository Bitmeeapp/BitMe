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
            SizedBox(
              height: 195,
              child: Stack(children: [
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
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(gradient: kGradient, shape: BoxShape.circle),
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                      child: GestureDetector(
                        onTap: _avatarMenu,
                        child: Stack(children: [
                          Avatar(name: _me, size: 84, image: _avatar),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                  color: kCard, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, size: 16),
                            ),
                          ),
                        ]),
                      )),
                ),
              ),
            ]),
            ),
            const SizedBox(height: 12),
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
          child: SingleChildScrollView(
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
              leading: Avatar(name: _me, size: 40, image: _avatar),
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Version 1.0.$kBuild',
                  style: const TextStyle(color: Colors.white38)),
            ),
            ]),
          ),
        ),
      );
}

// EOF
