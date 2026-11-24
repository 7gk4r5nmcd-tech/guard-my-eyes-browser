import 'settings.dart';

/// Aturan yang sama dengan ekstensi laptop, tapi dijalankan di sisi aplikasi (Dart),
/// sehingga tidak bisa diakali oleh skrip di halaman web.
class Rules {
  Rules(this.s);
  final Settings s;

  static List<String> _lines(dynamic v) => '${v ?? ''}'
      .split('\n')
      .map((x) => x.trim().toLowerCase())
      .where((x) => x.isNotEmpty)
      .toList();

  static bool _onList(String host, dynamic list) {
    host = host.toLowerCase();
    for (var d in _lines(list)) {
      if (d.startsWith('*.')) d = d.substring(2);
      if (host == d || host.endsWith('.$d')) return true;
    }
    return false;
  }

  /// Kata utuh (bukan bagian kata lain), mendukung huruf non-Latin.
  static String? matchKeyword(String text, dynamic keywords) {
    final t = ' ${text.toLowerCase()} ';
    for (final k in _lines(keywords)) {
      final re = RegExp('(^|[^\\p{L}\\p{N}])${RegExp.escape(k)}(\$|[^\\p{L}\\p{N}])', unicode: true);
      if (re.hasMatch(t)) return k;
    }
    return null;
  }

  bool isWhitelisted(String host) => _onList(host, s['whitelist']);

  bool isPornHost(String host) {
    if (s['blockPornSites'] != true || host.isEmpty) return false;
    host = host.toLowerCase();
    if (_onList(host, s['pornSites'])) return true;
    final cleaned = host.replaceAll(RegExp(r'(es|sus|middle|wes)sex|sextant|sexton|sextet|sexagesim'), '');
    return _lines(s['pornDomainKeywords']).any(cleaned.contains);
  }

  /// Pemeriksaan alamat & judul halaman. Mengembalikan alasan bila harus dikunci.
  String? checkPage(Uri? uri, String? title) {
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    final host = uri.host.toLowerCase();
    if (isWhitelisted(host)) return null;
    if (isPornHost(host)) return 'situs porno';
    if (s['detectGaming'] == true && _onList(host, s['gamingSites'])) return 'situs streaming game';
    if (s['blockByTitle'] == true) {
      var path = '${uri.path} ${uri.query}';
      try {
        path = Uri.decodeComponent(path);
      } catch (_) {}
      final text = '${title ?? ''} ${path.replaceAll(RegExp(r'[-_/+.=&?]+'), ' ')}';
      final kw = matchKeyword(text, s['pornTitleKeywords']);
      if (kw != null) return 'judul/alamat halaman berisi "$kw"';
    }
    return null;
  }

  double _num(String k, double d) {
    final v = s[k];
    return v is num ? v.toDouble() : d;
  }

  /// Penilaian hasil AI (sama dengan ekstensi).
  String? evaluate(Map<String, dynamic> r) {
    final scores = Map<String, dynamic>.from((r['scores'] as Map?) ?? const {});
    double sc(String k) => (scores[k] is num) ? (scores[k] as num).toDouble() : 0;
    final porn = sc('Porn'), hentai = sc('Hentai'), sexy = sc('Sexy');
    if (s['detectPorn'] == true) {
      if (hentai >= _num('hentaiThreshold', 0.35)) return 'konten hentai';
      final pt = _num('pornThreshold', 0.6);
      if (porn >= pt || porn + hentai >= pt) return 'konten porno';
    }
    if (s['detectSexy'] == true && sexy >= _num('sexyThreshold', 0.75)) return 'konten seksi / sugestif';
    if (s['detectFemaleFace'] == true) {
      final minFace = _num('minFaceSize', 40);
      final thr = _num('femaleThreshold', 0.75);
      for (final f in (r['faces'] as List? ?? const [])) {
        if (f is! Map) continue;
        final p = (f['p'] is num) ? (f['p'] as num).toDouble() : 0.0;
        final w = (f['w'] is num) ? (f['w'] as num).toDouble() : 0.0;
        final h = (f['h'] is num) ? (f['h'] as num).toDouble() : 0.0;
        if (f['gender'] == 'female' && p >= thr && (w < h ? w : h) >= minFace) return 'wajah wanita';
      }
    }
    return null;
  }
}
