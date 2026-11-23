import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'classifier.dart';
import 'settings.dart';

/// Jembatan antara skrip Guard My Eyes di halaman (assets/gw/content.js) dan aplikasi.
/// Menjawab pesan yang di ekstensi laptop dijawab oleh background.js.
class Guard {
  Guard(this.classifier, this.settings);

  final Classifier classifier;
  Settings settings;
  final Set<String> _flagged = {};
  final Map<String, Map<String, dynamic>> _yt = {};
  String? _script;

  static const _flaggedKey = 'gw_flagged';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _flagged.addAll(prefs.getStringList(_flaggedKey) ?? const []);
  }

  /// Skrip yang disuntikkan ke setiap halaman & iframe sejak awal dimuat.
  Future<UserScript> userScript() async {
    _script ??= '${await rootBundle.loadString('assets/gw/shadow-hook.js')}\n'
        '${await rootBundle.loadString('assets/gw/content.js')}';
    final settingsJs = 'window.__gwSettings = ${jsonEncode(settings.merged)};';
    return UserScript(
      source: '$settingsJs\n$_script',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
  }

  void attach(InAppWebViewController c, {required void Function() onFinished}) {
    c.addJavaScriptHandler(
      handlerName: 'gw',
      callback: (args) async {
        if (args.isEmpty || args.first is! Map) return {'error': 'bad message'};
        final msg = Map<String, dynamic>.from(args.first as Map);
        return _handle(c, msg, onFinished);
      },
    );
  }

  Future<dynamic> _handle(InAppWebViewController c, Map<String, dynamic> msg, void Function() onFinished) async {
    switch (msg['type']) {
      case 'classify':
        final dataUrl = msg['dataUrl'] as String?;
        if (dataUrl != null) return classifier.classifyDataUrl(dataUrl);
        final url = msg['url'] as String?;
        if (url == null) return {'error': 'no url'};
        final page = (await c.getUrl())?.toString();
        return classifier.classifyUrl(url, page);

      case 'classifyVideo':
        // Video dari server lain belum bisa diperiksa di HP -> skrip akan membiarkannya ter-blur.
        return {'error': 'unsupported'};

      case 'flag':
        final page = (await c.getUrl())?.toString();
        if (page != null && _flagged.add(page)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(_flaggedKey, _flagged.toList().reversed.take(300).toList());
        }
        await c.evaluateJavascript(
          source: 'window.__gwDispatch && window.__gwDispatch({type:"lock", reason:${jsonEncode(msg['reason'] ?? 'konten terlarang')}});',
        );
        return {'ok': true};

      case 'isFlagged':
        return {'flagged': _flagged.contains(msg['url'])};

      case 'ytInfo':
        return _ytInfo(msg['id'] as String? ?? '');

      case 'finished':
        onFinished();
        return {'ok': true};
    }
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
