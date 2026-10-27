import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'converter.dart';
import 'splash.dart';
import 'tutor.dart';

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

enum OutputTarget { clash, singbox }
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

  // GlobalKeys untuk spotlight tutor (coach-mark).
  final _keyInput = GlobalKey();
  final _keyMode = GlobalKey();
  final _keyBug = GlobalKey();
  final _keyConvert = GlobalKey();
  final _keyOutput = GlobalKey();
  final _keyCoreNav = GlobalKey();
  final _keyCoraButton = GlobalKey();

  /// Sapaan Cora di AppBar (sekali per sesi buka aplikasi).
  bool _coraGreetingVisible = false;
  String _coraGreetingText = '';
  OverlayEntry? _coraGreetingEntry;

  OutputTarget _target = OutputTarget.clash;
  // Arah slide halaman saat berpindah core: 1 = ke kanan (Sing-box), -1 = ke kiri (Clash).
  int _slideDir = 1;
  // Mode per core: Clash & Sing-box masing-masing default ke Minimal.
  final Map<OutputTarget, ConverterModeType> _modeByTarget = {
    OutputTarget.clash: ConverterModeType.minimal,
    OutputTarget.singbox: ConverterModeType.minimal,
  };
  ConverterModeType get _mode =>
      _modeByTarget[_target] ?? ConverterModeType.minimal;
  set _mode(ConverterModeType v) => _modeByTarget[_target] = v;
  String _customStudioTab = 'rules'; // 'rules' | 'dns' | 'geo' | 'routing'

  // Custom Addons State
  // Default awal mengikuti isi mode Minimal (Clash + Sing-box) yang terbukti konek:
  //  - HIDUP (disarankan tetap default; berisiko jika diubah):
  //      Fake-IP (Clash), Private/LAN DIRECT, AUTO-TERCEPAT, Blokir QUIC,
  //      DNS Cloudflare+Google, DNS Strategy IPv4 only.
  //  - MATI (opsional, risiko rendah):
  //      Anti-Ads, AI, Streaming, Gaming, Bypass ID/bank, Blokir torrent,
  //      GeoIP ID, Direct DNS perbankan, TUN Mode (Clash).
  // Addon berisiko menampilkan dialog konfirmasi saat diubah oleh pengguna.
  String _primaryDns = 'cloudflare';
  String _customPrimaryDnsUrl = '';
  String _secondaryDns = 'google';
  String _dnsStrategy = 'ipv4_only';
  bool _fakeIp = true;
  bool _directBankDns = false;

  bool _antiAds = false;
  bool _aiRouting = false;
  bool _streamingRouting = false;
  bool _gamingRouting = false;
  bool _domesticBypass = false;
  bool _blockTorrent = false;
  bool _blockQuic = true;

  final List<CustomRuleItem> _customRules = [];
  String _newRuleType = 'DOMAIN-SUFFIX';
  final _newRulePayloadController = TextEditingController();
  String _newRuleTarget = 'DIRECT';

  bool _geoipId = false;
  bool _privateIp = true;

  String _mainGroupName = 'PILIH-PROXY';
  bool _autoFastest = true;
  int _urlTestInterval = 300;
  int _mixedPort = kDefaultClashMixedPort;
  bool _tunEnabled = false;

  // Controller dibuat sekali di state (bukan di build) agar kursor tidak loncat
  // dan teks tidak ter-reset setiap kali _convert() memicu rebuild.
  final _mainGroupController = TextEditingController(text: 'PILIH-PROXY');
  final _mixedPortController =
      TextEditingController(text: '$kDefaultClashMixedPort');
  final _customDnsController = TextEditingController();
  final _bugController = TextEditingController();
  final _seranggaIpController = TextEditingController();
  final _seranggaNameController = TextEditingController();
  final _seranggaCountController = TextEditingController(text: '3');

  /// Mode wildcard bug yang aktif (none = tidak diterapkan).
  BugWildcardMode _bugMode = BugWildcardMode.none;

  /// Multi-serangga: gandakan tiap akun × N (opsional).
  bool _seranggaEnabled = false;
  int _seranggaCount = 3;

  /// Panel opsi lanjutan Multi Serangga sedang dibuka.
  bool _seranggaManualOpen = false;

  /// Cara penerapan Wildcard Multi Serangga (pilihan sama dengan
  /// menu Wildcard). Default serverHost = server + Host header, sama dengan
  /// perilaku sebelumnya.
  BugWildcardMode _seranggaIpMode = BugWildcardMode.serverHost;

  /// Wildcard utama (kartu Wildcard + Input Bug) sedang aktif.
  bool get _mainWildcardActive =>
      _bugMode != BugWildcardMode.none &&
      _bugController.text.trim().isNotEmpty;

  /// Jumlah item bug yang diketik di Wildcard Multi Serangga.
  int get _seranggaWildcardCount =>
      parseSeranggaHostList(_seranggaIpController.text).length;

  /// Wildcard Multi Serangga aktif: Multi Serangga hidup, daftar terisi, dan
  /// wildcard utama tidak aktif. Keduanya tidak boleh aktif bersamaan.
  bool get _seranggaWildcardActive =>
      _seranggaEnabled && _seranggaWildcardCount > 0 && !_mainWildcardActive;

  /// Kartu Wildcard utama dikunci selama Wildcard Multi Serangga aktif.
  bool get _mainWildcardLocked => _seranggaWildcardActive;

  /// Wildcard Multi Serangga dikunci selama Wildcard utama aktif.
  bool get _seranggaWildcardLocked => _mainWildcardActive;

  /// Rapikan isi kolom jumlah serangga: kosong/di luar batas → dibatasi ke
  /// [kSeranggaMin]..[kSeranggaMax], lalu teks kolom disamakan dengan nilainya.
  void _normalizeSeranggaCount() {
    final parsed = int.tryParse(_seranggaCountController.text.trim());
    final n = (parsed ?? _seranggaCount).clamp(kSeranggaMin, kSeranggaMax);
    final text = '$n';
    setState(() {
      _seranggaCount = n;
      if (_seranggaCountController.text != text) {
        _seranggaCountController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
  }

  List<Node> _parsedNodes = [];
  String _clashOutput = '';
  String _singboxOutput = '';
  String? _status;
  bool _isSuccessStatus = true;
  bool _busy = false;

  /// Daftar sapaan acak Cora — dipilih satu tiap kali aplikasi dibuka.
  static const List<String> _coraGreetings = [
    'Halo! Siap konversi proxy hari ini?',
    'Selamat datang kembali. Ada link baru?',
    'Hai! Cora siap membantu.',
    'Mode Minimal atau Lengkap hari ini?',
    'Jangan lupa: semua berjalan offline.',
    'Tempel link, lalu biarkan saya yang urus.',
    'Semoga config-nya lancar!',
    'Butuh tour lagi? Ketuk saya kapan saja.',
    'Clash atau Sing-box — pilih di bawah ya.',
    'Halo! Mari buat config yang rapi.',
    'Siap tempel VMess / VLESS / Trojan?',
    'Tips: mode Custom untuk aturan sendiri.',
  ];

  @override
  void initState() {
    super.initState();
    // Tutor dulu (jika perlu), lalu sapaan Cora agar tidak bertabrakan.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final tutorDone = prefs.getBool(kTutorCompletedKey) == true;
      if (!tutorDone) {
        await maybeShowTutor(
          context,
          steps: _buildTutorSteps(),
          onFinished: () {
            if (mounted) _scheduleCoraGreeting();
          },
        );
      } else {
        _scheduleCoraGreeting();
      }
    });
  }

  void _scheduleCoraGreeting() {
    if (!mounted) return;
    // Jeda singkat agar UI stabil, lalu tampilkan bubble sapaan.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _showCoraGreeting();
    });
  }

  void _showCoraGreeting() {
    _removeCoraGreeting();
    final rnd = math.Random();
    _coraGreetingText = _coraGreetings[rnd.nextInt(_coraGreetings.length)];
    _coraGreetingVisible = true;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _coraGreetingEntry = OverlayEntry(
      builder: (ctx) {
        // Posisi relatif ke tombol Cora di AppBar.
        final box = _keyCoraButton.currentContext?.findRenderObject() as RenderBox?;
        double right = 12;
        double top = MediaQuery.of(ctx).padding.top + 52;
        if (box != null && box.hasSize) {
          final offset = box.localToGlobal(Offset.zero);
          // Bubble di bawah-kiri tombol agar tetap di layar.
          right = MediaQuery.of(ctx).size.width - offset.dx - box.size.width + 4;
          top = offset.dy + box.size.height - 2;
        }
        return Positioned(
          right: right.clamp(8.0, 120.0),
          top: top,
          child: _CoraGreetingBubble(
            text: _coraGreetingText,
            onDismiss: _removeCoraGreeting,
          ),
        );
      },
    );
    overlay.insert(_coraGreetingEntry!);

    // Hilang otomatis setelah beberapa detik agar tidak mengganggu.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _removeCoraGreeting();
    });
  }

  void _removeCoraGreeting() {
    _coraGreetingEntry?.remove();
    _coraGreetingEntry = null;
    if (_coraGreetingVisible && mounted) {
      setState(() => _coraGreetingVisible = false);
    } else {
      _coraGreetingVisible = false;
    }
  }

  List<TutorStep> _buildTutorSteps() {
    return [
      TutorStep(
        id: 'intro',
        title: 'Halo! Saya Cora',
        body:
            'Saya asisten resmi Proxy Converter. Mari kenali fitur utama aplikasi ini dalam beberapa langkah singkat. Anda bisa melewati kapan saja.',
        tip: 'Tour ini hanya muncul sekali saat pertama kali membuka aplikasi.',
        icon: Icons.waving_hand_rounded,
        accent: const Color(0xFF6366F1),
        demo: TutorDemoType.none,
      ),
      TutorStep(
        id: 'input',
        title: 'Tempel Link Proxy',
        body:
            'Skenario: tempel beberapa link VMess/VLESS/Trojan → parser offline membaca protokol → node dikelompokkan per wilayah. Semua berjalan tanpa internet.',
        tip: 'Gunakan tombol Tempel untuk mengambil dari clipboard secara cepat.',
        icon: Icons.content_paste_rounded,
        accent: const Color(0xFF06B6D4),
        targetKey: _keyInput,
        demo: TutorDemoType.pasteLinks,
      ),
      TutorStep(
        id: 'mode',
        title: 'Pilih Mode Konversi',
        body:
            'Skenario: coba Minimal (ringan), Lengkap (50+ rule-set), lalu Custom (Studio). Banner dan tag di atas otomatis menyesuaikan pilihan Anda.',
        tip: 'Banner di atas berubah sesuai mode yang aktif.',
        icon: Icons.tune_rounded,
        accent: const Color(0xFF10B981),
        targetKey: _keyMode,
        demo: TutorDemoType.modeSwitch,
      ),
      TutorStep(
        id: 'bug',
        title: 'Bug Host & Wildcard',
        body:
            'Skenario: isi domain bug → pilih mode (SNI / server / Host) → preview diterapkan ke semua node. Kosongkan kolom jika tidak ingin mengubah host.',
        tip: 'Kosongkan Input Bug jika tidak ingin mengubah host.',
        icon: Icons.bug_report_outlined,
        accent: const Color(0xFFA78BFA),
        targetKey: _keyBug,
        demo: TutorDemoType.bugWildcard,
      ),
      TutorStep(
        id: 'convert',
        title: 'Jalankan Konversi',
        body:
            'Skenario: setelah link dan mode siap, tekan Konversi. Progress membangun grup, DNS, dan rule → file YAML/JSON siap dipakai.',
        tip: 'Status sukses atau error akan muncul tepat di bawah tombol.',
        icon: Icons.play_arrow_rounded,
        accent: const Color(0xFF6366F1),
        targetKey: _keyConvert,
        demo: TutorDemoType.convertPulse,
      ),
      TutorStep(
        id: 'output',
        title: 'Hasil Konfigurasi',
        body:
            'Skenario: salin ke clipboard, bagikan ke aplikasi lain, atau simpan ke Download. Nama file mengikuti inti aktif (Clash/Sing-box).',
        tip: 'Pastikan izin penyimpanan sudah diberikan agar Simpan berfungsi.',
        icon: Icons.description_outlined,
        accent: const Color(0xFF06B6D4),
        targetKey: _keyOutput,
        demo: TutorDemoType.outputActions,
      ),
      TutorStep(
        id: 'core',
        title: 'Beralih Inti',
        body:
            'Skenario: beralih Clash Meta (YAML) ↔ Sing-box (JSON). Setiap inti menyimpan mode dan hasilnya sendiri, sehingga Anda bisa membandingkan keduanya.',
        tip: 'Mode Custom hanya memengaruhi inti yang sedang aktif.',
        icon: Icons.swap_horiz_rounded,
        accent: const Color(0xFF818CF8),
        targetKey: _keyCoreNav,
        demo: TutorDemoType.coreNav,
      ),
      TutorStep(
        id: 'done',
        title: 'Siap Digunakan',
        body:
            'Anda sudah mengenal alur utamanya. Jelajahi Studio Custom untuk aturan lanjutan kapan pun dibutuhkan. Selamat mencoba!',
        tip: 'Buka kembali tour ini lewat ikon bantuan di pojok kanan atas.',
        icon: Icons.verified_rounded,
        accent: const Color(0xFF10B981),
        demo: TutorDemoType.none,
      ),
    ];
  }

  @override
  void dispose() {
    _removeCoraGreeting();
    _inputController.dispose();
    _searchController.dispose();
    _newRulePayloadController.dispose();
    _mainGroupController.dispose();
    _mixedPortController.dispose();
    _customDnsController.dispose();
    _bugController.dispose();
    _seranggaIpController.dispose();
    _seranggaNameController.dispose();
    _seranggaCountController.dispose();
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
        _status = null; // reset status; konversi hanya via tombol
      });
      _parseNodesFromInput();
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
        // QUIC tetap diblokir (sama dengan Minimal): UDP/QUIC lewat proxy bug/WS
        // sering tidak diteruskan server → aplikasi macet seolah tanpa internet.
        _blockQuic = true;
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
        _blockQuic = true;
      } else if (key == 'clean') {
        _antiAds = false;
        _aiRouting = false;
        _streamingRouting = false;
        _gamingRouting = false;
        _domesticBypass = true;
        _blockTorrent = false;
        _blockQuic = true;
      }
    });
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
  }

  void _removeCustomRule(String id) {
    setState(() {
      _customRules.removeWhere((r) => r.id == id);
    });
  }

  /// Konversi hanya dipanggil dari tombol «Konversi & Perbarui Konfigurasi».
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

    // Sedikit jeda agar animasi loading tombol terlihat (konversi lokal sangat cepat).
    await Future<void>.delayed(const Duration(milliseconds: 380));

    try {
      // Bug/wildcard dulu, lalu multi-serangga (gandakan per akun × N IP)
      var nodesForOutput = applyBugWildcard(
        _parsedNodes,
        _bugController.text,
        _bugMode,
      );
      nodesForOutput = applyMultiSerangga(
        nodesForOutput,
        enabled: _seranggaEnabled,
        count: _seranggaCount,
        // Wildcard utama aktif → daftar bug serangga diabaikan (tidak boleh bersamaan).
        ipListText: _seranggaWildcardLocked ? '' : _seranggaIpController.text,
        nameListText: _seranggaNameController.text,
        ipMode: _seranggaIpMode,
      );
      final multiInfo = (_seranggaEnabled &&
              nodesForOutput.length != _parsedNodes.length)
          ? ' → ${nodesForOutput.length} outbound (Multi Serangga ×$_seranggaCount)'
          : '';
      // multiInfo tetap dipakai di string status agar kompatibel dengan banner.

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
              'Berhasil mengonversi ${_parsedNodes.length} node$multiInfo (Mode: ${_mode.name.toUpperCase()}).';
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
            'Berhasil mengonversi ${_parsedNodes.length} node$multiInfo (Mode: ${_mode.name.toUpperCase()}).';
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

  /// True jika halaman aktif adalah Clash (YAML), false jika Sing-box (JSON).
  bool get _isClashResult => _target == OutputTarget.clash;

  String get _currentResultText => _isClashResult ? _clashOutput : _singboxOutput;

  /// Warna aksen inti: amber untuk Clash, cyan untuk Sing-box.
  Color get _coreAccent =>
      _isClashResult ? const Color(0xFFF59E0B) : const Color(0xFF22D3EE);

  String get _coreTitle => _isClashResult ? 'Clash Meta' : 'Sing-box';
  String get _coreExt => _isClashResult ? '.yaml' : '.json';

  /// Isi banner untuk mode yang aktif. Mode Custom ikut menampilkan ringkasan opsi
  /// yang sedang dipilih, jadi banner berubah setiap kali opsi di Studio diubah.
  _ModeInfo get _modeInfo {
    if (_mode == ConverterModeType.minimal) {
      return const _ModeInfo(
        label: 'Minimal',
        icon: Icons.bolt,
        color: Color(0xFF10B981),
        title: 'Konfigurasi Ringkas & Ringan',
        description: 'Ringan: DNS dasar, 2 grup, tanpa rule-set. Semua traffic lewat proxy.',
        tags: ['2 grup', 'tanpa rule-set', 'MATCH all'],
      );
    }
    if (_mode == ConverterModeType.lengkap) {
      return const _ModeInfo(
        label: 'Lengkap',
        icon: Icons.layers,
        color: Color(0xFF06B6D4),
        title: 'Template Siap Pakai',
        description: 'Siap pakai: failover, load-balance, 50+ rule-set, DNS berlapis.',
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
      title: 'Konfigurasi Sesuai Kebutuhan',
      description: 'Susun DNS, rules, dan GeoIP di Studio sesuai kebutuhan.',
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Column(
                key: ValueKey(info.label),
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
                        Text(
                          'Mode ${info.label} aktif',
                          style: TextStyle(
                            fontSize: 10,
                            color: soft,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    info.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.description,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: info.tags.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D131F).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: info.color.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: soft,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
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
    _showCapsuleSnack(
      message: 'Konfigurasi disalin ke clipboard',
      icon: Icons.content_copy_rounded,
      isSuccess: true,
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
      _showCapsuleSnack(
        message: 'Disimpan ke Download/$fileName',
        icon: Icons.download_done_rounded,
        isSuccess: true,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!mounted) return;
      _showCapsuleSnack(
        message:
            'Gagal menyimpan. Pastikan izin penyimpanan diberikan.',
        icon: Icons.error_outline_rounded,
        isSuccess: false,
        duration: const Duration(seconds: 5),
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
                '1. Pilih inti\n'
                'Beralih Clash Meta atau Sing-box lewat navigasi bawah.\n\n'
                '2. Tempel tautan\n'
                'Parser offline untuk VMess, VLESS, dan Trojan.\n\n'
                '3. Mode & opsi\n'
                'Minimal, Lengkap, atau Custom (DNS, rules, geo, routing).\n\n'
                '4. Konversi & ekspor\n'
                'Tekan Konversi, lalu salin, bagikan, atau simpan hasil.',
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
      extendBody: true,
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1422),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isClashResult
                      ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                      : const [Color(0xFF22D3EE), Color(0xFF0891B2)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _coreAccent.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _isClashResult ? Icons.hub_outlined : Icons.terminal,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proxy Converter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$_coreTitle  ·  $_coreExt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _coreAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF9CA3AF), size: 22),
            tooltip: 'Panduan singkat',
            onPressed: _showGuideDialog,
          ),
          IconButton(
            key: _keyCoraButton,
            icon: TutorRobot(
              size: 28,
              accent: const Color(0xFF6366F1),
              mood: _coraGreetingVisible ? RobotMood.wave : RobotMood.idle,
            ),
            tooltip: 'Tour bersama Cora',
            onPressed: () {
              _removeCoraGreeting();
              showTutorAgain(context, steps: _buildTutorSteps());
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey<OutputTarget>(_target);
              // Halaman baru masuk dari arah tujuan, halaman lama keluar ke arah berlawanan.
              final begin = Offset(incoming ? _slideDir.toDouble() : -_slideDir.toDouble(), 0);
              return SlideTransition(
                position: Tween<Offset>(begin: begin, end: Offset.zero).animate(animation),
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0.0, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: ListView(
          key: ValueKey<OutputTarget>(_target),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            // Banner mode (berubah mengikuti mode yang dipilih)
            _buildModeBanner(),
            const SizedBox(height: 16),

            // Node Input Card
            Card(
              key: _keyInput,
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                      onChanged: (_) {
                        // Hanya deteksi node; konfigurasi dibuat saat tombol ditekan.
                        _parseNodesFromInput();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Tempel link proxy satu per baris:\nvmess://...\nvless://...\ntrojan://...',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: _parsedNodes.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 14,
                                        color: Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Node terdeteksi (${_parsedNodes.length})',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (var i = 0; i < _parsedNodes.length; i++)
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration: Duration(
                                            milliseconds: 280 + (i * 40).clamp(0, 320),
                                          ),
                                          curve: Curves.easeOutBack,
                                          builder: (context, value, child) {
                                            return Opacity(
                                              opacity: value.clamp(0.0, 1.0),
                                              child: Transform.scale(
                                                scale: 0.85 + (0.15 * value),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: _buildNodeBadge(_parsedNodes[i]),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Mode Selection (inti dipilih lewat floating nav bawah)
            Card(
              key: _keyMode,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 16, color: _coreAccent),
                        const SizedBox(width: 8),
                        const Text(
                          'Mode Konversi',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildModeOption('Minimal', ConverterModeType.minimal),
                        const SizedBox(width: 10),
                        _buildModeOption('Lengkap', ConverterModeType.lengkap),
                        const SizedBox(width: 10),
                        _buildModeOption('Custom', ConverterModeType.custom),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

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
                              'Studio Custom',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
              key: _keyBug,
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
            const SizedBox(height: 8),
            _buildSeranggaCard(),
            const SizedBox(height: 10),

            // Tombol Konversi — hanya di sini konfigurasi dibuat/diperbarui
            KeyedSubtree(
              key: _keyConvert,
              child: _buildConvertButton(),
            ),

            if (_status != null) ...[
              const SizedBox(height: 10),
              _buildStatusBanner(),
            ],
            const SizedBox(height: 14),

            // Output Card
            Card(
              key: _keyOutput,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.code_rounded, size: 18, color: _coreAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hasil Konfigurasi',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                '$_coreTitle  $_coreExt',
                                style: TextStyle(fontSize: 10, color: _coreAccent, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        _buildOutputIconButton(Icons.copy_rounded, 'Salin', _copyOutput),
                        _buildOutputIconButton(Icons.share_rounded, 'Bagikan', _shareOutput),
                        _buildOutputIconButton(Icons.save_alt_rounded, 'Simpan', _saveOutput),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 72),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentResultText.isEmpty
                              ? const Color(0xFF1F2937)
                              : _coreAccent.withOpacity(0.25),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _currentResultText.isEmpty
                            ? const Padding(
                                key: ValueKey('empty'),
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    'Tekan «Konversi & Perbarui Konfigurasi»\nuntuk menampilkan hasil di sini',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              )
                            : SelectableText(
                                _currentResultText,
                                key: ValueKey(_currentResultText.hashCode),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  height: 1.35,
                                  color: Color(0xFFE5E7EB),
                                ),
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
        ),
      ),
      bottomNavigationBar: _buildFloatingCoreNav(),
    );
  }

  /// Floating bottom navigation — beralih antara halaman Clash dan Sing-box.
  Widget _buildFloatingCoreNav() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          key: _keyCoreNav,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withOpacity(0.96),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF1F2937)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  label: 'Clash Meta',
                  subtitle: 'YAML',
                  icon: Icons.hub_outlined,
                  selected: _target == OutputTarget.clash,
                  accent: const Color(0xFFF59E0B),
                  onTap: () {
                    if (_target == OutputTarget.clash) return;
                    setState(() {
                      _slideDir = -1;
                      _target = OutputTarget.clash;
                    });
                  },
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: const Color(0xFF1F2937),
              ),
              Expanded(
                child: _buildNavItem(
                  label: 'Sing-box',
                  subtitle: 'JSON',
                  icon: Icons.terminal,
                  selected: _target == OutputTarget.singbox,
                  accent: const Color(0xFF22D3EE),
                  onTap: () {
                    if (_target == OutputTarget.singbox) return;
                    setState(() {
                      _slideDir = 1;
                      _target = OutputTarget.singbox;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent.withOpacity(0.45) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : const Color(0xFF9CA3AF),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: selected ? accent : const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(String title, ConverterModeType val) {
    final isSelected = _mode == val;
    IconData icon;
    switch (val) {
      case ConverterModeType.minimal:
        icon = Icons.bolt_rounded;
        break;
      case ConverterModeType.lengkap:
        icon = Icons.layers_rounded;
        break;
      case ConverterModeType.custom:
        icon = Icons.auto_awesome_rounded;
        break;
    }
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _mode = val),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF6366F1).withOpacity(0.20)
                  : const Color(0xFF0D131F),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF1F2937),
                width: isSelected ? 1.3 : 1.0,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.0 : 0.92,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? const Color(0xFFA5B4FC)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : const Color(0xFF9CA3AF),
                  ),
                ),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _applyPreset(key),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE5E7EB),
              ),
            ),
          ),
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
          '🛡️ Anti-Ads & Pelacak',
          'Blokir iklan & pelacak (grup ADBLOCK)',
          _antiAds,
          (v) => setState(() => _antiAds = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🤖 Layanan AI',
          'Routing ke grup AI-CHATGPT',
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
          '🎬 Streaming Media',
          'Routing ke grup STREAMING',
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
          '🎮 Gaming Low Latency',
          'Grup GAME, prioritas UDP rendah',
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
          '🏛️ Bypass Layanan Indonesia',
          'Grup FINANSIAL-BANK & E-COMMERCE, default DIRECT',
          _domesticBypass,
          (v) => setState(() => _domesticBypass = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '🚫 Blokir BitTorrent / P2P',
          'Cegah risiko DMCA (grup DOWNLOAD-TORRENT)',
          _blockTorrent,
          (v) => setState(() => _blockTorrent = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          '⚡ Blokir QUIC (UDP 443)',
          'Paksa streaming lewat TCP/TLS',
          _blockQuic,
          (v) => setState(() => _blockQuic = v ?? false),
          core: 'both',
          risky: true,
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
                      '+ Tambah Aturan Custom',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF)),
                    ),
                  ),
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
          },
        ),
        const SizedBox(height: 8),
        _buildCheckboxTile(
          'Direct DNS Perbankan & Domestik',
          'Resolve domain bank lewat bootstrap IP',
          _directBankDns,
          (v) => setState(() => _directBankDns = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'Fake-IP & Hijack DNS',
          'Anti DNS leak (Clash Meta / Mihomo)',
          _fakeIp,
          (v) => setState(() => _fakeIp = v ?? false),
          core: 'clash',
          risky: true,
        ),
      ],
    );
  }

  Widget _buildGeoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckboxTile(
          'Bypass GeoIP Indonesia',
          'IP Indonesia → DIRECT',
          _geoipId,
          (v) => setState(() => _geoipId = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'Bypass Private & LAN IP',
          'LAN dan domain lokal → DIRECT',
          _privateIp,
          (v) => setState(() => _privateIp = v ?? false),
          core: 'both',
          risky: true,
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
                      decoration: InputDecoration(isDense: true, hintText: '$kDefaultClashMixedPort'),
                      onChanged: (v) {
                        _mixedPort = int.tryParse(v) ?? kDefaultClashMixedPort;
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
          },
        ),
        const SizedBox(height: 8),
        _buildCheckboxTile(
          'Grup AUTO-TERCEPAT',
          'Pilih node tercepat otomatis',
          _autoFastest,
          (v) => setState(() => _autoFastest = v ?? false),
          core: 'both',
        ),
        _buildCheckboxTile(
          'TUN Mode (VPN)',
          'Routing seluruh jaringan perangkat',
          _tunEnabled,
          (v) => setState(() => _tunEnabled = v ?? false),
          core: 'both',
          risky: true,
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
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasText
            ? const Color(0xFF6366F1).withOpacity(0.08)
            : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasText
              ? const Color(0xFF6366F1).withOpacity(0.50)
              : const Color(0xFF1F2937),
          width: hasText ? 1.2 : 1.0,
        ),
        boxShadow: hasText
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: hasText
                      ? const Color(0xFF6366F1).withOpacity(0.22)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.bug_report_outlined,
                  size: 14,
                  color: hasText
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Input Bug',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hostname/domain bug. Banyak akun? Tulis satu bug per baris, urut sesuai akun.',
            style: TextStyle(
              fontSize: 9.5,
              height: 1.3,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bugController,
            // Multi bug: Enter = baris baru, satu bug per baris (bug ke-N untuk akun ke-N).
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Bug.com\nBug2.com',
              hintMaxLines: 2,
              hintStyle: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4B5563),
              ),
              filled: true,
              fillColor: const Color(0xFF0A0E17),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFF6366F1),
                  width: 1.3,
                ),
              ),
            ),
            onChanged: (v) {
              if (v.trim().isEmpty && _bugMode != BugWildcardMode.none) {
                setState(() => _bugMode = BugWildcardMode.none);
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
    final hasBug = _bugController.text.trim().isNotEmpty;
    final locked = _mainWildcardLocked;
    // canUse: bisa ditekan (Input Bug terisi dan tidak dikunci Multi Serangga).
    final canUse = hasBug && !locked;
    final active = _bugMode != BugWildcardMode.none && canUse;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: canUse ? 1.0 : 0.55,
      child: IgnorePointer(
        ignoring: !canUse,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: canUse ? _showWildcardPicker : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF6366F1).withOpacity(0.10)
                    : const Color(0xFF0D131F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? const Color(0xFF6366F1).withOpacity(0.50)
                      : const Color(0xFF1F2937),
                  width: active ? 1.2 : 1.0,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF6366F1).withOpacity(0.22)
                              : const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: canUse
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Wildcard',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: canUse
                                ? Colors.white
                                : const Color(0xFF6B7280),
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                      if (active)
                        GestureDetector(
                          onTap: () {
                            setState(() => _bugMode = BugWildcardMode.none);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    locked
                        ? 'Dikunci: Wildcard Multi Serangga sedang aktif.'
                        : (canUse
                            ? 'Ketuk untuk memilih mode penerapan.'
                            : 'Isi Input Bug terlebih dahulu.'),
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.3,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF6366F1).withOpacity(0.35)
                            : const Color(0xFF1F2937),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: Row(
                        key: ValueKey('$canUse-$locked-$active-$_bugMode'),
                        children: [
                          if (active) ...[
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: Color(0xFF818CF8),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              locked
                                  ? 'Dikunci'
                                  : (canUse
                                      ? (active
                                          ? _bugModeLabel(_bugMode)
                                          : 'Pilih mode wildcard')
                                      : 'Menunggu Input Bug'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w500,
                                color: active
                                    ? const Color(0xFFA5B4FC)
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          if (canUse && !active)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: Color(0xFF6B7280),
                            ),
                        ],
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
        return 'Wildcard biasa';
      case BugWildcardMode.sni:
        return 'Timpa SNI';
      case BugWildcardMode.serverHost:
        return 'Server & WS Host';
      case BugWildcardMode.serverOnly:
        return 'Server saja';
      case BugWildcardMode.none:
        return '';
    }
  }

  Widget _buildActiveBugBanner() {
    final bugs = parseSeranggaHostList(_bugController.text);
    final multiBug = bugs.length > 1;
    final bug = multiBug ? '<bug akun>' : (bugs.isEmpty ? '' : bugs.first);
    String title;
    String detail;
    switch (_bugMode) {
      case BugWildcardMode.biasa:
        title = 'Wildcard biasa';
        detail = 'server = $bug  ·  SNI/Host = $bug.<asli>';
        break;
      case BugWildcardMode.sni:
        title = 'Timpa SNI';
        detail = 'servername = $bug  ·  server tetap asli';
        break;
      case BugWildcardMode.serverHost:
        title = 'Server & WS Host';
        detail = 'server = $bug  ·  Host = $bug';
        break;
      case BugWildcardMode.serverOnly:
        title = 'Server saja';
        detail = 'server = $bug  ·  SNI & Host tetap asli';
        break;
      case BugWildcardMode.none:
        title = '';
        detail = '';
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF6366F1).withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.verified_outlined,
                size: 15,
                color: Color(0xFFA5B4FC),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bug aktif · $title${multiBug ? ' · ${bugs.length} bug (per akun)' : ''}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE0E7FF),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFA5B4FC),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Snackbar berbentuk kapsul mengambang (floating capsule) dengan animasi masuk.
  void _showCapsuleSnack({
    required String message,
    required IconData icon,
    required bool isSuccess,
    Duration duration = const Duration(seconds: 3),
  }) {
    final accent =
        isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final bg = isSuccess ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: duration,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        content: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: Transform.scale(
                  scale: 0.92 + (0.08 * value),
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: accent.withOpacity(0.45),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: accent),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSuccess
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFFEE2E2),
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tombol utama Konversi & Perbarui Konfigurasi.
  /// Konfigurasi hanya dihasilkan saat tombol ini ditekan.
  Widget _buildConvertButton() {
    final canPress = !_busy;
    return AnimatedScale(
      scale: _busy ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canPress ? () => _convert(showEmptyError: true) : null,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
            decoration: BoxDecoration(
              gradient: _busy
                  ? const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(_busy ? 0.25 : 0.40),
                  blurRadius: _busy ? 10 : 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) {
                    return ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    );
                  },
                  child: _busy
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          key: ValueKey('idle'),
                          size: 20,
                          color: Colors.white,
                        ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _busy ? 'Sedang mengonversi…' : 'Konversi & Perbarui Konfigurasi',
                    key: ValueKey(_busy ? 'busy-label' : 'idle-label'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Banner status konversi (sukses / gagal) dengan hierarki visual yang rapi
  /// dan animasi masuk yang halus.
  Widget _buildStatusBanner() {
    final isSuccess = _isSuccessStatus;
    final accent = isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final softBg = accent.withOpacity(0.10);
    final borderColor = accent.withOpacity(0.35);

    // Ekstrak info tambahan dari string status agar bisa ditampilkan sebagai badge.
    final statusText = _status ?? '';
    final hasMulti = statusText.contains('Multi Serangga');
    final multiMatch = RegExp(r'Multi Serangga ×(\d+)').firstMatch(statusText);
    final multiCount = multiMatch?.group(1);
    final modeMatch = RegExp(r'\(Mode:\s*([A-Z]+)\)').firstMatch(statusText);
    final modeLabel = modeMatch?.group(1);

    // Teks utama yang lebih bersih (tanpa bagian yang sudah jadi badge).
    String mainMessage = statusText
        .replaceAll(RegExp(r'\s*→\s*\d+\s*outbound\s*\(Multi Serangga ×\d+\)'), '')
        .replaceAll(RegExp(r'\s*\(Mode:\s*[A-Z]+\)\.?'), '')
        .trim();
    if (mainMessage.endsWith('.')) {
      mainMessage = mainMessage.substring(0, mainMessage.length - 1);
    }
    if (isSuccess && hasMulti && multiCount != null) {
      // Tambahkan info outbound secara ringkas di teks utama.
      final outMatch = RegExp(r'→\s*(\d+)\s*outbound').firstMatch(statusText);
      final outCount = outMatch?.group(1);
      if (outCount != null) {
        mainMessage = '$mainMessage → $outCount outbound';
      }
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: softBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.1),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon dengan animasi subtle
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess ? Icons.check_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainMessage.isNotEmpty
                        ? mainMessage
                        : (isSuccess ? 'Konversi berhasil' : 'Konversi gagal'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: isSuccess
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFFEE2E2),
                    ),
                  ),
                  if (isSuccess && (hasMulti || modeLabel != null)) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (hasMulti && multiCount != null)
                          _statusBadge(
                            icon: Icons.bug_report_outlined,
                            label: 'Multi Serangga ×$multiCount',
                            color: const Color(0xFF6366F1),
                          ),
                        if (modeLabel != null)
                          _statusBadge(
                            icon: Icons.layers_outlined,
                            label: 'Mode $modeLabel',
                            color: const Color(0xFF06B6D4),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Badge kecil untuk status (Multi Serangga / Mode).
  Widget _statusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.95),
            ),
          ),
        ],
      ),
    );
  }

  /// Panel opsional multi-serangga: tiap akun digandakan × N dengan IP berbeda.
  Widget _buildSeranggaCard() {
    final totalPreview = _parsedNodes.isEmpty
        ? null
        : _parsedNodes.length *
            (_seranggaEnabled
                ? _seranggaCount.clamp(kSeranggaMin, kSeranggaMax)
                : 1);

    final sample = _parsedNodes.isEmpty ? null : _parsedNodes.first;
    final sampleBase = sample == null
        ? 'akun'
        : (sample.name.trim().isEmpty ? sample.protocol : sample.name.trim());
    final shownCount = _seranggaCount < 3 ? _seranggaCount : 3;
    final customNames = parseSeranggaHostList(_seranggaNameController.text);
    final namePreview = customNames.isNotEmpty
        ? (customNames.take(shownCount).join(', ') +
            (_seranggaCount > shownCount && customNames.length > shownCount
                ? ', …'
                : (customNames.length < _seranggaCount
                    ? ' (diulang)'
                    : '')))
        : ([
              for (var i = 1; i <= shownCount; i++)
                seranggaVariantName(sampleBase, i),
            ].join(', ') +
            (_seranggaCount > 3
                ? ', … ${seranggaVariantName(sampleBase, _seranggaCount)}'
                : ''));
    // manualHostCount = jumlah bug yang diketik; activeHostCount = yang benar-benar
    // dipakai (0 bila Wildcard utama sedang aktif dan mengunci bagian ini).
    final manualHostCount = _seranggaWildcardCount;
    final activeHostCount = _seranggaWildcardActive ? manualHostCount : 0;
    final manualNameCount = customNames.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _seranggaEnabled
            ? const Color(0xFF6366F1).withOpacity(0.10)
            : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _seranggaEnabled
              ? const Color(0xFF6366F1).withOpacity(0.55)
              : const Color(0xFF1F2937),
          width: _seranggaEnabled ? 1.4 : 1.0,
        ),
        boxShadow: _seranggaEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _seranggaEnabled
                      ? const Color(0xFF6366F1).withOpacity(0.25)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.bug_report_outlined,
                  size: 16,
                  color: _seranggaEnabled
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Multi Serangga',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _seranggaEnabled
                          ? 'Aktif · ${_seranggaCount} salinan / akun'
                          : 'Gandakan akun menjadi beberapa outbound',
                      style: TextStyle(
                        fontSize: 10,
                        color: _seranggaEnabled
                            ? const Color(0xFFA5B4FC)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 30,
                child: Switch.adaptive(
                  value: _seranggaEnabled,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    // Wildcard utama aktif → minta konfirmasi dulu; switch tetap
                    // mati sampai pengguna memilih Lanjutkan.
                    if (v && _mainWildcardActive) {
                      _showSeranggaWildcardConflictDialog();
                      return;
                    }
                    setState(() => _seranggaEnabled = v);
                  },
                ),
              ),
            ],
          ),

          // Description
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Gandakan tiap akun menjadi N outbound bernama unik. '
              'Server asli dipertahankan kecuali Wildcard Multi Serangga diisi.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: _seranggaEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Count row
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Jumlah serangga per akun',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                            ),
                            Container(
                              width: 78,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D131F),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withOpacity(0.4),
                                ),
                              ),
                              child: TextField(
                                controller: _seranggaCountController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  hintText: '3',
                                  hintStyle: TextStyle(color: Color(0xFF4B5563)),
                                ),
                                onChanged: (v) {
                                  final n = int.tryParse(v.trim());
                                  if (n == null) return;
                                  if (n > kSeranggaMax) {
                                    _normalizeSeranggaCount();
                                    return;
                                  }
                                  setState(() {
                                    _seranggaCount =
                                        n.clamp(kSeranggaMin, kSeranggaMax);
                                  });
                                },
                                onEditingComplete: () {
                                  _normalizeSeranggaCount();
                                  FocusScope.of(context).unfocus();
                                },
                                onTapOutside: (_) {
                                  _normalizeSeranggaCount();
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Batas: $kSeranggaMin – $kSeranggaMax  ·  '
                          '${totalPreview == null ? 'Contoh: 2 akun × $_seranggaCount = ${2 * _seranggaCount} outbound' : 'Perkiraan: ${_parsedNodes.length} × $_seranggaCount = $totalPreview outbound'}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                          ),
                        ),

                        // Name preview
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    manualNameCount > 0
                                        ? Icons.edit_note_rounded
                                        : Icons.auto_awesome,
                                    size: 13,
                                    color: const Color(0xFFA5B4FC),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    manualNameCount > 0
                                        ? 'Nama kustom aktif'
                                        : 'Nama otomatis',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFA5B4FC),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                namePreview,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFFE5E7EB),
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (activeHostCount > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Wildcard ($activeHostCount item)'
                                  ' · ${_bugModeLabel(_seranggaIpMode)}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Expandable advanced options
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(
                              () => _seranggaManualOpen = !_seranggaManualOpen,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  AnimatedRotation(
                                    turns: _seranggaManualOpen ? 0.5 : 0.0,
                                    duration: const Duration(milliseconds: 250),
                                    child: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      (activeHostCount > 0 ||
                                              manualNameCount > 0)
                                          ? 'Opsi lanjutan aktif'
                                          : 'Opsi lanjutan (Wildcard & nama kustom)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: (activeHostCount > 0 ||
                                                manualNameCount > 0)
                                            ? const Color(0xFFA5B4FC)
                                            : const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ),
                                  if (activeHostCount > 0 ||
                                      manualNameCount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${activeHostCount + manualNameCount}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFA5B4FC),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: _seranggaManualOpen
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Wildcard Multi Serangga (dikunci saat Wildcard utama aktif)
                                      if (_seranggaWildcardLocked)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 6),
                                          child: Text(
                                            'Dikunci: Wildcard utama sedang aktif. Nonaktifkan dulu untuk memakai bagian ini.',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              height: 1.3,
                                              color: Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ),
                                      AnimatedOpacity(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        opacity:
                                            _seranggaWildcardLocked ? 0.45 : 1.0,
                                        child: IgnorePointer(
                                          ignoring: _seranggaWildcardLocked,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                      const Text(
                                        'Wildcard',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Tulis bug berbeda untuk tiap serangga, satu per baris. Dipakai bergiliran '
                                        'sesuai cara penerapan di bawah. Kosongkan untuk mempertahankan server asli.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          height: 1.3,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _seranggaIpController,
                                        maxLines: 3,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText:
                                              'contoh.com\n1.2.3.4\ncdn.example.net',
                                          hintStyle: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF4B5563),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFF0A0E17),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF1F2937)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF1F2937)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF6366F1),
                                              width: 1.4,
                                            ),
                                          ),
                                        ),
                                        onChanged: (_) {
                                          setState(() {});
                                          if (_parsedNodes.isNotEmpty) {
                                          }
                                        },
                                      ),

                                      // Apply toggles
                                      if (manualHostCount > 0) ...[
                                        const SizedBox(height: 10),
                                        const Text(
                                          'Terapkan juga ke',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFE5E7EB),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildSeranggaModeChip(
                                                  BugWildcardMode.biasa),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildSeranggaModeChip(
                                                  BugWildcardMode.sni),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildSeranggaModeChip(
                                                  BugWildcardMode.serverHost),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildSeranggaModeChip(
                                                  BugWildcardMode.serverOnly),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${_seranggaModeDetail(_seranggaIpMode)}. '
                                          'Sesuaikan dengan jenis koneksi (WS, TLS, atau gRPC).',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            height: 1.3,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],

                                            ],
                                          ),
                                        ),
                                      ),

                                      // Custom names section
                                      const SizedBox(height: 14),
                                      const Text(
                                        'Daftar nama kustom (opsional)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Satu nama per baris (huruf, angka, atau kata). '
                                        'Jika diisi, dipakai sebagai nama outbound alih-alih -1, -2, ….',
                                        style: TextStyle(
                                          fontSize: 10,
                                          height: 1.3,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _seranggaNameController,
                                        maxLines: 3,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText:
                                              'SG-Premium-A\nSG-Premium-B\nID-Fast',
                                          hintStyle: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF4B5563),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFF0A0E17),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF1F2937)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF1F2937)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF6366F1),
                                              width: 1.4,
                                            ),
                                          ),
                                        ),
                                        onChanged: (_) {
                                          setState(() {});
                                          if (_parsedNodes.isNotEmpty) {
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Chip pilihan cara penerapan Wildcard Multi Serangga (pilih satu, sama dengan Wildcard).
  Widget _buildSeranggaModeChip(BugWildcardMode mode) {
    return _buildSeranggaToggleChip(
      label: _bugModeLabel(mode),
      value: _seranggaIpMode == mode,
      onChanged: (_) => setState(() => _seranggaIpMode = mode),
    );
  }

  /// Ringkasan hasil tiap cara penerapan; `<host>` = bug pada daftar Wildcard Multi Serangga.
  String _seranggaModeDetail(BugWildcardMode mode) {
    switch (mode) {
      case BugWildcardMode.biasa:
        return 'server = <host> · SNI/Host = <host>.<asli>';
      case BugWildcardMode.sni:
        return 'servername = <host> · server tetap asli';
      case BugWildcardMode.serverHost:
        return 'server = <host> · Host = <host>';
      case BugWildcardMode.serverOnly:
        return 'server = <host> · SNI & Host tetap asli';
      case BugWildcardMode.none:
        return '';
    }
  }

  /// Chip kecil pilihan tunggal di kartu Multi Serangga.
  Widget _buildSeranggaToggleChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: value
          ? const Color(0xFF6366F1).withOpacity(0.2)
          : const Color(0xFF111827),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value
                  ? const Color(0xFF6366F1).withOpacity(0.6)
                  : const Color(0xFF1F2937),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: value
                    ? const Color(0xFFA5B4FC)
                    : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: value
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF9CA3AF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWildcardPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 24 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF374151),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: Color(0xFFA5B4FC),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pilih Mode Wildcard',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                () {
                                  final list = parseSeranggaHostList(
                                      _bugController.text);
                                  if (list.length <= 1) {
                                    return 'Bug: ${list.isEmpty ? '' : list.first}';
                                  }
                                  return '${list.length} bug (per akun): ${list.join(' · ')}';
                                }(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFFA5B4FC),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D131F),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Pilih cara penerapan bug. Sesuaikan dengan jenis koneksi (WS, TLS, atau gRPC).',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildWildcardOption(
                      ctx,
                      BugWildcardMode.biasa,
                      'Wildcard biasa',
                      'Server = bug. SNI/Host = bug digabung server asli (bug.server-asli).',
                      Icons.language_rounded,
                    ),
                    _buildWildcardOption(
                      ctx,
                      BugWildcardMode.sni,
                      'Timpa SNI',
                      'Hanya SNI/servername diganti ke bug. Server tetap milik akun asli.',
                      Icons.badge_outlined,
                    ),
                    _buildWildcardOption(
                      ctx,
                      BugWildcardMode.serverHost,
                      'Server & WS Host',
                      'Server dan Host header diganti ke bug. Cocok untuk WebSocket.',
                      Icons.dns_outlined,
                    ),
                    _buildWildcardOption(
                      ctx,
                      BugWildcardMode.serverOnly,
                      'Server saja',
                      'Hanya server diganti. SNI dan Host tetap milik akun asli.',
                      Icons.swap_horiz_rounded,
                    ),
                    if (_bugMode != BugWildcardMode.none) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _bugMode = BugWildcardMode.none);
                          },
                          icon: const Icon(
                            Icons.highlight_off_rounded,
                            size: 16,
                            color: Color(0xFF9CA3AF),
                          ),
                          label: const Text(
                            'Nonaktifkan wildcard',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            Navigator.pop(ctx);
            setState(() => _bugMode = mode);
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF6366F1).withOpacity(0.14)
                  : const Color(0xFF0D131F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFF6366F1).withOpacity(0.55)
                    : const Color(0xFF1F2937),
                width: selected ? 1.3 : 1.0,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF6366F1).withOpacity(0.25)
                        : const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? const Color(0xFFA5B4FC)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedOpacity(
                  opacity: selected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF818CF8),
                  ),
                ),
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

  /// True jika addon dengan [core] relevan terhadap halaman inti yang aktif.
  bool _isCoreRelevant(String core) {
    if (core == 'both') return true;
    if (_target == OutputTarget.clash && core == 'clash') return true;
    if (_target == OutputTarget.singbox && core == 'singbox') return true;
    return false;
  }

  /// Dialog peringatan untuk addon berisiko (dapat menyebabkan gagal konek / error).
  /// Gaya diselaraskan dengan tema gelap aplikasi (latar #111827, aksen indigo).
  void _showRiskyAddonWarning({required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1F2937)),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Peringatan Addon',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Opsi ini bersifat lanjutan. Biarkan default jika Anda belum familiar.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFFD1D5DB),
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF9CA3AF),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Batal', style: TextStyle(fontSize: 13)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Lanjutkan', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Peringatan saat Multi Serangga dihidupkan sementara Wildcard utama aktif.
  /// Multi Serangga memakai Wildcard miliknya sendiri; Lanjutkan = nonaktifkan
  /// Wildcard utama, hidupkan Multi Serangga, lalu buka Opsi lanjutan.
  /// Tampilan: kartu bertema gelap-indigo dengan animasi masuk, ikon peringatan
  /// berdenyut, panah alur yang bergerak, dan tombol yang bereaksi saat disentuh.
  Future<void> _showSeranggaWildcardConflictDialog() async {
    HapticFeedback.mediumImpact();
    final bugCount = parseSeranggaHostList(_bugController.text).length;
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'peringatan-wildcard',
      barrierColor: Colors.black.withOpacity(0.72),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, anim, secondary) => Center(
        child: _SeranggaConflictDialog(bugCount: bugCount),
      ),
      transitionBuilder: (ctx, anim, secondary, child) {
        final fade = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        final pop = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(fade),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1.0).animate(pop),
              child: child,
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _bugMode = BugWildcardMode.none;
      _seranggaEnabled = true;
      _seranggaManualOpen = true;
    });
    _showCapsuleSnack(
      message: 'Multi Serangga aktif · Wildcard utama dinonaktifkan',
      icon: Icons.bug_report_outlined,
      isSuccess: true,
    );
  }

  Widget _buildCheckboxTile(
    String title,
    String subtitle,
    bool val,
    ValueChanged<bool?> onChanged, {
    String core = 'both',
    bool risky = false,
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
            ],
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF9CA3AF)),
          ),
          value: val,
          activeColor: const Color(0xFF6366F1),
          onChanged: (v) {
            if (risky) {
              _showRiskyAddonWarning(
                onConfirm: () {
                  onChanged(v);
                },
              );
            } else {
              onChanged(v);
            }
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
        ],
      ),
    );
  }

  Widget _buildNodeBadge(Node n) {
    Color badgeColor = const Color(0xFF6366F1);
    if (n.protocol == 'vmess') badgeColor = const Color(0xFFA855F7);
    if (n.protocol == 'trojan') badgeColor = const Color(0xFFF59E0B);
    final name = n.name.trim().isEmpty ? n.server : n.name.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            n.protocol.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: badgeColor,
            ),
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
          if (n.region.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              n.region,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF06B6D4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tombol aksi kecil bergaya "pill" (Tempel / Hapus) di header kartu input.
  Widget _buildMiniAction(String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tombol ikon hasil konfigurasi dengan feedback visual.
  Widget _buildOutputIconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    final enabled = _currentResultText.isNotEmpty;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.35,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? _coreAccent.withOpacity(0.12)
                    : const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled
                      ? _coreAccent.withOpacity(0.30)
                      : const Color(0xFF1F2937),
                ),
              ),
              child: Icon(
                icon,
                size: 17,
                color: enabled ? _coreAccent : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bubble sapaan Cora (overlay ringan di bawah ikon AppBar)
// ═══════════════════════════════════════════════════════════════════════════

class _CoraGreetingBubble extends StatefulWidget {
  final String text;
  final VoidCallback onDismiss;

  const _CoraGreetingBubble({
    required this.text,
    required this.onDismiss,
  });

  @override
  State<_CoraGreetingBubble> createState() => _CoraGreetingBubbleState();
}

class _CoraGreetingBubbleState extends State<_CoraGreetingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.08, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Ekor kecil mengarah ke ikon Cora
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: CustomPaint(
                      size: const Size(12, 7),
                      painter: _BubbleTailPainter(
                        color: const Color(0xFF111827),
                        borderColor: const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1F2937)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TutorRobot(
                          size: 22,
                          accent: Color(0xFF6366F1),
                          mood: RobotMood.wave,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.text,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 2, top: 1),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
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
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _BubbleTailPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) =>
      old.color != color || old.borderColor != borderColor;
}

