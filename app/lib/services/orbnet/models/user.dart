/// OrbNet account user model.
///
/// Ported from OrbX and stripped of `equatable` to stay self-contained. This
/// is the shared OrbVPN/OrbNet identity — email is primary; the backend nests
/// profile fields under `profile` and (on login) returns subscription
/// separately, which the repository merges in before calling [User.fromJson].
library;

import 'subscription_status.dart' show StringFormatting;

class User {
  final String id;
  final String? uuid;
  final String email;
  final String? username;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? country;
  final String? language;
  final String? role;
  final bool active;
  final bool emailVerified;
  final UserSubscription? subscription;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;

  const User({
    required this.id,
    this.uuid,
    required this.email,
    this.username,
    this.displayName,
    this.firstName,
    this.lastName,
    this.country,
    this.language,
    this.role,
    this.active = true,
    this.emailVerified = false,
    this.subscription,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
  });

  /// Full name, falling back to the email when no name is present.
  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? email;
  }

  /// Display name for UI (uses displayName, else fullName).
  String get displayNameOrFull => displayName ?? fullName;

  /// Whether the subscription is active (lifetime = no expiry).
  bool get hasActiveSubscription {
    if (subscription == null) return false;
    if (subscription!.expiryDate == null) return true;
    return subscription!.expiryDate!.isAfter(DateTime.now());
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // Backend nests some fields under a `profile` object.
    final profile = json['profile'] as Map<String, dynamic>?;

    return User(
      id: json['id'].toString(),
      uuid: json['uuid'] as String?,
      email: json['email'] as String,
      username: json['username'] as String?,
      displayName: json['display_name'] as String?,
      firstName:
          profile?['first_name'] as String? ?? json['first_name'] as String?,
      lastName:
          profile?['last_name'] as String? ?? json['last_name'] as String?,
      country: profile?['country'] as String? ?? json['country'] as String?,
      language: profile?['language'] as String? ?? json['language'] as String?,
      role: json['role'] as String?,
      active: json['active'] as bool? ?? json['enabled'] as bool? ?? true,
      emailVerified: json['email_verified'] as bool? ?? false,
      subscription: json['subscription'] != null
          ? UserSubscription.fromJson(
              json['subscription'] as Map<String, dynamic>)
          : null,
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
      lastLoginAt: _parseDate(json['last_login_at'] ?? json['lastLoginAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'email': email,
      'username': username,
      'display_name': displayName,
      'role': role,
      'country': country,
      'active': active,
      'email_verified': emailVerified,
      'profile': {
        'first_name': firstName,
        'last_name': lastName,
        'country': country,
        'language': language,
      },
      'subscription': subscription?.toJson(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  @override
  String toString() => 'User(id: $id, email: $email, role: $role)';
}

/// A user's active subscription, as returned by the OrbNet backend.
class UserSubscription {
  final String id;
  final String planName;
  final int maxDevices;
  final DateTime? expiryDate;
  final bool isActive;
  final int? durationDays;
  final DateTime? createdAt;

  const UserSubscription({
    required this.id,
    required this.planName,
    required this.maxDevices,
    this.expiryDate,
    this.isActive = true,
    this.durationDays,
    this.createdAt,
  });

  /// Whether the subscription has expired (null expiry = lifetime).
  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  /// Days remaining until expiry (null = lifetime).
  int? get daysRemaining {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  /// Properly formatted plan name for UI.
  String get displayPlanName => planName.toDisplayName();

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    // Supports both the flat Go structure and a nested `group` object.
    final group = json['group'] as Map<String, dynamic>?;

    final groupId = json['group_id']?.toString() ??
        group?['id']?.toString() ??
        json['id']?.toString() ??
        '0';
    final groupName = json['group_name'] as String? ??
        json['plan_name'] as String? ??
        group?['name'] as String? ??
        'Unknown Plan';

    final maxDevices =
        json['max_devices'] as int? ?? json['maxDevices'] as int? ?? 1;

    DateTime? expiryDate;
    if (json['expires_at'] != null) {
      expiryDate = DateTime.tryParse(json['expires_at'] as String);
    } else if (json['expiresAt'] != null) {
      expiryDate = DateTime.tryParse(json['expiresAt'] as String);
    }

    final durationDays = json['duration'] as int?;

    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.tryParse(json['created_at'] as String);
    } else if (json['createdAt'] != null) {
      createdAt = DateTime.tryParse(json['createdAt'] as String);
    }

    return UserSubscription(
      id: groupId,
      planName: groupName,
      maxDevices: maxDevices,
      expiryDate: expiryDate,
      isActive: json['status'] == 'ACTIVE' ||
          (expiryDate != null ? expiryDate.isAfter(DateTime.now()) : true),
      durationDays: durationDays,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'group': {
        'id': int.tryParse(id) ?? 0,
        'name': planName,
      },
      'max_devices': maxDevices,
      'expiresAt': expiryDate?.toIso8601String(),
      'duration': durationDays,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
