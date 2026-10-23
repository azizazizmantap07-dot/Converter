import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key: dialog izin sudah pernah ditampilkan sejak install (sekali saja).
const _kStoragePermissionPrompted = 'storage_permission_prompted_v1';

/// Layar peluncuran animasi + permintaan izin penyimpanan sekali (tema gelap indigo).
class LaunchScreen extends StatefulWidget {
  final Widget home;

  const LaunchScreen({super.key, required this.home});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _pulse;
  late final AnimationController _orbit;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _ringExpand;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _barProgress;
  late final Animation<double> _fadeOut;

  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090D16),
    ));

    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.12).chain(CurveTween(curve: Curves.easeOutBack)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
    ]).animate(_master);

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.0, 0.25, curve: Curves.easeOut)),
    );

    _ringExpand = Tween<double>(begin: 0.6, end: 1.35).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.15, 0.55, curve: Curves.easeOutCubic)),
    );

    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.35, 0.55, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.35, 0.55, curve: Curves.easeOutCubic)),
    );
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.48, 0.68, curve: Curves.easeOut)),
    );
    _barProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.4, 0.88, curve: Curves.easeInOutCubic)),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.88, 1.0, curve: Curves.easeIn)),
    );

    _master.forward().whenComplete(_onAnimationDone);
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
    _pulse.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: AnimatedBuilder(
        animation: Listenable.merge([_master, _pulse, _orbit]),
        builder: (context, _) {
          final pulse = 0.85 + (_pulse.value * 0.15);
          return Opacity(
            opacity: _fadeOut.value.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background gradient + soft glow
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.25),
                      radius: 1.15,
                      colors: [
                        Color(0xFF1A1F3A),
                        Color(0xFF090D16),
                        Color(0xFF06080F),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
                // Ambient indigo glow
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.22,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 220 * pulse,
                      height: 220 * pulse,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.22 * _logoOpacity.value),
                            blurRadius: 80,
                            spreadRadius: 10,
                          ),
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.08 * _logoOpacity.value),
                            blurRadius: 100,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Orbiting dots
                ..._buildOrbitDots(context),
                // Main content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Expanding ring behind logo
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: (1.0 - ((_ringExpand.value - 0.6) / 0.75).clamp(0.0, 1.0)) * _logoOpacity.value,
                              child: Transform.scale(
                                scale: _ringExpand.value,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF6366F1).withOpacity(0.35),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Opacity(
                              opacity: _logoOpacity.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF818CF8),
                                        Color(0xFF6366F1),
                                        Color(0xFF4F46E5),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1).withOpacity(0.45),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.hub_rounded,
                                    size: 42,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Title
                      Opacity(
                        opacity: _titleOpacity.value,
                        child: Transform.translate(
                          offset: Offset(0, _titleSlide.value),
                          child: const Text(
                            'Proxy Converter',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: _subtitleOpacity.value,
                        child: const Text(
                          'Clash Meta  ·  Sing-box  ·  Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      // Progress bar
                      Opacity(
                        opacity: _subtitleOpacity.value,
                        child: SizedBox(
                          width: 140,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _barProgress.value,
                              minHeight: 3,
                              backgroundColor: const Color(0xFF1F2937),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Footer
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 36 + MediaQuery.of(context).padding.bottom,
                  child: Opacity(
                    opacity: _subtitleOpacity.value * 0.7,
                    child: const Text(
                      'Konfigurasi privat · Tanpa server',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildOrbitDots(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    const radius = 78.0;
    final dots = <Widget>[];
    for (var i = 0; i < 3; i++) {
      final angle = (_orbit.value * 2 * math.pi) + (i * 2 * math.pi / 3);
      final dx = cx + radius * math.cos(angle) - 4;
      final dy = cy + radius * math.sin(angle) - 4;
      dots.add(
        Positioned(
          left: dx,
          top: dy,
          child: Opacity(
            opacity: 0.55 * _logoOpacity.value,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == 0
                    ? const Color(0xFF818CF8)
                    : i == 1
                        ? const Color(0xFF06B6D4)
                        : const Color(0xFFA78BFA),
                boxShadow: [
                  BoxShadow(
                    color: (i == 0
                            ? const Color(0xFF6366F1)
                            : i == 1
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFFA78BFA))
                        .withOpacity(0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return dots;
  }
}
