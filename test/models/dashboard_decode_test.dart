/// Golden decode tests for GET /api/v1/stats/dashboard.
///
/// Fixtures mirror the exact JSON emitted by the live backend handler
/// (orbguard.lab/internal/api/handlers/alerts.go, GetDashboard):
/// - `recent_alerts` items are `alertItem` structs
///   {id, title, description, severity, category, source, is_read,
///    created_at, read_at?, metadata?}
/// - `protection` is models.ProtectionStatus
///   {is_active, score, grade, features:{sms|web|app|network|vpn:
///    {enabled, status}}, last_scan}
/// - `activity` and `device_health` are handler-built maps (see GetDashboard)
/// - sections are OMITTED (never fabricated) when their data source is
///   unavailable: protection/activity/device_health need device identity,
///   threats needs the indicators DB.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/models/api/threat_indicator.dart';
import 'package:orbguard/models/api/threat_stats.dart';

/// Full payload for a device-authenticated request with every section
/// present. Values follow the backend's computation rules:
/// - protection score = enabled modules / 6 * 100 (4 of 6 -> 66.67, grade C)
/// - device_health score = passed checks / 4 * 100 (3 of 4 -> 75, grade B)
const _fullDashboardJson = '''
{
  "generated_at": "2026-06-10T12:00:00Z",
  "recent_alerts": [
    {
      "id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
      "title": "Phishing SMS blocked",
      "description": "A smishing message impersonating your bank was detected",
      "severity": "high",
      "category": "sms",
      "source": "sms_analysis",
      "is_read": false,
      "created_at": "2026-06-10T11:45:00Z",
      "metadata": {"action_url": "/sms/history"}
    },
    {
      "id": "1c0a5c4e-88f1-4a3e-9c5e-2f0d7b3dcb6e",
      "title": "New breach detected",
      "description": "Your email appeared in a new data breach",
      "severity": "critical",
      "category": "darkweb",
      "source": "darkweb_monitor",
      "is_read": true,
      "created_at": "2026-06-09T08:30:00Z",
      "read_at": "2026-06-09T09:00:00Z"
    }
  ],
  "unread_alerts": 1,
  "total_alerts": 2,
  "threats": {
    "total_indicators": 12500,
    "by_type": {"domain": 8000, "url": 3000, "ip": 1500},
    "by_severity": {"critical": 120, "high": 480, "medium": 6900, "low": 5000},
    "high_severity": 600,
    "new_today": 42,
    "new_week": 310,
    "new_month": 1200,
    "pegasus_indicators": 85,
    "mobile_indicators": 4300,
    "active_campaigns": 7,
    "campaigns_targeting_device": 3
  },
  "protection": {
    "is_active": true,
    "score": 66.66666666666666,
    "grade": "C",
    "features": {
      "sms": {"enabled": true, "status": "protected"},
      "web": {"enabled": true, "status": "protected"},
      "app": {"enabled": false, "status": "disabled"},
      "network": {"enabled": true, "status": "protected"},
      "vpn": {"enabled": true, "status": "protected"}
    },
    "last_scan": "2026-06-10T11:59:00Z"
  },
  "activity": {
    "threats_detected_today": 2,
    "threats_detected_week": 9,
    "threats_detected_month": 31,
    "threats_detected_total": 57,
    "messages_analyzed_total": 1043,
    "trend": [
      {"date": "2026-06-09", "analyzed": 40, "count": 3},
      {"date": "2026-06-10", "analyzed": 12, "count": 2}
    ]
  },
  "device_health": {
    "score": 75.0,
    "grade": "B",
    "is_rooted": false,
    "is_encrypted": true,
    "has_screen_lock": true,
    "security_patch": "2025-09-01",
    "has_latest_security_patch": false,
    "platform": "android",
    "os_version": "15",
    "model": "Pixel 9",
    "issues": ["Security patch level is outdated or unknown"],
    "recommendations": ["Install the latest system security updates"]
  }
}
''';

