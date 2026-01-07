/// Link Preview Service
///
/// Safe link preview scanning:
/// - URL expansion (short URLs)
/// - Destination analysis
/// - Redirect chain tracking
/// - Preview content extraction
/// - Threat detection before clicking

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Link preview status
enum PreviewStatus {
  safe('Safe', 'No threats detected'),
  suspicious('Suspicious', 'Potential risks found'),
  dangerous('Dangerous', 'Known threat'),
  unknown('Unknown', 'Could not analyze'),
  error('Error', 'Analysis failed');

  final String displayName;
  final String description;

  const PreviewStatus(this.displayName, this.description);
}

/// Redirect entry in chain
class RedirectEntry {
  final String url;
  final int statusCode;
  final Map<String, String> headers;
  final Duration responseTime;

  RedirectEntry({
    required this.url,
    required this.statusCode,
    this.headers = const {},
    required this.responseTime,
  });

  bool get isRedirect => statusCode >= 300 && statusCode < 400;
}

/// Link preview result
class LinkPreview {
  final String originalUrl;
  final String finalUrl;
  final PreviewStatus status;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final List<RedirectEntry> redirectChain;
  final List<String> threats;
  final Map<String, dynamic> analysis;
  final DateTime scannedAt;

  LinkPreview({
    required this.originalUrl,
    required this.finalUrl,
    required this.status,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    this.redirectChain = const [],
    this.threats = const [],
    this.analysis = const {},
    required this.scannedAt,
  });

  int get redirectCount => redirectChain.length;
  bool get hasRedirects => redirectChain.isNotEmpty;
  bool get isSafe => status == PreviewStatus.safe;

  Map<String, dynamic> toJson() => {
    'original_url': originalUrl,
    'final_url': finalUrl,
    'status': status.name,
    'title': title,
    'description': description,
    'image_url': imageUrl,
    'site_name': siteName,
    'favicon_url': faviconUrl,
    'redirect_count': redirectCount,
    'threats': threats,
    'analysis': analysis,
    'scanned_at': scannedAt.toIso8601String(),
  };
}

/// Link Preview Service
class LinkPreviewService {
  final http.Client _httpClient;
  final Duration _timeout;
  final int _maxRedirects;

  // URL shortener services
  static const _urlShorteners = [
    'bit.ly', 'tinyurl.com', 'goo.gl', 't.co', 'ow.ly',
    'is.gd', 'buff.ly', 'adf.ly', 'bit.do', 'mcaf.ee',
    'su.pr', 'tiny.cc', 'lnkd.in', 'db.tt', 'qr.ae',
    'cur.lv', 'ity.im', 'q.gs', 'po.st', 'bc.vc',
    'twitthis.com', 'u.telegramm.ml', 'rb.gy', 'cutt.ly',
    'shorturl.at', 'v.gd', 'bl.ink', 'short.io', 'rebrand.ly',
  ];

  // Suspicious redirect patterns
  static const _suspiciousRedirectPatterns = [
    r'redirect',
    r'goto',
    r'url=',
    r'link=',
    r'dest=',
    r'redir',
    r'click',
    r'out\.',
    r'away\.',
  ];

  // Known phishing TLDs
  static const _suspiciousTlds = [
    '.tk', '.ml', '.ga', '.cf', '.gq',
    '.xyz', '.top', '.work', '.click',
    '.link', '.info', '.biz', '.online',
  ];

