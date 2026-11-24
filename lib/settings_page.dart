import 'package:flutter/material.dart';

import 'pin.dart';
import 'settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});
  final Settings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const switches = <String, String>{
    'blockPornSites': 'Situs porno (berdasarkan nama situs)',
    'detectPorn': 'Konten porno / hentai (AI)',
    'detectSexy': 'Konten seksi / sugestif (AI)',
    'detectFemaleFace': 'Wajah wanita (AI)',
    'blockByTitle': 'Judul, alamat & label halaman berisi kata porno',
    'scanPageMenu': 'Situs yang menunya punya kategori porno',
    'detectGaming': 'Video game (YouTube & situs game)',
    'checkVideos': 'Periksa video',
    'blurUntilChecked': 'Blur gambar sampai lolos pemeriksaan',
    'holdPage': 'Tunda halaman sampai gambar pertama diperiksa',
    'blurUnreadableVideos': 'Gambar/video yang tidak bisa diperiksa tetap di-blur',
    'screenScan': 'Pemindaian layar (AI memeriksa tampilan layar setiap beberapa detik)',
  };

  static const texts = <String, String>{
    'commitmentText': 'Tahap 1 – Komitmen',
    'prayerText': 'Tahap 2 – Doa',
    'pornSites': 'Situs porno (satu domain per baris)',
    'pornDomainKeywords': 'Kata di nama situs (satu per baris)',
    'pornTitleKeywords': 'Kata di judul/alamat halaman (satu per baris)',
    'gamingKeywords': 'Kata kunci judul video game (satu per baris)',
    'gamingSites': 'Situs game (satu domain per baris)',
    'whitelist': 'Situs yang dikecualikan (satu domain per baris)',
  };

  late final Map<String, TextEditingController> _ctl = {
    for (final k in texts.keys) k: TextEditingController(text: '${widget.settings[k] ?? ''}'),
  };
  bool _changed = false;

  Future<void> _save() async {
    for (final e in _ctl.entries) {
      widget.settings.set(e.key, e.value.text);
    }
    await widget.settings.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pengaturan'),
          actions: [TextButton(onPressed: _save, child: const Text('Simpan'))],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            for (final e in switches.entries)
              SwitchListTile(
                title: Text(e.value),
                value: widget.settings[e.key] == true,
                onChanged: (v) => setState(() {
                  widget.settings.set(e.key, v);
                  _changed = true;
                }),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('PIN Pengaturan'),
              subtitle: const Text('Supaya filter tidak bisa dimatikan sendiri. Sebaiknya dibuat oleh orang yang dipercaya.'),
              onTap: () async {
                final pin = await Pin.ask(context, 'PIN baru (kosongkan untuk menghapus)');
                if (pin == null) return;
                if (pin.isNotEmpty && pin.length < 4) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN minimal 4 angka.')));
                  }
                  return;
                }
                if (pin.isNotEmpty) {
                  if (!context.mounted) return;
                  final again = await Pin.ask(context, 'Ulangi PIN');
                  if (again != pin) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN tidak sama.')));
                    }
                    return;
                  }
                }
                await Pin.set(pin);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(pin.isEmpty ? 'PIN dihapus.' : 'PIN disimpan.')));
                }
              },
            ),
            const Divider(),
            for (final e in texts.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _ctl[e.key],
                  minLines: 2,
                  maxLines: 8,
                  onChanged: (_) => _changed = true,
                  decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () async {
                  await widget.settings.reset();
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                child: const Text('Kembalikan bawaan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
