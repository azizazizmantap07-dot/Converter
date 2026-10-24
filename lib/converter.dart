import 'dart:convert';

/// Parsed proxy node model.
class Node {
  String protocol; // vmess | vless | trojan | ssh | http
  String name;
  String server;
  int port;
  String uuid;
  String password;
  String username; // SSH / HTTP proxy auth
  int alterId;
  String cipher;
  String network;
  bool tls;
  String sni;
  List<String> alpn;
  String fingerprint;
  bool skipCertVerify;
  String flow;
  String path;
  String host;
  String serviceName;
  bool reality;
  String publicKey;
  String shortId;
  String packetEncoding;
  String encryption;

  /// SSH: raw payload string (untuk dokumentasi / header approximation).
  String payload;

  /// SSH: remote HTTP proxy "host:port" atau "user:pass@host:port".
  String proxy;

  /// Nama outbound perantara (dialer-proxy / detour) bila ada HTTP proxy.
  String dialerProxy;

  /// Header tambahan untuk HTTP outbound (hasil parsing payload sederhana).
  Map<String, String> extraHeaders;

  /// Kode region hasil deteksi dari nama node (SG, ID, HK, ...), atau '' jika tidak dikenali.
  String get region => detectRegion(name);

  Node({
    required this.protocol,
    this.name = '',
    this.server = '',
    this.port = 443,
    this.uuid = '',
    this.password = '',
    this.username = '',
    this.alterId = 0,
    this.cipher = 'auto',
    this.network = 'tcp',
    this.tls = false,
    this.sni = '',
    List<String>? alpn,
    this.fingerprint = '',
    this.skipCertVerify = false,
    this.flow = '',
    this.path = '',
    this.host = '',
    this.serviceName = '',
    this.reality = false,
    this.publicKey = '',
    this.shortId = '',
    this.packetEncoding = '',
    this.encryption = '',
    this.payload = '',
    this.proxy = '',
    this.dialerProxy = '',
    Map<String, String>? extraHeaders,
  })  : alpn = alpn ?? [],
        extraHeaders = extraHeaders ?? {};

  Node copyWith({
    String? protocol,
    String? name,
    String? server,
    int? port,
    String? uuid,
    String? password,
    String? username,
    int? alterId,
    String? cipher,
    String? network,
    bool? tls,
    String? sni,
    List<String>? alpn,
    String? fingerprint,
    bool? skipCertVerify,
    String? flow,
    String? path,
    String? host,
    String? serviceName,
    bool? reality,
    String? publicKey,
    String? shortId,
    String? packetEncoding,
    String? encryption,
    String? payload,
    String? proxy,
    String? dialerProxy,
    Map<String, String>? extraHeaders,
  }) {
    return Node(
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      username: username ?? this.username,
      alterId: alterId ?? this.alterId,
      cipher: cipher ?? this.cipher,
      network: network ?? this.network,
      tls: tls ?? this.tls,
      sni: sni ?? this.sni,
      alpn: alpn ?? List<String>.from(this.alpn),
      fingerprint: fingerprint ?? this.fingerprint,
      skipCertVerify: skipCertVerify ?? this.skipCertVerify,
      flow: flow ?? this.flow,
      path: path ?? this.path,
      host: host ?? this.host,
      serviceName: serviceName ?? this.serviceName,
      reality: reality ?? this.reality,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      packetEncoding: packetEncoding ?? this.packetEncoding,
      encryption: encryption ?? this.encryption,
      payload: payload ?? this.payload,
      proxy: proxy ?? this.proxy,
      dialerProxy: dialerProxy ?? this.dialerProxy,
      extraHeaders: extraHeaders ?? Map<String, String>.from(this.extraHeaders),
    );
  }
}

/// Hasil parsing string proxy remote: host, port, username, password opsional.
class ParsedProxyAddr {
  final String host;
  final int port;
  final String username;
  final String password;
  ParsedProxyAddr({
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
  });
}

/// Parse "host:port", "[ipv6]:port", "user:pass@host:port".
ParsedProxyAddr? parseProxyAddress(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  String user = '';
  String pass = '';
  final at = s.lastIndexOf('@');
  if (at > 0) {
    final cred = s.substring(0, at);
    s = s.substring(at + 1);
    final colon = cred.indexOf(':');
    if (colon >= 0) {
      user = cred.substring(0, colon);
      pass = cred.substring(colon + 1);
    } else {
      user = cred;
    }
  }
  String host;
  int port;
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end < 0) return null;
    host = s.substring(1, end);
    final rest = s.substring(end + 1);
    if (!rest.startsWith(':')) return null;
    port = int.tryParse(rest.substring(1)) ?? 80;
  } else {
    final colon = s.lastIndexOf(':');
    if (colon < 0) {
      host = s;
      port = 80;
    } else {
      host = s.substring(0, colon);
      port = int.tryParse(s.substring(colon + 1)) ?? 80;
    }
  }
  if (host.isEmpty) return null;
  return ParsedProxyAddr(host: host, port: port, username: user, password: pass);
}

/// Parse "host:port" atau "[ipv6]:port" untuk SSH.
({String host, int port})? parseHostPort(String raw, {int defaultPort = 22}) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end < 0) return null;
    final host = s.substring(1, end);
    final rest = s.substring(end + 1);
    final port = rest.startsWith(':')
        ? (int.tryParse(rest.substring(1)) ?? defaultPort)
        : defaultPort;
    return (host: host, port: port);
  }
  final colon = s.lastIndexOf(':');
  if (colon < 0) return (host: s, port: defaultPort);
  final host = s.substring(0, colon);
  final port = int.tryParse(s.substring(colon + 1)) ?? defaultPort;
  if (host.isEmpty) return null;
  return (host: host, port: port);
}

/// Bangun daftar node dari form SSH (boleh menyertakan HTTP proxy perantara).
///
/// [payload] didekati lewat header HTTP (Connection/Upgrade/Host) karena
/// Clash Meta & Sing-box tidak mendukung front-inject penuh.
List<Node> buildSshNodes({
  required String sshHostPort,
  required String username,
  required String password,
  String name = '',
  String payload = '',
  String proxy = '',
  bool useTls = false,
  String sni = '',
}) {
  final hp = parseHostPort(sshHostPort, defaultPort: 22);
  if (hp == null || username.trim().isEmpty) return [];

  final displayName = name.trim().isEmpty
      ? 'SSH-${hp.host}:${hp.port}'
      : name.trim();

  final headers = <String, String>{};
  // Dekati payload WebSocket-upgrade umum
  final pl = payload.trim().toLowerCase();
  if (pl.contains('upgrade') || pl.contains('websocket')) {
    headers['Connection'] = 'Upgrade';
    headers['Upgrade'] = 'websocket';
  }
  // Ambil Host dari payload jika ada pola Host: xxx
  final hostMatch = RegExp(
    r'Host:\s*([^\r\n\[]+)',
    caseSensitive: false,
  ).firstMatch(payload);
  if (hostMatch != null) {
    var h = hostMatch.group(1)!.trim();
    if (h == '[host]' || h.isEmpty) {
      // placeholder → pakai SNI atau server proxy
    } else {
      headers['Host'] = h;
    }
  }

  final nodes = <Node>[];
  String dialer = '';

  final proxyAddr = parseProxyAddress(proxy);
  if (proxyAddr != null) {
    final proxyName = '$displayName-HTTP';
    dialer = proxyName;
    final httpNode = Node(
      protocol: 'http',
      name: proxyName,
      server: proxyAddr.host,
      port: proxyAddr.port,
      username: proxyAddr.username,
      password: proxyAddr.password,
      tls: useTls,
      sni: sni.trim().isNotEmpty
          ? sni.trim()
          : (headers['Host'] ?? ''),
      path: '/',
      extraHeaders: headers,
      skipCertVerify: true,
    );
    nodes.add(httpNode);
  }

  nodes.add(Node(
    protocol: 'ssh',
    name: displayName,
    server: hp.host,
    port: hp.port,
    username: username.trim(),
    password: password,
    payload: payload,
    proxy: proxy,
    dialerProxy: dialer,
    tls: useTls,
    sni: sni.trim(),
  ));

  return nodes;
}

/// Mode wildcard / bug host yang diterapkan ke setiap node.
/// - [none]: tanpa modifikasi
/// - [biasa]: server=bug, SNI/Host = bug.original
/// - [sni]: hanya SNI diganti bug
/// - [serverHost]: server=bug, WS Host=bug
/// - [serverOnly]: hanya server=bug (SNI/Host tetap asli)
enum BugWildcardMode { none, biasa, sni, serverHost, serverOnly }

