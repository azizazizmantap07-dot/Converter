import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'converter.dart';
import 'splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF090D16),
  ));
  runApp(const ProxyConverterApp());
}

class ProxyConverterApp extends StatelessWidget {
  const ProxyConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxy Converter & Config Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo
          secondary: Color(0xFF06B6D4), // Cyan
          surface: Color(0xFF111827), // Slate 900
          outline: Color(0xFF1F2937), // Slate 800
        ),
        fontFamily: 'sans-serif',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D131F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1F2937)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1F2937)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF111827),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F2937)),
          ),
        ),
      ),
      home: const LaunchScreen(home: HomePage()),
    );
  }
}

enum OutputTarget { clash, singbox, both }
enum ConverterModeType { minimal, lengkap, custom }

/// Data tampilan banner yang berubah mengikuti mode konversi yang dipilih.
class _ModeInfo {
  final String label;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<String> tags;

  const _ModeInfo({
    required this.label,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.tags,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _inputController = TextEditingController();
  final _searchController = TextEditingController();

  OutputTarget _target = OutputTarget.both;
  ConverterModeType _mode = ConverterModeType.custom;
  String _activeResultTab = 'clash'; // 'clash' | 'singbox'
  String _customStudioTab = 'rules'; // 'rules' | 'dns' | 'geo' | 'routing'

  // Custom Addons State
  String _primaryDns = 'cloudflare';
  String _customPrimaryDnsUrl = '';
  String _secondaryDns = 'google';
  String _dnsStrategy = 'ipv4_only';
  bool _fakeIp = true;
  bool _directBankDns = true;

  bool _antiAds = true;
  bool _aiRouting = true;
  bool _streamingRouting = true;
  bool _gamingRouting = false;
  bool _domesticBypass = true;
  bool _blockTorrent = true;
  bool _blockQuic = false;

  final List<CustomRuleItem> _customRules = [];
  String _newRuleType = 'DOMAIN-SUFFIX';
  final _newRulePayloadController = TextEditingController();
  String _newRuleTarget = 'DIRECT';

  bool _geoipId = true;
  bool _privateIp = true;

  String _mainGroupName = 'PILIH-PROXY';
  bool _autoFastest = true;
  int _urlTestInterval = 300;
  int _mixedPort = 7890;
  bool _tunEnabled = false;

  // Controller dibuat sekali di state (bukan di build) agar kursor tidak loncat
  // dan teks tidak ter-reset setiap kali _convert() memicu rebuild.
  final _mainGroupController = TextEditingController(text: 'PILIH-PROXY');
  final _mixedPortController = TextEditingController(text: '7890');
  final _customDnsController = TextEditingController();
  final _bugController = TextEditingController();

  /// Mode wildcard bug yang aktif (none = tidak diterapkan).
  BugWildcardMode _bugMode = BugWildcardMode.none;

  List<Node> _parsedNodes = [];
  String _clashOutput = '';
  String _singboxOutput = '';
  String? _status;
  bool _isSuccessStatus = true;
  bool _busy = false;

  @override
  void dispose() {
    _inputController.dispose();
    _searchController.dispose();
    _newRulePayloadController.dispose();
    _mainGroupController.dispose();
    _mixedPortController.dispose();
    _customDnsController.dispose();
    _bugController.dispose();
    super.dispose();
  }

  void _parseNodesFromInput() {
    final nodes = parseLinks(_inputController.text);
    setState(() {
      _parsedNodes = nodes;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _inputController.text = data.text!;
      });
      _convert(showEmptyError: true);
    }
  }

  void _clearInput() {
    setState(() {
      _inputController.clear();
      _parsedNodes = [];
      _clashOutput = '';
      _singboxOutput = '';
      _status = null;
    });
  }

  Future<String> _loadTemplate(String assetPath) async {
    return rootBundle.loadString(assetPath);
  }

  void _applyPreset(String key) {
    setState(() {
      if (key == 'balanced') {
        _antiAds = true;
        _aiRouting = true;
        _streamingRouting = true;
        _gamingRouting = false;
        _domesticBypass = true;
        _blockTorrent = true;
        _blockQuic = false;
      } else if (key == 'gaming') {
        _antiAds = true;
        _aiRouting = false;
        _streamingRouting = false;
        _gamingRouting = true;
        _domesticBypass = true;
        _blockTorrent = true;
        _blockQuic = true;
        _urlTestInterval = 60;
        _tunEnabled = true;
      } else if (key == 'privacy') {
        _primaryDns = 'adguard';
        _secondaryDns = 'quad9';
        _antiAds = true;
        _aiRouting = true;
        _streamingRouting = false;
        _gamingRouting = false;
        _domesticBypass = true;
        _blockTorrent = true;
      } else if (key == 'clean') {
        _antiAds = false;
        _aiRouting = false;
        _streamingRouting = false;
        _gamingRouting = false;
        _domesticBypass = true;
        _blockTorrent = false;
        _blockQuic = false;
      }
    });
    _convert();
  }

  void _addCustomRule() {
    final payload = _newRulePayloadController.text.trim();
    if (payload.isEmpty) return;
    setState(() {
      _customRules.add(CustomRuleItem(
        id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
        type: _newRuleType,
        payload: payload,
        target: _newRuleTarget,
      ));
      _newRulePayloadController.clear();
    });
    _convert();
  }

  void _removeCustomRule(String id) {
    setState(() {
      _customRules.removeWhere((r) => r.id == id);
    });
    _convert();
  }

  /// [showEmptyError] hanya true saat pengguna menekan tombol Konversi / Tempel;
  /// pemanggilan otomatis (mengetik, toggle opsi) tidak memunculkan pesan error.
  Future<void> _convert({bool showEmptyError = false}) async {
    _parseNodesFromInput();
    if (_parsedNodes.isEmpty) {
      setState(() {
        _clashOutput = '';
        _singboxOutput = '';
        if (showEmptyError) {
          _status = _inputController.text.trim().isEmpty
              ? 'Tempel minimal satu link vmess/vless/trojan terlebih dahulu.'
              : 'Tidak ada link vmess/vless/trojan yang valid.';
          _isSuccessStatus = false;
        } else {
          _status = null;
        }
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      // Terapkan bug/wildcard ke salinan node sebelum generate config
      final nodesForOutput = applyBugWildcard(
        _parsedNodes,
        _bugController.text,
        _bugMode,
      );

      if (_mode == ConverterModeType.custom) {
        final opts = CustomAddonOptions(
          primaryDns: _primaryDns,
          customPrimaryUrl: _customPrimaryDnsUrl,
          secondaryDns: _secondaryDns,
          dnsStrategy: _dnsStrategy,
          enableFakeIp: _fakeIp,
          directDomesticBankingDns: _directBankDns,
          enableAntiAds: _antiAds,
          enableAiRouting: _aiRouting,
          enableStreamingRouting: _streamingRouting,
          enableGamingRouting: _gamingRouting,
          enableDomesticBypass: _domesticBypass,
          enableBlockTorrent: _blockTorrent,
          enableBlockQuic: _blockQuic,
          customRules: _customRules,
          enableGeoipIdDirect: _geoipId,
          enablePrivateDirect: _privateIp,
          autoCreateRegionGroups: false,
          selectedRegions: const [],
          mainGroupName: _mainGroupName,
          autoFastest: _autoFastest,
          urlTestInterval: _urlTestInterval,
          mixedPort: _mixedPort,
          tunEnabled: _tunEnabled,
        );

        final clashOut = renderClashCustom(nodesForOutput, opts);
        final sbOut = renderSingboxCustom(nodesForOutput, opts);
        if (!mounted) return;
        setState(() {
          _clashOutput = clashOut;
          _singboxOutput = sbOut;
          _status =
              'Berhasil mengonversi ${_parsedNodes.length} node (Mode: ${_mode.name.toUpperCase()}).';
          _isSuccessStatus = true;
          _busy = false;
        });
        return;
      }

      final modeStr = _mode == ConverterModeType.minimal ? 'minimal' : 'lengkap';
      final clashTpl =
          await _loadTemplate('assets/templates/template-clash-$modeStr.yaml');
      final sbTpl =
          await _loadTemplate('assets/templates/template-Singbox-$modeStr.json');
      final clashOut = renderClash(clashTpl, nodesForOutput);
      final sbOut = renderSingbox(sbTpl, nodesForOutput);
      if (!mounted) return;
      setState(() {
        _clashOutput = clashOut;
        _singboxOutput = sbOut;
        _status =
            'Berhasil mengonversi ${_parsedNodes.length} node (Mode: ${_mode.name.toUpperCase()}).';
        _isSuccessStatus = true;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Gagal mengonversi: $e';
        _isSuccessStatus = false;
        _busy = false;
      });
    }
  }

  /// True jika hasil yang sedang ditampilkan adalah Clash (YAML), false jika Sing-box (JSON).
  bool get _isClashResult {
    if (_target == OutputTarget.clash) return true;
    if (_target == OutputTarget.singbox) return false;
    return _activeResultTab == 'clash';
  }

  String get _currentResultText => _isClashResult ? _clashOutput : _singboxOutput;

  /// Isi banner untuk mode yang aktif. Mode Custom ikut menampilkan ringkasan opsi
  /// yang sedang dipilih, jadi banner berubah setiap kali opsi di Studio diubah.
  _ModeInfo get _modeInfo {
    if (_mode == ConverterModeType.minimal) {
      return const _ModeInfo(
        label: 'Minimal',
        icon: Icons.bolt,
        color: Color(0xFF10B981),
        title: 'Konfigurasi Ringkas & Ringan',
        description: 'Template benar-benar minimal: DNS dasar, grup PILIH-PROXY & AUTO-TERCEPAT, tanpa rule-set. Semua traffic lewat proxy (MATCH).',
        tags: ['2 grup', 'tanpa rule-set', 'MATCH all'],
      );
    }
    if (_mode == ConverterModeType.lengkap) {
      return const _ModeInfo(
        label: 'Lengkap',
        icon: Icons.layers,
        color: Color(0xFF06B6D4),
        title: 'Template Siap Pakai, Serba Lengkap',
        description: 'Memakai template lengkap: failover, load-balance, puluhan rule-set layanan, serta DNS berlapis. Tanpa grup regional. Tinggal tempel akun.',
        tags: ['30+ grup', '50+ rule-set', 'DNS berlapis'],
      );
    }

    const dnsLabels = {
      'cloudflare': 'Cloudflare',
      'google': 'Google',
      'adguard': 'AdGuard',
      'quad9': 'Quad9',
      'custom': 'DoH Custom',
    };
    final activeRules = [
      _antiAds,
      _aiRouting,
      _streamingRouting,
      _gamingRouting,
      _domesticBypass,
      _blockTorrent,
      _blockQuic,
    ].where((on) => on).length + _customRules.length;
    return _ModeInfo(
      label: 'Custom',
      icon: Icons.auto_awesome,
      color: const Color(0xFF6366F1),
      title: 'Bangun Konfigurasi Sesuai Kebutuhan Anda',
      description: 'Atur sendiri DNS, rules, dan GeoIP lewat Studio di bawah. Konfigurasi dibuat dari nol sesuai pilihanmu.',
      tags: [
        'DNS ${dnsLabels[_primaryDns] ?? _primaryDns}',
        '$activeRules aturan aktif',
        if (_tunEnabled) 'TUN',
      ],
    );
  }

  /// Banner di bagian atas halaman; warna, ikon, teks, dan tag-nya mengikuti mode terpilih.
  Widget _buildModeBanner() {
    final info = _modeInfo;
    final soft = Color.lerp(info.color, Colors.white, 0.6)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [info.color.withOpacity(0.28), const Color(0xFF0E1422)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: info.color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: SizedBox(
            key: ValueKey(_mode),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: info.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: info.color.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(info.icon, size: 12, color: info.color),
                      const SizedBox(width: 4),
                      Text('Mode ${info.label} Aktif', style: TextStyle(fontSize: 10, color: soft, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(info.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(info.description, style: const TextStyle(fontSize: 11, height: 1.35, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: info.tags.map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D131F).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: info.color.withOpacity(0.35)),
                      ),
                      child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: soft)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyOutput() async {
    final text = _currentResultText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Konfigurasi disalin ke clipboard!'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  Future<void> _shareOutput() async {
    final text = _currentResultText;
    if (text.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final ext = _isClashResult ? 'yaml' : 'json';
    final file = File('${dir.path}/config_converted.$ext');
    await file.writeAsString(text);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Konfigurasi Proxy Hasil Konversi',
    );
  }

  Future<void> _saveOutput() async {
    final text = _currentResultText;
    if (text.isEmpty) return;

    final ext = _isClashResult ? 'yaml' : 'json';
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final prefix = _isClashResult ? 'clash' : 'singbox';
    final defaultBase = '${prefix}_config_$stamp';

    // Popup nama file kustom (opsional — Lewati = pakai nama default)
    final customName = await _showSaveFilenameDialog(defaultBase, ext);
    if (customName == null) return; // dibatalkan

    final base = customName.trim().isEmpty ? defaultBase : customName.trim();
    // Hapus ekstensi jika user mengetik ulang, lalu pakai ekstensi yang benar
    var cleanBase = base;
    if (cleanBase.toLowerCase().endsWith('.$ext')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - ext.length - 1);
    }
    cleanBase = cleanBase
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    if (cleanBase.isEmpty) cleanBase = defaultBase;
    final fileName = '$cleanBase.$ext';

    try {
      const downloadPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('$downloadPath/$fileName');
      await file.writeAsString(text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Disimpan ke: Download/$fileName'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal menyimpan ke Download. Pastikan izin penyimpanan diberikan.\n$e',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Dialog penamaan file. Return null = batal, '' / teks = nama (kosong = default via Lewati).
  Future<String?> _showSaveFilenameDialog(String defaultBase, String ext) {
    final controller = TextEditingController(text: defaultBase);
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'nama-file',
      barrierColor: Colors.black.withOpacity(0.72),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, secondary) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: math.min(MediaQuery.of(ctx).size.width - 48, 340),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF141B2D), Color(0xFF0D131F)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.16),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6366F1).withOpacity(0.15),
                              border: Border.all(
                                color: const Color(0xFF6366F1).withOpacity(0.4),
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_document,
                              size: 20,
                              color: Color(0xFFA5B4FC),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nama File Konfigurasi',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Opsional — bisa dilewati',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Nama file',
                          labelStyle: const TextStyle(fontSize: 12),
                          suffixText: '.$ext',
                          suffixStyle: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF818CF8),
                            fontFamily: 'monospace',
                          ),
                          hintText: defaultBase,
                          hintStyle: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        onSubmitted: (v) => Navigator.of(ctx).pop(v),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Disimpan ke /storage/emulated/0/Download/',
                        style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(''),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF9CA3AF),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                'Lewati',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.of(ctx).pop(controller.text),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Simpan',
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

  void _showGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF1F2937))),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF06B6D4), size: 22),
            SizedBox(width: 8),
            Text('Alur Kerja Mode Custom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Ekstraksi Link:\n'
                'Parser mengurai vmess, vless reality, dan trojan secara offline.\n\n'
                '2. Addon Modular:\n'
                '• DNS: Cloudflare/Google/AdGuard/Quad9 + Anti DNS Leak\n'
                '• Rules: Anti-Ads, AI ChatGPT, Streaming Netflix/YT, Gaming, Bypass Bank Indonesia, BitTorrent block\n'
                '• Geo: GeoIP Indonesia Direct & Private/LAN Direct\n\n'
                '3. Generator:\n'
                'Menghasilkan berkas konfigurasi valid untuk Clash Meta (YAML) dan Sing-box (JSON v1.8+).',
                style: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB), height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1422),
        elevation: 0,
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF06B6D4)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.layers, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proxy Converter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Clash Meta & Sing-box Builder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 12, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text('Offline', style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFF06B6D4), size: 20),
            tooltip: 'Panduan Alur Kerja',
            onPressed: _showGuideDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // Banner mode (berubah mengikuti mode yang dipilih)
            _buildModeBanner(),
            const SizedBox(height: 14),

            // Node Input Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.link, size: 18, color: Color(0xFF6366F1)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tautan Proxy',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                'VMess · VLESS · Trojan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMiniAction('Tempel', Icons.content_paste, const Color(0xFF818CF8), _pasteFromClipboard),
                        if (_inputController.text.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildMiniAction('Hapus', Icons.delete_outline, Colors.redAccent, _clearInput),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _inputController,
                      maxLines: 5,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
                      onChanged: (_) => _convert(),
                      decoration: const InputDecoration(
                        hintText: 'Tempel link proxy satu per baris:\nvmess://...\nvless://...\ntrojan://...',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                      ),
                    ),
                    if (_parsedNodes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text('Node Terdeteksi (${_parsedNodes.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _parsedNodes.map((n) {
                          Color badgeColor = const Color(0xFF6366F1);
                          if (n.protocol == 'vmess') badgeColor = const Color(0xFFA855F7);
                          if (n.protocol == 'trojan') badgeColor = const Color(0xFFF59E0B);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D131F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1F2937)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  n.protocol.toUpperCase(),
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 110),
                                  child: Text(
                                    n.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                                if (n.region.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(n.region, style: const TextStyle(fontSize: 9, color: Color(0xFF06B6D4), fontWeight: FontWeight.bold)),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Target Format & Mode Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Target Format Keluaran', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFormatOption('Clash Meta', '.yaml', OutputTarget.clash),
                        const SizedBox(width: 8),
                        _buildFormatOption('Sing-box', '.json', OutputTarget.singbox),
                        const SizedBox(width: 8),
                        _buildFormatOption('Keduanya', 'YAML+JSON', OutputTarget.both),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Pilihan Mode Konversi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildModeOption('Minimal', ConverterModeType.minimal),
                        const SizedBox(width: 8),
                        _buildModeOption('Lengkap', ConverterModeType.lengkap),
                        const SizedBox(width: 8),
                        _buildModeOption('Custom', ConverterModeType.custom, isNew: true),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Mode Custom Studio Card
            if (_mode == ConverterModeType.custom) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune, size: 16, color: Color(0xFF6366F1)),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Studio Mode Custom (Addon)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      // Legenda badge hanya saat format = keduanya
                      if (_target == OutputTarget.both) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Label: ', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                            _buildCoreBadges('clash'),
                            const SizedBox(width: 6),
                            const Text('= hanya Clash', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                            const SizedBox(width: 10),
                            _buildCoreBadges('singbox'),
                            const SizedBox(width: 6),
                            const Text('= hanya Sing-box', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const SizedBox(width: 36),
                            _buildCoreBadges('both'),
                            const SizedBox(width: 6),
                            const Text('= berlaku di kedua core', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Presets Bar
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text('Preset: ', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                            _buildPresetChip('Seimbang', 'balanced'),
                            _buildPresetChip('Gaming', 'gaming'),
                            _buildPresetChip('Privasi', 'privacy'),
                            _buildPresetChip('Minimalis', 'clean'),
                          ],
                        ),
                      ),
                      const Divider(color: Color(0xFF1F2937), height: 20),

                      // Studio Tabs
                      Row(
                        children: [
                          _buildStudioTab('Rules', 'rules', Icons.rule),
                          _buildStudioTab('DNS', 'dns', Icons.dns),
                          _buildStudioTab('Geo', 'geo', Icons.public),
                          _buildStudioTab('Routing', 'routing', Icons.alt_route),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Tab Contents (animasi ganti tab)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.04, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_customStudioTab),
                          child: _customStudioTab == 'rules'
                              ? _buildRulesTab()
                              : _customStudioTab == 'dns'
                                  ? _buildDnsTab()
                                  : _customStudioTab == 'geo'
                                      ? _buildGeoTab()
                                      : _buildRoutingTab(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Baris: Input Bug + Wildcard (tinggi disamakan)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildBugInputCard()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildWildcardCard()),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: (_bugMode != BugWildcardMode.none &&
                      _bugController.text.trim().isNotEmpty)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildActiveBugBanner(),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),

            // Action Convert Button
            AnimatedScale(
              scale: _busy ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 180),
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _convert(showEmptyError: true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _busy
                      ? const SizedBox(
                          key: ValueKey('busy'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow, key: ValueKey('idle'), size: 18),
                ),
                label: const Text(
                  'Konversi & Perbarui Konfigurasi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),

            if (_status != null) ...[
              const SizedBox(height: 8),
              AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 300),
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (_isSuccessStatus ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (_isSuccessStatus ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(_isSuccessStatus ? Icons.check_circle : Icons.error_outline, size: 14, color: _isSuccessStatus ? const Color(0xFF10B981) : Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_status!, style: TextStyle(fontSize: 11, color: _isSuccessStatus ? const Color(0xFF10B981) : Colors.redAccent)),
                    ),
                  ],
                ),
              ),
              ),
            ],
            const SizedBox(height: 14),

            // Output Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.code, size: 18, color: Color(0xFF06B6D4)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Hasil Konfigurasi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        _buildOutputIconButton(Icons.copy, 'Salin', _copyOutput),
                        _buildOutputIconButton(Icons.share, 'Bagikan', _shareOutput),
                        _buildOutputIconButton(Icons.save_alt, 'Simpan', _saveOutput),
                      ],
                    ),
                    if (_target == OutputTarget.both) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildResultFormatButton('Clash (YAML)', 'clash'),
                          const SizedBox(width: 8),
                          _buildResultFormatButton('Sing-box (JSON)', 'singbox'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: SelectableText(
                        _currentResultText.isEmpty ? '# Hasil konversi akan muncul di sini' : _currentResultText,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          height: 1.35,
                          color: _currentResultText.isEmpty ? const Color(0xFF6B7280) : const Color(0xFFE5E7EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatOption(String title, String subtitle, OutputTarget val) {
    final isSelected = _target == val;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _target = val);
          _convert();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withOpacity(0.15) : const Color(0xFF0D131F),
            border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1F2937)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF9CA3AF))),
              Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(String title, ConverterModeType val, {bool isNew = false}) {
    final isSelected = _mode == val;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _mode = val);
          _convert();
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withOpacity(0.2) : const Color(0xFF0D131F),
            border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1F2937)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF9CA3AF))),
                if (isNew) ...[
                  const SizedBox(width: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFF06B6D4), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Baru', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => _applyPreset(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFE5E7EB))),
        ),
      ),
    );
  }

  Widget _buildStudioTab(String label, String key, IconData icon) {
    final isSelected = _customStudioTab == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _customStudioTab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    icon,
                    size: 12,
                    color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRulesTab() {
    return Column(
      children: [
        _buildCheckboxTile(
          '🛡️ Anti-Ads & Pelacak (Adblock)',
          'Blokir iklan pop-up & tracker (REJECT)',
          _antiAds,
          (v) => setState(() => _antiAds = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🤖 Layanan AI (ChatGPT, Claude, Gemini)',
          'Routing khusus ke grup AI-CHATGPT',
          _aiRouting,
          (v) => setState(() {
            _aiRouting = v ?? false;
            if (!_aiRouting && _newRuleTarget == 'AI-CHATGPT') {
              _newRuleTarget = 'DIRECT';
            }
          }),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🎬 Streaming Media (Netflix, YouTube)',
          'Routing kecepatan tinggi ke STREAMING',
          _streamingRouting,
          (v) => setState(() {
            _streamingRouting = v ?? false;
            if (!_streamingRouting && _newRuleTarget == 'STREAMING') {
              _newRuleTarget = 'DIRECT';
            }
          }),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🎮 Gaming Low Latency (Steam, Epic, Riot)',
          'Grup GAME dengan UDP ping rendah',
          _gamingRouting,
          (v) => setState(() {
            _gamingRouting = v ?? false;
            if (!_gamingRouting && _newRuleTarget == 'GAME') {
              _newRuleTarget = 'DIRECT';
            }
          }),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🏛️ Bypass Layanan ID (Bank, E-Wallet, Gov)',
          'Akses BCA, Mandiri, BRI langsung DIRECT',
          _domesticBypass,
          (v) => setState(() => _domesticBypass = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🚫 Blokir BitTorrent / P2P',
          'Cegah DMCA notice / copyright strike',
          _blockTorrent,
          (v) => setState(() => _blockTorrent = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '⚡ Blokir Protokol QUIC (UDP 443)',
          'Paksa video streaming menggunakan TCP/TLS',
          _blockQuic,
          (v) => setState(() => _blockQuic = v ?? false),
          core: 'both',
        ),
        const SizedBox(height: 10),
        // Custom Rule Builder
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF0D131F), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1F2937))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '+ Tambah Aturan Mandiri (Custom Rules)',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                  if (_target == OutputTarget.both) _buildCoreBadges('both'),
                ],
              ),
              const SizedBox(height: 10),
              // Baris 1: tipe aturan + tujuan (lebar dibagi rata)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _newRuleType,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: const Color(0xFF111827),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Tipe aturan', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'DOMAIN-SUFFIX', child: Text('DOMAIN-SUFFIX', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'DOMAIN-KEYWORD', child: Text('DOMAIN-KEYWORD', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'IP-CIDR', child: Text('IP-CIDR')),
                        DropdownMenuItem(value: 'GEOIP', child: Text('GEOIP')),
                      ],
                      onChanged: (v) => setState(() => _newRuleType = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _newRuleTarget,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: const Color(0xFF111827),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Tujuan', isDense: true),
                      items: [
                        const DropdownMenuItem(value: 'DIRECT', child: Text('DIRECT')),
                        const DropdownMenuItem(value: 'REJECT', child: Text('REJECT')),
                        const DropdownMenuItem(value: 'PILIH-PROXY', child: Text('PROXY')),
                        if (_aiRouting)
                          const DropdownMenuItem(value: 'AI-CHATGPT', child: Text('AI')),
                        if (_streamingRouting)
                          const DropdownMenuItem(value: 'STREAMING', child: Text('STREAMING')),
                        if (_gamingRouting)
                          const DropdownMenuItem(value: 'GAME', child: Text('GAME')),
                      ],
                      onChanged: (v) => setState(() => _newRuleTarget = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Baris 2: isi aturan selebar mungkin + tombol tambah
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newRulePayloadController,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      onSubmitted: (_) => _addCustomRule(),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Domain / IP / kode negara',
                        hintText: 'contoh.com atau 1.1.1.1/32',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addCustomRule,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              if (_customRules.isNotEmpty) ...[
                const SizedBox(height: 10),
                ..._customRules.map((cr) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${cr.type}, ${cr.payload} → ${cr.target}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF818CF8)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                            tooltip: 'Hapus aturan',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeCustomRule(cr.id),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDnsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldCoreLabel('Primary DoH Server', core: 'both'),
        DropdownButtonFormField<String>(
          value: _primaryDns,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 'cloudflare', child: Text('Cloudflare (1.1.1.1)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'google', child: Text('Google (8.8.8.8)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'adguard', child: Text('AdGuard (Anti-Ads)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'quad9', child: Text('Quad9 (Malware Block)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'custom', child: Text('Custom DoH URL', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _primaryDns = v);
            _convert();
          },
        ),
        if (_primaryDns == 'custom') ...[
          const SizedBox(height: 6),
          TextField(
            controller: _customDnsController,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white),
            decoration: const InputDecoration(hintText: 'https://dns.example.com/dns-query', isDense: true),
            onChanged: (v) {
              _customPrimaryDnsUrl = v;
              _convert();
            },
          ),
        ],
        const SizedBox(height: 10),
        _buildFieldCoreLabel('Secondary DoH Server (Fallback)', core: 'both'),
        DropdownButtonFormField<String>(
          value: _secondaryDns,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 'cloudflare', child: Text('Cloudflare (1.1.1.1)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'google', child: Text('Google (8.8.8.8)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'adguard', child: Text('AdGuard (Anti-Ads)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'quad9', child: Text('Quad9 (Malware Block)', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _secondaryDns = v);
            _convert();
          },
        ),
        const SizedBox(height: 10),
        _buildFieldCoreLabel('DNS Strategy (IPv4/IPv6)', core: 'both'),
        DropdownButtonFormField<String>(
          value: _dnsStrategy,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 'ipv4_only', child: Text('IPv4 Only', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'prefer_ipv4', child: Text('Prefer IPv4', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'prefer_ipv6', child: Text('Prefer IPv6', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _dnsStrategy = v);
            _convert();
          },
        ),
        const SizedBox(height: 8),
        _buildCheckboxTile(
          'Direct DNS Perbankan & Domestik',
          'Resolve domain bank Indonesia lewat bootstrap IP (bukan DoH)',
          _directBankDns,
          (v) => setState(() => _directBankDns = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'Fake-IP & Hijack DNS (Anti DNS Leak)',
          'enhanced-mode: fake-ip pada Clash Meta / Mihomo',
          _fakeIp,
          (v) => setState(() => _fakeIp = v ?? false),
          core: 'clash',
        ),
      ],
    );
  }

  Widget _buildGeoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckboxTile(
          'Bypass GeoIP Indonesia (DIRECT)',
          'IP server di Indonesia langsung direct',
          _geoipId,
          (v) => setState(() => _geoipId = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'Bypass Private & LAN IP',
          '192.168.x.x dan domain lokal otomatis DIRECT',
          _privateIp,
          (v) => setState(() => _privateIp = v ?? false),
          core: 'both',
        ),
      ],
    );
  }

  Widget _buildRoutingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldCoreLabel('Nama Grup Utama', core: 'both'),
                  TextField(
                    controller: _mainGroupController,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      _mainGroupName = v;
                      _convert();
                    },
                  ),
                ],
              ),
            ),
            if (_isCoreRelevant('clash')) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldCoreLabel('Mixed Port', core: 'clash'),
                    TextField(
                      controller: _mixedPortController,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, hintText: '7890'),
                      onChanged: (v) {
                        _mixedPort = int.tryParse(v) ?? 7890;
                        _convert();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _buildFieldCoreLabel('Interval URL-Test (detik)', core: 'both'),
        DropdownButtonFormField<int>(
          value: _urlTestInterval,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 60, child: Text('60 detik (1 menit)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 180, child: Text('180 detik (3 menit)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 300, child: Text('300 detik (5 menit)', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 600, child: Text('600 detik (10 menit)', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _urlTestInterval = v);
            _convert();
          },
        ),
        const SizedBox(height: 8),
        _buildCheckboxTile(
          'Grup AUTO-TERCEPAT (URL-Test)',
          'Pilih otomatis node berkecepatan terbaik',
          _autoFastest,
          (v) => setState(() => _autoFastest = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'TUN Mode (Auto-Route VPN)',
          'Routing seluruh jaringan perangkat',
          _tunEnabled,
          (v) => setState(() => _tunEnabled = v ?? false),
          core: 'both',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bug Host & Wildcard UI
  // ---------------------------------------------------------------------------

  Widget _buildBugInputCard() {
    final hasText = _bugController.text.trim().isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasText
              ? const Color(0xFF6366F1).withOpacity(0.55)
              : const Color(0xFF1F2937),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 14,
                color: hasText ? const Color(0xFF818CF8) : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 5),
              const Text(
                'Input Bug',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bugController,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'contoh: Bug.com',
              hintStyle: TextStyle(fontSize: 10, color: Color(0xFF4B5563)),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (v) {
              if (v.trim().isEmpty && _bugMode != BugWildcardMode.none) {
                setState(() => _bugMode = BugWildcardMode.none);
                if (_parsedNodes.isNotEmpty) _convert();
              } else {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWildcardCard() {
    final canUse = _bugController.text.trim().isNotEmpty;
    final active = _bugMode != BugWildcardMode.none && canUse;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: canUse ? 1.0 : 0.45,
      child: IgnorePointer(
        ignoring: !canUse,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: canUse ? _showWildcardPicker : null,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF6366F1).withOpacity(0.12)
                    : const Color(0xFF0D131F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? const Color(0xFF6366F1).withOpacity(0.55)
                      : const Color(0xFF1F2937),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: canUse
                            ? const Color(0xFF818CF8)
                            : const Color(0xFF4B5563),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Wildcard',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: canUse ? Colors.white : const Color(0xFF6B7280),
                        ),
                      ),
                      const Spacer(),
                      if (active)
                        GestureDetector(
                          onTap: () {
                            setState(() => _bugMode = BugWildcardMode.none);
                            if (_parsedNodes.isNotEmpty) _convert();
                          },
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Area setinggi field Input Bug agar kedua card seimbang
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1F2937)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        canUse
                            ? (active
                                ? _bugModeLabel(_bugMode)
                                : 'Ketuk untuk pilih mode')
                            : 'Isi Input Bug dulu',
                        key: ValueKey('$canUse-$active-$_bugMode'),
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: active ? 'monospace' : null,
                          color: active
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _bugModeLabel(BugWildcardMode mode) {
    switch (mode) {
      case BugWildcardMode.biasa:
        return 'Mode: Wildcard biasa';
      case BugWildcardMode.sni:
        return 'Mode: Timpa SNI';
      case BugWildcardMode.serverHost:
        return 'Mode: Timpa server & WS Host';
      case BugWildcardMode.none:
        return '';
    }
  }

  Widget _buildActiveBugBanner() {
    final bug = _bugController.text.trim();
    String preview;
    switch (_bugMode) {
      case BugWildcardMode.biasa:
        preview = 'server="$bug" · SNI/Host="$bug.<asli>"';
        break;
      case BugWildcardMode.sni:
        preview = 'servername="$bug"';
        break;
      case BugWildcardMode.serverHost:
        preview = 'server="$bug" · Host="$bug"';
        break;
      case BugWildcardMode.none:
        preview = '';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
      ),
      child: Text(
        'Bug aktif · $preview',
        style: const TextStyle(fontSize: 10, color: Color(0xFFA5B4FC)),
      ),
    );
  }

  void _showWildcardPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF374151),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pilih Mode Wildcard',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bug: ${_bugController.text.trim()}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 12),
                _buildWildcardOption(
                  ctx,
                  BugWildcardMode.biasa,
                  'Wildcard biasa',
                  'server = bug\nSNI / Host = bug.<server-asli>',
                  Icons.language,
                ),
                _buildWildcardOption(
                  ctx,
                  BugWildcardMode.sni,
                  'Timpa SNI',
                  'servername = bug (server tetap asli)',
                  Icons.badge_outlined,
                ),
                _buildWildcardOption(
                  ctx,
                  BugWildcardMode.serverHost,
                  'Timpa server & WS Host',
                  'server = bug · headers Host = bug',
                  Icons.dns_outlined,
                ),
                if (_bugMode != BugWildcardMode.none) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _bugMode = BugWildcardMode.none);
                      if (_parsedNodes.isNotEmpty) _convert();
                    },
                    child: const Text(
                      'Nonaktifkan wildcard',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWildcardOption(
    BuildContext ctx,
    BugWildcardMode mode,
    String title,
    String desc,
    IconData icon,
  ) {
    final selected = _bugMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? const Color(0xFF6366F1).withOpacity(0.15)
            : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.pop(ctx);
            setState(() => _bugMode = mode);
            if (_parsedNodes.isNotEmpty) _convert();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFF6366F1).withOpacity(0.55)
                    : const Color(0xFF1F2937),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : const Color(0xFFE5E7EB),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9CA3AF),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF6366F1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Badge kecil: inti mana yang memakai addon ini.
  /// [core] = 'both' | 'clash' | 'singbox'
  Widget _buildCoreBadges(String core) {
    Widget chip(String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.55), width: 0.8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: color,
          ),
        ),
      );
    }

    switch (core) {
      case 'clash':
        return chip('CLASH', const Color(0xFFF59E0B));
      case 'singbox':
        return chip('SING-BOX', const Color(0xFF22D3EE));
      case 'both':
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip('CLASH', const Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            chip('SING-BOX', const Color(0xFF22D3EE)),
          ],
        );
    }
  }

  /// True jika addon dengan [core] relevan terhadap format output yang dipilih.
  bool _isCoreRelevant(String core) {
    if (core == 'both') return true;
    if (_target == OutputTarget.both) return true;
    if (_target == OutputTarget.clash && core == 'clash') return true;
    if (_target == OutputTarget.singbox && core == 'singbox') return true;
    return false;
  }

  Widget _buildCheckboxTile(
    String title,
    String subtitle,
    bool val,
    ValueChanged<bool?> onChanged, {
    String core = 'both',
  }) {
    // Sembunyikan addon yang tidak relevan dengan format output yang dipilih
    if (!_isCoreRelevant(core)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: val
              ? const Color(0xFF6366F1).withOpacity(0.08)
              : const Color(0xFF0D131F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: val
                ? const Color(0xFF6366F1).withOpacity(0.45)
                : const Color(0xFF1F2937),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              // Badge hanya saat format = keduanya, agar UI tetap ringkas
              if (_target == OutputTarget.both) _buildCoreBadges(core),
            ],
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF9CA3AF)),
          ),
          value: val,
          activeColor: const Color(0xFF6366F1),
          onChanged: (v) {
            onChanged(v);
            _convert();
          },
        ),
      ),
    );
  }

  /// Label field (dropdown / text) dengan badge inti di atasnya.
  /// Kosong jika core tidak relevan dengan format output.
  Widget _buildFieldCoreLabel(String label, {String core = 'both'}) {
    if (!_isCoreRelevant(core)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          if (_target == OutputTarget.both) _buildCoreBadges(core),
        ],
      ),
    );
  }

  /// Tombol pemilih hasil (Clash / Sing-box), lebar dibagi rata dalam satu Row.
  Widget _buildResultFormatButton(String label, String key) {
    final isSel = _activeResultTab == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeResultTab = key),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF6366F1) : const Color(0xFF0D131F),
            border: Border.all(color: isSel ? const Color(0xFF6366F1) : const Color(0xFF1F2937)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSel ? Colors.white : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }

  /// Tombol ikon kecil di header kartu hasil (dinonaktifkan jika belum ada hasil).
  Widget _buildOutputIconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: _currentResultText.isEmpty ? null : onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  /// Tombol aksi kecil bergaya "pill" (Tempel / Hapus) di header kartu input.
  Widget _buildMiniAction(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
