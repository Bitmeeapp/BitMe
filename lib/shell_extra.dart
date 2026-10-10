part of 'shell.dart';

extension _ShellExtra on _ShellState {
  Future<void> _checkUpdate() async {
    _sk.currentState?.closeEndDrawer();
    _snack('Checking for updates...');
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await c
          .getUrl(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'));
      req.headers.set('User-Agent', 'BitMee');
      final res = await req.close();
      if (!mounted) return;
      if (res.statusCode == 404) {
        c.close();
        return _snack('No updates available yet');
      }
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      c.close();
      final n =
          int.tryParse((j['tag_name'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (!mounted) return;
      if (n <= kBuild) return _snack("You're on the latest version ✅");
      final assets = (j['assets'] as List?) ?? [];
      final url = assets.isNotEmpty
          ? assets.first['browser_download_url'] as String
          : j['html_url'] as String;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Update available'),
          content: Text('BitMee version 1.0.$n is available. Download it now?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download')),
          ],
        ),
      );
      if (go == true) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) _snack('Could not check for updates. Please check your internet.');
    }
  }

  Widget _tile(Peer p) {
    final last = (t.chats[p.key] ?? []).isEmpty ? null : t.chats[p.key]!.last;
    final un = t.unread[p.key] ?? 0;
    final sub = last != null
        ? '${last.mine ? 'You: ' : ''}${last.text}'
        : (p.id.startsWith('mesh:')
            ? 'Via mesh relay • say hi'
            : p.connected
                ? 'Connected • say hi'
                : 'Tap to connect');
    return InkWell(
      onTap: () => _open(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(
              name: p.name,
              image: t.avatarOf(p.name),
              online: p.connected && !p.id.startsWith('mesh:')),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: un > 0 ? Colors.lightBlueAccent : Colors.white60)),
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

  Widget _errorView() => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t.error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (t.needLocation)
              FilledButton.tonal(
                  onPressed: () => const AndroidIntent(
                          action: 'android.settings.LOCATION_SOURCE_SETTINGS')
                      .launch(),
                  child: const Text('Turn on Location')),
            if (t.needBluetooth)
              FilledButton.tonal(
                  onPressed: () => const AndroidIntent(
                          action: 'android.bluetooth.adapter.action.REQUEST_ENABLE')
                      .launch(),
                  child: const Text('Turn on Bluetooth')),
            if (t.needSettings) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                  onPressed: openAppSettings, child: const Text('Open app settings')),
            ],
            const SizedBox(height: 8),
            FilledButton(onPressed: _restart, child: const Text('Try again')),
          ])));
}

// EOF
