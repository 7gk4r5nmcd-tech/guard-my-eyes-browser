import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'classifier.dart';
import 'guard.dart';
import 'lock_screen.dart';
import 'pin.dart';
import 'settings.dart';
import 'settings_page.dart';

const homeUrl = 'https://www.google.com/?safe=active';
const bg = Color(0xFF323437);
const panel = Color(0xFF2C2E31);
const fg = Color(0xFFD1D0C5);
const accent = Color(0xFFE2B714);
const maxTabs = 10;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final classifier = Classifier();
  await classifier.start();
  final guard = Guard(classifier, settings);
  await guard.init();
  runApp(GuardApp(guard: guard));
}

class GuardApp extends StatelessWidget {
  const GuardApp({super.key, required this.guard});
  final Guard guard;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guard My Eyes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(primary: accent, surface: panel),
        useMaterial3: true,
      ),
      home: BrowserPage(guard: guard),
    );
  }
}

class BrowserTab {
  BrowserTab(this.id, this.initialUrl);
  final int id;
  final String initialUrl;
  InAppWebViewController? c;
  String url = '';
  String title = '';
  double progress = 0;
  bool canBack = false;
  String? lockReason;
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.guard});
  final Guard guard;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  final _tabs = <BrowserTab>[];
  int _current = 0;
  int _nextId = 1;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  Timer? _scanTimer;
  bool _scanning = false;
  bool _foreground = true;

  Guard get guard => widget.guard;
  BrowserTab get tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newTab(homeUrl);
    _restartScan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  // ---------- Tab ----------

  void _newTab(String url) {
    if (_tabs.length >= maxTabs) {
      _toast('Maksimal $maxTabs tab. Tutup salah satu dulu.');
      return;
    }
    setState(() {
      _tabs.add(BrowserTab(_nextId++, url));
      _current = _tabs.length - 1;
      _address.text = url;
    });
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _tabs.add(BrowserTab(_nextId++, homeUrl));
        _current = 0;
      } else if (_current >= _tabs.length) {
        _current = _tabs.length - 1;
      } else if (index < _current) {
        _current--;
      }
      _address.text = tab.url;
    });
  }

  void _switchTo(int index) {
    setState(() {
      _current = index;
      _address.text = tab.url;
    });
  }

  // ---------- Navigasi ----------

  void _go(String input) {
    final text = input.trim();
    if (text.isEmpty) return;
    final looksLikeUrl = !text.contains(' ') && (text.contains('.') || text.startsWith('http'));
    final url = looksLikeUrl
        ? (text.startsWith('http://') || text.startsWith('https://') ? text : 'https://$text')
        : 'https://www.google.com/search?safe=active&q=${Uri.encodeQueryComponent(text)}';
    tab.c?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    _addressFocus.unfocus();
  }

  // ---------- Penguncian (native) ----------

  /// Kunci tab: hentikan halaman, simpan alamat sebagai "pernah terdeteksi", tampilkan layar native.
  void _lock(BrowserTab t, String reason) {
    if (t.lockReason != null) return;
    final url = t.url;
    setState(() => t.lockReason = reason);
    guard.addFlag(url);
    // Tampilkan sampul di halaman dulu (seketika), lalu hentikan halaman sepenuhnya.
    t.c?.evaluateJavascript(
        source: 'window.__gwDispatch && window.__gwDispatch({type:"lock", reason:${jsonEncode(reason)}});');
    t.c?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
  }

  void _unlock(BrowserTab t) {
    setState(() => t.lockReason = null);
    t.c?.loadUrl(urlRequest: URLRequest(url: WebUri(homeUrl)));
  }

  /// Pemeriksaan alamat/judul di sisi aplikasi (tidak bisa diakali skrip situs).
  void _checkPage(BrowserTab t, WebUri? url) {
    if (url == null || t.lockReason != null) return;
    final s = url.toString();
    if (guard.isFlagged(s)) return _lock(t, 'halaman yang sebelumnya sudah terdeteksi');
    final reason = guard.rules.checkPage(Uri.tryParse(s), t.title);
    if (reason != null) _lock(t, reason);
  }

  // ---------- Pemindaian layar ----------
  // Memotret tampilan browser secara berkala dan memeriksanya dengan AI. Ini menangkap apa pun
  // yang benar-benar terlihat di layar, termasuk yang lolos dari skrip (kanvas, video lintas domain,
  // trik CSS, dll.).

  void _restartScan() {
    _scanTimer?.cancel();
    if (guard.settings['screenScan'] == false) return;
    final secs = guard.settings['screenScanSeconds'];
    final period = Duration(milliseconds: ((secs is num ? secs.toDouble() : 3.0) * 1000).round().clamp(1500, 30000));
    _scanTimer = Timer.periodic(period, (_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || !_foreground || _tabs.isEmpty) return;
    final t = tab;
    final c = t.c;
    if (c == null || t.lockReason != null || !t.url.startsWith('http')) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _scanning = true;
    try {
      final shot = await c.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.JPEG, quality: 55),
      );
      if (shot == null || t.lockReason != null) return;
      final r = await guard.classifier.classifyDataUrl('data:image/jpeg;base64,${base64Encode(shot)}');
      if (r['error'] != null || r['skip'] == true) return;
      final reason = guard.rules.evaluate(r);
      if (reason != null && mounted && t.c == c && !guard.rules.isWhitelisted(Uri.tryParse(t.url)?.host ?? '')) {
        _lock(t, '$reason (pemindaian layar)');
      }
    } catch (_) {
      // Pemindaian gagal sesekali (mis. halaman sedang berganti) -> coba lagi di putaran berikutnya.
    } finally {
      _scanning = false;
    }
  }

  // ---------- Pengaturan ----------

  Future<void> _openSettings() async {
    if (!await Pin.verify(context)) return;
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsPage(settings: guard.settings)),
    );
    if (changed == true) {
      final s = guard.userScript();
      for (final t in _tabs) {
        await t.c?.removeAllUserScripts();
        await t.c?.addUserScript(userScript: s);
        await t.c?.reload();
      }
      _restartScan();
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    final locked = _tabs.isNotEmpty && tab.lockReason != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || locked) return;
        if (await tab.c?.canGoBack() ?? false) await tab.c?.goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _toolbar(),
                  if (tab.progress < 1) LinearProgressIndicator(value: tab.progress, minHeight: 2, color: accent),
                  Expanded(
                    child: IndexedStack(
                      index: _current,
                      children: [for (final t in _tabs) _webView(t)],
                    ),
                  ),
                ],
              ),
              if (locked)
                Positioned.fill(
                  child: LockScreen(
                    key: ValueKey('lock-${tab.id}'),
                    reason: tab.lockReason!,
                    stages: [
                      ('Tulis komitmenmu', '${guard.settings['commitmentText'] ?? ''}'.trim()),
                      ('Doa Salam Maria', '${guard.settings['prayerText'] ?? ''}'.trim()),
                    ].where((s) => s.$2.isNotEmpty).toList(),
                    onFinished: () => _unlock(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: panel,
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: tab.canBack ? () => tab.c?.goBack() : null,
          ),
          Expanded(
            child: TextField(
              controller: _address,
              focusNode: _addressFocus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              style: const TextStyle(fontSize: 14, color: fg),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari atau ketik alamat',
                filled: true,
                fillColor: bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onTap: () => _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length),
              onSubmitted: _go,
            ),
          ),
          // Tombol jumlah tab
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _showTabs,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: fg, width: 1.6), borderRadius: BorderRadius.circular(6)),
              child: Text('${_tabs.length}', style: const TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w600)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'new':
                  _newTab(homeUrl);
                case 'reload':
                  tab.c?.reload();
                case 'forward':
                  tab.c?.goForward();
                case 'home':
                  _go(homeUrl);
                case 'settings':
                  _openSettings();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('Tab baru')),
              PopupMenuItem(value: 'reload', child: Text('Muat ulang')),
              PopupMenuItem(value: 'forward', child: Text('Maju')),
              PopupMenuItem(value: 'home', child: Text('Beranda')),
              PopupMenuItem(value: 'settings', child: Text('Pengaturan')),
            ],
          ),
        ],
      ),
    );
  }

  void _showTabs() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('${_tabs.length} tab', style: const TextStyle(color: accent)),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Tab baru'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _newTab(homeUrl);
                    },
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _tabs.length,
                    itemBuilder: (_, i) {
                      final t = _tabs[i];
                      final host = Uri.tryParse(t.url)?.host ?? '';
                      return ListTile(
                        selected: i == _current,
                        selectedTileColor: bg,
                        leading: Icon(t.lockReason != null ? Icons.lock : Icons.public, color: fg),
                        title: Text(t.lockReason != null ? 'Terkunci' : (t.title.isEmpty ? host : t.title),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(ctx);
                          _switchTo(i);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          // Tab terkunci tidak bisa ditutup begitu saja: selesaikan doanya dulu.
                          onPressed: t.lockReason != null
                              ? null
                              : () {
                                  _closeTab(i);
                                  setSheet(() {});
                                },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _webView(BrowserTab t) {
    return InAppWebView(
      key: ValueKey('tab-${t.id}'),
      initialUrlRequest: URLRequest(url: WebUri(t.initialUrl)),
      initialUserScripts: UnmodifiableListView([guard.userScript()]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsBackForwardNavigationGestures: true,
        isFraudulentWebsiteWarningEnabled: true,
        safeBrowsingEnabled: true,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        geolocationEnabled: false,
        thirdPartyCookiesEnabled: false,
        useOnDownloadStart: true,
      ),
      onWebViewCreated: (c) {
        t.c = c;
        guard.attach(c, onLock: (reason) => _lock(t, reason));
      },
      onLoadStart: (c, url) {
        t.url = url?.toString() ?? '';
        t.title = '';
        if (t == tab && !_addressFocus.hasFocus) _address.text = t.url;
        _checkPage(t, url);
      },
      onTitleChanged: (c, title) {
        t.title = title ?? '';
        _checkPage(t, WebUri(t.url));
        setState(() {});
      },
      onLoadStop: (c, url) async {
        t.url = url?.toString() ?? t.url;
        if (t == tab && !_addressFocus.hasFocus) _address.text = t.url;
        t.canBack = await c.canGoBack();
        if (mounted) setState(() {});
      },
      onUpdateVisitedHistory: (c, url, _) async {
        t.url = url?.toString() ?? t.url;
        if (t == tab && !_addressFocus.hasFocus) _address.text = t.url;
        _checkPage(t, url);
        t.canBack = await c.canGoBack();
        if (mounted) setState(() {});
      },
      onProgressChanged: (c, p) {
        t.progress = p / 100;
        if (t == tab) setState(() {});
      },
      // "Buka di tab baru" -> tab baru sungguhan.
      onCreateWindow: (c, action) async {
        final url = action.request.url;
        if (url != null && (url.scheme == 'http' || url.scheme == 'https')) _newTab(url.toString());
        return false;
      },
      // Hanya http/https. Situs tidak boleh membuka aplikasi lain (intent://, itms://, tel:, dll.),
      // file lokal (file://), atau halaman data: di tab utama (sering dipakai penipuan).
      shouldOverrideUrlLoading: (c, action) async {
        final scheme = action.request.url?.scheme ?? '';
        if (scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'blob') {
          return NavigationActionPolicy.ALLOW;
        }
        if (scheme == 'data' && action.isForMainFrame == false) return NavigationActionPolicy.ALLOW;
        return NavigationActionPolicy.CANCEL;
      },
      // Unduhan file sengaja tidak didukung: tidak ada file yang tersimpan ke HP.
      onDownloadStartRequest: (c, request) => _toast('Unduhan file dinonaktifkan di browser ini.'),
      onPermissionRequest: (c, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
    );
  }
}
