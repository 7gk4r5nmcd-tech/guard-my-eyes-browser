import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Melindungi dari "SSRF": situs web menyuruh aplikasi mengakses alamat di jaringan lokal
/// (router, printer, dll.). Aplikasi hanya boleh mengunduh gambar dari internet publik.
class NetGuard {
  static bool _privateV4(List<int> b) {
    final a = b[0], c = b[1];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 100 && c >= 64 && c <= 127) || // CGNAT 100.64.0.0/10
        (a == 169 && c == 254) || // link-local
        (a == 172 && c >= 16 && c <= 31) ||
        (a == 192 && c == 168) ||
        (a == 192 && c == 0 && b[2] == 0) ||
        (a == 198 && (c == 18 || c == 19)) ||
        a >= 224; // multicast & reserved
  }

  static bool _privateAddress(InternetAddress addr) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
    final b = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4) return _privateV4(b);
    if (b.length == 16) {
      if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique local
      if (b.every((x) => x == 0)) return true; // ::
      // IPv4-mapped ::ffff:a.b.c.d
      final mapped = b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
      if (mapped) return _privateV4(b.sublist(12));
    }
    return false;
  }

  /// true bila alamat aman untuk diunduh (http/https ke host publik).
  static Future<bool> isPublic(Uri uri) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host.endsWith('.home.arpa')) {
      return false;
    }
    final literal = InternetAddress.tryParse(host.replaceAll('[', '').replaceAll(']', ''));
    if (literal != null) return !_privateAddress(literal);
    try {
      final addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      if (addrs.isEmpty) return false;
      return !addrs.any(_privateAddress);
    } catch (_) {
      return false;
    }
  }

  /// GET dengan pemeriksaan di setiap pengalihan (redirect), maks. 4 kali, maks. [maxBytes].
  static Future<({int status, String contentType, Uint8List bytes})?> get(
    Uri uri, {
    Map<String, String> headers = const {},
    int maxBytes = 12 * 1024 * 1024,
  }) async {
    final client = http.Client();
    try {
      var current = uri;
      for (var hop = 0; hop < 5; hop++) {
        if (!await isPublic(current)) return null;
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(headers);
        final resp = await client.send(req).timeout(const Duration(seconds: 15));
        if (resp.isRedirect || (resp.statusCode >= 300 && resp.statusCode < 400)) {
          final loc = resp.headers['location'];
          await resp.stream.drain<void>();
          if (loc == null) return null;
          current = current.resolve(loc);
          continue;
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 20))) {
          builder.add(chunk);
          if (builder.length > maxBytes) return null;
        }
        return (
          status: resp.statusCode,
          contentType: (resp.headers['content-type'] ?? '').split(';').first.trim(),
          bytes: builder.takeBytes(),
        );
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
