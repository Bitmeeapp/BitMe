import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const kPrivacyUrl = 'https://github.com/Bitmeeapp/BitMe/blob/main/PRIVACY.md';
const _updated = 'Last updated: 9 October 2026';

class _Sec {
  final String title;
  final List<String> body; // lines starting with "- " are bullets
  const _Sec(this.title, this.body);
}

const _sections = <_Sec>[
  _Sec(r'''1. Summary''', [
    r'''BitMee is a chat app that works without internet, over Bluetooth and WiFi. The BitMee developers do not run any servers, do not create accounts, and do not collect, store or sell your personal data. What you write stays on your phone and on the phones of the people you chat with.''',
  ]),
  _Sec(r'''2. What BitMee stores on your phone''', [
    r'''- Your username, bio, About text and profile picture (plus a small 64x64 copy of the picture).''',
    r'''- Your chats (up to the last 200 messages in each chat), their delivery/read status, the photos and videos you send or receive, the groups you joined, and your app settings.''',
    r'''This data is kept in BitMee's private storage on your phone. We cannot see it.''',
  ]),
  _Sec(r'''3. What is shared with other people''', [
    r'''When you connect or chat with someone nearby, BitMee sends the following directly to their phone:''',
    r'''- your username, bio, About text and the small profile picture;''',
    r'''- the messages you send, and delivery/read confirmations;''',
    r'''- the photos and videos you choose to send in a one-to-one chat;''',
    r'''- in WiFi mode: your username and the names of groups you joined are broadcast on the local WiFi network every few seconds so that others can find you;''',
    r'''- in Mesh relay mode: your username is announced to nearby phones, and messages may pass through other people's phones on their way to the receiver.''',
    r'''This is the purpose of the app. This data goes only to other devices, never to servers owned by us.''',
  ]),
  _Sec(r'''4. Security: please read''', [
    r'''- BitMee does not add its own end-to-end encryption. In WiFi mode, messages travel unencrypted over the local network, so other people on the same network may be able to capture them.''',
    r'''- In Mesh relay mode, the phones that pass your message along can read it.''',
    r'''- BitMee currently accepts connection requests from nearby BitMee users automatically, so anyone nearby who uses the app can connect to you and send you messages.''',
    r'''- Do not send passwords, bank details or other sensitive information.''',
  ]),
  _Sec(r'''5. Permissions''', [
    r'''- Bluetooth / Nearby devices: to find, connect and chat with phones near you.''',
    r'''- Location: Android requires this permission to discover nearby devices. BitMee does not collect, store or send your location.''',
    r'''- WiFi and network state: to find phones on the same WiFi network.''',
    r'''- Notifications: to alert you about new messages.''',
    r'''- Camera and photos: only the pictures and videos you take or choose to send in a chat, or use as your profile photo, through the system camera and picker. A photo or video is saved to your gallery only when you tap Save.''',
    r'''- Internet: used only when you tap "Update app", to check for and download updates from GitHub.''',
  ]),
  _Sec(r'''6. Features that use other services''', [
    r'''- Update app: contacts GitHub (api.github.com and github.com). GitHub may receive your IP address and device information as part of normal web requests, under GitHub's own privacy statement.''',
    r'''- Send SMS: opens your phone's SMS app with your text. BitMee does not send or read SMS itself. Your mobile carrier's terms and charges apply.''',
    r'''- Share app: uses Android's share menu.''',
    r'''- Nearby connections: BitMee uses Google's Nearby Connections technology (part of Google Play services), which is covered by Google's privacy policy.''',
    r'''- Donate: shows a QR code. Payments are made in your own payment app, not in BitMee.''',
  ]),
  _Sec(r'''7. No ads and no tracking''', [
    r'''BitMee has no advertising, analytics, crash-reporting or tracking tools.''',
  ]),
  _Sec(r'''8. Your choices and deleting your data''', [
    r'''- Open a chat, tap the three dots and choose "Clear chat" to delete it, including its photos and videos, from your phone.''',
    r'''- Press and hold a group in the Messages list to leave it.''',
    r'''- Change or remove your profile photo, bio and About in the Profile tab.''',
    r'''- Uninstalling BitMee, or going to Settings > Apps > BitMee > Storage > Clear data, removes everything BitMee stored on your phone.''',
    r'''Messages and profile details you already sent are saved on the other person's phone, and we cannot delete them from there.''',
  ]),
  _Sec(r'''9. Children''', [
    r'''BitMee is not meant for children under 13, and we do not knowingly collect information from children. Because anyone nearby can message you, parents should supervise younger users.''',
  ]),
  _Sec(r'''10. Changes to this policy''', [
    r'''We may update this policy. The latest version is always in the app (menu > Privacy policy) and online at https://github.com/Bitmeeapp/BitMe/blob/main/PRIVACY.md. The date at the top shows when it was last changed.''',
  ]),
  _Sec(r'''11. Contact''', [
    r'''Questions or requests: open an issue at https://github.com/Bitmeeapp/BitMe/issues''',
  ]),
];

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacy policy')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('BitMee Privacy Policy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(_updated, style: TextStyle(color: Colors.white54)),
          for (final s in _sections) ...[
            const SizedBox(height: 22),
            Text(s.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final line in s.body)
              line.startsWith('- ')
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('\u2022  '),
                        Expanded(
                            child: Text(line.substring(2),
                                style: const TextStyle(height: 1.4, color: Colors.white70))),
                      ]))
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(line,
                          style: const TextStyle(height: 1.4, color: Colors.white70))),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse(kPrivacyUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open online version'),
          ),
          const SizedBox(height: 16),
        ]),
      );
}

// EOF
