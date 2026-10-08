import 'package:flutter/material.dart';

// ---------------------------------------------------------------- config
const kBuild = int.fromEnvironment('BUILD', defaultValue: 0);
const kRepo = 'Bitmeeapp/BitMe'; // GitHub repo (used for update check + share link)
const kShareLink = 'https://github.com/$kRepo';

const kBg = Color(0xFF07070D);
const kCard = Color(0xFF16171F);
const kBubble = Color(0xFF1E2029);
const kBlue = Color(0xFF2E6BFF);
const kPurple = Color(0xFF9B3BFF);
const kGreen = Color(0xFF19C37D);
const kGradient = LinearGradient(
    colors: [kBlue, kPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight);

// ---------------------------------------------------------------- helpers

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

Future<String?> askText(BuildContext c, String title,
    {String initial = '', String hint = '', String ok = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const GradientButton({super.key, required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        decoration: BoxDecoration(
            gradient: kGradient, borderRadius: BorderRadius.circular(27)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(27),
            onTap: onTap,
            child: Center(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))),
          ),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool online;
  const Avatar({super.key, required this.name, this.size = 52, this.online = false});

  static const _cols = [
    Color(0xFF2E6BFF),
    Color(0xFF9B3BFF),
    Color(0xFFE040A0),
    Color(0xFF00A884),
    Color(0xFFFF8A3D),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final c = _cols[seed % _cols.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [c, c.withValues(alpha: .6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.bold)),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * .26,
              height: size * .26,
              decoration: BoxDecoration(
                  color: kGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: kBg, width: 2)),
            ),
          ),
      ]),
    );
  }
}

class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Donate')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Text('Bitme is free ❤️',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('If you like the app, you can support it.\nScan the QR code to donate.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(16)),
                // To change the QR, replace assets/donate_qr.png (same file name)
                child: Image.asset('assets/donate_qr.png',
                    width: 260,
                    height: 260,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 260,
                        height: 260,
                        child: Center(
                            child: Text('QR coming soon',
                                style: TextStyle(color: Colors.black))))),
              ),
              const SizedBox(height: 16),
              const Text('Thank you 🙏'),
            ]),
          ),
        ),
      );
}

// EOF
