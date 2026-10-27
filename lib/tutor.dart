import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: tour sudah pernah diselesaikan / dilewati.
const kTutorCompletedKey = 'tutor_completed_v1';

// ─── Theme tokens (selaras dengan main.dart) ───────────────────────────────
const _kBg = Color(0xFF090D16);
const _kCard = Color(0xFF111827);
const _kIndigo = Color(0xFF6366F1);
const _kIndigoSoft = Color(0xFF818CF8);
const _kCyan = Color(0xFF06B6D4);
const _kMuted = Color(0xFF9CA3AF);
const _kBorder = Color(0xFF1F2937);

// ─── Gaya teks kartu tutor ──────────────────────────────────────────────────
// Dipakai bersama oleh tampilan kartu DAN pengukuran tinggi (lihat
// _measureTextHeight), jadi tinggi yang dihitung selalu sama dengan yang tampil.
// `height` dibuat eksplisit agar tidak bergantung pada tinggi baris bawaan tema.
const _kPillStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.bold,
  height: 1.2,
);
const _kTitleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.bold,
  height: 1.25,
  color: Colors.white,
);
const _kBodyStyle = TextStyle(
  fontSize: 12,
  height: 1.35,
  color: Color(0xFFD1D5DB),
);
const _kTipStyle = TextStyle(
  fontSize: 10.5,
  height: 1.3,
  color: _kMuted,
);

/// Mengukur tinggi teks persis seperti widget `Text` di [context]
/// (gaya bawaan tema + skala font sistem + lebar yang tersedia).
double _measureTextHeight(
  BuildContext context,
  String text,
  TextStyle style,
  double maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.max(maxWidth, 1.0));
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Hasil perhitungan tata letak kartu (lihat _TutorOverlayState._planCard).
class _CardPlan {
  final double robot;
  final double gapHeader;
  final double gapBlock;
  final double gapActions;
  final bool showTip;

  /// Tinggi mini-demo yang ditampilkan. 0 = demo disembunyikan.
  final double demoHeight;

  const _CardPlan({
    required this.robot,
    required this.gapHeader,
    required this.gapBlock,
    required this.gapActions,
    required this.showTip,
    required this.demoHeight,
  });
}

/// Tinggi "kanvas desain" tiap mini-demo: tinggi yang dibutuhkan isinya agar
/// tampil utuh tanpa meluap. Saat ruang kartu sempit, demo digambar pada tinggi
/// ini lalu diperkecil proporsional (lihat _ScaledDemo), bukan dipotong.
double _demoDesignHeight(TutorDemoType type) {
  switch (type) {
    case TutorDemoType.pasteLinks:
      return 164;
    case TutorDemoType.modeSwitch:
      return 160;
    case TutorDemoType.convertPulse:
      return 146;
    case TutorDemoType.outputActions:
      return 188;
    case TutorDemoType.coreNav:
      return 152;
    case TutorDemoType.bugWildcard:
      return 182;
    case TutorDemoType.studioCustom:
      return 150;
    case TutorDemoType.none:
      return 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA LANGKAH TOUR
// ═══════════════════════════════════════════════════════════════════════════

class TutorStep {
  final String id;
  final String title;
  final String body;
  final String tip;
  final IconData icon;
  final Color accent;
  /// GlobalKey target di HomePage. Null = langkah intro / penutup (penuh layar).
  final GlobalKey? targetKey;
  /// Jenis mini-demo animasi di kartu penjelasan.
  final TutorDemoType demo;

  const TutorStep({
    required this.id,
    required this.title,
    required this.body,
    required this.tip,
    required this.icon,
    required this.accent,
    this.targetKey,
    this.demo = TutorDemoType.none,
  });
}

enum TutorDemoType {
  none,
  pasteLinks,
  modeSwitch,
  convertPulse,
  outputActions,
  coreNav,
  bugWildcard,
  studioCustom,
}

// ═══════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════

/// Cek apakah tour sudah selesai. Jika belum, tampilkan overlay tutor.
Future<void> maybeShowTutor(
  BuildContext context, {
  required List<TutorStep> steps,
  VoidCallback? onFinished,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kTutorCompletedKey) == true) return;
  if (!context.mounted) return;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'tutor',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, secondary, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: TutorOverlay(
          steps: steps,
          onFinished: () async {
            await prefs.setBool(kTutorCompletedKey, true);
            onFinished?.call();
          },
        ),
      );
    },
  );
}