/// Payload for an unauthenticated request: the backend emits ONLY the
/// alert counters, generated_at, and the global threats section. There is
/// no protection/activity/device_health and no placeholder values.
const _anonymousDashboardJson = '''
{
  "generated_at": "2026-06-10T12:00:00Z",
  "recent_alerts": [],
  "unread_alerts": 0,
  "total_alerts": 0,
  "threats": {
    "total_indicators": 12500,
    "by_type": {"domain": 8000},
    "by_severity": {"critical": 120, "high": 480},
    "high_severity": 600,
    "new_today": 42,
    "new_week": 310,
    "new_month": 1200,
    "pegasus_indicators": 85,
    "mobile_indicators": 4300,
    "active_campaigns": 7
  }
}
''';

/// Degenerate payload when even the indicators DB is unreachable: only the
/// alerts block and timestamp remain.
const _minimalDashboardJson = '''
{
  "generated_at": "2026-06-10T12:00:00Z",
  "recent_alerts": [],
  "unread_alerts": 0,
  "total_alerts": 0
}
''';

Map<String, dynamic> _decode(String fixture) =>
    jsonDecode(fixture) as Map<String, dynamic>;

void main() {
  group('DashboardSummary.fromJson — full device-authenticated payload', () {
    late DashboardSummary summary;

    setUp(() {
      summary = DashboardSummary.fromJson(_decode(_fullDashboardJson));
    });

    test('parses top-level alert counters and timestamp', () {
      expect(summary.unreadAlerts, 1);
      expect(summary.totalAlerts, 2);
      expect(summary.generatedAt, DateTime.utc(2026, 6, 10, 12));
    });

    test('parses the protection section as available', () {
      expect(summary.protection.available, isTrue);
      expect(summary.protection.isProtected, isTrue);
      expect(summary.protection.protectionScore, closeTo(66.67, 0.01));
      expect(summary.protection.protectionGrade, 'C');
    });

    test('maps nested feature objects {enabled, status}', () {
      expect(summary.protection.smsProtection.isEnabled, isTrue);
      expect(summary.protection.smsProtection.status, 'protected');
      expect(summary.protection.appProtection.isEnabled, isFalse);
      expect(summary.protection.appProtection.status, 'disabled');
      expect(summary.protection.enabledFeatureCount, 4);
    });

    test('parses the global threats section', () {
      expect(summary.threats.available, isTrue);
      expect(summary.threats.totalIndicators, 12500);
      expect(summary.threats.byType['domain'], 8000);
      expect(summary.threats.bySeverity['critical'], 120);
      expect(summary.threats.highSeverityThreats, 600);
      expect(summary.threats.newIndicatorsToday, 42);
      expect(summary.threats.pegasusIndicators, 85);
      expect(summary.threats.activeCampaigns, 7);
      expect(summary.threats.campaignsTargetingDevice, 3);
    });

    test('parses per-device activity counts into detection fields', () {
      expect(summary.threats.threatsDetectedToday, 2);
      expect(summary.threats.threatsDetectedWeek, 9);
      expect(summary.threats.threatsDetectedMonth, 31);
      expect(summary.threats.threatsDetectedTotal, 57);
      expect(summary.threats.messagesAnalyzedTotal, 1043);
    });

    test('parses the activity trend points (date + count)', () {
      expect(summary.threats.trends, hasLength(2));
      // The backend emits bare YYYY-MM-DD dates for trend points, which
      // DateTime.parse reads as timezone-naive — compare the date parts.
      final firstDate = summary.threats.trends.first.date;
      expect(firstDate.year, 2026);
      expect(firstDate.month, 6);
      expect(firstDate.day, 9);
      expect(summary.threats.trends.first.count, 3);
      expect(summary.threats.trends.last.count, 2);
    });

    test('parses recent alerts from the alertItem wire shape', () {
      expect(summary.recentAlerts, hasLength(2));
      final first = summary.recentAlerts.first;
      expect(first.id, '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d');
      expect(first.title, 'Phishing SMS blocked');
      // `message` comes from the backend `description` key.
      expect(first.message,
          'A smishing message impersonating your bank was detected');
      // `type` comes from the backend `category` key.
      expect(first.type, 'sms');
      expect(first.severity, SeverityLevel.high);
      expect(first.isRead, isFalse);
      expect(first.actionUrl, '/sms/history');
      expect(first.timestamp, DateTime.utc(2026, 6, 10, 11, 45));

      final second = summary.recentAlerts.last;
      expect(second.severity, SeverityLevel.critical);
      expect(second.isRead, isTrue);
      expect(second.actionUrl, isNull);
    });

    test('parses the device_health section', () {
      final health = summary.deviceHealth;
      expect(health, isNotNull);
      expect(health!.overallScore, 75.0);
      expect(health.grade, 'B');
      expect(health.isRooted, isFalse);
      expect(health.isEncrypted, isTrue);
      expect(health.hasSecureScreenLock, isTrue);
      expect(health.hasLatestSecurityPatch, isFalse);
      expect(health.securityPatch, '2025-09-01');
      expect(health.platform, 'android');
      expect(health.osVersion, '15');
      expect(health.model, 'Pixel 9');
      expect(health.issues,
          ['Security patch level is outdated or unknown']);
      expect(health.hasIssues, isTrue);
    });
  });

  group('DashboardSummary.fromJson — anonymous payload (sections omitted)',
      () {
    late DashboardSummary summary;

    setUp(() {
      summary = DashboardSummary.fromJson(_decode(_anonymousDashboardJson));
    });

    test('does not throw when protection/activity/device_health are absent',
        () {
      expect(summary.recentAlerts, isEmpty);
      expect(summary.unreadAlerts, 0);
      expect(summary.totalAlerts, 0);
    });

    test('marks protection unavailable instead of faking values', () {
      expect(summary.protection.available, isFalse);
      expect(summary.protection.isProtected, isFalse);
      // 'U' is the app-wide unknown-grade sentinel, not a measurement.
      expect(summary.protection.protectionGrade, 'U');
      expect(summary.protection.smsProtection.status, 'unknown');
    });

    test('keeps the global threats section available', () {
      expect(summary.threats.available, isTrue);
      expect(summary.threats.totalIndicators, 12500);
      // Device-only field omitted by the backend without device identity.
      expect(summary.threats.campaignsTargetingDevice, 0);
      // Activity section absent: per-device counts are zero, not invented.
      expect(summary.threats.threatsDetectedTotal, 0);
      expect(summary.threats.trends, isEmpty);
    });

    test('leaves device health null when the section is omitted', () {
      expect(summary.deviceHealth, isNull);
    });
  });

  group('DashboardSummary.fromJson — minimal payload (no data sources)', () {
    test('marks the threat overview unavailable when both threats and '
        'activity are omitted', () {
      final summary =
          DashboardSummary.fromJson(_decode(_minimalDashboardJson));
      expect(summary.threats.available, isFalse);
      expect(summary.threats.totalIndicators, 0);
      expect(summary.protection.available, isFalse);
      expect(summary.deviceHealth, isNull);
    });
  });

  group('ProtectionStatus.fromJson — GET /api/v1/stats/protection', () {
    test('parses the nested {enabled, status} feature objects', () {
      final status = ProtectionStatus.fromJson(
          _decode(_fullDashboardJson)['protection'] as Map<String, dynamic>);
      expect(status.isActive, isTrue);
      expect(status.score, closeTo(66.67, 0.01));
      expect(status.grade, 'C');
      expect(status.isFeatureEnabled('sms'), isTrue);
      expect(status.isFeatureEnabled('app'), isFalse);
      expect(status.featureStates['web'], 'protected');
      expect(status.featureStates['app'], 'disabled');
      expect(status.enabledFeatures, containsAll(['sms', 'web', 'network', 'vpn']));
      expect(status.disabledFeatures, ['app']);
    });
  });
}
