import 'dart:io' show Platform;
import 'dart:math' as math;

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
    // Debu ambient dikurangi drastis (hanya aksen ringan).
    _dust = _generateDust();

    _master = AnimationController(
      vsync: this,
      // Sedikit lebih singkat agar terasa responsif.
      duration: const Duration(milliseconds: 3600),
    );
    // Ambient lebih pelan; dipakai hanya untuk aura halus, bukan ratusan partikel.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _master.forward().whenComplete(_onAnimationDone);
  }

  // ───────────────────────── Data generator (ringan) ─────────────────────────

  /// ~28 partikel (sebelumnya 300+) — cukup untuk efek menyatu, jauh lebih hemat.
  List<_Particle> _generateParticles() {
    final rnd = math.Random(2026);
    final list = <_Particle>[];
    const r = _logoR;

    double rr(double a, double b) => a + rnd.nextDouble() * (b - a);

    // Cincin luar — 18 titik merata
    for (var i = 0; i < 18; i++) {
      final a = i / 18 * 2 * math.pi;
      list.add(_Particle(
        tx: math.cos(a) * r,
        ty: math.sin(a) * r,
        size: rr(2.2, 3.4),
        delay: rnd.nextDouble() * 0.22,
        swirl: (rnd.nextBool() ? 1 : -1) * rr(0.35, 0.85) * math.pi,
        a0: rnd.nextDouble() * 2 * math.pi,
        d0: rr(0.45, 0.95),
        ci: rnd.nextInt(4),
        dust: false,
      ));
    }

    // Inti + 3 satelit (bentuk logo) — 10 titik
    for (var i = 0; i < 4; i++) {
      final ang = i == 0 ? 0.0 : (-math.pi / 2 + (i - 1) * 2 * math.pi / 3);
      final rad = i == 0 ? 0.0 : 24 * (r / 48.0);
      list.add(_Particle(
        tx: math.cos(ang) * rad,
        ty: math.sin(ang) * rad,
        size: rr(2.8, 4.0),
        delay: rnd.nextDouble() * 0.18,
        swirl: (rnd.nextBool() ? 1 : -1) * rr(0.3, 0.7) * math.pi,
        a0: rnd.nextDouble() * 2 * math.pi,
        d0: rr(0.4, 0.85),
        ci: i % 4,
        dust: false,
      ));
    }

    // Beberapa titik isian acak di dalam cincin — 6 titik
    for (var i = 0; i < 6; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rad = r * 0.55 * math.sqrt(rnd.nextDouble());
      list.add(_Particle(
        tx: math.cos(a) * rad,
        ty: math.sin(a) * rad,
        size: rr(1.6, 2.6),
        delay: rnd.nextDouble() * 0.25,
        swirl: (rnd.nextBool() ? 1 : -1) * rr(0.4, 0.9) * math.pi,
        a0: rnd.nextDouble() * 2 * math.pi,
        d0: rr(0.5, 1.0),
        ci: rnd.nextInt(4),
        dust: true,
      ));
    }
    return list;
  }

  List<_LetterSpec> _generateLetters() {
    final rnd = math.Random(77);
    final order = List<int>.generate(_title.length, (i) => i)..shuffle(rnd);
    return List<_LetterSpec>.generate(_title.length, (i) {
      return _LetterSpec(
        dx: (rnd.nextDouble() * 2 - 1) * 0.45,
        dy: (rnd.nextDouble() * 2 - 1) * 0.35,
        rot: (rnd.nextDouble() * 2 - 1) * math.pi * 0.55,
        scale: 0.55 + rnd.nextDouble() * 0.9,
        delay: order[i] / math.max(_title.length - 1, 1) * 0.4,
        wobble: (rnd.nextBool() ? 1 : -1) * (8 + rnd.nextDouble() * 12),
      );
    });
  }

  /// Debu latar sangat sedikit (sebelumnya 38).
  List<List<double>> _generateDust() {
    final rnd = math.Random(5);
    return List.generate(
      10,
      (_) => [
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.8 + rnd.nextDouble() * 1.2,
        0.5 + rnd.nextDouble() * 0.9,
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
    // Tanpa ImageFiltered blur (mahal di GPU) — cukup opacity + transform.
    final sh = ((m - 0.78) / 0.14).clamp(0.0, 1.0);
    final xc = -1.5 + 3.0 * Curves.easeInOut.transform(sh);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment(xc - 0.55, 0),
        end: Alignment(xc + 0.55, 0),
        colors: const [Color(0xFFC7D2FE), Colors.white, Color(0xFFC7D2FE)],
      ).createShader(rect),
      child: _titleRow(m, w, h),
    );
  }

  Widget _titleRow(double m, double w, double h) {
    const style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      height: 1.1,
      color: Colors.white,
    );
    // Timeline disesuaikan durasi master 3.6s
    final tt = ((m - 0.42) / 0.32).clamp(0.0, 1.0);

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

      Widget t = Text(ch, style: style);
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

