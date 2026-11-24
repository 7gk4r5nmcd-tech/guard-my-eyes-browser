import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'classifier.dart';
import 'rules.dart';
import 'settings.dart';

/// Jembatan antara skrip Guard My Eyes di halaman (assets/gw/content.js) dan aplikasi.
///
/// Catatan keamanan: pesan dari halaman TIDAK dipercaya. Situs bisa memanggil
/// callHandler('gw', ...) sendiri, jadi:
///  - unduhan gambar hanya ke internet publik (NetGuard),
///  - pesan dari halaman hanya bisa MENGUNCI, tidak pernah membuka kunci,
///  - kunci yang sebenarnya adalah layar native aplikasi.
class Guard {
  Guard(this.classifier, this.settings) : rules = Rules(settings);

  final Classifier classifier;
  final Settings settings;
  final Rules rules;
  final List<String> _flagged = [];
  final Map<String, Map<String, dynamic>> _yt = {};
  String? _shadowHook, _content;

  static const _flaggedKey = 'gw_flagged';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _flagged.addAll(prefs.getStringList(_flaggedKey) ?? const []);
    _shadowHook = await rootBundle.loadString('assets/gw/shadow-hook.js');
    _content = await rootBundle.loadString('assets/gw/content.js');
  }

  bool isFlagged(String? url) => url != null && _flagged.contains(url);

  Future<void> addFlag(String? url) async {
    if (url == null || !url.startsWith('http') || _flagged.contains(url)) return;
    _flagged.add(url);
    if (_flagged.length > 300) _flagged.removeAt(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_flaggedKey, _flagged);
  }

  /// Skrip yang disuntikkan ke setiap halaman & iframe sejak awal dimuat.
  UserScript userScript() {
    final settingsJs = 'window.__gwSettings = ${jsonEncode(settings.merged)};';
    return UserScript(
      source: '$settingsJs\n$_shadowHook\n$_content',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
  }

  /// [onLock] dipanggil saat skrip halaman menemukan konten terlarang.
  void attach(InAppWebViewController c, {required void Function(String reason) onLock}) {
    c.addJavaScriptHandler(
      handlerName: 'gw',
      callback: (args) async {
        if (args.isEmpty || args.first is! Map) return {'error': 'bad message'};
        final msg = Map<String, dynamic>.from(args.first as Map);
        return _handle(c, msg, onLock);
      },
    );
  }

  Future<dynamic> _handle(InAppWebViewController c, Map<String, dynamic> msg, void Function(String) onLock) async {
    switch (msg['type']) {
      case 'classify':
        final dataUrl = msg['dataUrl'];
        if (dataUrl is String) {
          if (!dataUrl.startsWith('data:image/') || dataUrl.length > 16 * 1024 * 1024) return {'skip': true};
          return classifier.classifyDataUrl(dataUrl);
        }
        final url = msg['url'];
        if (url is! String) return {'error': 'no url'};
        final page = (await c.getUrl())?.toString();
        return classifier.classifyUrl(url, page);

      case 'classifyVideo':
        // Video dari server lain belum bisa diperiksa di HP -> tetap ter-blur.
        // (Pemindaian layar native tetap memeriksa apa pun yang tampil.)
        return {'error': 'unsupported'};

      case 'flag':
        final reason = '${msg['reason'] ?? 'konten terlarang'}';
        onLock(reason.length > 120 ? reason.substring(0, 120) : reason);
        return {'ok': true};

      case 'isFlagged':
        return {'flagged': isFlagged(msg['url'] as String?)};

      case 'ytInfo':
        return _ytInfo('${msg['id'] ?? ''}');
    }
    // 'finished' dan pesan lain dari halaman diabaikan: hanya layar native yang bisa membuka kunci.
    return {'error': 'unknown message'};
  }

  Future<Map<String, dynamic>> _ytInfo(String id) async {
    if (!RegExp(r'^[\w-]{11}$').hasMatch(id)) return {'error': 'id'};
    final cached = _yt[id];
    if (cached != null) return cached;
    try {
      final resp = await http.get(Uri.parse('https://www.youtube.com/watch?v=$id&hl=en'),
          headers: {'User-Agent': Classifier.userAgent}).timeout(const Duration(seconds: 15));
      final html = resp.body;
      String pick(RegExp re) => re.firstMatch(html)?.group(1) ?? '';
      String decode(String s) {
        try {
          return jsonDecode('"$s"') as String;
        } catch (_) {
          return s;
        }
      }

      final info = {
        'category': decode(pick(RegExp(r'"category":"((?:[^"\\]|\\.)*)"'))),
        'title': decode(pick(RegExp(r'"videoDetails":\{[^}]*?"title":"((?:[^"\\]|\\.)*)"'))),
        'channel': decode(pick(RegExp(r'"ownerChannelName":"((?:[^"\\]|\\.)*)"'))),
      };
      _yt[id] = info;
      return info;
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
