/// How each shield looks and what it says it covers, in one place, so Home's
/// orbit and the Protect list can never drift apart.
library;

import '../../presentation/widgets/duotone_icon.dart';
import '../../services/home/home_brief.dart';

extension ShieldLook on Shield {
  /// The one icon this shield goes by.
  String get icon => switch (this) {
        Shield.spyware => AppIcons.searchBug,
        Shield.watching => AppIcons.eyeScan,
        Shield.scam => AppIcons.chatRoundCheck,
        Shield.identity => AppIcons.userId,
        Shield.hiddenVpn => AppIcons.eyeClosed,
        Shield.secureCall => AppIcons.phoneCalling,
      };

  /// What it covers, in one plain line.
  String get covers => switch (this) {
        Shield.spyware => 'Check for professional spy software',
        Shield.watching => 'Hidden trackers, stalkerware and risky permissions',
        Shield.scam => 'Texts, links and QR codes',
        Shield.identity => 'Find your accounts exposed on the dark web',
        Shield.hiddenVpn => 'Spot traffic being secretly rerouted',
        Shield.secureCall => 'Check your device before sensitive calls',
      };
}
