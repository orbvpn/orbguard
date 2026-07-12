/// URL Reputation Models
/// Models for URL/web protection from OrbGuard Lab API

import 'threat_indicator.dart';

/// URL categories
enum UrlCategory {
  safe('safe'),
  phishing('phishing'),
  malware('malware'),
  scam('scam'),
  spam('spam'),
  adult('adult'),
  gambling('gambling'),
  drugs('drugs'),
  violence('violence'),
  ads('ads'),
  tracking('tracking'),
  cryptomining('cryptomining'),
  parked('parked'),
  suspiciousTld('suspicious_tld'),
  typosquatting('typosquatting'),
  unknown('unknown');

  final String value;
  const UrlCategory(this.value);

  static UrlCategory fromString(String value) {
    return UrlCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UrlCategory.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case UrlCategory.safe:
        return 'Safe';
      case UrlCategory.phishing:
        return 'Phishing';
      case UrlCategory.malware:
        return 'Malware';
      case UrlCategory.scam:
        return 'Scam';
      case UrlCategory.spam:
        return 'Spam';
      case UrlCategory.adult:
        return 'Adult Content';
      case UrlCategory.gambling:
        return 'Gambling';
      case UrlCategory.drugs:
        return 'Drugs';
      case UrlCategory.violence:
        return 'Violence';
      case UrlCategory.ads:
        return 'Advertising';
      case UrlCategory.tracking:
        return 'Tracking';
      case UrlCategory.cryptomining:
        return 'Cryptomining';
      case UrlCategory.parked:
        return 'Parked Domain';
      case UrlCategory.suspiciousTld:
        return 'Suspicious TLD';
      case UrlCategory.typosquatting:
        return 'Typosquatting';
      case UrlCategory.unknown:
        return 'Unknown';
    }
  }

  bool get isDangerous =>
      this == UrlCategory.phishing ||
      this == UrlCategory.malware ||
      this == UrlCategory.scam;
}

/// URL reputation result
class UrlReputationResult {
  final String url;
  final String domain;
  final bool isSafe;
  final bool shouldBlock;
  final SeverityLevel severity;
  final double riskScore;
  final List<UrlCategory> categories;
  final List<UrlThreat> threats;
  final String? recommendation;
  final DateTime checkedAt;

  UrlReputationResult({
    required this.url,
    required this.domain,
    required this.isSafe,
    required this.shouldBlock,
    required this.severity,
    required this.riskScore,
    required this.categories,
    required this.threats,
    this.recommendation,
    required this.checkedAt,
  });

