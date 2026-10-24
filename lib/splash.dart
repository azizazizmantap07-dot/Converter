import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key: dialog izin sudah pernah ditampilkan sejak install (sekali saja).
const _kStoragePermissionPrompted = 'storage_permission_prompted_v1';

const _kBg = Color(0xFF090D16);
const _kIndigo = Color(0xFF6366F1);
const _kIndigoLight = Color(0xFF818CF8);
const _kCyan = Color(0xFF06B6D4);
const _kViolet = Color(0xFFA78BFA);

/// Layar peluncuran: partikel terpisah berputar lalu menyatu menjadi logo,
/// huruf-huruf tersebar terbang menyatu menjadi "Proxy Converter".
/// Setelah itu izin penyimpanan diminta sekali (tema gelap indigo).
class LaunchScreen extends StatefulWidget {
  final Widget home;

  const LaunchScreen({super.key, required this.home});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with TickerProviderStateMixin {
  static const String _title = 'Proxy Converter';
  static const double _logoR = 46;
  static const double _logoBox = 124;
  static const double _gap = 26;
  static const double _textH = 40;

  late final AnimationController _master;
  late final AnimationController _ambient;
  late final List<_Particle> _particles;
  late final List<_LetterSpec> _letters;
  late final List<List<double>> _dust;

  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _kBg,
    ));

    _particles = _generateParticles();
    _letters = _generateLetters();
    _dust = _generateDust();

    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();

    _master.forward().whenComplete(_onAnimationDone);
  }

  // ───────────────────────── Data generator ─────────────────────────

  List<_Particle> _generateParticles() {
    final rnd = math.Random(2026);
    final list = <_Particle>[];
    const r = _logoR;
    const u = r / 48.0;

    double rr(double a, double b) => a + rnd.nextDouble() * (b - a);

    void add(double x, double y, double size, {bool dust = false}) {
      list.add(_Particle(
        tx: x,
        ty: y,
        size: size,
        delay: rnd.nextDouble() * 0.38,
        swirl: (rnd.nextBool() ? 1 : -1) * rr(0.5, 1.1) * math.pi,
        a0: rnd.nextDouble() * 2 * math.pi,
        d0: rr(0.35, 1.0),
        ci: rnd.nextInt(5),
        dust: dust,
      ));
    }

    // Cincin luar logo
    const ringN = 140;
    for (var i = 0; i < ringN; i++) {
      final a = i / ringN * 2 * math.pi;
      final rad = r + rr(-0.6, 0.6);
      add(math.cos(a) * rad, math.sin(a) * rad, rr(1.1, 1.9));
    }

    // Simpul pusat
    for (var i = 0; i < 30; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rad = 7 * u * math.sqrt(rnd.nextDouble());
      add(math.cos(a) * rad, math.sin(a) * rad, rr(1.0, 1.7));
    }

    // Tiga simpul satelit + garis penghubung
    for (var k = 0; k < 3; k++) {
      final ang = -math.pi / 2 + k * 2 * math.pi / 3;
      final sx = math.cos(ang) * 24 * u;
      final sy = math.sin(ang) * 24 * u;
      for (var i = 0; i < 16; i++) {
        final a = rnd.nextDouble() * 2 * math.pi;
        final rad = 6 * u * math.sqrt(rnd.nextDouble());
        add(sx + math.cos(a) * rad, sy + math.sin(a) * rad, rr(1.0, 1.7));
      }
      for (var i = 0; i < 20; i++) {
        final t = i / 19;
        add(sx * t + rr(-0.7, 0.7), sy * t + rr(-0.7, 0.7), rr(0.9, 1.5));
      }
    }

    // Debu isian di dalam cakram
    for (var i = 0; i < 90; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rad = r * 0.9 * math.sqrt(rnd.nextDouble());
      add(math.cos(a) * rad, math.sin(a) * rad, rr(0.6, 1.1), dust: true);
    }
    return list;
  }

  List<_LetterSpec> _generateLetters() {
    final rnd = math.Random(77);
    final order = List<int>.generate(_title.length, (i) => i)..shuffle(rnd);
    return List<_LetterSpec>.generate(_title.length, (i) {
      return _LetterSpec(
        dx: (rnd.nextDouble() * 2 - 1) * 0.62,
        dy: (rnd.nextDouble() * 2 - 1) * 0.5,
        rot: (rnd.nextDouble() * 2 - 1) * math.pi * 1.2,
        scale: 0.3 + rnd.nextDouble() * 2.1,
        delay: order[i] / (_title.length - 1) * 0.5,
        wobble: (rnd.nextBool() ? 1 : -1) * (18 + rnd.nextDouble() * 26),
      );
    });
  }

  List<List<double>> _generateDust() {
    final rnd = math.Random(5);
    return List.generate(
      38,
      (_) => [
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.7 + rnd.nextDouble() * 1.4,
        0.4 + rnd.nextDouble() * 1.2,
        rnd.nextDouble() * 2 * math.pi,
      ],
    );
  }

  Future<void> _onAnimationDone() async {
    if (!mounted || _navigating) return;
    await _ensureStoragePermissionOnce();
    if (!mounted) return;
    _goHome();
  }

  /// Dialog + request izin hanya sekali sejak install.
  /// Pengaman untuk perangkat Android di bawah 10 (API &lt; 29) yang masih
  /// membutuhkan WRITE_EXTERNAL_STORAGE agar bisa menulis ke folder Download.
  Future<void> _ensureStoragePermissionOnce() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kStoragePermissionPrompted) == true) {
      return; // sudah pernah ditampilkan — tidak muncul lagi
    }

    // Tandai dulu agar crash/kill tidak memicu dialog berulang di sesi berikutnya
    await prefs.setBool(_kStoragePermissionPrompted, true);

    // Jika sudah granted (mis. user pernah izinkan lewat setelan), lewati dialog
    final status = await Permission.storage.status;
    if (status.isGranted || status.isLimited) return;

    final accepted = await _showPermissionDialog();
    if (accepted == true) {
      final result = await Permission.storage.request();
      if (result.isPermanentlyDenied && mounted) {
        final open = await _showOpenSettingsDialog();
        if (open == true) await openAppSettings();
      }
    }
  }

  Future<bool?> _showPermissionDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'permission',
      barrierColor: Colors.black.withOpacity(0.72),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim, secondary) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: math.min(MediaQuery.of(ctx).size.width - 48, 340),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF141B2D), Color(0xFF0D131F)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.18),
                        blurRadius: 32,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6366F1).withOpacity(0.35),
                              const Color(0xFF06B6D4).withOpacity(0.2),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFF6366F1).withOpacity(0.45),
                          ),
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          color: Color(0xFFA5B4FC),
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Izin Penyimpanan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Agar file konfigurasi dapat disimpan ke folder Download, aplikasi meminta izin penyimpanan.\n\nTerutama diperlukan pada Android 9 ke bawah. Dialog ini hanya muncul sekali.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF6366F1).withOpacity(0.25),
                          ),
                        ),
                        child: const Text(
                          'Data tidak dikirim ke server. Semua konversi berjalan offline di perangkat Anda.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Color(0xFFA5B4FC),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF9CA3AF),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                'Nanti saja',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Izinkan',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showOpenSettingsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.3)),
        ),
        title: const Text(
          'Izin Diperlukan',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'Izin penyimpanan dinonaktifkan secara permanen. Buka pengaturan aplikasi untuk mengaktifkannya secara manual (berguna pada Android 9 ke bawah).',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tutup', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
  }

  void _goHome() {
    if (_navigating || !mounted) return;
    _navigating = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.home,
        transitionDuration: const Duration(milliseconds: 480),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _master.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_master, _ambient]),
        builder: (context, _) {
          final m = _master.value;
          final fadeOut = (1 - ((m - 0.94) / 0.06)).clamp(0.0, 1.0);

          return Opacity(
            opacity: fadeOut,
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                final h = cons.maxHeight;
                const groupH = _logoBox + _gap + _textH;
                final top = (h - groupH) / 2;
                final center = Offset(w / 2, top + _logoBox / 2);
                final ay = (center.dy / h) * 2 - 1;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, ay),
                          radius: 1.1,
                          colors: const [
                            Color(0xFF1A1F3A),
                            Color(0xFF090D16),
                            Color(0xFF06080F),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _SplashPainter(
                        m: m,
                        ambient: _ambient.value,
                        center: center,
                        radius: _logoR,
                        particles: _particles,
                        dust: _dust,
                      ),
                    ),
                    Positioned(
                      top: top + _logoBox + _gap,
                      left: 0,
                      right: 0,
                      height: _textH,
                      child: Center(child: _buildTitle(m, w, h)),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── Judul: huruf menyatu ─────────────────────────

  Widget _buildTitle(double m, double w, double h) {
    final settle = ((m - 0.70) / 0.12).clamp(0.0, 1.0);
    final sh = ((m - 0.80) / 0.15).clamp(0.0, 1.0);
    final xc = -1.7 + 3.4 * Curves.easeInOut.transform(sh);

    final crisp = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment(xc - 0.6, 0),
        end: Alignment(xc + 0.6, 0),
        colors: const [Color(0xFFC7D2FE), Colors.white, Color(0xFFC7D2FE)],
      ).createShader(rect),
      child: _titleRow(m, w, h, glow: false),
    );

    final glowLayer = Opacity(
      opacity: 0.55 * settle,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
          tileMode: TileMode.decal,
        ),
        child: _titleRow(m, w, h, glow: true),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [if (settle > 0) glowLayer, crisp],
    );
  }

  Widget _titleRow(double m, double w, double h, {required bool glow}) {
    final style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      height: 1.1,
      color: glow ? _kIndigo : Colors.white,
    );
    final tt = ((m - 0.44) / 0.36).clamp(0.0, 1.0);

    final children = <Widget>[];
    for (var i = 0; i < _title.length; i++) {
      final ch = _title[i];
      if (ch == ' ') {
        children.add(const SizedBox(width: 12));
        continue;
      }
      final s = _letters[i];
      final local = ((tt - s.delay) / 0.5).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(local);
      final eBack = Curves.easeOutBack.transform(local);
      final op = Curves.easeOut.transform((local * 2.2).clamp(0.0, 1.0));
      final off = Offset(
        s.dx * w * (1 - e),
        s.dy * h * (1 - e) + math.sin(math.pi * e) * s.wobble,
      );
      final rot = s.rot * (1 - e);
      final sc = 1 + (s.scale - 1) * (1 - eBack);
      final blur = 9 * (1 - e);

      Widget t = Text(ch, style: style);
      if (!glow && blur > 0.3) {
        t = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: TileMode.decal,
          ),
          child: t,
        );
      }
      t = Opacity(opacity: op, child: t);
      t = Transform.scale(scale: sc, child: t);
      t = Transform.rotate(angle: rot, child: t);
      t = Transform.translate(offset: off, child: t);
      children.add(t);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