/// Paksa tampilkan ulang tour (dari tombol bantuan).
Future<void> showTutorAgain(
  BuildContext context, {
  required List<TutorStep> steps,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kTutorCompletedKey, false);
  if (!context.mounted) return;
  await maybeShowTutor(context, steps: steps);
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERLAY UTAMA
// ═══════════════════════════════════════════════════════════════════════════

class TutorOverlay extends StatefulWidget {
  final List<TutorStep> steps;
  final VoidCallback onFinished;

  const TutorOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  @override
  State<TutorOverlay> createState() => _TutorOverlayState();
}

class _TutorOverlayState extends State<TutorOverlay>
    with TickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _pulse;
  late final AnimationController _robotBob;
  late final AnimationController _enter;

  TutorStep get _step => widget.steps[_index];
  bool get _isFirst => _index == 0;
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _robotBob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();

    // Jika langkah awal punya target, pastikan terlihat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _step.targetKey;
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.12,
        );
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _robotBob.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _enter
        ..reset()
        ..forward();
    });
    // Scroll target ke viewport: sisakan ruang untuk kartu tutor di sisi berlawanan.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final key = _step.targetKey;
      final ctx = key?.currentContext;
      if (ctx != null) {
        // alignment rendah = target di atas → kartu di bawah; tinggi = sebaliknya
        final preferCardBottom = _preferCardBelowTarget();
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: preferCardBottom ? 0.12 : 0.55,
        );
        if (mounted) setState(() {});
      }
    });
  }

  /// true = letakkan kartu di bawah target (target ada di bagian atas layar).
  bool _preferCardBelowTarget() {
    final rect = _targetRect();
    if (rect == null) return true;
    final h = MediaQuery.sizeOf(context).height;
    // Pusat target di setengah atas → kartu di bawah.
    return rect.center.dy < h * 0.48;
  }

  void _finish() {
    Navigator.of(context).pop();
    widget.onFinished();
  }

  Rect? _targetRect() {
    final key = _step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final rect = _targetRect();
    final hasTarget = rect != null;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Spotlight / dim layer ──────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                hole: hasTarget
                    ? RRect.fromRectAndRadius(
                        rect!.inflate(8),
                        const Radius.circular(16),
                      )
                    : null,
                pulse: _pulse.value,
              ),
            ),
          ),

          // ── Highlight border on target ─────────────────────────────────
          if (hasTarget)
            Positioned(
              left: rect!.left - 8,
              top: rect.top - 8,
              width: rect.width + 16,
              height: rect.height + 16,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final t = _pulse.value;
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _step.accent.withOpacity(0.55 + 0.35 * t),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _step.accent.withOpacity(0.25 + 0.2 * t),
                          blurRadius: 12 + 8 * t,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // ── Card + robot (selalu di sisi berlawanan target) ────────────
          _buildPositionedCard(size, rect, hasTarget),
        ],
      ),
    );
  }

  Widget _buildPositionedCard(Size size, Rect? rect, bool hasTarget) {
    final padTop = MediaQuery.of(context).padding.top;
    final padBottom = MediaQuery.of(context).padding.bottom;
    // Kartu di bawah jika target di atas; sebaliknya di atas.
    final cardBelow = !hasTarget || _preferCardBelowTarget();
    // Batasi tinggi kartu agar tidak menabrak target. Isi kartu menyesuaikan
    // diri dengan batas ini (lihat _planCard), jadi tombol tetap terlihat utuh.
    // Batas bawah 190 = tinggi minimum agar header + teks + tombol tetap muat.
    final maxAllowed = size.height * 0.6;
    double maxCardH = size.height * 0.55;
    if (hasTarget && rect != null) {
      if (cardBelow) {
        final spaceBelow = size.height - rect.bottom - padBottom - 28;
        maxCardH = math.min(maxAllowed, math.max(190.0, spaceBelow));
      } else {
        final spaceAbove = rect.top - padTop - 20;
        maxCardH = math.min(maxAllowed, math.max(190.0, spaceAbove));
      }
    }

    return Positioned(
      left: 14,
      right: 14,
      top: cardBelow ? null : padTop + 12,
      bottom: cardBelow ? padBottom + 18 : null,
      child: FadeTransition(
        opacity: _enter,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
          ),
          child: _buildCard(hasTarget, maxCardH),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // KARTU TUTOR — tata letak adaptif
  //
  // Tombol aksi (Lewati / Lanjut) selalu "dipaku" di bawah kartu, di luar area
  // scroll, sehingga tidak pernah terpotong. Isi kartu (header, teks, tip, demo)
  // disesuaikan otomatis dengan ruang yang tersedia agar umumnya TIDAK perlu
  // scroll sama sekali. Urutan penyesuaian saat ruang sempit:
  //   1. mini-demo diperkecil proporsional (sampai ±76%),
  //   2. robot & jarak antar-elemen dirapatkan,
  //   3. kotak tip disembunyikan,
  //   4. mini-demo disembunyikan.
  // Jika masih tidak muat (mis. ukuran font sistem sangat besar), hanya bagian
  // isi yang bisa di-scroll — tombol tetap terlihat.
  // ═════════════════════════════════════════════════════════════════════════

  static const double _kCardHPad = 14;
  static const double _kCardVPad = 12;
  static const double _kCardBorderW = 1;
  // Tinggi baris tombol: FilledButton 40dp + area sentuh Material 48dp.
  static const double _kActionsH = 48;

  String get _pillLabel => _isFirst
      ? 'Asisten'
      : (_isLast ? 'Selesai' : 'Langkah $_index/${widget.steps.length - 1}');

  /// Menentukan ukuran tiap bagian kartu supaya seluruhnya muat di [maxHeight].
  _CardPlan _planCard(
    BuildContext context,
    double cardWidth,
    double maxHeight,
  ) {
    final innerW = cardWidth - _kCardHPad * 2 - _kCardBorderW * 2;
    // Ruang isi yang boleh dipakai: setelah padding + border, dikurangi 6dp
    // toleransi agar selisih pembulatan/metrik font tidak memicu scroll.
    final availH = maxHeight - _kCardVPad * 2 - _kCardBorderW * 2 - 6;

    final bodyH = _measureTextHeight(context, _step.body, _kBodyStyle, innerW);
    final hasTip = _step.tip.isNotEmpty;
    // Kotak tip: padding 9 + border 1 di tiap sisi, ikon 13 + jarak 6 → teks
    // mendapat (innerW - 39). Tinggi: teks + padding 7×2 + border 1×2.
    final tipBoxH = hasTip
        ? _measureTextHeight(context, _step.tip, _kTipStyle, innerW - 39) + 16
        : 0.0;
    // Lencana "Langkah x/y": teks + padding 3×2 + border 1×2; ikon di sebelahnya 16.
    final pillRowH = math.max(
      _measureTextHeight(context, _pillLabel, _kPillStyle, innerW) + 8,
      16.0,
    );
    final designH = _demoDesignHeight(_step.demo);

    // Tinggi seluruh isi KECUALI mini-demo (dan jaraknya).
    double fixedHeight(bool compact, bool withTip) {
      final robot = compact ? 44.0 : 56.0;
      final titleH = _measureTextHeight(
        context,
        _step.title,
        _kTitleStyle,
        innerW - robot - 12,
      );
      final header = math.max(robot, pillRowH + 6 + titleH);
      var h = header + (compact ? 8.0 : 12.0) + bodyH;
      if (withTip && hasTip) h += (compact ? 6.0 : 8.0) + tipBoxH;
      h += (compact ? 8.0 : 10.0) + _kActionsH;
      return h;
    }

    _CardPlan makePlan(bool compact, bool withTip, double demoH) {
      return _CardPlan(
        robot: compact ? 44.0 : 56.0,
        gapHeader: compact ? 8.0 : 12.0,
        gapBlock: compact ? 6.0 : 8.0,
        gapActions: compact ? 8.0 : 10.0,
        showTip: withTip && hasTip,
        demoHeight: demoH,
      );
    }

    if (designH > 0) {
      _CardPlan? tryDemo(bool compact, bool withTip, double minScale) {
        final gap = compact ? 6.0 : 8.0;
        final remaining = availH - fixedHeight(compact, withTip) - gap;
        if (remaining < designH * minScale) return null;
        return makePlan(compact, withTip, math.min(remaining, designH));
      }

      final withDemo = tryDemo(false, true, 0.88) ??
          tryDemo(true, true, 0.88) ??
          tryDemo(true, true, 0.76) ??
          tryDemo(true, false, 0.76);
      if (withDemo != null) return withDemo;
    }

    // Tanpa mini-demo (langkah tanpa demo, atau ruang terlalu sempit).
    if (fixedHeight(false, true) <= availH) return makePlan(false, true, 0);
    if (fixedHeight(true, true) <= availH) return makePlan(true, true, 0);
    return makePlan(true, false, 0);
  }

  Widget _buildCard(bool hasTarget, [double maxHeight = 420]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.min(constraints.maxWidth, 420.0);
        final plan = _planCard(context, cardWidth, maxHeight);

        return Container(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
          padding: const EdgeInsets.fromLTRB(
            _kCardHPad,
            _kCardVPad,
            _kCardHPad,
            _kCardVPad,
          ),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder, width: _kCardBorderW),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Isi kartu. Hanya bagian ini yang bisa di-scroll (cadangan saja,
              // bila ruang benar-benar tidak cukup).
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(plan),
                      SizedBox(height: plan.gapHeader),
                      Text(_step.body, style: _kBodyStyle),
                      if (plan.showTip) ...[
                        SizedBox(height: plan.gapBlock),
                        _buildTip(),
                      ],
                      if (plan.demoHeight > 0) ...[
                        SizedBox(height: plan.gapBlock),
                        _ScaledDemo(
                          type: _step.demo,
                          accent: _step.accent,
                          height: plan.demoHeight,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: plan.gapActions),
              // Tombol aksi — selalu terlihat, tidak ikut ter-scroll.
              _buildActions(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(_CardPlan plan) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _robotBob,
          builder: (_, __) {
            return Transform.translate(
              offset: Offset(0, -3 * math.sin(_robotBob.value * math.pi)),
              child: TutorRobot(
                size: plan.robot,
                accent: _step.accent,
                mood: _isLast
                    ? RobotMood.happy
                    : (_isFirst ? RobotMood.wave : RobotMood.talk),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _step.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _step.accent.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      _pillLabel,
                      style: _kPillStyle.copyWith(color: _step.accent),
                    ),
                  ),
                  const Spacer(),
                  Icon(_step.icon, size: 16, color: _step.accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(_step.title, style: _kTitleStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 13, color: _step.accent),
          const SizedBox(width: 6),
          Expanded(child: Text(_step.tip, style: _kTipStyle)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        if (!_isLast)
          TextButton(
            onPressed: _finish,
            style: TextButton.styleFrom(
              foregroundColor: _kMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            child: const Text('Lewati', style: TextStyle(fontSize: 13)),
          ),
        const Spacer(),
        FilledButton(
          onPressed: _next,
          style: FilledButton.styleFrom(
            backgroundColor: _step.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            _isLast ? 'Mulai Pakai' : (_isFirst ? 'Mulai Tour' : 'Lanjut'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPOTLIGHT PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _SpotlightPainter extends CustomPainter {
  final RRect? hole;
  final double pulse;

  _SpotlightPainter({required this.hole, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withOpacity(0.72),
      );
      return;
    }
    final cut = Path()..addRRect(hole!);
    final dim = Path.combine(PathOperation.difference, full, cut);
    canvas.drawPath(
      dim,
      Paint()..color = Colors.black.withOpacity(0.72),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse;
}

// ═══════════════════════════════════════════════════════════════════════════
// ROBOT ROUND — konsisten tema indigo/cyan
// ═══════════════════════════════════════════════════════════════════════════

enum RobotMood { idle, wave, talk, happy }

class TutorRobot extends StatelessWidget {
  final double size;
  final Color accent;
  final RobotMood mood;

  const TutorRobot({
    super.key,
    this.size = 56,
    this.accent = _kIndigo,
    this.mood = RobotMood.idle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RobotPainter(accent: accent, mood: mood),
      ),
    );
  }
}

class _RobotPainter extends CustomPainter {
  final Color accent;
  final RobotMood mood;

  _RobotPainter({required this.accent, required this.mood});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final r = s * 0.42;

    // Soft glow
    canvas.drawCircle(
      c,
      r + 4,
      Paint()
        ..color = accent.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Body gradient circle
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(accent, Colors.white, 0.15)!,
          accent,
          Color.lerp(accent, const Color(0xFF312E81), 0.45)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, bodyPaint);

    // Inner ring
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withOpacity(0.18),
    );

    // Antenna
    final antTop = Offset(c.dx, c.dy - r - s * 0.08);
    canvas.drawLine(
      Offset(c.dx, c.dy - r + 2),
      antTop,
      Paint()
        ..color = _kCyan
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      antTop,
      s * 0.045,
      Paint()..color = _kCyan,
    );

    // Face panel
    final faceR = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + s * 0.02),
        width: r * 1.35,
        height: r * 1.05,
      ),
      Radius.circular(r * 0.45),
    );
    canvas.drawRRect(
      faceR,
      Paint()..color = const Color(0xFF0B1220).withOpacity(0.55),
    );

    // Eyes
    final eyeY = c.dy - s * 0.02;
    final eyeDx = s * 0.12;
    final eyeR = s * 0.055;
    final eyePaint = Paint()..color = _kCyan;
    final eyeGlow = Paint()
      ..color = _kCyan.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    if (mood == RobotMood.happy) {
      // Happy arcs
      final leftPath = Path()
        ..moveTo(c.dx - eyeDx - eyeR, eyeY)
        ..quadraticBezierTo(
          c.dx - eyeDx,
          eyeY + eyeR * 1.2,
          c.dx - eyeDx + eyeR,
          eyeY,
        );
      final rightPath = Path()
        ..moveTo(c.dx + eyeDx - eyeR, eyeY)
        ..quadraticBezierTo(
          c.dx + eyeDx,
          eyeY + eyeR * 1.2,
          c.dx + eyeDx + eyeR,
          eyeY,
        );
      final smileStroke = Paint()
        ..color = _kCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(leftPath, smileStroke);
      canvas.drawPath(rightPath, smileStroke);
    } else {
      canvas.drawCircle(Offset(c.dx - eyeDx, eyeY), eyeR + 2, eyeGlow);
      canvas.drawCircle(Offset(c.dx + eyeDx, eyeY), eyeR + 2, eyeGlow);
      canvas.drawCircle(Offset(c.dx - eyeDx, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(c.dx + eyeDx, eyeY), eyeR, eyePaint);
      // Pupils
      canvas.drawCircle(
        Offset(c.dx - eyeDx + 1, eyeY - 0.5),
        eyeR * 0.4,
        Paint()..color = Colors.white.withOpacity(0.9),
      );
      canvas.drawCircle(
        Offset(c.dx + eyeDx + 1, eyeY - 0.5),
        eyeR * 0.4,
        Paint()..color = Colors.white.withOpacity(0.9),
      );
    }

    // Mouth
    final mouthY = c.dy + s * 0.12;
    if (mood == RobotMood.talk) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx, mouthY),
            width: s * 0.14,
            height: s * 0.08,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = _kCyan.withOpacity(0.85),
      );
    } else if (mood == RobotMood.happy) {
      final smile = Path()
        ..moveTo(c.dx - s * 0.09, mouthY - 1)
        ..quadraticBezierTo(c.dx, mouthY + s * 0.07, c.dx + s * 0.09, mouthY - 1);
      canvas.drawPath(
        smile,
        Paint()
          ..color = _kCyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else if (mood == RobotMood.wave) {
      canvas.drawLine(
        Offset(c.dx - s * 0.07, mouthY),
        Offset(c.dx + s * 0.07, mouthY),
        Paint()
          ..color = _kCyan.withOpacity(0.8)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawLine(
        Offset(c.dx - s * 0.06, mouthY),
        Offset(c.dx + s * 0.06, mouthY),
        Paint()
          ..color = _kCyan.withOpacity(0.7)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Cheek dots
    canvas.drawCircle(
      Offset(c.dx - s * 0.2, c.dy + s * 0.06),
      s * 0.03,
      Paint()..color = accent.withOpacity(0.35),
    );
    canvas.drawCircle(
      Offset(c.dx + s * 0.2, c.dy + s * 0.06),
      s * 0.03,
      Paint()..color = accent.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _RobotPainter old) =>
      old.accent != accent || old.mood != mood;
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI DEMO ANIMATIONS — skenario lengkap, multi-fase, informatif
// ═══════════════════════════════════════════════════════════════════════════

/// Menampilkan [_MiniDemo] pada tinggi [height]. Demo selalu digambar pada
/// tinggi desainnya (agar isinya tidak meluap), lalu diperkecil proporsional
/// bila [height] lebih kecil — seperti miniatur layar.
class _ScaledDemo extends StatelessWidget {
  final TutorDemoType type;
  final Color accent;
  final double height;

  const _ScaledDemo({
    required this.type,
    required this.accent,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final designH = _demoDesignHeight(type);
    if (designH <= 0) return const SizedBox.shrink();
    final scale = math.min(1.0, height / designH);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          width: width,
          height: designH * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            child: SizedBox(
              // Lebar kanvas dilebarkan 1/scale agar setelah diperkecil
              // tetap persis selebar kartu.
              width: width / scale,
              height: designH,
              child: _MiniDemo(type: type, accent: accent, height: designH),
            ),
          ),
        );
      },
    );
  }
}

class _MiniDemo extends StatefulWidget {
  final TutorDemoType type;
  final Color accent;
  final double height;

  const _MiniDemo({
    required this.type,
    required this.accent,
    this.height = 148,
  });

  @override
  State<_MiniDemo> createState() => _MiniDemoState();
}

class _MiniDemoState extends State<_MiniDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      // Tinggi baris teks demo dipatok 1.2× (bukan 1.43× bawaan Material 3)
      // supaya isi demo muat pada tinggi desainnya (_demoDesignHeight).
      child: DefaultTextStyle.merge(
        style: const TextStyle(height: 1.2),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => _buildContent(_ctrl.value),
        ),
      ),
    );
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  int _phase(double t, int count) => (t * count).floor().clamp(0, count - 1);

  Widget _scenarioHeader(String caption, int phase, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        border: Border(bottom: BorderSide(color: _kBorder.withOpacity(0.8))),
      ),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, size: 13, color: widget.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: widget.accent,
              ),
            ),
          ),
          Text(
            '${phase + 1}/$total',
            style: const TextStyle(fontSize: 9.5, color: _kMuted),
          ),
        ],
      ),
    );
  }

  Widget _stepDots(int phase, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i == phase;
        final done = i < phase;
        return Container(
          width: on ? 14 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: on
                ? widget.accent
                : (done ? widget.accent.withOpacity(0.45) : const Color(0xFF374151)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _chip(String label, {bool active = false, Color? color}) {
    final c = color ?? widget.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: active ? c.withOpacity(0.18) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: active ? c.withOpacity(0.55) : _kBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? c : _kMuted,
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _fakeField({required String hint, required bool filled, String? value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filled ? widget.accent.withOpacity(0.5) : _kBorder,
        ),
      ),
      child: Text(
        filled ? (value ?? '') : hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontFamily: filled ? 'monospace' : null,
          color: filled ? Colors.white : const Color(0xFF4B5563),
        ),
      ),
    );
  }

  Widget _buildContent(double t) {
    switch (widget.type) {
      case TutorDemoType.pasteLinks:
        return _demoPaste(t);
      case TutorDemoType.modeSwitch:
        return _demoModes(t);
      case TutorDemoType.convertPulse:
        return _demoConvert(t);
      case TutorDemoType.outputActions:
        return _demoOutput(t);
      case TutorDemoType.coreNav:
        return _demoNav(t);
      case TutorDemoType.bugWildcard:
        return _demoBug(t);
      case TutorDemoType.studioCustom:
        return _demoStudio(t);
      case TutorDemoType.none:
        return const SizedBox.shrink();
    }
  }

  // ─── 1. PASTE LINKS — skenario lengkap ───────────────────────────────────

  Widget _demoPaste(double t) {
    // Fase: 0 kosong → 1 tempel → 2 parsing → 3 node terdeteksi → 4 siap
    const total = 5;
    final phase = _phase(t, total);
    final captions = [
      'Kotak tautan masih kosong',
      'Tempel 3 link dari clipboard',
      'Parser offline membaca protokol…',
      '3 node terdeteksi & dikelompokkan',
      'Siap dikonversi ke config',
    ];
    final links = [
      'vmess://eyJ2IjoiMiIsInBzIjoi...',
      'vless://a1b2c3d4@sg.example.com:443',
      'trojan://secret@jp.example.com:443',
    ];
    final nodes = [
      ('SG-01', 'VMess', const Color(0xFF06B6D4)),
      ('JP-02', 'VLESS', const Color(0xFF818CF8)),
      ('US-03', 'Trojan', const Color(0xFFF59E0B)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fake input area
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: phase >= 1
                            ? widget.accent.withOpacity(0.45)
                            : _kBorder,
                      ),
                    ),
                    child: phase == 0
                        ? Text(
                            'Tempel link proxy satu per baris:\nvmess://...\nvless://...',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFF4B5563),
                              height: 1.35,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(3, (i) {
                              final show = phase >= 1 && (phase >= 2 || i == 0) &&
                                  (phase >= 3 || i <= 1 || phase == 1 && i == 0);
                              // Progressive reveal
                              final visible = phase == 1
                                  ? i == 0
                                  : phase == 2
                                      ? i <= 1
                                      : true;
                              return Opacity(
                                opacity: visible ? 1 : 0.2,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    links[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      color: visible ? Colors.white : _kMuted,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                  ),
                ),
                if (phase >= 3) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Node Terdeteksi (3)',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _kMuted,
                        ),
                      ),
                      const Spacer(),
                      if (phase >= 4)
                        _badge('Siap', const Color(0xFF10B981)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: nodes
                        .map((n) => _chip('${n.$1} · ${n.$2}',
                            active: true, color: n.$3))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  // ─── 2. MODE SWITCH — skenario pemilihan mode ────────────────────────────

  Widget _demoModes(double t) {
    const total = 4;
    final phase = _phase(t, total);
    final captions = [
      'Pilih Minimal — config ringan, 2 grup',
      'Pilih Lengkap — 50+ rule-set siap pakai',
      'Pilih Custom — atur DNS & rules sendiri',
      'Banner & tag ikut berubah sesuai mode',
    ];
    final modes = [
      ('Minimal', Icons.bolt, const Color(0xFF10B981),
          '2 grup · tanpa rule-set · MATCH all'),
      ('Lengkap', Icons.layers, const Color(0xFF06B6D4),
          '30+ grup · 50+ rule-set · DNS berlapis'),
      ('Custom', Icons.auto_awesome, const Color(0xFF6366F1),
          'DNS · rules · GeoIP lewat Studio'),
    ];
    final activeIdx = phase == 3 ? 2 : phase.clamp(0, 2);
    final m = modes[activeIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              children: [
                Row(
                  children: List.generate(3, (i) {
                    final on = i == activeIdx;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: on
                                ? modes[i].$3.withOpacity(0.15)
                                : const Color(0xFF0D131F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: on
                                  ? modes[i].$3.withOpacity(0.6)
                                  : _kBorder,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(modes[i].$2,
                                  size: 16,
                                  color: on ? modes[i].$3 : _kMuted),
                              const SizedBox(height: 3),
                              Text(
                                modes[i].$1,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight:
                                      on ? FontWeight.bold : FontWeight.normal,
                                  color: on ? Colors.white : _kMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        m.$3.withOpacity(0.22),
                        const Color(0xFF0E1422),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: m.$3.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode ${m.$1} Aktif',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color.lerp(m.$3, Colors.white, 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.$4,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  // ─── 3. CONVERT — skenario menekan tombol & hasil ────────────────────────

  Widget _demoConvert(double t) {
    const total = 5;
    final phase = _phase(t, total);
    final captions = [
      'Link sudah diisi, mode Minimal aktif',
      'Tekan tombol Konversi…',
      'Membangun grup & DNS…',
      'Menyusun rule-set…',
      'Konfigurasi YAML/JSON siap!',
    ];
    final progress = phase <= 1
        ? 0.0
        : phase == 2
            ? 0.4
            : phase == 3
                ? 0.75
                : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              children: [
                // Status chips
                Row(
                  children: [
                    _badge('3 node', const Color(0xFF06B6D4)),
                    const SizedBox(width: 6),
                    _badge('Minimal', const Color(0xFF10B981)),
                    const Spacer(),
                    if (phase >= 4)
                      _badge('Selesai', const Color(0xFF10B981)),
                  ],
                ),
                const Spacer(),
                // Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: phase == 1
                        ? Color.lerp(widget.accent, Colors.white, 0.12)
                        : widget.accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: phase == 1
                        ? [
                            BoxShadow(
                              color: widget.accent.withOpacity(0.45),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (phase >= 2 && phase < 4)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(
                          phase >= 4
                              ? Icons.check_rounded
                              : Icons.play_arrow_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        phase >= 4
                            ? 'Konfigurasi Siap'
                            : (phase >= 2
                                ? 'Memproses…'
                                : 'Konversi & Perbarui'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF1F2937),
                    color: phase >= 4
                        ? const Color(0xFF10B981)
                        : widget.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phase >= 4
                      ? 'clash-config.yaml · 12 KB'
                      : (phase >= 2
                          ? 'Membangun konfigurasi offline…'
                          : 'Tekan untuk menghasilkan config'),
                  style: const TextStyle(fontSize: 9, color: _kMuted),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  // ─── 4. OUTPUT ACTIONS — salin / bagikan / simpan ────────────────────────

  Widget _demoOutput(double t) {
    const total = 4;
    final phase = _phase(t, total);
    final captions = [
      'Hasil config muncul di panel bawah',
      'Salin ke clipboard — siap tempel di app',
      'Bagikan file ke aplikasi lain',
      'Simpan ke folder Download perangkat',
    ];
    final actions = [
      (Icons.copy_rounded, 'Salin', 'Disalin ke clipboard!'),
      (Icons.share_rounded, 'Bagikan', 'Membuka share sheet…'),
      (Icons.save_alt_rounded, 'Simpan', 'Download/clash-config.yaml'),
    ];
    final activeAction = phase == 0 ? -1 : (phase - 1).clamp(0, 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              children: [
                // Fake code preview
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Text(
                      phase == 0
                          ? '# Hasil konversi akan muncul di sini'
                          : 'proxies:\n  - name: SG-01\n    type: vmess\n    server: sg.example.com\n…',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        height: 1.3,
                        color: phase == 0
                            ? const Color(0xFF6B7280)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(3, (i) {
                    final on = i == activeAction;
                    return Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: on
                                ? widget.accent.withOpacity(0.2)
                                : const Color(0xFF0D131F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: on
                                  ? widget.accent.withOpacity(0.6)
                                  : _kBorder,
                            ),
                          ),
                          child: Icon(
                            actions[i].$1,
                            size: 18,
                            color: on ? widget.accent : _kMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          actions[i].$2,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight:
                                on ? FontWeight.bold : FontWeight.normal,
                            color: on ? widget.accent : _kMuted,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                if (activeAction >= 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    actions[activeAction].$3,
                    style: TextStyle(
                      fontSize: 9,
                      color: const Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  // ─── 5. CORE NAV — beralih Clash ↔ Sing-box ──────────────────────────────

  Widget _demoNav(double t) {
    const total = 4;
    final phase = _phase(t, total);
    final captions = [
      'Saat ini di Clash Meta (YAML)',
      'Ketuk Sing-box — beralih inti',
      'Mode & hasil tersimpan per inti',
      'Kembali ke Clash Meta kapan saja',
    ];
    final isClash = phase == 0 || phase == 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                // Floating nav mock
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _navItem(
                          'Clash Meta',
                          'YAML',
                          Icons.hub_outlined,
                          isClash,
                          const Color(0xFFF59E0B),
                        ),
                      ),
                      Container(
                          width: 1, height: 24, color: _kBorder),
                      Expanded(
                        child: _navItem(
                          'Sing-box',
                          'JSON',
                          Icons.terminal_rounded,
                          !isClash,
                          const Color(0xFF06B6D4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Side-by-side result hint
                Row(
                  children: [
                    Expanded(
                      child: _coreResultCard(
                        'Clash Meta',
                        '.yaml',
                        isClash,
                        const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _coreResultCard(
                        'Sing-box',
                        '.json',
                        !isClash,
                        const Color(0xFF06B6D4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  Widget _navItem(
      String label, String sub, IconData icon, bool on, Color accent) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: on ? accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: on ? accent : _kMuted),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: on ? FontWeight.bold : FontWeight.normal,
              color: on ? Colors.white : _kMuted,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 8.5,
              color: on ? accent : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coreResultCard(
      String name, String ext, bool active, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: active ? accent.withOpacity(0.1) : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? accent.withOpacity(0.45) : _kBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.circle_outlined,
            size: 12,
            color: active ? accent : _kMuted,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              active ? '$name aktif$ext' : '$name tersimpan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: active ? accent : _kMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. BUG WILDCARD — skenario lengkap ──────────────────────────────────

  Widget _demoBug(double t) {
    const total = 5;
    final phase = _phase(t, total);
    final captions = [
      'Isi domain bug di kolom Input Bug',
      'Ketuk kartu Wildcard untuk pilih mode',
      'Mode Timpa SNI dipilih',
      'Preview: servername diganti ke bug',
      'Semua node menerapkan bug host',
    ];
    final modes = [
      'Wildcard biasa',
      'Timpa SNI',
      'Timpa server & WS Host',
      'Timpa server saja',
    ];
    final selectedMode = phase >= 2 ? 1 : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Input Bug',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _kMuted)),
                          const SizedBox(height: 3),
                          _fakeField(
                            hint: 'contoh: Bug.com',
                            filled: phase >= 1,
                            value: 'bug.example.com',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mode Wildcard',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _kMuted)),
                          const SizedBox(height: 3),
                          _fakeField(
                            hint: 'Isi Input Bug dulu',
                            filled: phase >= 2,
                            value: phase >= 2
                                ? 'Mode: ${modes[selectedMode]}'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (phase >= 2 && phase < 4) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: List.generate(4, (i) {
                      return _chip(modes[i], active: i == selectedMode);
                    }),
                  ),
                ],
                if (phase >= 3) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: widget.accent.withOpacity(0.35)),
                    ),
                    child: Text(
                      phase >= 4
                          ? '✓ 3 node · servername="bug.example.com"'
                          : 'Preview: servername="bug.example.com"',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'monospace',
                        color: widget.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }

  // ─── 7. STUDIO CUSTOM — tab Rules/DNS/Geo/Routing ────────────────────────

  Widget _demoStudio(double t) {
    const total = 5;
    final phase = _phase(t, total);
    final captions = [
      'Buka Studio Custom — 4 tab pengaturan',
      'Rules: aktifkan Anti-Ads & Streaming',
      'DNS: pilih Cloudflare + Fake-IP',
      'Geo: bypass IP Indonesia & LAN',
      'Routing: AUTO-TERCEPAT + TUN opsional',
    ];
    final tabs = ['Rules', 'DNS', 'Geo', 'Routing'];
    final tabIdx = phase == 0 ? 0 : (phase - 1).clamp(0, 3);
    final previews = [
      ['🛡️ Anti-Ads', '🎬 Streaming', '🎮 Gaming'],
      ['Cloudflare', 'Fake-IP', 'IPv4 Only'],
      ['GeoIP ID → DIRECT', 'LAN → DIRECT'],
      ['AUTO-TERCEPAT', 'Interval 5 mnt', 'TUN off'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scenarioHeader(captions[phase], phase, total),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              children: [
                Row(
                  children: List.generate(4, (i) {
                    final on = i == tabIdx;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
                        child: _chip(tabs[i], active: on),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: previews[tabIdx].map((p) {
                        return _chip(p, active: phase > 0, color: widget.accent);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _stepDots(phase, total),
        ),
      ],
    );
  }
}
