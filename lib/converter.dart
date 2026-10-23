import 'dart:convert';

/// Parsed proxy node model.
class Node {
  String protocol; // vmess | vless | trojan
  String name;
  String server;
  int port;
  String uuid;
  String password;
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

  /// Kode region hasil deteksi dari nama node (SG, ID, HK, ...), atau '' jika tidak dikenali.
  String get region => detectRegion(name);

  Node({
    required this.protocol,
    this.name = '',
    this.server = '',
    this.port = 443,
    this.uuid = '',
    this.password = '',
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
  }) : alpn = alpn ?? [];

  Node copyWith({
    String? protocol,
    String? name,
    String? server,
    int? port,
    String? uuid,
    String? password,
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
  }) {
    return Node(
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
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
    );
  }
}

/// Mode wildcard / bug host yang diterapkan ke setiap node.
/// - [none]: tanpa modifikasi
/// - [biasa]: server=bug, SNI/Host = bug.original
/// - [sni]: hanya SNI diganti bug
/// - [serverHost]: server=bug, WS Host=bug
enum BugWildcardMode { none, biasa, sni, serverHost }

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
      case BugWildcardMode.none:
        return n.copyWith();
    }
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

/// Sing-box outbound entry (format outbound modern: type vmess/vless/trojan).
Map<String, dynamic> toSingboxOutbound(Node node) {
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
        lower == 'no';
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
    this.directDomesticBankingDns = true,
    this.enableAntiAds = true,
    this.enableAiRouting = true,
    this.enableStreamingRouting = true,
    this.enableGamingRouting = false,
    this.enableDomesticBypass = true,
    this.enableBlockTorrent = true,
    this.enableBlockQuic = false,
    this.customRules = const [],
    this.enableGeoipIdDirect = true,
    this.enablePrivateDirect = true,
    this.autoCreateRegionGroups = false,
    this.selectedRegions = const [],
    this.mainGroupName = 'PILIH-PROXY',
    this.autoFastest = true,
    this.urlTestInterval = 300,
    this.mixedPort = 7890,
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
    mainProxies.add('⚡ AUTO-TERCEPAT');
    proxyGroups.add({
      'name': '⚡ AUTO-TERCEPAT',
      'type': 'url-test',
      'include-all-proxies': true,
      'url': 'https://www.gstatic.com/generate_204',
      'interval': opts.urlTestInterval,
      'tolerance': 50,
    });
  }

  if (opts.enableAiRouting) {
    mainProxies.add('🤖 AI-CHATGPT');
    proxyGroups.add({
      'name': '🤖 AI-CHATGPT',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['⚡ AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.enableStreamingRouting) {
    mainProxies.add('🎬 STREAMING');
    proxyGroups.add({
      'name': '🎬 STREAMING',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['⚡ AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.enableGamingRouting) {
    mainProxies.add('🎮 GAME');
    proxyGroups.add({
      'name': '🎮 GAME',
      'type': 'select',
      'include-all-proxies': true,
      'proxies': opts.autoFastest ? ['⚡ AUTO-TERCEPAT', 'DIRECT'] : ['DIRECT'],
    });
  }

  if (opts.autoCreateRegionGroups) {
    for (final reg in opts.selectedRegions) {
      final regName = '🌏 REGION-$reg';
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
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads-all.mrs',
    };
  }
  if (opts.enableAiRouting) {
    ruleProviders['gs-ai'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-ai.mrs',
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/openai.mrs',
    };
  }
  if (opts.enableStreamingRouting) {
    ruleProviders['gs-streaming'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-streaming.mrs',
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/netflix.mrs',
    };
  }
  if (opts.enableGamingRouting) {
    ruleProviders['gs-games'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-games.mrs',
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-games.mrs',
    };
  }
  if (opts.enableGeoipIdDirect) {
    ruleProviders['gi-id'] = {
      'type': 'http',
      'behavior': 'ipcidr',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gi-id.mrs',
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/id.mrs',
    };
  }
  if (opts.enablePrivateDirect) {
    ruleProviders['gs-private'] = {
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'interval': 86400,
      'path': './ruleset/gs-private.mrs',
      'url': 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.mrs',
    };
  }

  final rules = <String>[];
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
  if (opts.enablePrivateDirect) {
    rules.add('RULE-SET,gs-private,DIRECT');
    rules.add('GEOIP,PRIVATE,DIRECT,no-resolve');
  }
  if (opts.enableGeoipIdDirect) {
    rules.add('RULE-SET,gi-id,DIRECT,no-resolve');
  }
  if (opts.enableAiRouting) rules.add('RULE-SET,gs-ai,🤖 AI-CHATGPT');
  if (opts.enableStreamingRouting) rules.add('RULE-SET,gs-streaming,🎬 STREAMING');
  if (opts.enableGamingRouting) rules.add('RULE-SET,gs-games,🎮 GAME');

  // Custom User Rules (map target logis ke nama grup Clash yang sebenarnya)
  for (final cr in opts.customRules) {
    if (cr.payload.isNotEmpty) {
      String target = cr.target;
      if (target == 'PILIH-PROXY') {
        target = mainGroupName;
      } else if (target == 'AI-CHATGPT') {
        target = '🤖 AI-CHATGPT';
      } else if (target == 'STREAMING') {
        target = '🎬 STREAMING';
      } else if (target == 'GAME') {
        target = '🎮 GAME';
      }
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
    'default-nameserver': ['1.1.1.1', '8.8.8.8'],
    'nameserver': nameserverList,
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
    'unified-delay': true,
    'tcp-concurrent': true,
    'tun': {
      'enable': opts.tunEnabled,
      'stack': 'mixed',
      'dns-hijack': ['any:53', 'tcp://any:53'],
      'auto-route': true,
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
      return customUrl.isNotEmpty ? customUrl : 'https://1.1.1.1/dns-query';
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

  final dohIp = _resolveDnsIp(opts.primaryDns, opts.customPrimaryUrl);
  final dohIpSecondary = _resolveDnsIp(opts.secondaryDns, opts.customSecondaryUrl);

  final mainGroupName = opts.mainGroupName.isNotEmpty ? opts.mainGroupName : 'PILIH-PROXY';

  // dns-bootstrap: UDP ke IP murni — dipakai route.default_domain_resolver
  // agar dial/DoH/rule-set tidak bergantung ke HTTP client default (deprecated 1.12+).
  final dnsServers = <Map<String, dynamic>>[
    {'type': 'udp', 'tag': 'dns-bootstrap', 'server': '1.1.1.1'},
    {'type': 'https', 'tag': 'dns-local', 'server': dohIp},
    {
      'type': 'https',
      'tag': 'dns-remote',
      'server': dohIp,
      'detour': mainGroupName,
    },
  ];
  if (dohIpSecondary != dohIp) {
    dnsServers.add({
      'type': 'https',
      'tag': 'dns-secondary',
      'server': dohIpSecondary,
    });
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
      'interval': '${(opts.urlTestInterval / 60).round()}m',
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
    final intervalStr = '${(opts.urlTestInterval / 60).round()}m';
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
  // type dns outbound dihapus di sing-box 1.13 — DNS lewat route action hijack-dns
  outbounds.add({'type': 'block', 'tag': 'REJECT'});

  final routeRules = <Map<String, dynamic>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
    {'clash_mode': 'Direct', 'outbound': 'DIRECT'},
    {'clash_mode': 'Global', 'outbound': mainGroupName},
  ];

  if (opts.enablePrivateDirect) {
    routeRules.add({'ip_is_private': true, 'outbound': 'DIRECT'});
  }

  if (opts.enableBlockTorrent) {
    routeRules.add({'port_range': ['6881:6889'], 'action': 'reject'});
  }
  if (opts.enableBlockQuic) {
    routeRules.add({'port': 443, 'network': 'udp', 'action': 'reject'});
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
  for (final cr in opts.customRules) {
    final target = cr.target == 'PILIH-PROXY' ? mainGroupName : cr.target;
    if (cr.type == 'DOMAIN-SUFFIX') {
      routeRules.add({'domain_suffix': [cr.payload], 'outbound': target});
    } else if (cr.type == 'DOMAIN-KEYWORD') {
      routeRules.add({'domain_keyword': [cr.payload], 'outbound': target});
    } else if (cr.type == 'IP-CIDR') {
      routeRules.add({'ip_cidr': [cr.payload], 'outbound': target});
    } else if (cr.type == 'GEOIP') {
      routeRules.add({'geoip': [cr.payload.toLowerCase()], 'outbound': target});
    }
  }

  // download_detour wajib (sing-box 1.14+): unduh rule-set lewat DIRECT, bukan default outbound.
  Map<String, dynamic> remoteRuleSet(String tag, String url) => {
        'tag': tag,
        'type': 'remote',
        'format': 'binary',
        'url': url,
        'download_detour': 'DIRECT',
        'update_interval': '1d',
      };

  final ruleSets = <Map<String, dynamic>>[];
  if (opts.enableAntiAds) {
    ruleSets.add(remoteRuleSet(
      'geosite-category-ads-all',
      'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs',
    ));
  }
  if (opts.enableDomesticBypass && opts.enableGeoipIdDirect) {
    ruleSets.add(remoteRuleSet(
      'geoip-id',
      'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/id.srs',
    ));
  }
  if (opts.enableAiRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-openai',
      'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs',
    ));
  }
  if (opts.enableStreamingRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-streaming',
      'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/netflix.srs',
    ));
  }
  if (opts.enableGamingRouting) {
    ruleSets.add(remoteRuleSet(
      'geosite-game',
      'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-games.srs',
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
  if (opts.tunEnabled) {
    inbounds.insert(0, {
      'type': 'tun',
      'tag': 'tun-in',
      'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
      'auto_route': true,
      'strict_route': true,
    });
  }

  final data = {
    'log': {'level': 'info', 'timestamp': true},
    'dns': {
      'servers': dnsServers,
      'rules': dnsRules,
      'final': 'dns-remote',
      'strategy': opts.dnsStrategy,
    },
    'inbounds': inbounds,
    'outbounds': outbounds,
    'route': {
      'rules': routeRules,
      'rule_set': ruleSets,
      'final': mainGroupName,
      'auto_detect_interface': true,
      'override_android_vpn': opts.tunEnabled,
      // Wajib sejak sing-box 1.12 (dihapus implisit di 1.14+)
      'default_domain_resolver': 'dns-bootstrap',
    },
    'experimental': {
      'cache_file': {'enabled': true},
      'clash_api': {'external_controller': '127.0.0.1:9090', 'default_mode': 'Rule'},
    },
  };

  return const JsonEncoder.withIndent('  ').convert(data);
}