// ═══════════════════════════════════════════════════════════════════════════
// Dialog peringatan: Multi Serangga vs Wildcard utama
// ═══════════════════════════════════════════════════════════════════════════

class _SeranggaConflictDialog extends StatefulWidget {
  /// Jumlah bug yang sedang diisi di Wildcard utama (untuk label kartu).
  final int bugCount;

  const _SeranggaConflictDialog({required this.bugCount});

  @override
  State<_SeranggaConflictDialog> createState() =>
      _SeranggaConflictDialogState();
}

class _SeranggaConflictDialogState extends State<_SeranggaConflictDialog>
    with TickerProviderStateMixin {
  static const _amber = Color(0xFFF59E0B);
  static const _indigo = Color(0xFF6366F1);
  static const _indigoSoft = Color(0xFFA5B4FC);

  /// Sekali jalan: ikon muncul membal, lalu konten muncul berurutan.
  late final AnimationController _enter;

  /// Berulang: cincin denyut, panah mengalir, cahaya kartu tujuan.
  late final AnimationController _loop;

  late final Animation<double> _iconPop;
  late final Animation<double> _shake;
  late final Animation<double> _stepTitle;
  late final Animation<double> _stepFlow;
  late final Animation<double> _stepBody;
  late final Animation<double> _stepButtons;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    Animation<double> seg(double from, double to, Curve curve) => _enter.drive(
          CurveTween(curve: Interval(from, to, curve: curve)),
        );
    _iconPop = seg(0.0, 0.55, Curves.elasticOut);
    _shake = seg(0.25, 0.9, Curves.linear);
    _stepTitle = seg(0.18, 0.5, Curves.easeOutCubic);
    _stepFlow = seg(0.32, 0.64, Curves.easeOutCubic);
    _stepBody = seg(0.46, 0.78, Curves.easeOutCubic);
    _stepButtons = seg(0.60, 0.92, Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Muncul pelan dari bawah (fade + geser) sesuai animasi [a].
  Widget _reveal(Animation<double> a, Widget child) {
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, c) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - a.value)),
          child: c,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(media.width - 48, 340),
          maxHeight: media.height * 0.88,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF141B2D), Color(0xFF0D131F)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _indigo.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: _indigo.withOpacity(0.16),
                blurRadius: 28,
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIcon(),
                const SizedBox(height: 10),
                _reveal(
                  _stepTitle,
                  const Column(
                    children: [
                      Text(
                        'Wildcard utama sedang aktif',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Tidak bisa dipakai bersamaan dengan Multi Serangga',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _reveal(_stepFlow, _buildFlow()),
                const SizedBox(height: 14),
                _reveal(_stepBody, _buildBody()),
                const SizedBox(height: 16),
                _reveal(_stepButtons, _buildButtons()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ikon peringatan: muncul membal + bergoyang, dua cincin denyut berselang.
  Widget _buildIcon() {
    return SizedBox(
      width: 76,
      height: 76,
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _loop]),
        builder: (context, _) {
          final t = _loop.value;
          final pop = _iconPop.value.clamp(0.0, 1.4);
          final shake =
              math.sin(_shake.value * math.pi * 6) * (1 - _shake.value) * 0.28;
          final glow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final phase in const [0.0, 0.5])
                Builder(builder: (_) {
                  final p = (t + phase) % 1.0;
                  final size = 46 + 30 * p;
                  return Opacity(
                    opacity: (0.45 * (1 - p)).clamp(0.0, 1.0),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _amber, width: 1.5),
                      ),
                    ),
                  );
                }),
              Transform.scale(
                scale: pop,
                child: Transform.rotate(
                  angle: shake,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _amber.withOpacity(0.15),
                      border: Border.all(color: _amber.withOpacity(0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: _amber.withOpacity(0.10 + 0.18 * glow),
                          blurRadius: 10 + 8 * glow,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 26,
                      color: _amber,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Alur: kartu Wildcard utama (dimatikan) → panah mengalir → Multi Serangga.
  Widget _buildFlow() {
    final mainSubtitle = widget.bugCount > 1
        ? '${widget.bugCount} bug · akan dimatikan'
        : 'akan dimatikan';
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final t = _loop.value;
        final glow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _flowChip(
                title: 'Wildcard utama',
                subtitle: mainSubtitle,
                active: false,
                glow: 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Opacity(
                      opacity: (0.2 +
                              0.8 *
                                  math.max(
                                    0.0,
                                    math.sin(
                                      (((t - i * 0.18) % 1.0) + 1.0) %
                                          1.0 *
                                          math.pi,
                                    ),
                                  ))
                          .clamp(0.0, 1.0),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: _indigoSoft,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _flowChip(
                title: 'Multi Serangga',
                subtitle: 'Wildcard sendiri',
                active: true,
                glow: glow,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _flowChip({
    required String title,
    required String subtitle,
    required bool active,
    required double glow,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: active ? _indigo.withOpacity(0.12) : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? _indigo.withOpacity(0.45 + 0.25 * glow)
              : const Color(0xFF1F2937),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _indigo.withOpacity(0.10 + 0.14 * glow),
                  blurRadius: 6 + 8 * glow,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bug_report_outlined,
            size: 18,
            color: active ? _indigoSoft : const Color(0xFF6B7280),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFFE0E7FF) : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              color: active ? _indigoSoft : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        const Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFFD1D5DB),
            ),
            children: [
              TextSpan(text: 'Jika memakai Multi Serangga, gunakan '),
              TextSpan(
                text: 'Wildcard milik Multi Serangga',
                style: TextStyle(
                  color: _indigoSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: ' (Opsi lanjutan → Wildcard) agar tiap serangga bisa '
                    'memakai bug berbeda.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _amber.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _amber.withOpacity(0.28)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: _amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lanjutkan akan menonaktifkan Wildcard utama.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: Color(0xFFFCD34D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: _PressableDialogButton(
            label: 'Batal',
            filled: false,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: _PressableDialogButton(
            label: 'Lanjutkan',
            icon: Icons.arrow_forward_rounded,
            filled: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }
}

/// Tombol dialog yang mengecil sedikit saat ditekan dan memberi getaran halus.
class _PressableDialogButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;

  const _PressableDialogButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  State<_PressableDialogButton> createState() => _PressableDialogButtonState();
}

class _PressableDialogButtonState extends State<_PressableDialogButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(11);
    return AnimatedScale(
      scale: _down ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          gradient: widget.filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                )
              : null,
          color: widget.filled ? null : const Color(0xFF0D131F),
          borderRadius: radius,
          border: Border.all(
            color: widget.filled
                ? const Color(0xFFA5B4FC).withOpacity(0.35)
                : const Color(0xFF1F2937),
          ),
          boxShadow: widget.filled
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onHighlightChanged: (v) => setState(() => _down = v),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.filled
                          ? Colors.white
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  if (widget.icon != null) ...[
                    const SizedBox(width: 6),
                    Icon(widget.icon, size: 16, color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