  factory UrlReputationResult.fromJson(Map<String, dynamic> json) {
    return UrlReputationResult(
      url: json['url'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      isSafe: json['is_safe'] as bool? ?? true,
      shouldBlock: json['should_block'] as bool? ?? false,
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'info'),
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => UrlCategory.fromString(c as String))
              .toList() ??
          [],
      threats: (json['threats'] as List<dynamic>?)
              ?.map((t) => UrlThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      recommendation: json['recommendation'] as String?,
      checkedAt: DateTime.parse(
          json['checked_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  /// Get the primary category
  UrlCategory? get primaryCategory =>
      categories.isNotEmpty ? categories.first : null;

  /// Check if URL has dangerous categories
  bool get hasDangerousCategories =>
      categories.any((c) => c.isDangerous);
}

/// URL threat info
class UrlThreat {
  final String type;
  final SeverityLevel severity;
  final String description;
  final String? source;
  final DateTime? firstSeen;

  UrlThreat({
    required this.type,
    required this.severity,
    required this.description,
    this.source,
    this.firstSeen,
  });

  factory UrlThreat.fromJson(Map<String, dynamic> json) {
    return UrlThreat(
      type: json['type'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      description: json['description'] as String? ?? '',
      source: json['source'] as String?,
      firstSeen: json['first_seen'] != null
          ? DateTime.parse(json['first_seen'] as String)
          : null,
    );
  }
}

/// Detailed domain reputation
class DomainReputation {
  final String domain;
  final bool isRegistered;
  final DateTime? createdDate;
  final DateTime? updatedDate;
  final DateTime? expiresDate;
  final int ageInDays;
  final String? registrar;
  final String? registrantCountry;
  final List<String>? nameservers;
  final List<String>? ipAddresses;
  final String? asn;
  final String? asnOrg;
  final double reputationScore;
  final List<UrlCategory> categories;
  final bool isOnBlocklist;
  final List<String>? blocklistSources;
  final WhoisInfo? whois;
  final SslInfo? ssl;
  final DnsInfo? dns;

  DomainReputation({
    required this.domain,
    required this.isRegistered,
    this.createdDate,
    this.updatedDate,
    this.expiresDate,
    required this.ageInDays,
    this.registrar,
    this.registrantCountry,
    this.nameservers,
    this.ipAddresses,
    this.asn,
    this.asnOrg,
    required this.reputationScore,
    required this.categories,
    required this.isOnBlocklist,
    this.blocklistSources,
    this.whois,
    this.ssl,
    this.dns,
  });

  factory DomainReputation.fromJson(Map<String, dynamic> json) {
    return DomainReputation(
      domain: json['domain'] as String? ?? '',
      isRegistered: json['is_registered'] as bool? ?? true,
      createdDate: json['created_date'] != null
          ? DateTime.parse(json['created_date'] as String)
          : null,
      updatedDate: json['updated_date'] != null
          ? DateTime.parse(json['updated_date'] as String)
          : null,
      expiresDate: json['expires_date'] != null
          ? DateTime.parse(json['expires_date'] as String)
          : null,
      ageInDays: json['age_in_days'] as int? ?? 0,
      registrar: json['registrar'] as String?,
      registrantCountry: json['registrant_country'] as String?,
      nameservers: (json['nameservers'] as List<dynamic>?)?.cast<String>(),
      ipAddresses: (json['ip_addresses'] as List<dynamic>?)?.cast<String>(),
      asn: json['asn'] as String?,
      asnOrg: json['asn_org'] as String?,
      reputationScore: (json['reputation_score'] as num?)?.toDouble() ?? 0.0,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => UrlCategory.fromString(c as String))
              .toList() ??
          [],
      isOnBlocklist: json['is_on_blocklist'] as bool? ?? false,
      blocklistSources:
          (json['blocklist_sources'] as List<dynamic>?)?.cast<String>(),
      whois: json['whois'] != null
          ? WhoisInfo.fromJson(json['whois'] as Map<String, dynamic>)
          : null,
      ssl: json['ssl'] != null
          ? SslInfo.fromJson(json['ssl'] as Map<String, dynamic>)
          : null,
      dns: json['dns'] != null
          ? DnsInfo.fromJson(json['dns'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Check if domain is newly registered (< 30 days)
  bool get isNewlyRegistered => ageInDays < 30;

  /// Check if domain is suspicious based on various factors
  bool get isSuspicious =>
      isNewlyRegistered || isOnBlocklist || reputationScore < 30;
}

/// WHOIS information
class WhoisInfo {
  final String? registrar;
  final String? registrantName;
  final String? registrantOrg;
  final String? registrantCountry;
  final String? registrantEmail;
  final bool isPrivate;

  WhoisInfo({
    this.registrar,
    this.registrantName,
    this.registrantOrg,
    this.registrantCountry,
    this.registrantEmail,
    required this.isPrivate,
  });

  factory WhoisInfo.fromJson(Map<String, dynamic> json) {
    return WhoisInfo(
      registrar: json['registrar'] as String?,
      registrantName: json['registrant_name'] as String?,
      registrantOrg: json['registrant_org'] as String?,
      registrantCountry: json['registrant_country'] as String?,
      registrantEmail: json['registrant_email'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
    );
  }
}

/// SSL certificate information
class SslInfo {
  final bool hasValidSsl;
  final String? issuer;
  final String? subject;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool isExpired;
  final bool isSelfSigned;
  final List<String>? sanDomains;
  final String? grade;

  SslInfo({
    required this.hasValidSsl,
    this.issuer,
    this.subject,
    this.validFrom,
    this.validTo,
    required this.isExpired,
    required this.isSelfSigned,
    this.sanDomains,
    this.grade,
  });

  factory SslInfo.fromJson(Map<String, dynamic> json) {
    return SslInfo(
      hasValidSsl: json['has_valid_ssl'] as bool? ?? false,
      issuer: json['issuer'] as String?,
      subject: json['subject'] as String?,
      validFrom: json['valid_from'] != null
          ? DateTime.parse(json['valid_from'] as String)
          : null,
      validTo: json['valid_to'] != null
          ? DateTime.parse(json['valid_to'] as String)
          : null,
      isExpired: json['is_expired'] as bool? ?? false,
      isSelfSigned: json['is_self_signed'] as bool? ?? false,
      sanDomains: (json['san_domains'] as List<dynamic>?)?.cast<String>(),
      grade: json['grade'] as String?,
    );
  }
}

/// DNS information
class DnsInfo {
  final List<String>? aRecords;
  final List<String>? aaaaRecords;
  final List<String>? mxRecords;
  final List<String>? txtRecords;
  final List<String>? nsRecords;
  final bool hasDmarc;
  final bool hasSpf;
  final bool hasDkim;

  DnsInfo({
    this.aRecords,
    this.aaaaRecords,
    this.mxRecords,
    this.txtRecords,
    this.nsRecords,
    required this.hasDmarc,
    required this.hasSpf,
    required this.hasDkim,
  });

  factory DnsInfo.fromJson(Map<String, dynamic> json) {
    return DnsInfo(
      aRecords: (json['a_records'] as List<dynamic>?)?.cast<String>(),
      aaaaRecords: (json['aaaa_records'] as List<dynamic>?)?.cast<String>(),
      mxRecords: (json['mx_records'] as List<dynamic>?)?.cast<String>(),
      txtRecords: (json['txt_records'] as List<dynamic>?)?.cast<String>(),
      nsRecords: (json['ns_records'] as List<dynamic>?)?.cast<String>(),
      hasDmarc: json['has_dmarc'] as bool? ?? false,
      hasSpf: json['has_spf'] as bool? ?? false,
      hasDkim: json['has_dkim'] as bool? ?? false,
    );
  }
}

/// App analysis request
class AppAnalysisRequest {
  final String packageName;
  final String? appName;
  final String? version;
  final List<String> permissions;
  final String installSource;
  final String? signature;

  AppAnalysisRequest({
    required this.packageName,
    this.appName,
    this.version,
    required this.permissions,
    required this.installSource,
    this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      'package_name': packageName,
      if (appName != null) 'app_name': appName,
      if (version != null) 'version': version,
      'permissions': permissions,
      'install_source': installSource,
      if (signature != null) 'signature': signature,
    };
  }
}

/// App analysis result
class AppAnalysisResult {
  final String packageName;
  final String? appName;
  final double riskScore;
  final String riskLevel;
  final List<PermissionRisk> permissionRisks;
  final List<TrackerInfo> detectedTrackers;
  final bool isSideloaded;
  final bool isKnownMalware;
  final String privacyGrade;
  final List<String> warnings;
  final String? recommendation;

  AppAnalysisResult({
    required this.packageName,
    this.appName,
    required this.riskScore,
    required this.riskLevel,
    required this.permissionRisks,
    required this.detectedTrackers,
    required this.isSideloaded,
    required this.isKnownMalware,
    required this.privacyGrade,
    required this.warnings,
    this.recommendation,
  });

  factory AppAnalysisResult.fromJson(Map<String, dynamic> json) {
    return AppAnalysisResult(
      packageName: json['package_name'] as String? ?? '',
      appName: json['app_name'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      riskLevel: json['risk_level'] as String? ?? 'unknown',
      permissionRisks: (json['permission_risks'] as List<dynamic>?)
              ?.map((p) => PermissionRisk.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      detectedTrackers: (json['detected_trackers'] as List<dynamic>?)
              ?.map((t) => TrackerInfo.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      isSideloaded: json['is_sideloaded'] as bool? ?? false,
      isKnownMalware: json['is_known_malware'] as bool? ?? false,
      privacyGrade: json['privacy_grade'] as String? ?? 'U',
      warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendation: json['recommendation'] as String?,
    );
  }
}

/// Permission risk info
class PermissionRisk {
  final String permission;
  final String riskLevel;
  final String description;
  final bool isDangerous;

  PermissionRisk({
    required this.permission,
    required this.riskLevel,
    required this.description,
    required this.isDangerous,
  });

  factory PermissionRisk.fromJson(Map<String, dynamic> json) {
    return PermissionRisk(
      permission: json['permission'] as String? ?? '',
      riskLevel: json['risk_level'] as String? ?? 'low',
      description: json['description'] as String? ?? '',
      isDangerous: json['is_dangerous'] as bool? ?? false,
    );
  }
}

/// Tracker info
class TrackerInfo {
  final String id;
  final String name;
  final String? company;
  final String category;
  final String? website;
  final String? description;
  final List<String>? domains;

  TrackerInfo({
    required this.id,
    required this.name,
    this.company,
    required this.category,
    this.website,
    this.description,
    this.domains,
  });

  factory TrackerInfo.fromJson(Map<String, dynamic> json) {
    return TrackerInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      company: json['company'] as String?,
      category: json['category'] as String? ?? 'unknown',
      website: json['website'] as String?,
      description: json['description'] as String?,
      domains: (json['domains'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Wi-Fi audit request
class WifiAuditRequest {
  final String ssid;
  final String? bssid;
  final String securityType;
  final int signalStrength;
  final String? ipAddress;
  final String? gateway;
  final List<String>? dnsServers;

  WifiAuditRequest({
    required this.ssid,
    this.bssid,
    required this.securityType,
    required this.signalStrength,
    this.ipAddress,
    this.gateway,
    this.dnsServers,
  });

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      if (bssid != null) 'bssid': bssid,
      'security_type': securityType,
      'signal_strength': signalStrength,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (gateway != null) 'gateway': gateway,
      if (dnsServers != null) 'dns_servers': dnsServers,
    };
  }
}

/// Wi-Fi audit result
class WifiAuditResult {
  final String ssid;
  final bool isSecure;
  final double securityScore;
  final String securityGrade;
  final List<WifiThreat> threats;
  final List<String> recommendations;
  final bool shouldUseVpn;

  WifiAuditResult({
    required this.ssid,
    required this.isSecure,
    required this.securityScore,
    required this.securityGrade,
    required this.threats,
    required this.recommendations,
    required this.shouldUseVpn,
  });

  factory WifiAuditResult.fromJson(Map<String, dynamic> json) {
    return WifiAuditResult(
      ssid: json['ssid'] as String? ?? '',
      isSecure: json['is_secure'] as bool? ?? false,
      securityScore: (json['security_score'] as num?)?.toDouble() ?? 0.0,
      securityGrade: json['security_grade'] as String? ?? 'U',
      threats: (json['threats'] as List<dynamic>?)
              ?.map((t) => WifiThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
      shouldUseVpn: json['should_use_vpn'] as bool? ?? false,
    );
  }
}

/// Wi-Fi threat
class WifiThreat {
  final String type;
  final SeverityLevel severity;
  final String description;

  WifiThreat({
    required this.type,
    required this.severity,
    required this.description,
  });

  factory WifiThreat.fromJson(Map<String, dynamic> json) {
    return WifiThreat(
      type: json['type'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      description: json['description'] as String? ?? '',
    );
  }
}

/// YARA scan request
class YaraScanRequest {
  final String data;
  final String? filename;
  final bool isBase64;

  YaraScanRequest({
    required this.data,
    this.filename,
    this.isBase64 = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      if (filename != null) 'filename': filename,
      'is_base64': isBase64,
    };
  }
}

/// YARA scan result
class YaraScanResult {
  final bool hasMatches;
  final int matchCount;
  final List<YaraMatch> matches;
  final double riskScore;
  final String? recommendation;

  YaraScanResult({
    required this.hasMatches,
    required this.matchCount,
    required this.matches,
    required this.riskScore,
    this.recommendation,
  });

  factory YaraScanResult.fromJson(Map<String, dynamic> json) {
    return YaraScanResult(
      hasMatches: json['has_matches'] as bool? ?? false,
      matchCount: json['match_count'] as int? ?? 0,
      matches: (json['matches'] as List<dynamic>?)
              ?.map((m) => YaraMatch.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      recommendation: json['recommendation'] as String?,
    );
  }
}

/// YARA match
class YaraMatch {
  final String ruleName;
  final String? ruleDescription;
  final String category;
  final SeverityLevel severity;
  final List<String>? tags;
  final List<String>? mitreTechniques;

  YaraMatch({
    required this.ruleName,
    this.ruleDescription,
    required this.category,
    required this.severity,
    this.tags,
    this.mitreTechniques,
  });

  factory YaraMatch.fromJson(Map<String, dynamic> json) {
    return YaraMatch(
      ruleName: json['rule_name'] as String? ?? '',
      ruleDescription: json['rule_description'] as String?,
      category: json['category'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