/// Terapkan bug host ke daftar node (hasil salinan, node asli tidak diubah).
List<Node> applyBugWildcard(
  List<Node> nodes,
  String bugHost,
  BugWildcardMode mode,
) {
  final bug = bugHost.trim();
  if (bug.isEmpty || mode == BugWildcardMode.none) {
    return nodes.map((n) => n.copyWith()).toList();
  }

  return nodes.map((n) {
    switch (mode) {
      case BugWildcardMode.biasa:
        // server: "Bug.com"
        // servername / Host: "Bug.com.sg2-contoh.com"
        final base = (n.sni.isNotEmpty ? n.sni : n.server).trim();
        final combined = base.isEmpty
            ? bug
            : '$bug.${base.replaceAll(RegExp(r'^\.+'), '')}';
        return n.copyWith(
          server: bug,
          sni: combined,
          host: combined,
          tls: true,
        );
      case BugWildcardMode.sni:
        // servername: "Bug.com"
        return n.copyWith(sni: bug, tls: true);
      case BugWildcardMode.serverHost:
        // server: "Bug.com", headers Host: "Bug.com"
        return n.copyWith(server: bug, host: bug);
      case BugWildcardMode.serverOnly:
        // server: "Bug.com" saja; SNI, Host, dan TLS tetap seperti akun asli
        return n.copyWith(server: bug);
      case BugWildcardMode.none:
        return n.copyWith();
    }
  }).toList();
}

/// Batas jumlah serangga per akun (dipakai logika dan UI agar selalu sama).
const int kSeranggaMin = 2;
const int kSeranggaMax = 20;

/// Nama dasar sebuah akun untuk keperluan penamaan otomatis.
String _seranggaBaseName(String name, String protocol) =>
    name.trim().isEmpty ? protocol : name.trim();

/// Nama otomatis serangga ke-[index] (mulai 1) dari akun bernama [baseName].
/// Contoh: `SG-Premium` → `SG-Premium-1`, `SG-Premium-2`, ...
String seranggaVariantName(String baseName, int index) =>
    '${_seranggaBaseName(baseName, 'akun')}-$index';

