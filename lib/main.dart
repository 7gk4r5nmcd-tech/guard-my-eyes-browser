import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'classifier.dart';
import 'guard.dart';
import 'settings.dart';
import 'settings_page.dart';

const homeUrl = 'https://www.google.com/?safe=active';
const bg = Color(0xFF323437);
const fg = Color(0xFFD1D0C5);
const accent = Color(0xFFE2B714);

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
        colorScheme: const ColorScheme.dark(primary: accent, surface: Color(0xFF2C2E31)),
        useMaterial3: true,
      ),
      home: BrowserPage(guard: guard),
    );
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.guard});
  final Guard guard;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _web;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  double _progress = 0;
  bool _canBack = false, _canForward = false;
  UserScript? _script;

  @override
  void initState() {
    super.initState();
    widget.guard.userScript().then((s) => setState(() => _script = s));
  }

  void _go(String input) {
    var text = input.trim();
    if (text.isEmpty) return;
    final looksLikeUrl = !text.contains(' ') && (text.contains('.') || text.startsWith('http'));
    final url = looksLikeUrl
        ? (text.startsWith('http://') || text.startsWith('https://') ? text : 'https://$text')
        : 'https://www.google.com/search?safe=active&q=${Uri.encodeQueryComponent(text)}';
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    _addressFocus.unfocus();
  }

  Future<void> _updateNav() async {
    final c = _web;
    if (c == null) return;
    final back = await c.canGoBack(), fwd = await c.canGoForward();
    if (mounted) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsPage(settings: widget.guard.settings)),
    );
    if (changed == true && _web != null) {
      final s = await widget.guard.userScript();
      await _web!.removeAllUserScripts();
      await _web!.addUserScript(userScript: s);
      await _web!.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && _web != null && await _web!.canGoBack()) await _web!.goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _toolbar(),
              if (_progress < 1) LinearProgressIndicator(value: _progress, minHeight: 2, color: accent),
              Expanded(child: _script == null ? const SizedBox() : _webView()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: const Color(0xFF2C2E31),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _canBack ? () => _web?.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canForward ? () => _web?.goForward() : null,
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _web?.reload()),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'home') _go(homeUrl);
              if (v == 'settings') _openSettings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'home', child: Text('Beranda')),
              PopupMenuItem(value: 'settings', child: Text('Pengaturan')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(homeUrl)),
      initialUserScripts: UnmodifiableListView([_script!]),
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
      ),
      onWebViewCreated: (c) {
        _web = c;
        widget.guard.attach(c, onFinished: () => c.loadUrl(urlRequest: URLRequest(url: WebUri(homeUrl))));
      },
      onLoadStart: (c, url) {
        if (!_addressFocus.hasFocus) _address.text = url?.toString() ?? '';
      },
      onLoadStop: (c, url) {
        if (!_addressFocus.hasFocus) _address.text = url?.toString() ?? '';
        _updateNav();
      },
      onUpdateVisitedHistory: (c, url, _) {
        if (!_addressFocus.hasFocus) _address.text = url?.toString() ?? '';
        _updateNav();
      },
      onProgressChanged: (c, p) => setState(() => _progress = p / 100),
      // Link "buka di tab baru" dibuka di halaman yang sama (popup iklan diabaikan).
      onCreateWindow: (c, action) async {
        final url = action.request.url;
        if (url != null && action.isDialog != true) await c.loadUrl(urlRequest: URLRequest(url: url));
        return false;
      },
      // Jangan biarkan halaman membuka aplikasi lain (intent://, itms:// dll.).
      shouldOverrideUrlLoading: (c, action) async {
        final scheme = action.request.url?.scheme ?? '';
        const allowed = {'http', 'https', 'about', 'data', 'blob', 'javascript'};
        return allowed.contains(scheme) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
      },
    );
  }
}
