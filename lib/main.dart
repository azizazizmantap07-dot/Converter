import 'dart:convert';
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

enum OutputTarget { clash, singbox }
enum ConverterModeType { minimal, lengkap, custom }
enum InputProtocolMode { xray, ssh }

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

/// Draft konfigurasi SSH tunggal (multi-akun).
class SshAccountDraft {
  String name;
  String hostPort;
  String username;
  String password;
  String payload;
  String proxy;
  String sni;
  bool useTls;

  SshAccountDraft({
    this.name = '',
    this.hostPort = '',
    this.username = '',
    this.password = '',
    this.payload =
        'GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]Upgrade: websocket[crlf][crlf]',
    this.proxy = '',
    this.sni = '',
    this.useTls = false,
  });

  SshAccountDraft copy() => SshAccountDraft(
        name: name,
        hostPort: hostPort,
        username: username,
        password: password,
        payload: payload,
        proxy: proxy,
        sni: sni,
        useTls: useTls,
      );

  bool get isFilled =>
      hostPort.trim().isNotEmpty && username.trim().isNotEmpty;
}

class HomePage extends StatefulWidget {

  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _searchController = TextEditingController();

  /// Mode input: tautan X-ray (vmess/vless/trojan) atau form SSH.
  InputProtocolMode _inputMode = InputProtocolMode.xray;

  // --- SSH multi-akun ---
  final List<SshAccountDraft> _sshAccounts = [SshAccountDraft()];
  int _sshActiveIndex = 0;
  int _sshSlideDir = 1; // 1 = ke kanan (indeks naik), -1 = ke kiri
  final _sshHostController = TextEditingController();
  final _sshUserController = TextEditingController();
  final _sshPassController = TextEditingController();
  final _sshNameController = TextEditingController();
  final _sshPayloadController = TextEditingController(
    text: 'GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]Upgrade: websocket[crlf][crlf]',
  );
  final _sshProxyController = TextEditingController();
  final _sshSniController = TextEditingController();
  bool _sshUseTls = false;
  bool _sshObscurePass = true;

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
  final _seranggaCountController = TextEditingController(text: '3');

  /// Mode wildcard bug yang aktif (none = tidak diterapkan).
  BugWildcardMode _bugMode = BugWildcardMode.none;

  /// Onering (domain fronting split-host). Tidak bisa bersamaan dengan Wildcard.
  bool _oneringEnabled = false;
  bool _oneringChecking = false;
  /// null = belum cek, true = match, false = mismatch.
  bool? _oneringCompatOk;
  String _oneringCompatMessage = '';
  /// Tahap animasi pengecekan: 0 idle, 1 normalisasi, 2 DNS bug, 3 HTTP bug,
  /// 4 DNS/HTTP VPS, 5 evaluasi.
  int _oneringCheckStage = 0;
  String _oneringCheckStageLabel = '';
  late final AnimationController _oneringPulseCtrl;
  late final AnimationController _oneringSweepCtrl;
  /// Key node yang sudah diterapkan Onering (name|serverAsli|uuid).
  final Set<String> _oneringAppliedKeys = {};
  /// Server VPS asli per key (sebelum Onering) untuk referensi.
  final Map<String, String> _oneringOriginalServer = {};

  /// Multi-serangga: gandakan tiap akun × N (opsional).
  bool _seranggaEnabled = false;
  int _seranggaCount = 3;

