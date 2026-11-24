import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN Pengaturan: supaya filter tidak bisa dimatikan sendiri saat tergoda.
/// Sebaiknya PIN dibuat & disimpan oleh orang yang dipercaya.
class Pin {
  static const _key = 'gw_pin_hash';
  static const _salt = 'guard-my-eyes:v1:';

  static String _hash(String pin) => sha256.convert(utf8.encode('$_salt$pin')).toString();

  static Future<bool> isSet() async => (await SharedPreferences.getInstance()).getString(_key) != null;

  static Future<void> set(String? pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (pin == null || pin.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, _hash(pin));
    }
  }

  static Future<bool> check(String pin) async =>
      (await SharedPreferences.getInstance()).getString(_key) == _hash(pin);

  /// Minta PIN bila sudah diatur. true = boleh lanjut.
  static Future<bool> verify(BuildContext context) async {
    if (!await isSet()) return true;
    if (!context.mounted) return false;
    final pin = await ask(context, 'Masukkan PIN Pengaturan');
    if (pin == null) return false;
    // Jeda kecil memperlambat tebak-tebakan PIN.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final ok = await check(pin);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN salah.')));
    }
    return ok;
  }

  static Future<String?> ask(BuildContext context, String title) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
          decoration: const InputDecoration(hintText: '4–12 angka'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
  }
}