// ───────────────────────── Model ─────────────────────────

class _Particle {
  final double tx, ty, size, delay, swirl, a0, d0;
  final int ci;
  final bool dust;

  const _Particle({
    required this.tx,
    required this.ty,
    required this.size,
    required this.delay,
    required this.swirl,
    required this.a0,
    required this.d0,
    required this.ci,
    required this.dust,
  });
}

class _LetterSpec {
  final double dx, dy, rot, scale, delay, wobble;

  const _LetterSpec({
    required this.dx,
    required this.dy,
    required this.rot,
    required this.scale,
    required this.delay,
    required this.wobble,
  });
}

// ───────────────────────── Painter ─────────────────────────

class _SplashPainter extends CustomPainter {
  final double m;
  final double ambient;
  final Offset center;
  final double radius;
  final List<_Particle> particles;
  final List<List<double>> dust;

  _SplashPainter({
    required this.m,
    required this.ambient,
    required this.center,
    required this.radius,
    required this.particles,
    required this.dust,
  });

  static const _palette = [
    _kIndigoLight,
    _kIndigo,
    _kCyan,
    _kViolet,
    Color(0xFFE0E7FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintDust(canvas, size);
    _paintAura(canvas);
    _paintLogo(canvas);
    _paintShockwaves(canvas);
    _paintParticles(canvas, size);
    _paintFlash(canvas);
  }

  void _layer(Canvas canvas, Rect bounds, double opacity, VoidCallback draw) {
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
    );
    draw();
    canvas.restore();
  }