  /// Panel "IP/host manual (opsional)" di kartu Multi Serangga sedang dibuka.
  bool _seranggaManualOpen = false;

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
    if (_parsedNodes.isNotEmpty) _convert();
  }

  List<Node> _parsedNodes = [];
  String _clashOutput = '';
  String _singboxOutput = '';
  String? _status;
  bool _isSuccessStatus = true;
  bool _busy = false;


  String _stableNodeKey(Node n) {
    final id = n.uuid.isNotEmpty ? n.uuid : n.password;
    return '${n.protocol}|${n.name}|$id';
  }

  /// Bersihkan input host: buang skema, path, port, spasi.
  String _normalizeHost(String raw) {
    var h = raw.trim().toLowerCase();
    if (h.isEmpty) return '';
    h = h.replaceFirst(RegExp(r'^https?://'), '');
    h = h.split('/').first;
    h = h.split('?').first;
    if (h.startsWith('[')) {
      final end = h.indexOf(']');
      if (end > 0) return h.substring(1, end);
    }
    final m = RegExp(r'^(.+):(\d+)$').firstMatch(h);
    if (m != null) h = m.group(1)!;
    return h.trim();
  }

  /// Deteksi CDN dari pola nama domain / CNAME target.
  String? _detectCdnFromHostname(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (h.isEmpty) return null;

    // CloudFront
    if (h.endsWith('.cloudfront.net') ||
        h == 'cloudfront.net' ||
        h.contains('.cloudfront.')) {
      return 'cloudfront';
    }
    // Cloudflare
    if (h.endsWith('.cdn.cloudflare.net') ||
        h.endsWith('.cloudflare.com') ||
        h.endsWith('.cloudflare.net') ||
        h.endsWith('.cloudflare-dns.com') ||
        h.contains('pages.dev') ||
        h.contains('workers.dev') ||
        h.contains('r2.dev')) {
      return 'cloudflare';
    }
    // Fastly
    if (h.endsWith('.fastly.net') ||
        h.endsWith('.fastlylb.net') ||
        h.endsWith('.global.ssl.fastly.net') ||
        h.contains('.fastly.')) {
      return 'fastly';
    }
    // Akamai
    if (h.endsWith('.akamai.net') ||
        h.endsWith('.akamaiedge.net') ||
        h.endsWith('.akamaized.net') ||
        h.endsWith('.edgekey.net') ||
        h.endsWith('.edgesuite.net') ||
        h.contains('akamai')) {
      return 'akamai';
    }
    // Azure CDN / Front Door
    if (h.endsWith('.azureedge.net') ||
        h.endsWith('.azurefd.net') ||
        h.endsWith('.trafficmanager.net')) {
      return 'azurecdn';
    }
    // Google / GFE
    if (h.endsWith('.googleusercontent.com') ||
        h.endsWith('.googlevideo.com') ||
        h.endsWith('.google.com') ||
        h.endsWith('.ghs.googlehosted.com')) {
      return 'google';
    }
    // Bunny / KeyCDN / StackPath / DDoS-Guard / Imperva
    if (h.endsWith('.b-cdn.net') || h.contains('bunnycdn')) return 'bunny';
    if (h.endsWith('.kxcdn.com')) return 'keycdn';
    if (h.contains('stackpath') || h.endsWith('.hwcdn.net')) return 'stackpath';
    if (h.endsWith('.ddos-guard.net')) return 'ddosguard';
    if (h.contains('incapsula') || h.endsWith('.incapdns.net')) return 'imperva';

    return null;
  }

  /// Lookup CNAME chain via DNS-over-HTTPS (Cloudflare + Google fallback).
  Future<List<String>> _lookupCnameChain(String host) async {
    final chain = <String>[];
    var current = host.toLowerCase();
    for (var depth = 0; depth < 6; depth++) {
      String? next;
      for (final base in [
        'https://cloudflare-dns.com/dns-query',
        'https://dns.google/resolve',
      ]) {
        try {
          final uri = Uri.parse(base).replace(queryParameters: {
            'name': current,
            'type': 'CNAME',
          });
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 4);
          final req =
              await client.getUrl(uri).timeout(const Duration(seconds: 4));
          req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
          req.headers.set(
            HttpHeaders.userAgentHeader,
            'ProxyConverter/1.0',
          );
          final res = await req.close().timeout(const Duration(seconds: 4));
          final body = await res.transform(utf8.decoder).join();
          client.close(force: true);
          final data = jsonDecode(body);
          if (data is Map && data['Answer'] is List) {
            for (final ans in data['Answer'] as List) {
              if (ans is Map &&
                  (ans['type'] == 5 || ans['type'] == '5') &&
                  ans['data'] is String) {
                next = (ans['data'] as String).toLowerCase().replaceAll(
                      RegExp(r'\.$'),
                      '',
                    );
                break;
              }
            }
          }
          if (next != null) break;
        } catch (_) {
          // coba resolver berikutnya
        }
      }
      if (next == null || next.isEmpty || next == current) break;
      chain.add(next);
      current = next;
      // jika sudah ketemu pola CDN di CNAME, cukup
      if (_detectCdnFromHostname(next) != null) break;
    }
    return chain;
  }

  /// Deteksi CDN dari issuer sertifikat TLS.
  Future<String?> _detectCdnFromTls(String host) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (_) => true,
      );
      final cert = socket.peerCertificate;
      socket.destroy();
      if (cert == null) return null;
      final subject = cert.subject.toLowerCase();
      final issuer = cert.issuer.toLowerCase();
      final blob = '$subject $issuer';
      if (blob.contains('cloudflare')) return 'cloudflare';
      if (blob.contains('amazon') ||
          blob.contains('cloudfront') ||
          blob.contains('aws')) {
        // Sertifikat Amazon sering dipakai CloudFront
        return 'cloudfront';
      }
      if (blob.contains('fastly')) return 'fastly';
      if (blob.contains('akamai')) return 'akamai';
      if (blob.contains('google')) return 'google';
      if (blob.contains('microsoft') || blob.contains('azure')) return 'azurecdn';
    } catch (_) {}
    return null;
  }

  Future<CdnDetectResult> _detectCdn(String host) async {
    final h = _normalizeHost(host);
    if (h.isEmpty) {
      return const CdnDetectResult(
        host: '',
        provider: 'unknown',
        detail: 'host kosong',
      );
    }

    final evidence = <String>[];

    // 1) Pola hostname langsung
    final byName = _detectCdnFromHostname(h);
    if (byName != null) {
      return CdnDetectResult(
        host: h,
        provider: byName,
        method: 'hostname',
        detail: 'pola domain → $byName',
      );
    }

    // 2) Rantai CNAME (DoH) — kritis untuk bug domain kustom di balik CDN
    try {
      final chain = await _lookupCnameChain(h);
      if (chain.isNotEmpty) {
        evidence.add('CNAME: ${chain.join(' → ')}');
        for (final c in chain) {
          final p = _detectCdnFromHostname(c);
          if (p != null) {
            return CdnDetectResult(
              host: h,
              provider: p,
              method: 'cname',
              detail: 'CNAME ${chain.join(' → ')} → $p',
            );
          }
        }
      }
    } catch (e) {
      evidence.add('CNAME gagal');
    }

    // 3) DNS A record → subnet CDN
    String? dnsIp;
    try {
      final list =
          await InternetAddress.lookup(h).timeout(const Duration(seconds: 5));
      for (final addr in list) {
        if (addr.type == InternetAddressType.IPv4) {
          dnsIp ??= addr.address;
          final provider = _matchCdnProviderByIp(addr.address);
          if (provider != null) {
            return CdnDetectResult(
              host: h,
              provider: provider,
              method: 'dns',
              detail: '${addr.address} → $provider',
            );
          }
        }
      }
      if (dnsIp != null) evidence.add('IP $dnsIp');
    } catch (_) {
      evidence.add('DNS gagal');
    }

    // 4) TLS certificate issuer
    try {
      final tls = await _detectCdnFromTls(h);
      if (tls != null) {
        return CdnDetectResult(
          host: h,
          provider: tls,
          method: 'tls',
          detail: 'sertifikat → $tls',
        );
      }
    } catch (_) {}

    // 5) HTTP fingerprint (header tetap dibaca meski 403/404)
    for (final scheme in ['https', 'http']) {
      for (final method in ['HEAD', 'GET']) {
        HttpClient? client;
        try {
          client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..idleTimeout = const Duration(seconds: 5)
            ..autoUncompress = true;
          client.badCertificateCallback = (cert, host, port) => true;
          final uri = Uri.parse('$scheme://$h/');
          final req = await client
              .openUrl(method, uri)
              .timeout(const Duration(seconds: 5));
          req.followRedirects = true;
          req.maxRedirects = 5;
          req.headers.set(
            HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          );
          req.headers.set(HttpHeaders.acceptHeader, '*/*');
          final res = await req.close().timeout(const Duration(seconds: 5));
          final headers = <String, String>{};
          res.headers.forEach((name, values) {
            headers[name.toLowerCase()] = values.join(', ');
          });
          await res.drain<void>().timeout(
                const Duration(seconds: 3),
                onTimeout: () => null,
              );
          client.close(force: true);

          final provider = _guessProviderFromHttpHeaders(headers);
          if (provider != 'unknown') {
            return CdnDetectResult(
              host: h,
              provider: provider,
              method: 'http',
              detail: '$scheme/$method ${res.statusCode} → $provider',
            );
          }
          // simpan petunjuk header mentah untuk debug
          final server = headers['server'] ?? '';
          final via = headers['via'] ?? '';
          if (server.isNotEmpty || via.isNotEmpty) {
            evidence.add('hdr server=$server via=$via');
          }
        } catch (_) {
          try {
            client?.close(force: true);
          } catch (_) {}
        }
      }
    }

    return CdnDetectResult(
      host: h,
      provider: 'unknown',
      method: 'none',
      detail: evidence.isEmpty
          ? 'CDN tidak dikenali'
          : evidence.join('; '),
    );
  }

  String? _matchCdnProviderByIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return null;

    // Cloudflare (publikasi rentang utama)
    if (a == 103 && (b == 21 || b == 22 || b == 31)) return 'cloudflare';
    if (a == 104 && b >= 16 && b <= 31) return 'cloudflare';
    if (a == 108 && b == 162) return 'cloudflare';
    if (a == 131 && b == 0) return 'cloudflare';
    if (a == 141 && b == 101) return 'cloudflare';
    if (a == 162 && (b == 158 || b == 159)) return 'cloudflare';
    if (a == 172 && b >= 64 && b <= 71) return 'cloudflare';
    if (a == 173 && b == 245) return 'cloudflare';
    if (a == 188 && b == 114) return 'cloudflare';
    if (a == 190 && b == 93) return 'cloudflare';
    if (a == 197 && b == 234) return 'cloudflare';
    if (a == 198 && b == 41) return 'cloudflare';

    // CloudFront — banyak POP di 3.x, 13.x, 18.x, 52.x, 54.x
    if (a == 3 && b >= 160 && b <= 175) return 'cloudfront';
    if (a == 13 && b >= 32 && b <= 249) return 'cloudfront';
    if (a == 18 && b >= 154 && b <= 238) return 'cloudfront';
    if (a == 52 && ((b >= 84 && b <= 86) || b == 222)) return 'cloudfront';
    if (a == 54 &&
        (b == 182 || b == 192 || b == 230 || b == 239 || b == 240)) {
      return 'cloudfront';
    }
    if (a == 64 && b == 252) return 'cloudfront';
    if (a == 65 && (b == 8 || b == 9)) return 'cloudfront';
    if (a == 70 && b == 132) return 'cloudfront';
    if (a == 71 && b == 152) return 'cloudfront';
    if (a == 99 && b >= 84 && b <= 87) return 'cloudfront';
    if (a == 143 && b == 204) return 'cloudfront';
    if (a == 204 && b == 246) return 'cloudfront';
    if (a == 205 && b == 251) return 'cloudfront';
    if (a == 216 && b == 137) return 'cloudfront';

    // Fastly
    if (a == 23 && b == 235) return 'fastly';
    if (a == 151 && b == 101) return 'fastly';
    if (a == 199 && b == 232) return 'fastly';

    // Akamai (sampel luas)
    if (a == 23 && b >= 32 && b <= 67) return 'akamai';
    if (a == 104 && b >= 64 && b <= 127) return 'akamai';

    return null;
  }

  String _guessProviderFromHttpHeaders(Map<String, String> headers) {
    final lower = <String, String>{};
    headers.forEach((k, v) => lower[k.toLowerCase()] = v.toLowerCase());
    final server = lower['server'] ?? '';
    final via = lower['via'] ?? '';
    final xcache = lower['x-cache'] ?? '';
    final powered = lower['x-powered-by'] ?? '';

    if (server.contains('cloudflare') ||
        lower.containsKey('cf-ray') ||
        lower.containsKey('cf-cache-status') ||
        lower.containsKey('cf-apo-via')) {
      return 'cloudflare';
    }
    if (via.contains('cloudfront') ||
        server.contains('cloudfront') ||
        lower.containsKey('x-amz-cf-id') ||
        lower.containsKey('x-amz-cf-pop') ||
        xcache.contains('cloudfront')) {
      return 'cloudfront';
    }
    if (lower.containsKey('x-served-by') ||
        xcache.contains('fastly') ||
        server.contains('fastly') ||
        via.contains('fastly')) {
      return 'fastly';
    }
    if (server.contains('akamai') ||
        server.contains('akamaighost') ||
        lower.containsKey('x-akamai-request-id')) {
      return 'akamai';
    }
    if (server.contains('gws') ||
        server.contains('gfe') ||
        lower.containsKey('x-google-')) {
      return 'google';
    }
    if (via.contains('azure') ||
        server.contains('azure') ||
        lower.containsKey('x-azure-ref')) {
      return 'azurecdn';
    }
    if (server.contains('ddos-guard') || powered.contains('ddos-guard')) {
      return 'ddosguard';
    }
    if (server.contains('incapsula') || lower.containsKey('x-cdn')) {
      final xcdn = lower['x-cdn'] ?? '';
      if (xcdn.contains('incapsula') || server.contains('incapsula')) {
        return 'imperva';
      }
    }
    if (server.contains('bunny') || lower.containsKey('cdn-pullzone')) {
      return 'bunny';
    }
    return 'unknown';
  }

  Future<void> _runOneringCompatCheck() async {
    final bug = _bugController.text.trim();
    if (bug.isEmpty) {
      setState(() {
        _oneringCompatOk = false;
        _oneringCompatMessage = 'Isi Input Bug dulu sebelum cek Onering.';
      });
      return;
    }
    final xray = _parsedNodes
        .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
        .toList();
    if (xray.isEmpty) {
      // parse dulu dari input
      final fromInput = parseLinks(_inputController.text)
          .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
          .toList();
      if (fromInput.isEmpty) {
        setState(() {
          _oneringCompatOk = false;
          _oneringCompatMessage =
              'Tempel minimal satu link vmess/vless/trojan untuk dicek.';
        });
        return;
      }
    }

    setState(() {
      _oneringChecking = true;
      _oneringCompatOk = null;
      _oneringCompatMessage = '';
      _oneringCheckStage = 1;
      _oneringCheckStageLabel = 'Menyiapkan host...';
    });
    _startOneringCheckAnim();

    try {
      final nodes = _parsedNodes
          .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
          .toList();
      final checkNodes = nodes.isNotEmpty
          ? nodes
          : parseLinks(_inputController.text)
              .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
              .toList();

      await _setOneringStage(2, 'Resolusi DNS & fingerprint bug...');
      final bugRes = await _detectCdn(bug);
      final servers = <String>{};
      for (final n in checkNodes) {
        final s = _normalizeHost(n.server);
        if (s.isNotEmpty) servers.add(s);
        if (servers.length >= 5) break;
      }
      if (servers.isEmpty) {
        setState(() {
          _oneringChecking = false;
          _oneringCompatOk = false;
          _oneringCompatMessage = 'Tidak ada server VPS pada link.';
        });
        return;
      }

      var anyMatch = false;
      var anyKnownPair = false;
      final lines = <String>[];
      lines.add(
        'Bug [${bugRes.host}]: ${bugRes.provider} (${bugRes.method})'
        '${bugRes.detail.isNotEmpty ? " — ${bugRes.detail}" : ""}',
      );

      await _setOneringStage(3, 'Memeriksa server VPS (${servers.length})...');
      var srvIdx = 0;
      for (final srv in servers) {
        srvIdx++;
        await _setOneringStage(
          3,
          'VPS $srvIdx/${servers.length}: $srv',
        );
        final vpsRes = await _detectCdn(srv);
        final match = vpsRes.isKnown &&
            bugRes.isKnown &&
            vpsRes.provider == bugRes.provider;
        if (vpsRes.isKnown && bugRes.isKnown) anyKnownPair = true;
        if (match) anyMatch = true;
        lines.add(
          'VPS [${vpsRes.host}]: ${vpsRes.provider} (${vpsRes.method})'
          ' → ${match ? "COCOK" : "beda"}'
          '${vpsRes.detail.isNotEmpty ? " — ${vpsRes.detail}" : ""}',
        );
      }

      await _setOneringStage(4, 'Mengevaluasi kecocokan CDN...');
      final ok = anyMatch;
      final detail = lines.join('\n');
      _stopOneringCheckAnim();
      setState(() {
        _oneringChecking = false;
        _oneringCheckStage = ok ? 5 : 0;
        _oneringCheckStageLabel = ok ? 'Selesai — cocok' : 'Selesai — tidak cocok';
        _oneringCompatOk = ok;
        if (ok) {
          _oneringCompatMessage =
              'CDN cocok (${bugRes.provider}). Tombol Terapkan tersedia pada node.\n$detail';
        } else if (!bugRes.isKnown) {
          _oneringCompatMessage =
              'Bug host tidak terdeteksi sebagai CDN dikenal.\n'
              'Pastikan domain bug memakai Cloudflare/CloudFront/Fastly '
              '(bukan IP mentah).\n$detail';
        } else if (!anyKnownPair) {
          _oneringCompatMessage =
              'CDN VPS tidak terdeteksi jelas. Onering diabaikan.\n$detail';
        } else {
          _oneringCompatMessage =
              'Mismatch CDN (Bug=${bugRes.provider}). '
              'Onering tidak disarankan / diabaikan.\n$detail';
        }
      });
    } catch (e) {
      _stopOneringCheckAnim();
      setState(() {
        _oneringChecking = false;
        _oneringCheckStage = 0;
        _oneringCheckStageLabel = '';
        _oneringCompatOk = false;
        _oneringCompatMessage = 'Gagal cek kompatibilitas: $e';
      });
    }
  }

  void _applyOneringToNode(Node n) {
    final bug = _bugController.text.trim();
    if (bug.isEmpty || _oneringCompatOk != true) return;
    final key = _stableNodeKey(n);
    _oneringOriginalServer.putIfAbsent(key, () => n.server);
    setState(() {
      _oneringAppliedKeys.add(key);
      // Mutually exclusive dengan wildcard
      _bugMode = BugWildcardMode.none;
    });
    _convert();
  }

  void _applyOneringToAllXray() {
    final bug = _bugController.text.trim();
    if (bug.isEmpty || _oneringCompatOk != true) return;
    final xray = parseLinks(_inputController.text);
    setState(() {
      for (final n in xray) {
        final key = _stableNodeKey(n);
        _oneringOriginalServer.putIfAbsent(key, () => n.server);
        _oneringAppliedKeys.add(key);
      }
      _bugMode = BugWildcardMode.none;
    });
    _convert();
  }

  void _clearOneringApplied() {
    setState(() {
      _oneringAppliedKeys.clear();
      _oneringOriginalServer.clear();
    });
    _convert();
  }

  /// Simpan isi form ke draft aktif.
  void _saveSshDraftFromControllers() {
    if (_sshAccounts.isEmpty) return;
    final i = _sshActiveIndex.clamp(0, _sshAccounts.length - 1);
    final d = _sshAccounts[i];
    d.name = _sshNameController.text;
    d.hostPort = _sshHostController.text;
    d.username = _sshUserController.text;
    d.password = _sshPassController.text;
    d.payload = _sshPayloadController.text;
    d.proxy = _sshProxyController.text;
    d.sni = _sshSniController.text;
    d.useTls = _sshUseTls;
  }

  /// Muat draft ke form controllers (tanpa setState).
  void _loadSshDraftToControllers(int index) {
    if (_sshAccounts.isEmpty) return;
    final i = index.clamp(0, _sshAccounts.length - 1);
    final d = _sshAccounts[i];
    _sshNameController.text = d.name;
    _sshHostController.text = d.hostPort;
    _sshUserController.text = d.username;
    _sshPassController.text = d.password;
    _sshPayloadController.text = d.payload;
    _sshProxyController.text = d.proxy;
    _sshSniController.text = d.sni;
    _sshUseTls = d.useTls;
  }

  void _switchSshAccount(int index) {
    if (index < 0 || index >= _sshAccounts.length || index == _sshActiveIndex) {
      return;
    }
    _saveSshDraftFromControllers();
    final dir = index > _sshActiveIndex ? 1 : -1;
    setState(() {
      _sshSlideDir = dir;
      _sshActiveIndex = index;
      _loadSshDraftToControllers(index);
    });
    _convert();
  }

  void _addSshAccount() {
    _saveSshDraftFromControllers();
    setState(() {
      _sshAccounts.add(SshAccountDraft());
      _sshSlideDir = 1;
      _sshActiveIndex = _sshAccounts.length - 1;
      _loadSshDraftToControllers(_sshActiveIndex);
    });
    _convert();
  }

  void _removeSshAccount(int index) {
    if (_sshAccounts.length <= 1) {
      // Reset satu-satunya akun
      _clearSshFormOnly();
      _convert();
      return;
    }
    _saveSshDraftFromControllers();
    setState(() {
      _sshAccounts.removeAt(index);
      if (_sshActiveIndex >= _sshAccounts.length) {
        _sshActiveIndex = _sshAccounts.length - 1;
      } else if (index < _sshActiveIndex) {
        _sshActiveIndex -= 1;
      }
      _sshSlideDir = -1;
      _loadSshDraftToControllers(_sshActiveIndex);
    });
    _convert();
  }

  void _clearSshFormOnly() {
    _sshHostController.clear();
    _sshUserController.clear();
    _sshPassController.clear();
    _sshNameController.clear();
    _sshProxyController.clear();
    _sshSniController.clear();
    _sshPayloadController.text =
        'GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]Upgrade: websocket[crlf][crlf]';
    _sshUseTls = false;
    if (_sshAccounts.isNotEmpty) {
      final d = _sshAccounts[_sshActiveIndex.clamp(0, _sshAccounts.length - 1)];
      d.name = '';
      d.hostPort = '';
      d.username = '';
      d.password = '';
      d.payload = _sshPayloadController.text;
      d.proxy = '';
      d.sni = '';
      d.useTls = false;
    }
  }

  @override
  @override
  void initState() {
    super.initState();
    _oneringPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _oneringSweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void _startOneringCheckAnim() {
    _oneringPulseCtrl.repeat(reverse: true);
    _oneringSweepCtrl.repeat();
  }

  void _stopOneringCheckAnim() {
    _oneringPulseCtrl.stop();
    _oneringPulseCtrl.reset();
    _oneringSweepCtrl.stop();
    _oneringSweepCtrl.reset();
  }

  Future<void> _setOneringStage(int stage, String label) async {
    if (!mounted) return;
    setState(() {
      _oneringCheckStage = stage;
      _oneringCheckStageLabel = label;
    });
    // jeda singkat agar animasi tahap terbaca
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  @override
  void dispose() {
    _oneringPulseCtrl.dispose();
    _oneringSweepCtrl.dispose();
    _inputController.dispose();
    _searchController.dispose();
    _sshHostController.dispose();
    _sshUserController.dispose();
    _sshPassController.dispose();
    _sshNameController.dispose();
    _sshPayloadController.dispose();
    _sshProxyController.dispose();
    _sshSniController.dispose();
    _newRulePayloadController.dispose();
    _mainGroupController.dispose();
    _mixedPortController.dispose();
    _customDnsController.dispose();
    _bugController.dispose();
    _seranggaIpController.dispose();
    _seranggaCountController.dispose();
    super.dispose();
  }

  void _parseNodesFromInput() {
    // Selalu gabungkan X-ray (vmess/vless/trojan) + semua akun SSH yang terisi.
    final nodes = <Node>[];
    nodes.addAll(parseLinks(_inputController.text));

    _saveSshDraftFromControllers();
    for (var i = 0; i < _sshAccounts.length; i++) {
      final d = _sshAccounts[i];
      if (!d.isFilled) continue;
      final built = buildSshNodes(
        sshHostPort: d.hostPort,
        username: d.username,
        password: d.password,
        name: d.name.isNotEmpty ? d.name : 'SSH-${i + 1}',
        payload: d.payload,
        proxy: d.proxy,
        useTls: d.useTls,
        sni: d.sni,
      );
      nodes.addAll(built);
    }
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
      if (_inputMode == InputProtocolMode.ssh) {
        // Hapus hanya akun aktif; jika terakhir, reset form
        if (_sshAccounts.length > 1) {
          _sshAccounts.removeAt(_sshActiveIndex);
          if (_sshActiveIndex >= _sshAccounts.length) {
            _sshActiveIndex = _sshAccounts.length - 1;
          }
          _loadSshDraftToControllers(_sshActiveIndex);
        } else {
          _sshAccounts
            ..clear()
            ..add(SshAccountDraft());
          _sshActiveIndex = 0;
          _clearSshFormOnly();
        }
      } else {
        _clearSshFormOnly();
      }
      _parsedNodes = [];
      _clashOutput = '';
      _singboxOutput = '';
      _status = null;
    });
    if (_inputMode == InputProtocolMode.ssh) _convert();
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
          final hasXrayText = _inputController.text.trim().isNotEmpty;
          final hasSshDraft = _sshAccounts.any((a) =>
              a.hostPort.trim().isNotEmpty || a.username.trim().isNotEmpty);
          if (hasXrayText || hasSshDraft) {
            _status =
                'Tidak ada akun valid. Periksa link vmess/vless/trojan atau isi SSH Host:Port + username.';
          } else {
            _status =
                'Tempel link vmess/vless/trojan dan/atau isi minimal satu akun SSH.';
          }
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
      // X-ray: Onering (opsional per-node) lalu bug/wildcard + multi-serangga.
      // SSH: multi-serangga (termasuk HTTP proxy perantara); tanpa bug host.
      final xrayNodes = _parsedNodes
          .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
          .toList();
      final sshNodes = _parsedNodes
          .where((n) => n.protocol == 'ssh' || n.protocol == 'http')
          .toList();
      var processedXray = xrayNodes.map((n) {
        final key = _stableNodeKey(n);
        if (_oneringEnabled &&
            _oneringCompatOk == true &&
            _oneringAppliedKeys.contains(key)) {
          return applyOneringToNode(n, _bugController.text);
        }
        return n.copyWith();
      }).toList();
      // Wildcard hanya jika Onering tidak aktif
      if (!_oneringEnabled || _oneringAppliedKeys.isEmpty) {
        processedXray = applyBugWildcard(
          processedXray,
          _bugController.text,
          _bugMode,
        );
      } else {
        // Tetap boleh wildcard untuk node yang belum di-Onering
        processedXray = processedXray.map((n) {
          final key = _stableNodeKey(n);
          if (_oneringAppliedKeys.contains(key)) return n;
          return applyBugWildcard([n], _bugController.text, _bugMode).first;
        }).toList();
      }
      processedXray = applyMultiSerangga(
        processedXray,
        enabled: _seranggaEnabled,
        count: _seranggaCount,
        ipListText: _seranggaIpController.text,
      );
      final processedSsh = applyMultiSeranggaSsh(
        sshNodes,
        enabled: _seranggaEnabled,
        count: _seranggaCount,
        ipListText: _seranggaIpController.text,
      );
      final nodesForOutput = [...processedXray, ...processedSsh];
      final multiInfo = (_seranggaEnabled &&
              nodesForOutput.length != _parsedNodes.length)
          ? ' → ${nodesForOutput.length} outbound (Multi Serangga ×$_seranggaCount)'
          : '';

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
          final xrayCount = nodesForOutput
              .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
              .length;
          final sshCount = _sshAccounts.where((a) => a.isFilled).length;
          final parts = <String>[];
          if (xrayCount > 0) parts.add('$xrayCount X-ray');
          if (sshCount > 0) parts.add('$sshCount SSH');
          final mix = parts.isEmpty ? '' : ' (${parts.join(' + ')})';
          _status =
              'Berhasil mengonversi ${nodesForOutput.length} node$mix$multiInfo (Mode: ${_mode.name.toUpperCase()}).';
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
        final xrayCount = nodesForOutput
            .where((n) => n.protocol != 'ssh' && n.protocol != 'http')
            .length;
        final sshCount = _sshAccounts.where((a) => a.isFilled).length;
        final parts = <String>[];
        if (xrayCount > 0) parts.add('$xrayCount X-ray');
        if (sshCount > 0) parts.add('$sshCount SSH');
        final mix = parts.isEmpty ? '' : ' (${parts.join(' + ')})';
        _status =
            'Berhasil mengonversi ${nodesForOutput.length} node$mix$multiInfo (Mode: ${_mode.name.toUpperCase()}).';
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
                '1. Pilih Inti:\n'
                'Gunakan bilah navigasi bawah untuk beralih antara halaman Clash Meta (YAML) dan Sing-box (JSON).\n\n'
                '2. Ekstraksi Link:\n'
                'Parser mengurai VMess, VLESS Reality, dan Trojan secara offline.\n\n'
                '3. Mode & Addon:\n'
                'Minimal / Lengkap / Custom. Pada Custom, atur DNS, rules, geo, dan routing sesuai kebutuhan.\n\n'
                '4. Hasil:\n'
                'Salin, bagikan, atau simpan konfigurasi inti yang aktif.',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 13, color: Color(0xFF10B981)),
                SizedBox(width: 5),
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF9CA3AF), size: 22),
            tooltip: 'Panduan',
            onPressed: _showGuideDialog,
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

            // Protocol mode selector: X-ray | SSH
            Row(
              children: [
                Expanded(
                  child: _buildProtocolCard(
                    mode: InputProtocolMode.xray,
                    title: 'X-ray',
                    subtitle: 'VMess · VLESS · Trojan',
                    icon: Icons.link_rounded,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildProtocolCard(
                    mode: InputProtocolMode.ssh,
                    title: 'SSH',
                    subtitle: 'SSH + Proxy + Payload',
                    icon: Icons.terminal_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Node Input Card (X-ray links or SSH form)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_inputMode == InputProtocolMode.xray) ...[
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
                    ] else ...[
                      // SSH form header
                      Row(
                        children: [
                          const Icon(Icons.terminal_rounded, size: 18, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Akun SSH',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  'Host · User · Password · Payload · Proxy · SNI',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
                          ),
                          _buildMiniAction('Hapus', Icons.delete_outline, Colors.redAccent, _clearInput),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Card nomor akun + tombol tambah
                      _buildSshAccountTabs(),
                      const SizedBox(height: 12),
                      // Form dengan animasi slide saat ganti akun
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offsetAnim = Tween<Offset>(
                            begin: Offset(_sshSlideDir.toDouble() * 0.25, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return ClipRect(
                            child: SlideTransition(
                              position: offsetAnim,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey<int>(_sshActiveIndex),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sshField(_sshNameController, 'Nama node (opsional)', Icons.badge_outlined),
                              const SizedBox(height: 8),
                              _sshField(
                                _sshHostController,
                                'SSH Host:Port',
                                Icons.dns_outlined,
                                hint: 'ssh.example.com:22 atau [2001:db8::1]:22',
                              ),
                              const SizedBox(height: 8),
                              _sshField(_sshUserController, 'Nama pengguna SSH', Icons.person_outline),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _sshPassController,
                                obscureText: _sshObscurePass,
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                                onChanged: (_) => _convert(),
                                decoration: InputDecoration(
                                  labelText: 'Kata sandi SSH',
                                  labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                  prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF9CA3AF)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _sshObscurePass ? Icons.visibility_off : Icons.visibility,
                                      size: 18,
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                    onPressed: () => setState(() => _sshObscurePass = !_sshObscurePass),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text('Metode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Tanpa TLS', style: TextStyle(fontSize: 11)),
                                    selected: !_sshUseTls,
                                    onSelected: (_) {
                                      setState(() => _sshUseTls = false);
                                      _convert();
                                    },
                                    selectedColor: const Color(0xFF374151),
                                    labelStyle: TextStyle(
                                      color: !_sshUseTls ? Colors.white : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('TLS', style: TextStyle(fontSize: 11)),
                                    selected: _sshUseTls,
                                    onSelected: (_) {
                                      setState(() => _sshUseTls = true);
                                      _convert();
                                    },
                                    selectedColor: const Color(0xFF065F46),
                                    labelStyle: TextStyle(
                                      color: _sshUseTls ? Colors.white : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ],
                              ),
                              if (_sshUseTls) ...[
                                const SizedBox(height: 8),
                                _sshField(
                                  _sshSniController,
                                  'SNI (Server Name Indication)',
                                  Icons.security_outlined,
                                  hint: 'contoh: www.example.com',
                                ),
                              ],
                              const SizedBox(height: 14),
                              const Text('Payload', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _sshPayloadController,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
                                onChanged: (_) => _convert(),
                                decoration: const InputDecoration(
                                  hintText: 'Payload kustom (opsional)',
                                  hintStyle: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _sshField(
                                _sshProxyController,
                                'Proxy jarak jauh',
                                Icons.cloud_outlined,
                                hint: 'host:port atau user:pass@host:port',
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D131F),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF1F2937)),
                                ),
                                child: const Text(
                                  'Catatan: payload front-inject penuh tidak didukung native oleh Clash/Sing-box. '
                                  'Header (Connection/Upgrade/Host) akan didekati pada HTTP proxy perantara bila diisi.',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                                        if (_parsedNodes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'Node Terdeteksi (${_parsedNodes.length})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF)),
                          ),
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
                          if (n.protocol == 'ssh') badgeColor = const Color(0xFF10B981);
                          if (n.protocol == 'http') badgeColor = const Color(0xFF06B6D4);
                          final isXray = n.protocol == 'vmess' ||
                              n.protocol == 'vless' ||
                              n.protocol == 'trojan';
                          final key = _stableNodeKey(n);
                          final oneringOn = _oneringEnabled &&
                              _oneringCompatOk == true &&
                              isXray;
                          final applied = _oneringAppliedKeys.contains(key);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D131F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: applied
                                    ? const Color(0xFF0EA5E9)
                                    : const Color(0xFF1F2937),
                              ),
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
                                  constraints: const BoxConstraints(maxWidth: 90),
                                  child: Text(
                                    n.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFFD1D5DB)),
                                  ),
                                ),
                                if (oneringOn) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      if (applied) {
                                        setState(() => _oneringAppliedKeys.remove(key));
                                        _convert();
                                      } else {
                                        _applyOneringToNode(n);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: applied
                                            ? const Color(0xFF0EA5E9).withOpacity(0.2)
                                            : const Color(0xFF0369A1).withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        applied ? 'ONERING' : 'Terapkan',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: applied
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFFE0F2FE),
                                        ),
                                      ),
                                    ),
                                  ),
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


            // Mode Selection (inti dipilih lewat floating nav bawah)
            Card(
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
                              'Studio Mode Custom (Addon)',
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

            // Bug host + wildcard hanya di tab X-ray (tidak relevan untuk SSH).
            if (_inputMode == InputProtocolMode.xray) ...[
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
              // Card Onering (muncul jika bug terisi)
              if (_bugController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildOneringCard(),
              ],
              const SizedBox(height: 8),
            ],
            // Multi-serangga tersedia untuk X-ray dan SSH.
            _buildSeranggaCard(),
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
                    if (_parsedNodes.isNotEmpty) _convert();
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
                    if (_parsedNodes.isNotEmpty) _convert();
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
                      '+ Tambah Aturan Mandiri (Custom Rules)',
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
                      decoration: InputDecoration(isDense: true, hintText: '$kDefaultClashMixedPort'),
                      onChanged: (v) {
                        _mixedPort = int.tryParse(v) ?? kDefaultClashMixedPort;
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



  Widget _buildOneringCheckPreview() {
    const stages = <String>[
      'Siapkan host',
      'DNS / fingerprint Bug',
      'Cek server VPS',
      'Evaluasi CDN',
      'Selesai',
    ];
    // Map internal stage 1..5 → index 0..4
    final activeIdx = (_oneringCheckStage.clamp(1, 5) - 1);

    return AnimatedBuilder(
      animation: Listenable.merge([_oneringPulseCtrl, _oneringSweepCtrl]),
      builder: (context, _) {
        final pulse = 0.55 + (_oneringPulseCtrl.value * 0.45);
        final sweep = _oneringSweepCtrl.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0F18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Color.lerp(
                    const Color(0xFF0EA5E9),
                    const Color(0xFF0369A1),
                    _oneringPulseCtrl.value,
                  )!
                  .withOpacity(0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0EA5E9).withOpacity(0.12 * pulse),
                blurRadius: 12 * pulse,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Radar / scan icon berdenyut
                  Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0EA5E9).withOpacity(0.15),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withOpacity(pulse),
                        ),
                      ),
                      child: const Icon(
                        Icons.radar,
                        size: 16,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Memindai kompatibilitas Onering',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            _oneringCheckStageLabel.isEmpty
                                ? 'Memulai...'
                                : _oneringCheckStageLabel,
                            key: ValueKey(_oneringCheckStageLabel),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF7DD3FC),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar dengan sweep shimmer
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFF1F2937)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ((activeIdx + 1) / stages.length)
                            .clamp(0.08, 1.0),
                        child: const ColoredBox(color: Color(0xFF0EA5E9)),
                      ),
                      // shimmer
                      FractionallySizedBox(
                        alignment: Alignment(-1.0 + sweep * 2, 0),
                        widthFactor: 0.25,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.35),
                                Colors.white.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Step chips
              Row(
                children: [
                  for (var i = 0; i < stages.length; i++) ...[
                    if (i > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          color: i <= activeIdx
                              ? const Color(0xFF0EA5E9)
                              : const Color(0xFF1F2937),
                        ),
                      ),
                    _oneringStepDot(
                      index: i,
                      active: i == activeIdx,
                      done: i < activeIdx,
                      pulse: pulse,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                stages[activeIdx.clamp(0, stages.length - 1)],
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _oneringStepDot({
    required int index,
    required bool active,
    required bool done,
    required double pulse,
  }) {
    final color = done || active
        ? const Color(0xFF0EA5E9)
        : const Color(0xFF374151);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 12 * pulse.clamp(0.85, 1.15) : 8,
      height: active ? 12 * pulse.clamp(0.85, 1.15) : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : (active ? color.withOpacity(0.9) : color),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFF0EA5E9).withOpacity(0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
        border: Border.all(
          color: active ? const Color(0xFF7DD3FC) : Colors.transparent,
          width: 1.2,
        ),
      ),
    );
  }

  Widget _buildOneringCard() {
    final bugFilled = _bugController.text.trim().isNotEmpty;
    final wildcardActive = _bugMode != BugWildcardMode.none;
    final dimmed = wildcardActive; // tidak bisa dipakai bersama Wildcard

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: dimmed ? 0.4 : 1.0,
      child: IgnorePointer(
        ignoring: dimmed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _oneringEnabled
                ? const Color(0xFF0EA5E9).withOpacity(0.10)
                : const Color(0xFF0D131F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _oneringEnabled
                  ? const Color(0xFF0EA5E9).withOpacity(0.5)
                  : const Color(0xFF1F2937),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 16,
                    color: _oneringEnabled
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Onering (opsional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _oneringEnabled,
                    activeColor: const Color(0xFF0EA5E9),
                    onChanged: !bugFilled
                        ? null
                        : (v) {
                            setState(() {
                              _oneringEnabled = v;
                              if (v) {
                                // Mutual exclusion dengan Wildcard
                                _bugMode = BugWildcardMode.none;
                              } else {
                                _oneringCompatOk = null;
                                _oneringCompatMessage = '';
                                _oneringAppliedKeys.clear();
                              }
                            });
                            if (!v) _convert();
                          },
                  ),
                ],
              ),
              const Text(
                'Memerlukan koneksi internet untuk cek kompatibilitas CDN.',
                style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), height: 1.3),
              ),
              if (dimmed)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Nonaktifkan Wildcard untuk memakai Onering.',
                    style: TextStyle(fontSize: 10, color: Color(0xFFFBBF24)),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _oneringEnabled
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _oneringChecking
                                  ? null
                                  : _runOneringCompatCheck,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0369A1),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: _oneringChecking
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.travel_explore, size: 16),
                              label: Text(
                                _oneringChecking
                                    ? 'Memeriksa CDN...'
                                    : 'Auto-cek kompatibilitas Onering',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            // Preview animasi proses pengecekan
                            AnimatedSize(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              child: _oneringChecking
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: _buildOneringCheckPreview(),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            if (_oneringCompatMessage.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0F18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _oneringCompatOk == true
                                        ? const Color(0xFF10B981).withOpacity(0.5)
                                        : _oneringCompatOk == false
                                            ? const Color(0xFFEF4444).withOpacity(0.45)
                                            : const Color(0xFF1F2937),
                                  ),
                                ),
                                child: Text(
                                  _oneringCompatMessage,
                                  style: TextStyle(
                                    fontSize: 10,
                                    height: 1.35,
                                    fontFamily: 'monospace',
                                    color: _oneringCompatOk == true
                                        ? const Color(0xFF6EE7B7)
                                        : _oneringCompatOk == false
                                            ? const Color(0xFFFCA5A5)
                                            : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                            ],
                            if (_oneringCompatOk == true) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _applyOneringToAllXray,
                                      icon: const Icon(Icons.done_all, size: 14),
                                      label: const Text('Terapkan semua',
                                          style: TextStyle(fontSize: 11)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF38BDF8),
                                        side: const BorderSide(
                                            color: Color(0xFF0EA5E9)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                      ),
                                    ),
                                  ),
                                  if (_oneringAppliedKeys.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _clearOneringApplied,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                        side: const BorderSide(
                                            color: Colors.redAccent),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                      ),
                                      child: const Text('Reset',
                                          style: TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Atau tekan Terapkan pada masing-masing badge node di atas.',
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFF6B7280)),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWildcardCard() {
    final canUse = _bugController.text.trim().isNotEmpty && !_oneringEnabled;
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
      case BugWildcardMode.serverOnly:
        return 'Mode: Timpa server saja';
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
      case BugWildcardMode.serverOnly:
        preview = 'server="$bug" saja';
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

  /// Panel opsional multi-serangga: tiap akun digandakan × N dengan IP berbeda.
  Widget _buildSeranggaCard() {
    final totalPreview = _parsedNodes.isEmpty
        ? null
        : _parsedNodes.length *
            (_seranggaEnabled
                ? _seranggaCount.clamp(kSeranggaMin, kSeranggaMax)
                : 1);

    // Contoh nama otomatis (memakai akun pertama bila sudah ada).
    final sample = _parsedNodes.isEmpty ? null : _parsedNodes.first;
    final sampleBase = sample == null
        ? 'akun'
        : (sample.name.trim().isEmpty ? sample.protocol : sample.name.trim());
    final shownCount = _seranggaCount < 3 ? _seranggaCount : 3;
    final namePreview = [
          for (var i = 1; i <= shownCount; i++)
            seranggaVariantName(sampleBase, i),
        ].join(', ') +
        (_seranggaCount > 3
            ? ', … ${seranggaVariantName(sampleBase, _seranggaCount)}'
            : '');
    final manualHostCount = parseSeranggaHostList(_seranggaIpController.text).length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _seranggaEnabled
            ? const Color(0xFF6366F1).withOpacity(0.08)
            : const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _seranggaEnabled
              ? const Color(0xFF6366F1).withOpacity(0.45)
              : const Color(0xFF1F2937),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hub_outlined,
                size: 14,
                color: _seranggaEnabled
                    ? const Color(0xFF818CF8)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Multi Serangga (opsional)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _seranggaEnabled,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    setState(() => _seranggaEnabled = v);
                    if (_parsedNodes.isNotEmpty) _convert();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Gandakan tiap akun jadi beberapa outbound. Cukup aktifkan lalu isi jumlah — nama & daftar dibuat otomatis.',
            style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _seranggaEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Jumlah serangga / akun',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 72,
                              child: TextField(
                                controller: _seranggaCountController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  hintText: '3',
                                ),
                                onChanged: (v) {
                                  // Hasil langsung ikut berubah saat mengetik; angka di
                                  // luar batas dirapikan setelah selesai mengetik.
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
                                  if (_parsedNodes.isNotEmpty) _convert();
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
                        const SizedBox(height: 2),
                        Text(
                          'Min $kSeranggaMin, maks $kSeranggaMax per akun',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          totalPreview == null
                              ? 'Contoh: 2 akun × $_seranggaCount = ${2 * _seranggaCount} outbound'
                              : 'Perkiraan output: ${_parsedNodes.length} akun × $_seranggaCount = $totalPreview outbound',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFA5B4FC),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          manualHostCount > 0
                              ? 'Nama otomatis: $namePreview · server dari IP/host manual'
                              : 'Nama otomatis: $namePreview · server tetap milik akun',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Daftar IP/host manual bersifat opsional & tersembunyi secara default.
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(
                            () => _seranggaManualOpen = !_seranggaManualOpen,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _seranggaManualOpen
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: const Color(0xFF9CA3AF),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    manualHostCount > 0
                                        ? 'IP/host manual aktif ($manualHostCount)'
                                        : 'Atur IP/host manual (opsional)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: manualHostCount > 0
                                          ? const Color(0xFFA5B4FC)
                                          : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_seranggaManualOpen) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Satu IP/host per baris. Dipakai sebagai server tiap serangga secara bergiliran. Kosongkan untuk mode otomatis.',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _seranggaIpController,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '1.2.3.4\n5.6.7.8\n9.10.11.12',
                              hintStyle: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF4B5563),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (_) {
                              setState(() {});
                              if (_parsedNodes.isNotEmpty) _convert();
                            },
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
                _buildWildcardOption(
                  ctx,
                  BugWildcardMode.serverOnly,
                  'Timpa server saja',
                  'server = bug (SNI & Host tetap asli)',
                  Icons.swap_horiz_rounded,
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
            setState(() {
              _bugMode = mode;
              // Mutual exclusion: Wildcard aktif → Onering off
              if (mode != BugWildcardMode.none) {
                _oneringEnabled = false;
                _oneringAppliedKeys.clear();
                _oneringCompatOk = null;
                _oneringCompatMessage = '';
              }
            });
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
          'Jika Anda tidak mengetahui mendalam tentang bagian ini, sebaiknya biarkan tetap default.',
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
                  _convert();
                },
              );
            } else {
              onChanged(v);
              _convert();
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


  /// Baris card nomor akun SSH + tombol tambah.
  Widget _buildSshAccountTabs() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _sshAccounts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // Tombol +
          if (index == _sshAccounts.length) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _addSshAccount,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D131F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                  ),
                  child: const Icon(Icons.add, size: 20, color: Color(0xFF10B981)),
                ),
              ),
            );
          }

          final selected = index == _sshActiveIndex;
          final filled = _sshAccounts[index].isFilled;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _switchSshAccount(index),
              onLongPress: () {
                // Long-press: konfirmasi hapus jika lebih dari 1
                if (_sshAccounts.length <= 1) return;
                showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF111827),
                    title: const Text('Hapus akun SSH?', style: TextStyle(color: Colors.white, fontSize: 16)),
                    content: Text(
                      'Konfigurasi #${index + 1} akan dihapus.',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ).then((ok) {
                  if (ok == true) _removeSshAccount(index);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF10B981).withOpacity(0.2)
                      : const Color(0xFF0D131F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF10B981)
                        : (filled ? const Color(0xFF374151) : const Color(0xFF1F2937)),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? const Color(0xFF10B981)
                        : (filled ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProtocolCard({
    required InputProtocolMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final selected = _inputMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_inputMode == mode) return;
          // Simpan draf SSH sebelum ganti tab agar data tidak hilang
          if (_inputMode == InputProtocolMode.ssh) {
            _saveSshDraftFromControllers();
          }
          setState(() {
            _inputMode = mode;
            _status = null;
          });
          // Parse ulang: X-ray + SSH digabung
          _convert();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : const Color(0xFF111827),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : const Color(0xFF1F2937),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.25) : const Color(0xFF0D131F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: selected ? color : const Color(0xFF9CA3AF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : const Color(0xFFD1D5DB),
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: selected ? color.withOpacity(0.9) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sshField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 12, color: Colors.white),
      onChanged: (_) => _convert(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
        hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
      ),
    );
  }

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
