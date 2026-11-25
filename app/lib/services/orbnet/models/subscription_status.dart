/// Subscription status parsed from OrbNet JWT claims.
///
/// Ported from OrbX. Self-contained (no `equatable`): OrbGuard reads the
/// account's entitlement from these claims to gate subscription/credits/
/// remote-control features in later phases. The [StringFormatting] extension
/// is kept here so both this model and [UserSubscription] can format plan
/// names without a separate file.
library;

/// Helper extension to format plan/tier names for display.
extension StringFormatting on String {
  /// Converts snake_case or other formats to a proper display name.
  /// e.g. "token_based_group" -> "Free Plan", "premium_monthly" -> "Premium Monthly".
  String toDisplayName() {
    final lowerName = toLowerCase();
    if (lowerName == 'token_based_group' || lowerName == 'token_based') {
      return 'Free Plan';
    }
    if (lowerName == 'free' || lowerName == 'free_plan') {
      return 'Free Plan';
    }
    return split(RegExp(r'[_\-]'))
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ')
        .trim();
  }
}

/// Subscription status derived from JWT token claims.
class SubscriptionStatusFromToken {
  // Subscription identification
  final String? subscriptionTier;
  final int? subscriptionId;
  final int? subscriptionGroupId;

  // Subscription status
  final bool subscriptionValid;
  final String? subscriptionStatus;
  final DateTime? subscriptionExpiresAt;

  // Grace period
  final DateTime? gracePeriodEndsAt;

  // Device limit
  final int deviceLimit;

  // Subscription type
  final bool isAdSupported;
  final bool autoRenew;
  final String? paymentGateway;

  // Account status
  final bool active;
  final bool enabled;
  final int? resellerId;

  const SubscriptionStatusFromToken({
    this.subscriptionTier,
    this.subscriptionId,
    this.subscriptionGroupId,
    this.subscriptionValid = false,
    this.subscriptionStatus,
    this.subscriptionExpiresAt,
    this.gracePeriodEndsAt,
    this.deviceLimit = 1,
    this.isAdSupported = false,
    this.autoRenew = false,
    this.paymentGateway,
    this.active = true,
    this.enabled = true,
    this.resellerId,
  });

  /// Create from a map (typically the normalized JWT claims produced by
  /// `TokenService.getSubscriptionInfo`).
  factory SubscriptionStatusFromToken.fromMap(Map<String, dynamic> map) {
    return SubscriptionStatusFromToken(
      subscriptionTier: map['subscriptionTier'] as String?,
      subscriptionId: map['subscriptionId'] as int?,
      subscriptionGroupId: map['subscriptionGroupId'] as int?,
      subscriptionValid: map['subscriptionValid'] as bool? ?? false,
      subscriptionStatus: map['subscriptionStatus'] as String?,
      subscriptionExpiresAt: map['subscriptionExpiresAt'] as DateTime?,
      gracePeriodEndsAt: map['gracePeriodEndsAt'] as DateTime?,
      deviceLimit: map['deviceLimit'] as int? ?? 1,
      isAdSupported: map['isAdSupported'] as bool? ?? false,
      autoRenew: map['autoRenew'] as bool? ?? false,
      paymentGateway: map['paymentGateway'] as String?,
      active: map['active'] as bool? ?? true,
      enabled: map['enabled'] as bool? ?? true,
      resellerId: map['resellerId'] as int?,
    );
  }

  /// Empty status (no subscription data / logged out).
  factory SubscriptionStatusFromToken.empty() {
    return const SubscriptionStatusFromToken();
  }

  // ---- Computed properties -------------------------------------------------

  /// Whether the user has any (valid) subscription.
  bool get hasSubscription => subscriptionId != null && subscriptionValid;

  /// Whether the subscription is currently expired.
  bool get isExpired {
    if (subscriptionExpiresAt == null) return true;
    return DateTime.now().isAfter(subscriptionExpiresAt!);
  }

  /// Whether the subscription is expiring within 7 days.
  bool get isExpiringSoon {
    if (subscriptionExpiresAt == null) return false;
    final daysUntilExpiry =
        subscriptionExpiresAt!.difference(DateTime.now()).inDays;
    return daysUntilExpiry >= 0 && daysUntilExpiry <= 7;
  }

  /// Whether the subscription is in its grace period.
  bool get isInGracePeriod {
    if (gracePeriodEndsAt == null) return false;
    if (!isExpired) return false;
    return DateTime.now().isBefore(gracePeriodEndsAt!);
  }

  /// Whether the user is on a free (ad-supported) plan.
  bool get isFreeUser =>
      isAdSupported || subscriptionTier?.toLowerCase() == 'free';

  /// Days remaining until the subscription expires (0 when expired/unknown).
  int get daysRemaining {
    if (subscriptionExpiresAt == null) return 0;
    final days = subscriptionExpiresAt!.difference(DateTime.now()).inDays;
    return days < 0 ? 0 : days;
  }

  /// Human-readable plan name.
  String get planName {
    if (subscriptionTier == null || subscriptionTier!.isEmpty) {
      return 'No Plan';
    }
    return subscriptionTier!.toDisplayName();
  }

  /// Whether the account is usable (active and enabled).
  bool get isAccountUsable => active && enabled;

  @override
  String toString() =>
      'SubscriptionStatusFromToken(tier: $subscriptionTier, valid: '
      '$subscriptionValid, status: $subscriptionStatus, '
      'expiresAt: $subscriptionExpiresAt, isAdSupported: $isAdSupported, '
      'deviceLimit: $deviceLimit)';
}