/// Pecah teks daftar IP/host manual (dipisah baris, koma, atau titik koma).
List<String> parseSeranggaHostList(String text) => text
    .split(RegExp(r'[\r\n,;]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// Multi-serangga: gandakan setiap akun menjadi [count] outbound.
///
/// Cukup aktifkan fitur dan tentukan [count]; penamaan dibuat otomatis:
/// - Setiap salinan diberi nama `<nama akun>-1`, `<nama akun>-2`, ... sampai [count].
/// - Nama dijamin unik di seluruh hasil (dua akun bernama sama tidak bentrok,
///   yang bisa membuat Clash/Sing-box menolak config).
/// - Server/SNI/Host tetap milik akun asli, sehingga koneksi tidak berubah.
///
/// Opsional ([ipListText] diisi manual): daftar IP/host dipakai sebagai `server`
/// tiap salinan secara bergiliran (cycle bila kurang dari [count]).
///
/// [count] di bawah [kSeranggaMin] → tidak digandakan (salinan 1:1).
/// [count] di atas [kSeranggaMax] dibatasi ke [kSeranggaMax].
List<Node> applyMultiSerangga(
  List<Node> nodes, {
  required bool enabled,
  required int count,
  String ipListText = '',
}) {
  if (!enabled || count < kSeranggaMin || nodes.isEmpty) {
    return nodes.map((n) => n.copyWith()).toList();
  }
  final total = count > kSeranggaMax ? kSeranggaMax : count;
  final ips = parseSeranggaHostList(ipListText);

  final out = <Node>[];
  final usedNames = <String>{};
  for (final n in nodes) {
    final baseName = _seranggaBaseName(n.name, n.protocol);
    for (var i = 1; i <= total; i++) {
      var newName = seranggaVariantName(baseName, i);
      // Pastikan unik di seluruh hasil (akun lain bisa saja bernama sama).
      if (usedNames.contains(newName)) {
        var dup = 2;
        while (usedNames.contains('${newName}_$dup')) {
          dup++;
        }
        newName = '${newName}_$dup';
      }
      usedNames.add(newName);

      final server = ips.isEmpty ? n.server : ips[(i - 1) % ips.length];
      out.add(n.copyWith(name: newName, server: server));
    }
  }
  return out;
}

String _uniqueSeranggaName(String base, Set<String> used) {
  var name = base;
  if (used.contains(name)) {
    var dup = 2;
    while (used.contains('${base}_$dup')) {
      dup++;
    }
    name = '${base}_$dup';
  }
  used.add(name);
  return name;
}

/// Multi-serangga khusus SSH (+ HTTP proxy perantara jika ada).
///
/// Setiap akun SSH digandakan [count] kali. Bila SSH memakai dialer-proxy/detour
/// ke outbound HTTP, outbound HTTP ikut digandakan dengan nama unik dan
/// referensi dialer pada SSH diselaraskan. Opsional [ipListText] mengganti
/// `server` SSH (dan HTTP proxy bila ada) secara bergiliran.
List<Node> applyMultiSeranggaSsh(
  List<Node> nodes, {
  required bool enabled,
  required int count,
  String ipListText = '',
}) {
  if (!enabled || count < kSeranggaMin || nodes.isEmpty) {
    return nodes.map((n) => n.copyWith()).toList();
  }
  final total = count > kSeranggaMax ? kSeranggaMax : count;
  final ips = parseSeranggaHostList(ipListText);

  final httpByName = <String, Node>{};
  for (final n in nodes) {
    if (n.protocol == 'http') httpByName[n.name] = n;
  }

  final sshList = nodes.where((n) => n.protocol == 'ssh').toList();
  // HTTP yang tidak direferensikan SSH ikut dilewatkan apa adanya
  final referencedHttp = {
    for (final s in sshList)
      if (s.dialerProxy.isNotEmpty) s.dialerProxy,
  };

  final out = <Node>[];
  final usedNames = <String>{};

  for (final ssh in sshList) {
    final baseName = _seranggaBaseName(ssh.name, 'ssh');
    final httpOrig =
        ssh.dialerProxy.isNotEmpty ? httpByName[ssh.dialerProxy] : null;

    for (var i = 1; i <= total; i++) {
      final server = ips.isEmpty ? ssh.server : ips[(i - 1) % ips.length];
      var dialer = '';

      if (httpOrig != null) {
        final httpBase = _seranggaBaseName(httpOrig.name, 'http');
        final httpName = _uniqueSeranggaName(
          seranggaVariantName(httpBase, i),
          usedNames,
        );
        final httpServer =
            ips.isEmpty ? httpOrig.server : ips[(i - 1) % ips.length];
        out.add(httpOrig.copyWith(name: httpName, server: httpServer));
        dialer = httpName;
      }

      final sshName = _uniqueSeranggaName(
        seranggaVariantName(baseName, i),
        usedNames,
      );
      out.add(ssh.copyWith(
        name: sshName,
        server: server,
        dialerProxy: dialer,
      ));
    }
  }

  // HTTP orphan (tidak dipakai SSH) — pertahankan 1:1
  for (final n in nodes) {
    if (n.protocol == 'http' && !referencedHttp.contains(n.name)) {
      out.add(n.copyWith());
    }
  }

  return out;
}


// ---------------------------------------------------------------------------
// Onering (domain fronting split-host) + CDN auto-detect
// ---------------------------------------------------------------------------

/// Hasil deteksi CDN untuk satu host.
class CdnDetectResult {
  final String host;
  final String provider; // cloudflare | cloudfront | fastly | akamai | unknown
  final String method; // dns | http | none
  final String detail;

  const CdnDetectResult({
    required this.host,
    required this.provider,
    this.method = 'none',
    this.detail = '',
  });

  bool get isKnown => provider != 'unknown' && provider.isNotEmpty;
}

/// Hasil evaluasi kompatibilitas Onering (VPS vs Bug).
class OneringCompatResult {
  final CdnDetectResult vps;
  final CdnDetectResult bug;
  final bool match;
  final String message;

  const OneringCompatResult({
    required this.vps,
    required this.bug,
    required this.match,
    required this.message,
  });
}

/// Subnet IPv4 CDN yang sering dipakai (cukup untuk deteksi praktis).
const List<(String, int, int, String)> kCdnIpv4Ranges = [
  // Cloudflare
  ('cloudflare', 0x68100000, 13, '104.16.0.0/13'), // 104.16.0.0/13
  ('cloudflare', 0x68180000, 14, '104.24.0.0/14'),
  ('cloudflare', 0xA29F0000, 16, '162.159.0.0/16'),
  ('cloudflare', 0xAC400000, 13, '172.64.0.0/13'),
  ('cloudflare', 0xC6290000, 16, '198.41.0.0/16'),
  ('cloudflare', 0x6CA2C000, 18, '108.162.192.0/18'),
  ('cloudflare', 0x8D650000, 16, '141.101.0.0/16'),
  ('cloudflare', 0xBC72A000, 19, '188.114.96.0/19'),
  ('cloudflare', 0xBE5A1800, 22, '190.93.240.0/22'),
  ('cloudflare', 0xC15A6000, 19, '197.234.240.0/22'), // approx
  // CloudFront (sampel)
  ('cloudfront', 0x0D200000, 15, '13.32.0.0/15'),
  ('cloudfront', 0x0D220000, 15, '13.34.0.0/15'),
  ('cloudfront', 0x0D600000, 14, '13.96.0.0/14'), // partial
  ('cloudfront', 0x34540000, 15, '52.84.0.0/15'),
  ('cloudfront', 0x36E90000, 16, '54.230.0.0/16'),
  ('cloudfront', 0x36EF0000, 16, '54.239.0.0/16'),
  // Fastly
  ('fastly', 0x97C30000, 16, '151.101.0.0/16'),
  ('fastly', 0xC701E000, 19, '199.27.72.0/21'),
];

int? _ipv4ToInt(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return null;
  final a = int.tryParse(p[0]);
  final b = int.tryParse(p[1]);
  final c = int.tryParse(p[2]);
  final d = int.tryParse(p[3]);
  if (a == null || b == null || c == null || d == null) return null;
  return ((a & 0xff) << 24) | ((b & 0xff) << 16) | ((c & 0xff) << 8) | (d & 0xff);
}

String? _matchCdnByIp(String ip) {
  final v = _ipv4ToInt(ip);
  if (v == null) return null;
  for (final (provider, base, prefix, _) in kCdnIpv4Ranges) {
    final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    if ((v & mask) == (base & mask)) return provider;
  }
  return null;
}

String _guessCdnFromHeaders(Map<String, String> headers) {
  final lower = <String, String>{};
  headers.forEach((k, v) => lower[k.toLowerCase()] = v.toLowerCase());
  final server = lower['server'] ?? '';
  if (server.contains('cloudflare') || lower.containsKey('cf-ray')) {
    return 'cloudflare';
  }
  if ((lower['via'] ?? '').contains('cloudfront') ||
      lower.containsKey('x-amz-cf-id') ||
      lower.containsKey('x-amz-cf-pop')) {
    return 'cloudfront';
  }
  if (lower.containsKey('x-served-by') ||
      (lower['x-cache'] ?? '').contains('fastly') ||
      server.contains('fastly')) {
    return 'fastly';
  }
  if (server.contains('akamai') ||
      lower.containsKey('x-akamai-request-id') ||
      (lower['server'] ?? '').contains('akamaighost')) {
    return 'akamai';
  }
  return 'unknown';
}

/// Terapkan metode Onering pada node:
/// server = bug, SNI = bug, Host header = domain VPS asli, TLS on.
Node applyOneringToNode(Node node, String bugHost) {
  final bug = bugHost.trim();
  if (bug.isEmpty) return node.copyWith();
  final vps = node.server.trim().isNotEmpty
      ? node.server.trim()
      : (node.sni.isNotEmpty ? node.sni : node.host);
  return node.copyWith(
    server: bug,
    sni: bug,
    host: vps.isNotEmpty ? vps : bug,
    tls: true,
  );
}

List<Node> applyOneringToNodes(List<Node> nodes, String bugHost) {
  final bug = bugHost.trim();
  if (bug.isEmpty) return nodes.map((n) => n.copyWith()).toList();
  return nodes.map((n) {
    if (n.protocol == 'ssh' || n.protocol == 'http') return n.copyWith();
    return applyOneringToNode(n, bug);
  }).toList();
}

String _safeB64Decode(String data) {
  var s = data.trim().replaceAll('-', '+').replaceAll('_', '/');
  final pad = s.length % 4;
  if (pad != 0) s += '=' * (4 - pad);
  return utf8.decode(base64.decode(s));
}


Node? parseLink(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
  final lower = trimmed.toLowerCase();
  try {
    if (lower.startsWith('vmess://')) return _parseVmess(trimmed);
    if (lower.startsWith('vless://')) return _parseVless(trimmed);
    if (lower.startsWith('trojan://')) return _parseTrojan(trimmed);
  } catch (_) {
    return null;
  }
  return null;
}

List<Node> parseLinks(String text) {
  final nodes = <Node>[];
  for (final line in text.split('\n')) {
    final n = parseLink(line);
    if (n != null) nodes.add(n);
  }
  return nodes;
}


// ---------------------------------------------------------------------------
// Deteksi region dari nama node (label UI saja; grup regional tidak dibuat)
// ---------------------------------------------------------------------------

const Map<String, List<String>> regionKeywords = {
  'SG': ['singapore', 'singapura', ' sgp', 'sg-', '-sg', ' sg ', '🇸🇬', 'sgp-'],
  'ID': ['indonesia', 'jakarta', ' id-', '-id', ' id ', '🇮🇩', 'idn'],
  'HK': ['hongkong', 'hong kong', ' hk-', '-hk', ' hk ', '🇭🇰', 'hkg'],
  'JP': ['japan', 'jepang', 'tokyo', ' jp-', '-jp', ' jp ', '🇯🇵', 'tyo'],
  'KR': ['korea', 'seoul', ' kr-', '-kr', ' kr ', '🇰🇷', 'sel'],
  'TW': ['taiwan', 'taipei', ' tw-', '-tw', ' tw ', '🇹🇼', 'tpe'],
  'US': [
    'america', 'united states', 'usa', ' us-', '-us', ' us ', '🇺🇸',
    'los angeles', 'new york', 'seattle', 'chicago',
  ],
  'EU': [
    'europe', 'eropa', 'germany', 'deutschland', 'france', 'netherlands',
    'holland', 'united kingdom', 'britain', 'london', 'poland', 'sweden',
    'finland', ' eu-', '-eu', ' de-', '-de', ' fr-', ' nl-', ' gb-', ' uk-',
    '🇪🇺', '🇩🇪', '🇫🇷', '🇳🇱', '🇬🇧',
  ],
};

/// Returns region code (SG, ID, ...) or empty if unknown.
String detectRegion(String name) {
  final lower = ' ${name.toLowerCase()} ';
  for (final entry in regionKeywords.entries) {
    for (final kw in entry.value) {
      if (lower.contains(kw.toLowerCase())) return entry.key;
    }
  }
  final upper = name.toUpperCase();
  for (final code in regionKeywords.keys) {
    if (RegExp('\\b$code\\b').hasMatch(upper) ||
        upper.startsWith('$code-') ||
        upper.startsWith('$code ') ||
        upper.endsWith('-$code') ||
        upper.endsWith(' $code')) {
      return code;
    }
  }
  return '';
}

Node _parseVmess(String uri) {
  var raw = uri.substring(8);
  String remark = '';
  final hashIdx = raw.indexOf('#');
  if (hashIdx >= 0) {
    remark = Uri.decodeComponent(raw.substring(hashIdx + 1));
    raw = raw.substring(0, hashIdx);
  }
  final data = jsonDecode(_safeB64Decode(raw)) as Map<String, dynamic>;
  final node = Node(protocol: 'vmess');
  node.name = remark.isNotEmpty
      ? remark
      : (data['ps']?.toString() ??
          data['remarks']?.toString() ??
          'vmess-${data['add'] ?? 'unknown'}');
  node.server = data['add']?.toString() ?? data['address']?.toString() ?? '';
  node.port = int.tryParse(data['port']?.toString() ?? '443') ?? 443;
  node.uuid = data['id']?.toString() ?? '';
  node.alterId =
      int.tryParse(data['aid']?.toString() ?? data['alterId']?.toString() ?? '0') ??
          0;
  node.cipher = data['scy']?.toString() ?? data['security']?.toString() ?? 'auto';
  final net = (data['net']?.toString() ?? data['network']?.toString() ?? 'tcp')
      .toLowerCase();
  node.network = net;
  final tlsVal = (data['tls']?.toString() ?? '').toLowerCase();
  node.tls = tlsVal == 'tls' || tlsVal == 'true' || tlsVal == '1';
  node.sni =
      data['sni']?.toString() ?? data['peer']?.toString() ?? data['host']?.toString() ?? '';
  node.host = data['host']?.toString() ?? '';
  node.path = data['path']?.toString() ?? '';
  node.fingerprint =
      data['fp']?.toString() ?? data['fingerprint']?.toString() ?? '';
  final alpn = data['alpn']?.toString() ?? '';
  if (alpn.isNotEmpty) {
    node.alpn = alpn.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  final insecure =
      data['allowInsecure']?.toString() ?? data['insecure']?.toString() ?? '0';
  node.skipCertVerify =
      insecure == '1' || insecure.toLowerCase() == 'true';
  if (data['type']?.toString() == 'grpc' || net == 'grpc') {
    node.serviceName =
        data['path']?.toString() ?? data['serviceName']?.toString() ?? '';
  }
  return node;
}

Node _parseVless(String uri) {
  final parsed = Uri.parse(uri);
  final node = Node(protocol: 'vless');
  node.uuid = Uri.decodeComponent(parsed.userInfo);
  node.server = parsed.host;
  node.port = parsed.hasPort ? parsed.port : 443;
  node.name = parsed.fragment.isNotEmpty
      ? Uri.decodeComponent(parsed.fragment)
      : 'vless-${node.server}';
  final params = parsed.queryParameters;

  node.encryption = params['encryption'] ?? 'none';
  final security = (params['security'] ?? '').toLowerCase();
  node.tls = security == 'tls' || security == 'reality';
  node.reality = security == 'reality';
  node.sni = params['sni'] ?? params['peer'] ?? '';
  node.fingerprint = params['fp'] ?? params['fingerprint'] ?? '';
  node.flow = params['flow'] ?? '';
  node.network =
      (params['type'] ?? params['network'] ?? 'tcp').toLowerCase();
  node.path = params['path'] ?? '';
  node.host = params['host'] ?? '';
  node.serviceName = params['serviceName'] ?? params['service_name'] ?? '';
  node.publicKey = params['pbk'] ?? params['publicKey'] ?? '';
  node.shortId = params['sid'] ?? params['shortId'] ?? '';
  node.packetEncoding =
      params['packetEncoding'] ?? params['packet_encoding'] ?? '';
  final alpn = params['alpn'] ?? '';
  if (alpn.isNotEmpty) {
    node.alpn = alpn.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  final insecure = params['insecure'] ?? params['allowInsecure'] ?? '0';
  node.skipCertVerify =
      insecure == '1' || insecure.toLowerCase() == 'true';
  return node;
}

Node _parseTrojan(String uri) {
  final parsed = Uri.parse(uri);
  final node = Node(protocol: 'trojan');
  node.password = Uri.decodeComponent(parsed.userInfo);
  node.server = parsed.host;
  node.port = parsed.hasPort ? parsed.port : 443;
  node.name = parsed.fragment.isNotEmpty
      ? Uri.decodeComponent(parsed.fragment)
      : 'trojan-${node.server}';
  final params = parsed.queryParameters;

  final security = (params['security'] ?? 'tls').toLowerCase();
  node.tls = security != 'none';
  node.sni = params['sni'] ?? params['peer'] ?? params['host'] ?? '';
  node.fingerprint = params['fp'] ?? params['fingerprint'] ?? '';
  node.network =
      (params['type'] ?? params['network'] ?? 'tcp').toLowerCase();
  node.path = params['path'] ?? '';
  node.host = params['host'] ?? '';
  node.serviceName = params['serviceName'] ?? params['service_name'] ?? '';
  final alpn = params['alpn'] ?? '';
  if (alpn.isNotEmpty) {
    node.alpn = alpn.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  final insecure = params['insecure'] ?? params['allowInsecure'] ?? '0';
  node.skipCertVerify =
      insecure == '1' || insecure.toLowerCase() == 'true';
  if (security == 'reality') {
    node.reality = true;
    node.publicKey = params['pbk'] ?? '';
    node.shortId = params['sid'] ?? '';
  }
  return node;
}

// ---------------------------------------------------------------------------
// Clash Meta YAML
// ---------------------------------------------------------------------------

/// Clash Meta / Mihomo proxy entry (kompatibel >= 1.19.x).
Map<String, dynamic> toClashProxy(Node node) {
  // ---- SSH ----
  if (node.protocol == 'ssh') {
    final proxy = <String, dynamic>{
      'name': node.name,
      'type': 'ssh',
      'server': node.server,
      'port': node.port,
      'username': node.username,
    };
    if (node.password.isNotEmpty) proxy['password'] = node.password;
    if (node.dialerProxy.isNotEmpty) {
      proxy['dialer-proxy'] = node.dialerProxy;
    }
    return proxy;
  }

  // ---- HTTP (proxy perantara untuk SSH) ----
  if (node.protocol == 'http') {
    final proxy = <String, dynamic>{
      'name': node.name,
      'type': 'http',
      'server': node.server,
      'port': node.port,
    };
    if (node.username.isNotEmpty) proxy['username'] = node.username;
    if (node.password.isNotEmpty) proxy['password'] = node.password;
    if (node.tls) {
      proxy['tls'] = true;
      if (node.sni.isNotEmpty) proxy['sni'] = node.sni;
      proxy['skip-cert-verify'] = node.skipCertVerify;
    }
    if (node.extraHeaders.isNotEmpty) {
      proxy['headers'] = Map<String, dynamic>.from(node.extraHeaders);
    }
    return proxy;
  }

  final proxy = <String, dynamic>{
    'name': node.name,
    'type': node.protocol,
    'server': node.server,
    'port': node.port,
    'udp': true,
  };

  if (node.protocol == 'vmess') {
    proxy['uuid'] = node.uuid;
    proxy['alterId'] = node.alterId;
    proxy['cipher'] = node.cipher.isEmpty ? 'auto' : node.cipher;
  } else if (node.protocol == 'vless') {
    proxy['uuid'] = node.uuid;
    // encryption: none adalah default VLESS
    proxy['encryption'] =
        node.encryption.isNotEmpty ? node.encryption : 'none';
    if (node.flow.isNotEmpty) proxy['flow'] = node.flow;
    if (node.packetEncoding.isNotEmpty) {
      proxy['packet-encoding'] = node.packetEncoding;
    }
  } else if (node.protocol == 'trojan') {
    proxy['password'] = node.password;
  }

  if (node.tls || node.reality) {
    proxy['tls'] = true;
    if (node.sni.isNotEmpty) {
      // Trojan memakai kunci `sni`; VMess/VLESS memakai `servername`
      if (node.protocol == 'trojan') {
        proxy['sni'] = node.sni;
      } else {
        proxy['servername'] = node.sni;
      }
    }
    if (node.alpn.isNotEmpty) proxy['alpn'] = node.alpn;
    // Per-proxy fingerprint (global global-client-fingerprint dihapus di Mihomo 1.19.27+)
    proxy['client-fingerprint'] =
        node.fingerprint.isNotEmpty ? node.fingerprint : 'chrome';
    proxy['skip-cert-verify'] = node.skipCertVerify;
    if (node.reality) {
      final opts = <String, dynamic>{'public-key': node.publicKey};
      if (node.shortId.isNotEmpty) opts['short-id'] = node.shortId;
      proxy['reality-opts'] = opts;
    }
  }

  var net = node.network.toLowerCase();
  if (net == 'websocket') net = 'ws';
  if (net.isNotEmpty && net != 'tcp') {
    proxy['network'] = net;
    if (net == 'ws' || net == 'httpupgrade') {
      final opts = <String, dynamic>{};
      if (node.path.isNotEmpty) opts['path'] = node.path;
      if (node.host.isNotEmpty) opts['headers'] = {'Host': node.host};
      if (opts.isNotEmpty) {
        // Meta: ws-opts untuk ws & httpupgrade
        proxy['ws-opts'] = opts;
      }
    } else if (net == 'grpc') {
      final opts = <String, dynamic>{};
      if (node.serviceName.isNotEmpty) {
        opts['grpc-service-name'] = node.serviceName;
      } else if (node.path.isNotEmpty) {
        opts['grpc-service-name'] = node.path;
      }
      if (opts.isNotEmpty) proxy['grpc-opts'] = opts;
    } else if (net == 'h2' || net == 'http') {
      final opts = <String, dynamic>{};
      if (node.path.isNotEmpty) opts['path'] = [node.path];
      if (node.host.isNotEmpty) opts['host'] = [node.host];
      if (opts.isNotEmpty) {
        proxy[net == 'h2' ? 'h2-opts' : 'http-opts'] = opts;
      }
    }
  }
  return proxy;
}


// ---------------------------------------------------------------------------
// Sing-box JSON
// ---------------------------------------------------------------------------

/// Sing-box outbound entry (format outbound modern: type vmess/vless/trojan/ssh/http).
Map<String, dynamic> toSingboxOutbound(Node node) {
  // ---- SSH ----
  if (node.protocol == 'ssh') {
    final outbound = <String, dynamic>{
      'type': 'ssh',
      'tag': node.name,
      'server': node.server,
      'server_port': node.port,
      'user': node.username,
    };
    if (node.password.isNotEmpty) outbound['password'] = node.password;
    if (node.dialerProxy.isNotEmpty) {
      outbound['detour'] = node.dialerProxy;
    }
    return outbound;
  }

  // ---- HTTP (proxy perantara untuk SSH) ----
  if (node.protocol == 'http') {
    final outbound = <String, dynamic>{
      'type': 'http',
      'tag': node.name,
      'server': node.server,
      'server_port': node.port,
    };
    if (node.username.isNotEmpty) outbound['username'] = node.username;
    if (node.password.isNotEmpty) outbound['password'] = node.password;
    if (node.path.isNotEmpty) outbound['path'] = node.path;
    if (node.extraHeaders.isNotEmpty) {
      outbound['headers'] = Map<String, dynamic>.from(node.extraHeaders);
    }
    if (node.tls) {
      final tls = <String, dynamic>{
        'enabled': true,
        'insecure': node.skipCertVerify,
      };
      if (node.sni.isNotEmpty) tls['server_name'] = node.sni;
      outbound['tls'] = tls;
    }
    return outbound;
  }

  final outbound = <String, dynamic>{
    'type': node.protocol,
    'tag': node.name,
    'server': node.server,
    'server_port': node.port,
  };

  if (node.protocol == 'vmess') {
    outbound['uuid'] = node.uuid;
    outbound['security'] = node.cipher.isEmpty ? 'auto' : node.cipher;
    outbound['alter_id'] = node.alterId;
    outbound['packet_encoding'] =
        node.packetEncoding.isNotEmpty ? node.packetEncoding : 'xudp';
  } else if (node.protocol == 'vless') {
    outbound['uuid'] = node.uuid;
    if (node.flow.isNotEmpty) outbound['flow'] = node.flow;
    outbound['packet_encoding'] =
        node.packetEncoding.isNotEmpty ? node.packetEncoding : 'xudp';
  } else if (node.protocol == 'trojan') {
    outbound['password'] = node.password;
  }

  if (node.tls || node.reality) {
    final tls = <String, dynamic>{'enabled': true};
    if (node.sni.isNotEmpty) tls['server_name'] = node.sni;
    if (node.alpn.isNotEmpty) tls['alpn'] = node.alpn;
    tls['insecure'] = node.skipCertVerify;
    // uTLS fingerprint (chrome default) — relevan untuk TLS/Reality
    final fp = node.fingerprint.isNotEmpty ? node.fingerprint : 'chrome';
    tls['utls'] = {'enabled': true, 'fingerprint': fp};
    if (node.reality) {
      final reality = <String, dynamic>{
        'enabled': true,
        'public_key': node.publicKey,
      };
      if (node.shortId.isNotEmpty) reality['short_id'] = node.shortId;
      tls['reality'] = reality;
    }
    outbound['tls'] = tls;
  }

  var net = node.network.toLowerCase();
  if (net == 'websocket') net = 'ws';
  if (net.isNotEmpty && net != 'tcp' && net != 'raw') {
    final transport = <String, dynamic>{};
    if (net == 'ws' || net == 'httpupgrade') {
      transport['type'] = net == 'httpupgrade' ? 'httpupgrade' : 'ws';
      if (node.path.isNotEmpty) transport['path'] = node.path;
      if (node.host.isNotEmpty) {
        transport['headers'] = {'Host': node.host};
      }
    } else if (net == 'grpc') {
      transport['type'] = 'grpc';
      if (node.serviceName.isNotEmpty) {
        transport['service_name'] = node.serviceName;
      } else if (node.path.isNotEmpty) {
        transport['service_name'] = node.path;
      }
    } else if (net == 'h2' || net == 'http') {
      transport['type'] = 'http';
      if (node.path.isNotEmpty) transport['path'] = node.path;
      if (node.host.isNotEmpty) transport['host'] = [node.host];
    }
    if (transport.isNotEmpty) outbound['transport'] = transport;
  }
  return outbound;
}


// ---------------------------------------------------------------------------
// YAML dumper (no external package)
// ---------------------------------------------------------------------------

String dumpYaml(dynamic data) {
  bool needsQuote(String s) {
    if (s.isEmpty || s.trim() != s) return true;
    const special = ':#{}[]&*?|>!%@`\'"';
    if (s.split('').any((c) => special.contains(c))) return true;
    final lower = s.toLowerCase();
    return lower == 'true' ||
        lower == 'false' ||
        lower == 'null' ||
        lower == 'yes' ||
        lower == 'no' ||
        lower == 'on' ||
        lower == 'off';
  }

  String fmtScalar(dynamic v) {
    if (v is bool) return v ? 'true' : 'false';
    if (v == null) return 'null';
    if (v is String) {
      if (needsQuote(v)) {
        final escaped = v.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        return '"$escaped"';
      }
      return v;
    }
    return v.toString();
  }

  List<String> dump(dynamic obj, [int indent = 0]) {
    final sp = '  ' * indent;
    final out = <String>[];
    if (obj is Map) {
      for (final entry in obj.entries) {
        final k = entry.key;
        final v = entry.value;
        if (v is Map) {
          if (v.isEmpty) {
            out.add('$sp$k: {}');
          } else {
            out.add('$sp$k:');
            out.addAll(dump(v, indent + 1));
          }
        } else if (v is List) {
          if (v.isEmpty) {
            out.add('$sp$k: []');
          } else {
            out.add('$sp$k:');
            out.addAll(dump(v, indent + 1));
          }
        } else {
          out.add('$sp$k: ${fmtScalar(v)}');
        }
      }
    } else if (obj is List) {
      for (final item in obj) {
        if (item is Map) {
          final keys = item.keys.toList();
          if (keys.isEmpty) {
            out.add('$sp- {}');
            continue;
          }
          final firstK = keys.first;
          final firstV = item[firstK];
          if (firstV is Map || firstV is List) {
            out.add('$sp- $firstK:');
            out.addAll(dump(firstV, indent + 2));
            for (var i = 1; i < keys.length; i++) {
              final k = keys[i];
              final v = item[k];
              if (v is Map || v is List) {
                out.add('$sp  $k:');
                out.addAll(dump(v, indent + 2));
              } else {
                out.add('$sp  $k: ${fmtScalar(v)}');
              }
            }
          } else {
            out.add('$sp- $firstK: ${fmtScalar(firstV)}');
            for (var i = 1; i < keys.length; i++) {
              final k = keys[i];
              final v = item[k];
              if (v is Map || v is List) {
                out.add('$sp  $k:');
                out.addAll(dump(v, indent + 2));
              } else {
                out.add('$sp  $k: ${fmtScalar(v)}');
              }
            }
          }
        } else if (item is List) {
          out.add('$sp-');
          out.addAll(dump(item, indent + 1));
        } else {
          out.add('$sp- ${fmtScalar(item)}');
        }
      }
    } else {
      out.add('$sp${fmtScalar(obj)}');
    }
    return out;
  }

  return '${dump(data).join('\n')}\n';
}

// ---------------------------------------------------------------------------
// Template injection — Clash YAML
// ---------------------------------------------------------------------------

/// Replace the `proxies:` block in a Clash template with converted proxies.
/// Groups keep `include-all-proxies: true` so names are not injected into groups.
String injectClashProxies(String templateYaml, List<Node> nodes) {
  final proxies = nodes.map(toClashProxy).toList();
  final proxiesBlock = StringBuffer();
  proxiesBlock.writeln('proxies:');
  final dumped = dumpYaml(proxies).trimRight().split('\n');
  for (final line in dumped) {
    proxiesBlock.writeln('  $line');
  }

  final lines = templateYaml.split('\n');
  final out = <String>[];
  var i = 0;
  var replaced = false;

  while (i < lines.length) {
    final line = lines[i];
    final isProxiesKey = RegExp(r'^proxies:\s*$').hasMatch(line);
    final isProxiesComment =
        line.contains('PROXIES STORAGE') || line.contains('INJECTED BY CONVERTER');

    if (!replaced && (isProxiesKey || isProxiesComment)) {
      if (isProxiesComment) {
        out.add(line);
        i++;
        while (i < lines.length && lines[i].trim().isEmpty) {
          out.add(lines[i]);
          i++;
        }
        if (i < lines.length && RegExp(r'^proxies:\s*$').hasMatch(lines[i])) {
          i++;
        }
      } else {
        i++;
      }

      while (i < lines.length) {
        final l = lines[i];
        if (l.trim().isEmpty) {
          i++;
          continue;
        }
        if (!l.startsWith(' ') && !l.startsWith('\t') && !l.startsWith('#')) {
          break;
        }
        if (RegExp(r'^proxy-groups:\s*$').hasMatch(l)) break;
        i++;
      }

      out.add(proxiesBlock.toString().trimRight());
      out.add('');
      replaced = true;
      continue;
    }

    out.add(line);
    i++;
  }

  if (!replaced) {
    out.add('');
    out.add(proxiesBlock.toString().trimRight());
  }

  return out.join('\n');
}

// ---------------------------------------------------------------------------
// Inject outbounds ke template Sing-box.
// ---------------------------------------------------------------------------

const _regionPlaceholderMap = {
  '==TAG_SG==': 'SG',
  '==TAG_ID==': 'ID',
  '==TAG_HK==': 'HK',
  '==TAG_JP==': 'JP',
  '==TAG_KR==': 'KR',
  '==TAG_TW==': 'TW',
  '==TAG_US==': 'US',
  '==TAG_EU==': 'EU',
};

/// Inject converted outbounds into a Sing-box template JSON string.
String injectSingboxOutbounds(String templateJson, List<Node> nodes) {
  final data = jsonDecode(templateJson) as Map<String, dynamic>;
  final allTags = nodes.map((n) => n.name).toList();

  final byRegion = <String, List<String>>{
    for (final code in regionKeywords.keys) code: <String>[],
  };
  for (final n in nodes) {
    final r = detectRegion(n.name);
    if (r.isNotEmpty) byRegion[r]!.add(n.name);
  }

  List<String> expandPlaceholders(List<dynamic> tags) {
    final result = <String>[];
    for (final t in tags) {
      final s = t.toString();
      if (s == '==DAFTAR_SEMUA_TAG_PROXY==') {
        result.addAll(allTags);
      } else if (_regionPlaceholderMap.containsKey(s)) {
        final code = _regionPlaceholderMap[s]!;
        final matched = byRegion[code] ?? [];
        if (matched.isEmpty) {
          result.add('DIRECT');
        } else {
          result.addAll(matched);
        }
      } else {
        result.add(s);
      }
    }
    final seen = <String>{};
    return result.where((e) => seen.add(e)).toList();
  }

  final outbounds = (data['outbounds'] as List).cast<Map<String, dynamic>>();
  final newOutbounds = <Map<String, dynamic>>[];

  for (final o in outbounds) {
    if (o.containsKey('outbounds') && o['outbounds'] is List) {
      o['outbounds'] = expandPlaceholders(o['outbounds'] as List);
    }
    newOutbounds.add(o);
  }

  final proxyOutbounds = nodes.map(toSingboxOutbound).toList();
  final directIdx =
      newOutbounds.indexWhere((o) => o['tag'] == 'DIRECT' && o['type'] == 'direct');
  if (directIdx >= 0) {
    newOutbounds.insertAll(directIdx, proxyOutbounds);
  } else {
    newOutbounds.addAll(proxyOutbounds);
  }

  data['outbounds'] = newOutbounds;
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Render Clash config from template + nodes.
String renderClash(String templateYaml, List<Node> nodes) {
  return injectClashProxies(templateYaml, nodes);
}

/// Render Sing-box config from template + nodes.
String renderSingbox(String templateJson, List<Node> nodes) {
  return injectSingboxOutbounds(templateJson, nodes);
}

// ---------------------------------------------------------------------------
// Mode Custom — generator penuh.
// ---------------------------------------------------------------------------

class CustomRuleItem {
  final String id;
  final String type; // DOMAIN-SUFFIX, DOMAIN-KEYWORD, IP-CIDR, GEOIP
  final String payload;
  final String target; // DIRECT, REJECT, PILIH-PROXY, AI-CHATGPT, STREAMING, GAME

  const CustomRuleItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.target,
  });
}

/// Mixed-port Clash bawaan. Sama dengan template Minimal & Lengkap (yang terbukti
/// konek) agar modul/aplikasi yang memakai port tersebut tetap cocok di mode Custom.
const int kDefaultClashMixedPort = 7892;

class CustomAddonOptions {
  final String primaryDns; // cloudflare | google | adguard | quad9 | custom
  final String customPrimaryUrl;
  final String secondaryDns;
  final String customSecondaryUrl;
  final String dnsStrategy; // ipv4_only | prefer_ipv4 | prefer_ipv6
  final bool enableFakeIp;
  final bool directDomesticBankingDns;

  final bool enableAntiAds;
  final bool enableAiRouting;
  final bool enableStreamingRouting;
  final bool enableGamingRouting;
  final bool enableDomesticBypass;
  final bool enableBlockTorrent;
  final bool enableBlockQuic;
  final List<CustomRuleItem> customRules;

  final bool enableGeoipIdDirect;
  final bool enablePrivateDirect;
  final bool autoCreateRegionGroups;
  final List<String> selectedRegions;

  final String mainGroupName;
  final bool autoFastest;
  final int urlTestInterval;
  final int mixedPort;
  final bool tunEnabled;

  const CustomAddonOptions({
    this.primaryDns = 'cloudflare',
    this.customPrimaryUrl = '',
    this.secondaryDns = 'google',
    this.customSecondaryUrl = '',
    this.dnsStrategy = 'ipv4_only',
    this.enableFakeIp = true,
    this.directDomesticBankingDns = false,
    this.enableAntiAds = false,
    this.enableAiRouting = false,
    this.enableStreamingRouting = false,
    this.enableGamingRouting = false,
    this.enableDomesticBypass = false,
    this.enableBlockTorrent = false,
    this.enableBlockQuic = true,
    this.customRules = const [],
    this.enableGeoipIdDirect = false,
    this.enablePrivateDirect = true,
    this.autoCreateRegionGroups = false,
    this.selectedRegions = const [],
    this.mainGroupName = 'PILIH-PROXY',
    this.autoFastest = true,
    this.urlTestInterval = 300,
    this.mixedPort = kDefaultClashMixedPort,
    this.tunEnabled = false,
  });
}

const List<String> domesticBankDomains = [
  'klikbca.com', 'bca.co.id', 'blubybcadigital.id', 'bri.co.id', 'brimo.bri.co.id',
  'bankmandiri.co.id', 'livinbymandiri.com', 'bni.co.id', 'btn.co.id', 'cimbniaga.co.id',
  'permatabank.com', 'danamon.co.id', 'ocbc.id', 'maybank.co.id', 'panin.co.id',
  'bankbsi.co.id', 'jago.com', 'seabank.co.id', 'allobank.com', 'jenius.com',
  'dana.id', 'ovo.id', 'gopay.co.id', 'linkaja.id', 'shopeepay.co.id',
  'tokopedia.com', 'tokopedia.net', 'shopee.co.id', 'lazada.co.id', 'bukalapak.com', 'blibli.com',
  'ojk.go.id', 'bi.go.id', 'pajak.go.id', 'kemenkeu.go.id'
];

/// Render Clash Meta YAML from scratch with custom modular addons matching web app.
String renderClashCustom(List<Node> nodes, CustomAddonOptions opts) {
  final proxies = nodes.map(toClashProxy).toList();
  final proxyGroups = <Map<String, dynamic>>[];
  final mainGroupName = opts.mainGroupName.isNotEmpty ? opts.mainGroupName : 'PILIH-PROXY';
  final mainProxies = <String>[];

  if (opts.autoFastest) {
    mainProxies.add('AUTO-TERCEPAT');
    proxyGroups.add({
      'name': 'AUTO-TERCEPAT',
      'type': 'url-test',
      'include-all-proxies': true,
      'url': 'https://www.gstatic.com/generate_204',
      'interval': opts.urlTestInterval,
      'tolerance': 50,
    });
  }

  if (opts.enableAiRouting) {
    mainProxies.add('AI-CHATGPT');
    proxyGroups.add({
      'name': 'AI-CHATGPT',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.enableStreamingRouting) {
    mainProxies.add('STREAMING');
    proxyGroups.add({
      'name': 'STREAMING',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.enableGamingRouting) {
    mainProxies.add('GAME');
    proxyGroups.add({
      'name': 'GAME',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.autoCreateRegionGroups) {
    for (final reg in opts.selectedRegions) {
      final regName = 'REGION-$reg';
      mainProxies.add(regName);
      final kw = regionKeywords[reg] ?? [reg.toLowerCase()];
      proxyGroups.add({
        'name': regName,
        'type': 'url-test',
        'include-all-proxies': true,
        'filter': '(?i)${kw.join('|')}',
        'url': 'https://www.gstatic.com/generate_204',
        'interval': opts.urlTestInterval,
      });
    }
  }

  mainProxies.add('DIRECT');

  proxyGroups.insert(0, {
    'name': mainGroupName,
    'type': 'select',
    'include-all-proxies': true,
    'proxies': mainProxies,
  });

  final ruleProviders = <String, dynamic>{};
  if (opts.enableAntiAds) {
    ruleProviders['gs-ads'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-ads.mrs',
      'url': 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-ads-all.mrs',
    };
  }
  if (opts.enableAiRouting) {
    ruleProviders['gs-ai'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-ai.mrs',
      'url': 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/openai.mrs',
    };
  }
  if (opts.enableStreamingRouting) {
    ruleProviders['gs-streaming'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-streaming.mrs',
      'url': 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/netflix.mrs',
    };
  }
  if (opts.enableGamingRouting) {
    ruleProviders['gs-games'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-games.mrs',
      'url': 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-games.mrs',
    };
  }
  if (opts.enableGeoipIdDirect) {
    ruleProviders['gi-id'] = {
      'type': 'http',
      'behavior': 'ipcidr',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gi-id.mrs',
      'url': 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geoip/id.mrs',
    };
  }
  final rules = <String>[];
  // Jaringan lokal paling atas, persis seperti Minimal/Lengkap. Tanpa rule-provider
  // remote: provider yang gagal diunduh saat start (jaringan bug/terbatas) membuat
  // core gagal memuat config atau macet, sehingga "konek tapi tidak ada internet".
  if (opts.enablePrivateDirect) {
    rules.add('GEOIP,LAN,DIRECT,no-resolve');
  }
  if (opts.enableBlockTorrent) {
    rules.add('DST-PORT,6881-6889,REJECT');
    rules.add('PROCESS-NAME,BitTorrent,REJECT');
    rules.add('PROCESS-NAME,uTorrent,REJECT');
  }
  if (opts.enableBlockQuic) {
    rules.add('AND,((DST-PORT,443),(NETWORK,UDP)),REJECT');
  }
  if (opts.enableAntiAds) rules.add('RULE-SET,gs-ads,REJECT');

  if (opts.enableDomesticBypass) {
    for (final d in domesticBankDomains.take(25)) {
      rules.add('DOMAIN-SUFFIX,$d,DIRECT');
    }
  }
  if (opts.enableGeoipIdDirect) {
    rules.add('RULE-SET,gi-id,DIRECT,no-resolve');
  }
  if (opts.enableAiRouting) rules.add('RULE-SET,gs-ai,AI-CHATGPT');
  if (opts.enableStreamingRouting) rules.add('RULE-SET,gs-streaming,STREAMING');
  if (opts.enableGamingRouting) rules.add('RULE-SET,gs-games,GAME');

  // Custom User Rules (map target logis ke nama grup Clash yang sebenarnya)
  for (final cr in opts.customRules) {
    if (cr.payload.isNotEmpty) {
      final target = _resolveRuleTarget(opts, mainGroupName, cr.target);
      rules.add('${cr.type},${cr.payload},$target');
    }
  }

  rules.add('MATCH,$mainGroupName');

  final dohUrl = _resolveDohUrl(opts.primaryDns, opts.customPrimaryUrl);
  final dohUrlSecondary = _resolveDohUrl(opts.secondaryDns, opts.customSecondaryUrl);

  final nameserverList = dohUrlSecondary != dohUrl
      ? [dohUrl, dohUrlSecondary]
      : [dohUrl, 'https://1.1.1.1/dns-query'];

  // Kebijakan DNS untuk domain bank/domestik: resolve lewat IP bootstrap (bukan DoH)
  // agar akses perbankan tidak terpengaruh pemblokiran DoH.
  final nameserverPolicy = <String, dynamic>{};
  if (opts.enableDomesticBypass && opts.directDomesticBankingDns) {
    for (final d in domesticBankDomains.take(30)) {
      nameserverPolicy['+.$d'] = '1.1.1.1';
    }
  }

  final dnsConfig = <String, dynamic>{
    'enable': true,
    'ipv6': opts.dnsStrategy != 'ipv4_only',
    'enhanced-mode': opts.enableFakeIp ? 'fake-ip' : 'redir-host',
    'fake-ip-range': '198.18.0.1/16',
    if (opts.enableFakeIp) 'fake-ip-filter': clashFakeIpFilter,
    'default-nameserver': ['1.1.1.1', '8.8.8.8'],
    'nameserver': nameserverList,
    // Me-resolve domain server proxy: IP biasa (UDP) di depan agar tetap jalan di
    // jaringan terbatas/paket bug yang memblokir DoH; DoH pilihan pengguna sebagai cadangan.
    'proxy-server-nameserver': ['1.1.1.1', '8.8.8.8', ...nameserverList],
  };
  if (nameserverPolicy.isNotEmpty) {
    dnsConfig['nameserver-policy'] = nameserverPolicy;
  }

  final config = <String, dynamic>{
    'mixed-port': opts.mixedPort,
    'allow-lan': false,
    'mode': 'rule',
    'log-level': 'info',
    'ipv6': opts.dnsStrategy != 'ipv4_only',
    'external-controller': '127.0.0.1:9090',
    'secret': '',
    'unified-delay': true,
    'tcp-concurrent': true,
    'find-process-mode': 'off',
    'geodata-mode': false,
    'profile': {'store-selected': true, 'store-fake-ip': true},
    'tun': {
      'enable': opts.tunEnabled,
      'stack': 'mixed',
      'dns-hijack': ['any:53', 'tcp://any:53'],
      'auto-route': true,
      'auto-detect-interface': true,
      'strict-route': false,
    },
    'dns': dnsConfig,
    'proxies': proxies,
    'proxy-groups': proxyGroups,
    'rules': rules,
  };
  if (ruleProviders.isNotEmpty) {
    config['rule-providers'] = ruleProviders;
  }

  return dumpYaml(config);
}

/// Domain yang dikecualikan dari fake-ip pada config Clash (jaringan lokal & cek
/// koneksi Windows). Sama dengan yang dipakai template Minimal.
const List<String> clashFakeIpFilter = [
  '*.lan',
  '*.local',
  '+.msftconnecttest.com',
  '+.msftncsi.com',
];

/// Nama grup tujuan untuk custom rule. Grup AI/STREAMING/GAME hanya ada bila
/// fiturnya aktif; jika aturan lama masih menunjuk grup yang sudah dimatikan,
/// dialihkan ke grup utama supaya tidak merujuk outbound/grup yang tidak ada
/// (trafik yang cocok dengan aturan itu akan gagal total).
String _resolveRuleTarget(
  CustomAddonOptions opts,
  String mainGroupName,
  String target,
) {
  switch (target) {
    case 'PILIH-PROXY':
      return mainGroupName;
    case 'AI-CHATGPT':
      return opts.enableAiRouting ? 'AI-CHATGPT' : mainGroupName;
    case 'STREAMING':
      return opts.enableStreamingRouting ? 'STREAMING' : mainGroupName;
    case 'GAME':
      return opts.enableGamingRouting ? 'GAME' : mainGroupName;
    default:
      return target;
  }
}

/// Tambahkan skema https:// bila pengguna menempel URL DoH tanpa skema.
String _withHttpsScheme(String url) {
  final t = url.trim();
  return t.contains('://') ? t : 'https://$t';
}

/// Resolve DoH URL from preset name or custom URL.
String _resolveDohUrl(String preset, String customUrl) {
  switch (preset) {
    case 'google':
      return 'https://8.8.8.8/dns-query';
    case 'adguard':
      return 'https://dns.adguard-dns.com/dns-query';
    case 'quad9':
      return 'https://dns.quad9.net/dns-query';
    case 'custom':
      return customUrl.trim().isNotEmpty
          ? _withHttpsScheme(customUrl)
          : 'https://1.1.1.1/dns-query';
    case 'cloudflare':
    default:
      return 'https://1.1.1.1/dns-query';
  }
}

/// Resolve plain DNS host/IP for Sing-box from preset name or custom DoH URL.
String _resolveDnsIp(String preset, [String customUrl = '']) {
  if (preset == 'custom' && customUrl.isNotEmpty) {
    try {
      final host = Uri.parse(customUrl).host;
      if (host.isNotEmpty) return host;
    } catch (_) {}
  }
  switch (preset) {
    case 'google':
      return '8.8.8.8';
    case 'adguard':
      return '94.140.14.14';
    case 'quad9':
      return '9.9.9.9';
    case 'cloudflare':
    default:
      return '1.1.1.1';
  }
}

/// Alamat server DoH untuk Sing-box: host, port, dan path.
class _DohSpec {
  final String host;
  final int port;
  final String path;
  const _DohSpec(this.host, [this.port = 443, this.path = '/dns-query']);

  bool sameAs(_DohSpec o) => host == o.host && port == o.port && path == o.path;
}

/// Preset memakai IP + path bawaan (`/dns-query`). URL custom dipertahankan utuh
/// (host, port, path) — sebelumnya hanya host yang diambil sehingga DoH dengan
/// path khusus (mis. `https://dns.nextdns.io/abc123`) menghasilkan DNS yang gagal.
_DohSpec _resolveDohSpec(String preset, [String customUrl = '']) {
  if (preset == 'custom' && customUrl.trim().isNotEmpty) {
    try {
      final u = Uri.parse(_withHttpsScheme(customUrl));
      if (u.host.isNotEmpty) {
        final path = (u.path.isEmpty || u.path == '/') ? '/dns-query' : u.path;
        return _DohSpec(u.host, u.hasPort ? u.port : 443, path);
      }
    } catch (_) {}
  }
  return _DohSpec(_resolveDnsIp(preset, customUrl));
}

/// Render Sing-box JSON with custom modular addons matching web app.
String renderSingboxCustom(List<Node> nodes, CustomAddonOptions opts) {
  final allTags = nodes.map((n) => n.name).toList();
  final byRegion = <String, List<String>>{
    for (final reg in opts.selectedRegions) reg: <String>[],
  };
  for (final n in nodes) {
    final r = detectRegion(n.name);
    if (r.isNotEmpty && byRegion.containsKey(r)) {
      byRegion[r]!.add(n.name);
    }
  }

  final doh = _resolveDohSpec(opts.primaryDns, opts.customPrimaryUrl);
  final dohSecondary =
      _resolveDohSpec(opts.secondaryDns, opts.customSecondaryUrl);

  final mainGroupName = opts.mainGroupName.isNotEmpty ? opts.mainGroupName : 'PILIH-PROXY';

  Map<String, dynamic> dohServer(String tag, _DohSpec s) => {
        'type': 'https',
        'tag': tag,
        'server': s.host,
        if (s.port != 443) 'server_port': s.port,
        if (s.path != '/dns-query') 'path': s.path,
        'detour': mainGroupName,
      };

  final dnsServers = <Map<String, dynamic>>[
    {'type': 'local', 'tag': 'dns-local'},
    dohServer('dns-remote', doh),
  ];
  if (!dohSecondary.sameAs(doh)) {
    dnsServers.add(dohServer('dns-secondary', dohSecondary));
  }

  if (opts.enableGamingRouting) {
    dnsServers.add({
      'type': 'udp',
      'tag': 'dns-game',
      'server': '8.8.8.8',
      'detour': 'GAME',
    });
  }

  final dnsRules = <Map<String, dynamic>>[];
  if (opts.enableAntiAds) {
    dnsRules.add({
      'rule_set': ['geosite-category-ads-all'],
      'action': 'predefined',
      'rcode': 'NXDOMAIN',
    });
  }
  if (opts.enableDomesticBypass && opts.directDomesticBankingDns) {
    dnsRules.add({
      'domain_suffix': domesticBankDomains.take(30).toList(),
      'server': 'dns-local',
    });
  }

  final mainSelectors = <String>[];
  final outbounds = <Map<String, dynamic>>[];

  if (opts.autoFastest) mainSelectors.add('AUTO-TERCEPAT');
  if (opts.enableAiRouting) mainSelectors.add('AI-CHATGPT');
  if (opts.enableStreamingRouting) mainSelectors.add('STREAMING');
  if (opts.enableGamingRouting) mainSelectors.add('GAME');

  if (opts.autoCreateRegionGroups) {
    for (final reg in opts.selectedRegions) {
      mainSelectors.add('REGION-$reg');
    }
  }
  mainSelectors.add('DIRECT');
  mainSelectors.addAll(allTags);

  outbounds.add({
    'type': 'selector',
    'tag': mainGroupName,
    'outbounds': mainSelectors,
    'default': opts.autoFastest ? 'AUTO-TERCEPAT' : (allTags.isNotEmpty ? allTags.first : 'DIRECT'),
  });

  if (opts.autoFastest) {
    outbounds.add({
      'type': 'urltest',
      'tag': 'AUTO-TERCEPAT',
      'outbounds': allTags.isNotEmpty ? allTags : ['DIRECT'],
      'url': 'https://www.gstatic.com/generate_204',
      'interval': '${(opts.urlTestInterval / 60).round().clamp(1, 1440)}m',
      'tolerance': 50,
    });
  }

  if (opts.enableAiRouting) {
    outbounds.add({
      'type': 'selector',
      'tag': 'AI-CHATGPT',
      'outbounds': [if (opts.autoFastest) 'AUTO-TERCEPAT', ...allTags, 'DIRECT'],
      'default': opts.autoFastest ? 'AUTO-TERCEPAT' : (allTags.isNotEmpty ? allTags.first : 'DIRECT'),
    });
  }

  if (opts.enableStreamingRouting) {
    outbounds.add({
      'type': 'selector',
      'tag': 'STREAMING',
      'outbounds': [if (opts.autoFastest) 'AUTO-TERCEPAT', ...allTags, 'DIRECT'],
      'default': opts.autoFastest ? 'AUTO-TERCEPAT' : (allTags.isNotEmpty ? allTags.first : 'DIRECT'),
    });
  }

  if (opts.enableGamingRouting) {
    outbounds.add({
      'type': 'selector',
      'tag': 'GAME',
      'outbounds': [if (opts.autoFastest) 'AUTO-TERCEPAT', ...allTags, 'DIRECT'],
      'default': opts.autoFastest ? 'AUTO-TERCEPAT' : (allTags.isNotEmpty ? allTags.first : 'DIRECT'),
    });
  }

  if (opts.autoCreateRegionGroups) {
    final intervalStr = '${(opts.urlTestInterval / 60).round().clamp(1, 1440)}m';
    for (final reg in opts.selectedRegions) {
      final regTags = byRegion[reg] ?? [];
      outbounds.add({
        'type': 'urltest',
        'tag': 'REGION-$reg',
        'outbounds': regTags.isNotEmpty ? regTags : ['DIRECT'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': intervalStr,
      });
    }
  }

  for (final n in nodes) {
    outbounds.add(toSingboxOutbound(n));
  }

  outbounds.add({'type': 'direct', 'tag': 'DIRECT'});
  // type dns & block outbound dihapus di sing-box 1.13 — DNS lewat action hijack-dns,
  // blokir lewat route action reject (lihat custom rules di bawah).

  final routeRules = <Map<String, dynamic>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
  ];
  // QUIC ditolak lewat sniff (`protocol: quic`) di posisi yang sama dengan
  // template Minimal/Lengkap yang terbukti konek. Aturan lama `port 443 + udp`
  // menolak semua UDP/443 tanpa sniff dan tidak identik dengan referensi.
  if (opts.enableBlockQuic) {
    routeRules.add({'protocol': 'quic', 'action': 'reject'});
  }
  routeRules.addAll([
    {'clash_mode': 'Direct', 'outbound': 'DIRECT'},
    {'clash_mode': 'Global', 'outbound': mainGroupName},
  ]);

  if (opts.enablePrivateDirect) {
    routeRules.add({'ip_is_private': true, 'outbound': 'DIRECT'});
  }

  if (opts.enableBlockTorrent) {
    routeRules.add({'port_range': ['6881:6889'], 'action': 'reject'});
  }
  if (opts.enableAntiAds) {
    routeRules.add({'rule_set': ['geosite-category-ads-all'], 'action': 'reject'});
  }
  if (opts.enableDomesticBypass) {
    routeRules.add({'domain_suffix': domesticBankDomains.take(30).toList(), 'outbound': 'DIRECT'});
    if (opts.enableGeoipIdDirect) {
      routeRules.add({'rule_set': ['geoip-id'], 'outbound': 'DIRECT'});
    }
  }
  if (opts.enableAiRouting) {
    routeRules.add({'rule_set': ['geosite-openai'], 'outbound': 'AI-CHATGPT'});
  }
  if (opts.enableStreamingRouting) {
    routeRules.add({'rule_set': ['geosite-streaming'], 'outbound': 'STREAMING'});
  }
  if (opts.enableGamingRouting) {
    routeRules.add({'rule_set': ['geosite-game'], 'outbound': 'GAME'});
  }

  // Custom User Rules in Singbox
  final extraGeoip = <String>{};
  for (final cr in opts.customRules) {
    final target = _resolveRuleTarget(opts, mainGroupName, cr.target);
    // REJECT bukan outbound lagi (block dihapus di 1.13) — pakai action reject.
    Map<String, dynamic> withTarget(Map<String, dynamic> m) {
      if (target == 'REJECT') {
        m['action'] = 'reject';
      } else {
        m['outbound'] = target;
      }
      return m;
    }

    if (cr.type == 'DOMAIN-SUFFIX') {
      routeRules.add(withTarget({'domain_suffix': [cr.payload]}));
    } else if (cr.type == 'DOMAIN-KEYWORD') {
      routeRules.add(withTarget({'domain_keyword': [cr.payload]}));
    } else if (cr.type == 'IP-CIDR') {
      routeRules.add(withTarget({'ip_cidr': [cr.payload]}));
    } else if (cr.type == 'GEOIP') {
      // field `geoip` dihapus di sing-box 1.12 — ganti dengan rule_set geoip-xx.
      final cc = cr.payload.trim().toLowerCase();
      if (cc.isNotEmpty) {
        extraGeoip.add(cc);
        routeRules.add(withTarget({'rule_set': ['geoip-$cc']}));
      }
    }
  }

  // Sing-box 1.14+ compliant: download rule-set lewat http_client saja.
  // JANGAN sertakan `download_detour` (deprecated) — bentrok dengan `http_client`
  // dan bikin core gagal start: "http_client is conflict with deprecated
  // download_detour field". Detour proxy sudah diatur di http_clients[default-http].
  Map<String, dynamic> remoteRuleSet(String tag, String url) => {
        'tag': tag,
        'type': 'remote',
        'format': 'binary',
        'url': url,
        'http_client': 'default-http',
        'update_interval': '1d',
      };

  final ruleSets = <Map<String, dynamic>>[];
  if (opts.enableAntiAds) {
    ruleSets.add(remoteRuleSet(
      'geosite-category-ads-all',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/category-ads-all.srs',
    ));
  }
  if (opts.enableDomesticBypass && opts.enableGeoipIdDirect) {
    ruleSets.add(remoteRuleSet(
      'geoip-id',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/id.srs',
    ));
  }
  for (final cc in extraGeoip) {
    if (ruleSets.any((r) => r['tag'] == 'geoip-$cc')) continue;
    ruleSets.add(remoteRuleSet(
      'geoip-$cc',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/$cc.srs',
    ));
  }
  if (opts.enableAiRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-openai',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/openai.srs',
    ));
  }
  if (opts.enableStreamingRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-streaming',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/netflix.srs',
    ));
  }
  if (opts.enableGamingRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-game',
      'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/category-games.srs',
    ));
  }

  final inbounds = <Map<String, dynamic>>[
    {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '127.0.0.1',
      'listen_port': 2080,
    },
  ];
  // TUN IPv4 saja (172.19.0.1/30) sama persis dengan Mode Minimal yang terbukti konek.
  // Menghindari blackhole IPv6 saat strict_route aktif pada Android.
  inbounds.insert(0, {
    'type': 'tun',
    'tag': 'tun-in',
    'address': ['172.19.0.1/30'],
    'auto_route': true,
    'strict_route': true,
  });

  // Bagian opsional hanya ditulis bila dipakai, sehingga config Custom tanpa
  // rule-set remote berbentuk sama dengan Minimal (tanpa `rules: []`,
  // `rule_set: []`, maupun http_clients yang tidak diperlukan).
  final needsHttpClient = ruleSets.isNotEmpty;

  final data = <String, dynamic>{
    'log': {'level': 'info', 'timestamp': true},
    'dns': {
      'servers': dnsServers,
      if (dnsRules.isNotEmpty) 'rules': dnsRules,
      'final': 'dns-remote',
      'strategy': opts.dnsStrategy,
    },
    'inbounds': inbounds,
    'outbounds': outbounds,
    'route': {
      'rules': routeRules,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
      'final': mainGroupName,
      'auto_detect_interface': true,
      'default_domain_resolver': 'dns-local',
      if (needsHttpClient) 'default_http_client': 'default-http',
    },
    'experimental': {
      'cache_file': {'enabled': true},
      'clash_api': {'external_controller': '127.0.0.1:9090', 'default_mode': 'Rule'},
    },
    if (needsHttpClient)
      'http_clients': [
        {'tag': 'default-http', 'detour': mainGroupName}
      ],
  };

  return const JsonEncoder.withIndent('  ').convert(data);
}