  LinkPreviewService({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
    int maxRedirects = 10,
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout,
        _maxRedirects = maxRedirects;

  /// Get link preview with full analysis
  Future<LinkPreview> getPreview(String url) async {
    final threats = <String>[];
    final analysis = <String, dynamic>{};
    final redirectChain = <RedirectEntry>[];

    try {
      // Normalize URL
      var normalizedUrl = _normalizeUrl(url);
      analysis['original_url'] = normalizedUrl;

      // Check if it's a known URL shortener
      final isShortUrl = _isShortUrl(normalizedUrl);
      analysis['is_short_url'] = isShortUrl;

      // Expand URL and follow redirects
      final expandResult = await _expandUrl(normalizedUrl);
      final finalUrl = expandResult['final_url'] as String;
      redirectChain.addAll(expandResult['chain'] as List<RedirectEntry>);

      analysis['final_url'] = finalUrl;
      analysis['redirect_count'] = redirectChain.length;

      // Analyze redirect chain for suspicious patterns
      if (redirectChain.length > 3) {
        threats.add('Excessive redirects (${redirectChain.length})');
      }

      for (final redirect in redirectChain) {
        for (final pattern in _suspiciousRedirectPatterns) {
          if (RegExp(pattern, caseSensitive: false).hasMatch(redirect.url)) {
            threats.add('Suspicious redirect pattern in chain');
            break;
          }
        }
      }

      // Analyze final URL
      final urlAnalysis = _analyzeUrl(finalUrl);
      analysis.addAll(urlAnalysis);

      if (urlAnalysis['is_ip_address'] == true) {
        threats.add('IP address instead of domain');
      }

      if (urlAnalysis['has_suspicious_tld'] == true) {
        threats.add('Suspicious TLD');
      }

      if (urlAnalysis['has_excessive_subdomains'] == true) {
        threats.add('Excessive subdomains');
      }

      if (urlAnalysis['looks_like_typosquat'] == true) {
        threats.add('Possible typosquatting');
      }

      // Fetch page metadata
      String? title;
      String? description;
      String? imageUrl;
      String? siteName;
      String? faviconUrl;

      try {
        final metadata = await _fetchMetadata(finalUrl);
        title = metadata['title'];
        description = metadata['description'];
        imageUrl = metadata['image'];
        siteName = metadata['site_name'];
        faviconUrl = metadata['favicon'];
      } catch (e) {
        analysis['metadata_error'] = e.toString();
      }

      // Determine status
      PreviewStatus status;
      if (threats.isEmpty) {
        status = PreviewStatus.safe;
      } else if (threats.length >= 3 ||
          threats.any((t) => t.contains('IP address') || t.contains('typosquat'))) {
        status = PreviewStatus.dangerous;
      } else {
        status = PreviewStatus.suspicious;
      }

      return LinkPreview(
        originalUrl: url,
        finalUrl: finalUrl,
        status: status,
        title: title,
        description: description,
        imageUrl: imageUrl,
        siteName: siteName,
        faviconUrl: faviconUrl,
        redirectChain: redirectChain,
        threats: threats,
        analysis: analysis,
        scannedAt: DateTime.now(),
      );

    } catch (e) {
      return LinkPreview(
        originalUrl: url,
        finalUrl: url,
        status: PreviewStatus.error,
        threats: ['Analysis failed: $e'],
        analysis: {'error': e.toString()},
        scannedAt: DateTime.now(),
      );
    }
  }

  /// Check if URL is a known shortener
  bool _isShortUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    return _urlShorteners.any((s) => host == s || host.endsWith('.$s'));
  }

  /// Normalize URL
  String _normalizeUrl(String url) {
    var normalized = url.trim();

    // Add scheme if missing
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }

    return normalized;
  }

  /// Expand URL and follow redirects
  Future<Map<String, dynamic>> _expandUrl(String url) async {
    final chain = <RedirectEntry>[];
    var currentUrl = url;
    var redirectCount = 0;

    while (redirectCount < _maxRedirects) {
      final stopwatch = Stopwatch()..start();

      try {
        final request = http.Request('HEAD', Uri.parse(currentUrl));
        request.followRedirects = false;

        final streamedResponse = await _httpClient.send(request).timeout(_timeout);
        stopwatch.stop();

        final headers = <String, String>{};
        streamedResponse.headers.forEach((key, value) {
          headers[key.toLowerCase()] = value;
        });

        chain.add(RedirectEntry(
          url: currentUrl,
          statusCode: streamedResponse.statusCode,
          headers: headers,
          responseTime: stopwatch.elapsed,
        ));

        // Check for redirect
        if (streamedResponse.statusCode >= 300 && streamedResponse.statusCode < 400) {
          final location = headers['location'];
          if (location != null && location.isNotEmpty) {
            // Handle relative redirects
            if (location.startsWith('/')) {
              final uri = Uri.parse(currentUrl);
              currentUrl = '${uri.scheme}://${uri.host}$location';
            } else {
              currentUrl = location;
            }
            redirectCount++;
            continue;
          }
        }

        // No more redirects
        break;

      } catch (e) {
        // Request failed
        chain.add(RedirectEntry(
          url: currentUrl,
          statusCode: 0,
          responseTime: stopwatch.elapsed,
        ));
        break;
      }
    }

    return {
      'final_url': currentUrl,
      'chain': chain,
    };
  }

  /// Analyze URL for suspicious patterns
  Map<String, dynamic> _analyzeUrl(String url) {
    final analysis = <String, dynamic>{};
    final uri = Uri.tryParse(url);

    if (uri == null) {
      analysis['valid_url'] = false;
      return analysis;
    }

    analysis['valid_url'] = true;
    analysis['scheme'] = uri.scheme;
    analysis['host'] = uri.host;
    analysis['path'] = uri.path;

    // Check for IP address
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    analysis['is_ip_address'] = ipPattern.hasMatch(uri.host);

    // Check TLD
    final hostParts = uri.host.split('.');
    if (hostParts.length >= 2) {
      final tld = '.${hostParts.last}';
      analysis['tld'] = tld;
      analysis['has_suspicious_tld'] = _suspiciousTlds.contains(tld.toLowerCase());
    }

    // Check subdomain count
    analysis['subdomain_count'] = hostParts.length - 2;
    analysis['has_excessive_subdomains'] = hostParts.length > 4;

    // Check for typosquatting
    analysis['looks_like_typosquat'] = _checkTyposquat(uri.host);

    // Check path length
    analysis['path_length'] = uri.path.length;
    analysis['has_long_path'] = uri.path.length > 200;

    // Check for suspicious path patterns
    final suspiciousPathPatterns = [
      r'\.exe$', r'\.zip$', r'\.apk$',
      r'login', r'signin', r'account', r'verify',
      r'secure', r'update', r'confirm',
    ];
    for (final pattern in suspiciousPathPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(uri.path)) {
        analysis['suspicious_path_pattern'] = pattern;
        break;
      }
    }