// ───────────────────────── Painter (ringan & smooth) ─────────────────────────

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
  ];

  // Timeline (master 0..1, durasi ~3.6s):
  // 0.00–0.45  partikel berputar menyatu
  // 0.35–0.55  logo muncul
  // 0.50–0.85  judul
  // 0.90–1.00  fade out

  @override
  void paint(Canvas canvas, Size size) {
    _paintDust(canvas, size);
    _paintAura(canvas);
    _paintParticles(canvas, size);
    _paintLogo(canvas);
    _paintFlash(canvas);
  }

  void _paintDust(Canvas canvas, Size size) {
    final vis = (m / 0.18).clamp(0.0, 1.0);
    if (vis <= 0) return;
    final p = Paint();
    for (final d in dust) {
      final y = (1 - ((d[1] + ambient * d[3] * 0.35) % 1.0)) * size.height;
      final x = d[0] * size.width +
          math.sin(ambient * math.pi * 2 + d[4]) * 4;
      p.color = _kIndigoLight.withOpacity(0.08 + 0.12 * vis);
      canvas.drawCircle(Offset(x, y), d[2], p);
    }
  }

  void _paintAura(Canvas canvas) {
    final t = ((m - 0.06) / 0.4).clamp(0.0, 1.0);
    if (t <= 0) return;
    final pulse = 1 + 0.04 * math.sin(ambient * math.pi * 2);
    final rad = radius * (1.3 + 0.9 * Curves.easeOut.transform(t)) * pulse;
    final rect = Rect.fromCircle(center: center, radius: rad);
    canvas.drawCircle(
      center,
      rad,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _kIndigo.withOpacity(0.28 * t),
            _kCyan.withOpacity(0.08 * t),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  void _paintParticles(Canvas canvas, Size size) {
    // Partikel menghilang setelah logo solid.
    final fade = (1 - ((m - 0.48) / 0.12)).clamp(0.0, 1.0);
    if (fade <= 0) return;

    final maxD = math.max(size.width, size.height) * 0.42;
    final dot = Paint();

    for (final p in particles) {
      final local = ((m - p.delay * 0.35) / 0.42).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final e = Curves.easeInOutCubic.transform(local);

      // Orbit → target
      final ang = p.a0 + p.swirl * (1 - e);
      final dist = p.d0 * maxD * (1 - e);
      final x = center.dx + math.cos(ang) * dist + p.tx * e;
      final y = center.dy + math.sin(ang) * dist + p.ty * e;

      final op = (local < 0.15
              ? local / 0.15
              : (local > 0.85 ? (1 - local) / 0.15 : 1.0))
          .clamp(0.0, 1.0) *
          fade;
      if (op < 0.02) continue;

      final sz = p.size * (0.7 + 0.3 * e);
      final col = _palette[p.ci % _palette.length];

      // Satu lingkaran saja (tanpa glow blur) — jauh lebih hemat.
      dot.color = col.withOpacity(0.75 * op);
      canvas.drawCircle(Offset(x, y), sz, dot);
    }
  }

  void _paintLogo(Canvas canvas) {
    final sp = ((m - 0.38) / 0.14).clamp(0.0, 1.0);
    if (sp <= 0) return;
    final op = Curves.easeOut.transform(sp);
    final sc = 0.82 + 0.18 * Curves.easeOutBack.transform(sp);
    final r = radius;
    final u = r / 48.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(sc);

    final discRect = Rect.fromCircle(center: Offset.zero, radius: r);

    // Cakram gradien (tanpa MaskFilter.blur)
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = _kIndigo.withOpacity(0.35 * op)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF818CF8).withOpacity(op),
            Color(0xFF6366F1).withOpacity(op),
            Color(0xFF4F46E5).withOpacity(op),
          ],
        ).createShader(discRect),
    );

    // Kilau ringan
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.9,
          colors: [
            Colors.white.withOpacity(0.22 * op),
            Colors.transparent,
          ],
        ).createShader(discRect),
    );

    // Rim
    canvas.drawCircle(
      Offset.zero,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.28 * op),
    );

    // Ikon hub
    final white = Paint()
      ..color = Colors.white.withOpacity(op)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = Colors.white.withOpacity(op)
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

    // Cincin tipis saat logo settle
    final ringA = ((m - 0.52) / 0.1).clamp(0.0, 1.0);
    if (ringA > 0) {
      canvas.drawCircle(
        Offset.zero,
        r + 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _kCyan.withOpacity(0.55 * ringA * op),
      );
    }

    canvas.restore();
  }

  void _paintFlash(Canvas canvas) {
    // Flash singkat saat partikel menyatu — satu lingkaran radial saja.
    final f = ((m - 0.40) / 0.06).clamp(0.0, 1.0);
    if (f <= 0 || f >= 1) return;
    final peak = math.sin(f * math.pi);
    final rad = radius * (0.6 + 1.8 * f);
    canvas.drawCircle(
      center,
      rad,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.35 * peak),
            _kIndigoLight.withOpacity(0.12 * peak),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: rad)),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) =>
      old.m != m ||
      old.ambient != ambient ||
      old.center != center ||
      old.radius != radius;
}
