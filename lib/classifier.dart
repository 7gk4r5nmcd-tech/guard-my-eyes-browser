import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

/// AI pemeriksa gambar. Model TensorFlow.js (sama dengan ekstensi laptop) dijalankan di WebView
/// tersembunyi yang memuat assets/classifier lewat server lokal di dalam aplikasi.
class Classifier {
  static const _port = 8765;
  static final _server = InAppLocalhostServer(documentRoot: 'assets/classifier', port: _port);

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  final _ready = Completer<void>();
  final _cache = LinkedHashMap<String, Map<String, dynamic>>();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  Future<void> start() async {
    if (!_server.isRunning()) await _server.start();
    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('http://localhost:$_port/index.html')),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true, isInspectable: true),
      onWebViewCreated: (c) => _controller = c,
      onLoadStop: (c, _) async {
        _controller = c;
        if (!_ready.isCompleted) _ready.complete();
      },
    );
    await _headless!.run();
  }

  /// Periksa gambar dari data URL. Hasil: {scores:{Porn,Hentai,Sexy,Neutral,Drawing}, faces:[...]}.
  Future<Map<String, dynamic>> classifyDataUrl(String dataUrl) async {
    await _ready.future.timeout(const Duration(seconds: 30));
    final res = await _controller!.callAsyncJavaScript(
      functionBody: 'while (!window.gwClassify) await new Promise(r => setTimeout(r, 100));'
          'return await window.gwClassify(d);',
      arguments: {'d': dataUrl},
    );
    if (res == null || res.error != null) return {'error': res?.error ?? 'no result'};
    final v = res.value;
    return v is Map ? Map<String, dynamic>.from(v) : {'error': 'bad result'};
  }

  /// Unduh gambar (dengan Referer halaman, supaya server tidak menolak), lalu periksa.
  Future<Map<String, dynamic>> classifyUrl(String url, String? referer) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': userAgent, if (referer != null) 'Referer': referer})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return {'error': 'HTTP ${resp.statusCode}'};
      var type = (resp.headers['content-type'] ?? '').split(';').first.trim();
      if (!type.startsWith('image/')) type = 'image/jpeg';
      if (resp.bodyBytes.length > 12 * 1024 * 1024) return {'skip': true};
      final result = await classifyDataUrl('data:$type;base64,${base64Encode(resp.bodyBytes)}');
      if (result['error'] == null) {
        _cache[url] = result;
        if (_cache.length > 600) _cache.remove(_cache.keys.first);
      }
      return result;
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