    // Check for data URI
    analysis['is_data_uri'] = uri.scheme == 'data';

    // Check for javascript URI
    analysis['is_javascript_uri'] = uri.scheme == 'javascript';

    return analysis;
  }

  /// Check for typosquatting
  bool _checkTyposquat(String host) {
    final typosquatPatterns = {
      r'g[o0]{2}gle': 'google',
      r'faceb[o0]{2}k': 'facebook',
      r'amaz[o0]n': 'amazon',
      r'micros[o0]ft': 'microsoft',
      r'app[l1]e': 'apple',
      r'netf[l1]ix': 'netflix',
      r'paypa[l1]': 'paypal',
      r'inst[a@]gram': 'instagram',
      r'twitt[e3]r': 'twitter',
      r'link[e3]din': 'linkedin',
    };

    final hostLower = host.toLowerCase();

    for (final entry in typosquatPatterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(hostLower)) {
        // Make sure it's not the actual domain
        if (!hostLower.contains(entry.value)) {
          return true;
        }
      }
    }

    // Check for common character substitutions
    final substitutions = {
      'o': '0',
      'l': '1',
      'i': '1',
      'e': '3',
      'a': '@',
      's': '5',
    };

    var suspiciousSubstitutions = 0;
    for (final entry in substitutions.entries) {
      if (hostLower.contains(entry.value)) {
        suspiciousSubstitutions++;
      }
    }

    return suspiciousSubstitutions >= 2;
  }

  /// Fetch page metadata
  Future<Map<String, String?>> _fetchMetadata(String url) async {
    try {
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'OrbGuard LinkPreview/1.0',
          'Accept': 'text/html',
        },
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        return {};
      }

      final body = response.body;
      final metadata = <String, String?>{};

      // Extract title
      final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
          .firstMatch(body);
      metadata['title'] = titleMatch?.group(1)?.trim();

      // Extract Open Graph tags
      final ogPatterns = {
        'description': r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)["\']',
        'image': r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']',
        'site_name': r'<meta[^>]+property=["\']og:site_name["\'][^>]+content=["\']([^"\']+)["\']',
      };

      for (final entry in ogPatterns.entries) {
        final match = RegExp(entry.value, caseSensitive: false).firstMatch(body);
        metadata[entry.key] ??= match?.group(1);
      }

      // Fallback to meta description
      if (metadata['description'] == null) {
        final descMatch = RegExp(
          r'<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)["\']',
          caseSensitive: false,
        ).firstMatch(body);
        metadata['description'] = descMatch?.group(1);
      }

      // Extract favicon
      final faviconMatch = RegExp(
        r'<link[^>]+rel=["\'](?:shortcut )?icon["\'][^>]+href=["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(body);
      if (faviconMatch != null) {
        var favicon = faviconMatch.group(1)!;
        if (favicon.startsWith('/')) {
          final uri = Uri.parse(url);
          favicon = '${uri.scheme}://${uri.host}$favicon';
        }
        metadata['favicon'] = favicon;
      } else {
        // Default favicon location
        final uri = Uri.parse(url);
        metadata['favicon'] = '${uri.scheme}://${uri.host}/favicon.ico';
      }

      return metadata;

    } catch (e) {
      return {};
    }
  }

  /// Quick check if URL is likely safe (without full expansion)
  Future<bool> quickCheck(String url) async {
    final normalized = _normalizeUrl(url);
    final uri = Uri.tryParse(normalized);

    if (uri == null) return false;

    // Check obvious bad patterns
    if (uri.scheme == 'javascript' || uri.scheme == 'data') {
      return false;
    }

    final analysis = _analyzeUrl(normalized);

    if (analysis['is_ip_address'] == true) return false;
    if (analysis['has_suspicious_tld'] == true) return false;
    if (analysis['looks_like_typosquat'] == true) return false;
    if (analysis['has_excessive_subdomains'] == true) return false;

    return true;
  }

  /// Batch preview multiple URLs
  Future<List<LinkPreview>> batchPreview(List<String> urls) async {
    final futures = urls.map((url) => getPreview(url));
    return await Future.wait(futures);
  }

  /// Dispose resources
  void dispose() {
    _httpClient.close();
  }
}
