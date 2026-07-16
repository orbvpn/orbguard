/// Which experience the app presents to the user.
///
/// [guard] is the default, consumer-first experience — one honest verdict, a
/// single "Check my phone" action, and a small set of plain-English protections.
/// It is what ~95% of users ever see.
///
/// [pro] additionally unlocks the full expert/analyst console (threat
/// intelligence, MITRE ATT&CK, correlation, STIX/TAXII, SIEM, playbooks, …) for
/// researchers, IT, and power users who deliberately opt in from Settings.
///
/// The mode is persisted by `SettingsProvider` and gates navigation only — no
/// screen is deleted, just hidden from the consumer surface until Pro is on.
enum AppMode {
  guard,
  pro;

  bool get isGuard => this == AppMode.guard;
  bool get isPro => this == AppMode.pro;

  /// Short human label for the mode toggle.
  String get label => this == AppMode.pro ? 'Pro' : 'Guard';

  /// Persistence round-trips through [name]; unknown/absent values default to
  /// the safe consumer default ([guard]).
  static AppMode fromName(String? name) =>
      name == AppMode.pro.name ? AppMode.pro : AppMode.guard;
}