  // Debu halus melayang di latar
  void _paintDust(Canvas canvas, Size size) {
    final vis = (m / 0.2).clamp(0.0, 1.0);
    final p = Paint();
    for (final d in dust) {
      final y = (1 - ((d[1] + ambient * d[3]) % 1.0)) * size.height;
      final x = d[0] * size.width + math.sin(ambient * 2 * math.pi * 2 + d[4]) * 6;
      final tw = 0.5 + 0.5 * math.sin(ambient * 2 * math.pi * 6 + d[4]);
      p.color = _kIndigoLight.withOpacity(0.05 + 0.22 * tw * vis);
      canvas.drawCircle(Offset(x, y), d[2], p);
    }
  }

  // Aura energi di belakang logo
  void _paintAura(Canvas canvas) {
    final t = ((m - 0.08) / 0.5).clamp(0.0, 1.0);
    if (t <= 0) return;
    final pulse = 1 + 0.06 * math.sin(ambient * 2 * math.pi * 4);
    final rad = radius * (1.4 + 1.3 * Curves.easeOut.transform(t)) * pulse;
    final rect = Rect.fromCircle(center: center, radius: rad);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          _kIndigo.withOpacity(0.34 * t),
          _kCyan.withOpacity(0.10 * t),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, rad, paint);
  }

  // Logo solid (cakram gradien + ikon hub), muncul saat partikel menyatu
  void _paintLogo(Canvas canvas) {
    final sp = ((m - 0.40) / 0.14).clamp(0.0, 1.0);
    if (sp <= 0) return;
    final op = Curves.easeOut.transform(sp);
    final breathe = 1 + 0.012 * math.sin(ambient * 2 * math.pi * 4);
    final sc = (0.78 + 0.22 * Curves.easeOutBack.transform(sp)) * breathe;
    final r = radius;
    final u = r / 48.0;
    final bounds = Rect.fromCircle(center: Offset.zero, radius: r + 80);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(sc);

    _layer(canvas, bounds, op, () {
      final discRect = Rect.fromCircle(center: Offset.zero, radius: r);

      // Bayangan cahaya
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = _kIndigo.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );

      // Cakram
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4F46E5)],
          ).createShader(discRect),
      );

      // Kilau kaca
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.55),
            radius: 0.95,
            colors: [
              Colors.white.withOpacity(0.28),
              Colors.white.withOpacity(0.0),
            ],
          ).createShader(discRect),
      );

      // Rim
      canvas.drawCircle(
        Offset.zero,
        r - 0.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withOpacity(0.3),
      );

      // Ikon hub
      final white = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final line = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 * u;
      for (var k = 0; k < 3; k++) {
        final ang = -math.pi / 2 + k * 2 * math.pi / 3;
        final s = Offset(math.cos(ang) * 24 * u, math.sin(ang) * 24 * u);
        canvas.drawLine(Offset.zero, s, line);
        canvas.drawCircle(s, 6 * u, white);
      }
      canvas.drawCircle(Offset.zero, 7 * u, white);
    });

    // Cincin cahaya yang berputar
    final ringA = ((m - 0.56) / 0.1).clamp(0.0, 1.0);
    if (ringA > 0) {
      final rr = r + 8;
      final rect = Rect.fromCircle(center: Offset.zero, radius: rr);
      _layer(canvas, rect.inflate(6), ringA * 0.9, () {
        canvas.drawCircle(
          Offset.zero,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              colors: const [
                Color(0x0006B6D4),
                Color(0xFF22D3EE),
                Color(0xFF818CF8),
                Color(0x006366F1),
              ],
              stops: const [0.0, 0.12, 0.28, 0.5],
              transform: GradientRotation(ambient * 2 * math.pi * 3),
            ).createShader(rect),
        );
      });
    }
    canvas.restore();
  }

  // Gelombang kejut saat partikel menyatu
  void _paintShockwaves(Canvas canvas) {
    void ring(double start, Color color) {
      final t = ((m - start) / 0.26).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) return;
      final e = Curves.easeOutCubic.transform(t);
      canvas.drawCircle(
        center,
        radius * (1 + 1.7 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + 2.4 * (1 - t)
          ..color = color.withOpacity(0.5 * (1 - t)),
      );
    }

    ring(0.50, _kIndigoLight);
    ring(0.55, _kCyan);
  }

  // Partikel: tersebar → berputar → menyatu membentuk logo
  void _paintParticles(Canvas canvas, Size size) {
    final pt = (m / 0.50).clamp(0.0, 1.0);
    final appear = (m / 0.06).clamp(0.0, 1.0);
    final gone = ((m - 0.48) / 0.10).clamp(0.0, 1.0);
    if (gone >= 1) return;
    final maxD = math.sqrt(size.width * size.width + size.height * size.height) * 0.55;

    final dot = Paint();
    final glow = Paint();
    final trail = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < particles.length; i++) {
      final p = particles[i];
      final local = ((pt - p.delay) / 0.62).clamp(0.0, 1.0);
      final e = Curves.easeInOutCubic.transform(local);

      final r1 = math.sqrt(p.tx * p.tx + p.ty * p.ty);
      final a1 = math.atan2(p.ty, p.tx);
      final r0 = p.d0 * maxD + radius;
      var da = (p.a0 - a1) % (2 * math.pi);
      if (da > math.pi) da -= 2 * math.pi;

      Offset posAt(double ee) {
        final rad = r1 + (r0 - r1) * (1 - ee);
        final ang = a1 + (da + p.swirl) * (1 - ee);
        return Offset(
          center.dx + math.cos(ang) * rad,
          center.dy + math.sin(ang) * rad,
        );
      }

      var pos = posAt(e);
      if (local >= 1) {
        // sedikit bergetar setelah menyatu
        pos += Offset(
          math.sin(ambient * 2 * math.pi * 9 + i) * 0.5,
          math.cos(ambient * 2 * math.pi * 7 + i) * 0.5,
        );
      }

      final fade = p.dust ? (1 - gone) * (1 - gone) : (1 - gone);
      final alpha = (appear * fade * (p.dust ? 0.6 : 1.0)).clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      final color = _palette[p.ci];

      // Jejak gerak
      if (local > 0 && local < 1) {
        final prev = posAt((e - 0.07).clamp(0.0, 1.0));
        trail
          ..strokeWidth = p.size * 0.9
          ..color = color.withOpacity(0.45 * alpha);
        canvas.drawLine(prev, pos, trail);
      }

      final tw = 0.8 + 0.4 * math.sin(ambient * 2 * math.pi * 12 + i * 1.7);
      final sz = p.size * tw * (local >= 1 ? 1.15 : 1.0);

      glow.color = color.withOpacity(0.16 * alpha);
      canvas.drawCircle(pos, sz * 2.8, glow);
      dot.color = color.withOpacity(alpha);
      canvas.drawCircle(pos, sz, dot);
    }
  }

  // Kilatan cahaya saat logo terbentuk
  void _paintFlash(Canvas canvas) {
    final f = (1 - ((m - 0.50) / 0.06).abs()).clamp(0.0, 1.0);
    if (f <= 0) return;
    final rad = radius * 2.6;
    canvas.drawCircle(
      center,
      rad,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.6 * f),
            _kIndigoLight.withOpacity(0.25 * f),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: rad)),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) => true;
}
