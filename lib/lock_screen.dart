import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Layar kunci native (Flutter). Berada di atas WebView, sehingga tidak bisa
/// disembunyikan atau dihapus oleh skrip situs mana pun.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.reason, required this.stages, required this.onFinished, this.onBack});

  final String reason;
  final List<(String title, String text)> stages;
  final VoidCallback onFinished;

  /// Kembali ke halaman aman tanpa mengetik.
  final VoidCallback? onBack;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const bg = Color(0xFF323437);
  static const sub = Color(0xFF646669);
  static const ok = Color(0xFFD1D0C5);
  static const bad = Color(0xFFCA4754);
  static const accent = Color(0xFFE2B714);

  final _ctl = TextEditingController();
  final _focus = FocusNode();
  int _stage = 0;
  bool _done = false;
  int _keys = 0, _correctKeys = 0;
  DateTime? _start;

  String get _target => widget.stages[_stage].$2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  /// Munculkan keyboard lagi. Jika kolom sudah fokus tapi keyboard ditutup (tombol back HP / ketuk
  /// di luar), requestFocus() saja tidak cukup: keyboard harus diminta tampil secara eksplisit.
  void _showKeyboard() {
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    if (_done) return;
    final typed = _prev;
    // Tambahan banyak huruf sekaligus = tempel (paste) / saran keyboard -> ditolak.
    if (v.length > typed.length + 2) {
      _set(typed);
      return;
    }
    if (v.length > _target.length) v = v.substring(0, _target.length);
    for (var i = typed.length; i < v.length; i++) {
      _start ??= DateTime.now();
      _keys++;
      if (v[i] == _target[i]) _correctKeys++;
    }
    _set(v);
    if (v == _target) {
      _done = true;
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        if (_stage < widget.stages.length - 1) {
          setState(() {
            _stage++;
            _done = false;
            _set('');
          });
        } else {
          setState(() {});
          Future.delayed(const Duration(milliseconds: 2200), () {
            if (mounted) widget.onFinished();
          });
        }
      });
    }
  }

  String _prev = '';
  void _set(String v) {
    _prev = v;
    _ctl.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final finished = _done && _stage == widget.stages.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !finished) widget.onBack?.call();
      },
      child: Material(
        color: bg,
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showKeyboard,
            child: Stack(
              children: [
                // Kolom teks tak terlihat yang menerima ketikan keyboard.
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _ctl,
                      focusNode: _focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableInteractiveSelection: false,
                      keyboardType: TextInputType.visiblePassword,
                      textCapitalization: TextCapitalization.none,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      contextMenuBuilder: (_, __) => const SizedBox.shrink(),
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
                      onChanged: _onChanged,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: finished ? _doneView() : _typingView(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typingView() {
    final target = _target;
    final typed = _prev;
    final spans = <TextSpan>[];
    for (var i = 0; i < target.length; i++) {
      final ch = target[i];
      Color c = sub;
      Color? bgc;
      if (i < typed.length) {
        if (typed[i] == ch) {
          c = ok;
        } else {
          c = bad;
          if (ch == ' ') bgc = bad.withValues(alpha: 0.35);
        }
      }
      final caret = i == typed.length;
      spans.add(TextSpan(
        text: ch,
        style: TextStyle(
          color: c,
          backgroundColor: bgc,
          decoration: caret ? TextDecoration.underline : null,
          decorationColor: accent,
          decorationThickness: 2.5,
        ),
      ));
    }
    final correct = [for (var i = 0; i < typed.length; i++) typed[i] == target[i]].where((x) => x).length;
    final minutes = _start == null ? 0 : DateTime.now().difference(_start!).inMilliseconds / 60000;
    final wpm = minutes > 0.02 ? (correct / 5 / minutes).round() : 0;
    final acc = _keys == 0 ? 100 : (_correctKeys * 100 / _keys).round();

    return ListView(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: bad, borderRadius: BorderRadius.circular(6)),
            child: const Text('KONTEN DIBLOKIR',
                style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.2)),
          ),
        ),
        const SizedBox(height: 14),
        const Center(
            child: Text('Berhenti sejenak.',
                style: TextStyle(color: accent, fontSize: 24, fontWeight: FontWeight.w600))),
        const SizedBox(height: 6),
        Center(
          child: Text('Terdeteksi: ${widget.reason}.\nKetik ulang teks di bawah untuk keluar.',
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8B8D90), fontSize: 13)),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(child: Text(widget.stages[_stage].$1, style: const TextStyle(color: accent, fontSize: 15))),
            Text('${_stage + 1} / ${widget.stages.length}', style: const TextStyle(color: sub)),
          ],
        ),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 19, height: 1.6),
            children: spans,
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          _stat('$wpm', 'wpm'),
          const SizedBox(width: 24),
          _stat('$acc%', 'akurasi'),
          const SizedBox(width: 24),
          _stat('${(correct * 100 / target.length).floor()}%', 'selesai'),
        ]),
        const SizedBox(height: 24),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _showKeyboard,
            icon: const Icon(Icons.keyboard, color: accent),
            label: const Text('Tampilkan keyboard', style: TextStyle(color: ok)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: sub)),
          ),
          if (widget.onBack != null)
            OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: ok),
              label: const Text('Kembali ke halaman aman', style: TextStyle(color: ok)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: sub)),
            ),
        ]),
        const SizedBox(height: 16),
        const Text('Ketuk layar bila keyboard tidak muncul • hapus untuk memperbaiki • tempel (paste) tidak bisa',
            style: TextStyle(color: sub, fontSize: 12)),
      ],
    );
  }

  Widget _stat(String v, String l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: const TextStyle(color: accent, fontSize: 20)),
        Text(l, style: const TextStyle(color: sub, fontSize: 12)),
      ]);

  Widget _doneView() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Amin. 🙏', style: TextStyle(color: accent, fontSize: 32)),
          SizedBox(height: 10),
          Text('Kamu memilih untuk tidak menyerah. Itu kemenangan.',
              textAlign: TextAlign.center, style: TextStyle(color: ok, fontSize: 16)),
        ]),
      );
}
