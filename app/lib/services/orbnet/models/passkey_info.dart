/// One registered passkey on the OrbNet account, as returned by
/// `GET /security/passkeys`. Only the fields the management UI needs.
class PasskeyInfo {
  final int id;
  final String name;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// Whether the credential is synced/backed up by the platform (iCloud
  /// Keychain / Google Password Manager) rather than device-bound.
  final bool backedUp;

  const PasskeyInfo({
    required this.id,
    required this.name,
    this.createdAt,
    this.lastUsedAt,
    this.backedUp = false,
  });

  factory PasskeyInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return PasskeyInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Passkey',
      createdAt: parse(json['created_at']),
      lastUsedAt: parse(json['last_used_at']),
      backedUp: json['backup_state'] as bool? ?? false,
    );
  }
}
