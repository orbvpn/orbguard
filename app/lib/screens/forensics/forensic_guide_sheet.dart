/// The Full Forensic Scan on a phone. An app cannot read the system logs of
/// the phone it runs on, so the scan reads a file the phone's own system
/// makes: an Android bug report, or an iPhone sysdiagnose. This sheet says how
/// to make that file, in steps, and its one action closes the sheet with true
/// so the screen opens the file picker. Nothing is checked or paid for here.
///
/// Every step names what the phone itself shows. The Android steps were
/// checked on an Android 15 emulator: Developer options, Bug report, Full
/// report, Report, the "Bug report captured" notification, OK on Android's
/// own warning, then Drive in the share sheet.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';

/// One step of making the file.
@immutable
class ForensicGuideStep {
  const ForensicGuideStep(this.title, this.detail);

  final String title;
  final String detail;
}

/// What a phone's full scan reads, and how a person makes it.
@immutable
class ForensicGuide {
  const ForensicGuide._({
    required this.lead,
    required this.steps,
    required this.choose,
    required this.acceptedSuffixes,
    required this.wrongFile,
  });

  /// What the file is and why the scan needs it.
  final String lead;
  final List<ForensicGuideStep> steps;

  /// The label of the one action, which opens the file picker. The picker
  /// shows every file: a bug report saved to Drive can carry Android's own
  /// bug report type rather than zip's, and a picker filtered by type would
  /// grey it out. The name is checked once it is chosen.
  final String choose;

  /// The endings the server reads. Anything else is not sent.
  final List<String> acceptedSuffixes;

  /// Said when the chosen file is something else.
  final String wrongFile;

  /// An Android bug report, read through the bug report upload.
  static const ForensicGuide android = ForensicGuide._(
    lead: 'No app can read what other apps on this phone do. Android can put '
        'its system logs in one file, a bug report. OrbGuard looks through '
        'it for known spyware and stalkerware.',
    steps: [
      ForensicGuideStep(
        'Turn on Developer options',
        'In Settings, open About phone and tap Build number seven times. On '
            'some phones it is under Software information.',
      ),
      ForensicGuideStep(
        'Take a bug report',
        'In Settings, open Developer options (on many phones it is under '
            'System). Tap Bug report, choose Full report, then tap Report.',
      ),
      ForensicGuideStep(
        'Save it to Drive',
        'It takes a few minutes. When the notification says the bug report '
            'is captured, tap it, tap OK, then choose Drive.',
      ),
      ForensicGuideStep(
        'Choose it here',
        'Come back and choose the bug report from Drive. OrbGuard\'s server '
            'reads it for this check, then deletes it.',
      ),
    ],
    choose: 'Choose the bug report',
    acceptedSuffixes: ['.zip', '.txt'],
    wrongFile: 'That file is not a bug report. Choose the .zip file the bug '
        'report saved.',
  );

  /// An iPhone sysdiagnose, read through the sysdiagnose upload. The
  /// sysdiagnose holds the shutdown log, and that upload reads it too.
  static const ForensicGuide iphone = ForensicGuide._(
    lead: 'No app can read the iPhone\'s system logs. iOS can put them in one '
        'file, a sysdiagnose, with the shutdown log too. OrbGuard looks '
        'through it for known spyware such as Pegasus.',
    steps: [
      ForensicGuideStep(
        'Start a sysdiagnose',
        'Press both volume buttons and the side button together, and let go '
            'within about a second. The iPhone vibrates briefly. Do not hold '
            'them: holding brings up Emergency SOS.',
      ),
      ForensicGuideStep(
        'Wait about 10 minutes',
        'The iPhone puts the file together in the background. You can keep '
            'using it.',
      ),
      ForensicGuideStep(
        'Save it to Files',
        'In Settings, open Privacy & Security, then Analytics & Improvements, '
            'then Analytics Data. Tap the newest file whose name starts with '
            'sysdiagnose, tap Share, then Save to Files.',
      ),
      ForensicGuideStep(
        'Choose it here',
        'Come back and choose it from Files. It is a large file, so Wi-Fi is '
            'best. OrbGuard\'s server reads it for this check, then deletes '
            'it.',
      ),
    ],
    choose: 'Choose the sysdiagnose',
    acceptedSuffixes: ['.tar.gz', '.tgz', '.zip'],
    wrongFile: 'That file is not a sysdiagnose. Choose the file whose name '
        'starts with sysdiagnose.',
  );

  /// The guide for a phone, or null where the full scan has no file to read.
  static ForensicGuide? of(TargetPlatform? platform) => switch (platform) {
        TargetPlatform.android => android,
        TargetPlatform.iOS => iphone,
        _ => null,
      };
}

/// The steps, and one action. Pops true when the person chooses the file.
class ForensicGuideSheet extends StatelessWidget {
  const ForensicGuideSheet({super.key, required this.guide});

  final ForensicGuide guide;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentPill,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
                ),
                child: Center(
                  child: DuotoneIcon(
                    AppIcons.forensics,
                    size: 26,
                    color: Brand.limeInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Full forensic scan',
              style: BrandText.h2(
                color: cs.onSurface,
                size: 21,
              ).copyWith(height: Brand.displayHeight(1.25)),
            ),
            const SizedBox(height: 8),
            Text(
              guide.lead,
              style: BrandText.body(
                size: 15,
                color: cs.onSurfaceVariant,
              ).copyWith(height: Brand.bodyHeight(1.45)),
            ),
            const SizedBox(height: 20),
            for (int i = 0; i < guide.steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _Step(number: i + 1, step: guide.steps[i]),
            ],
            const SizedBox(height: 22),
            BrandButton(
              label: guide.choose,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: Text(
                'Not now',
                textAlign: TextAlign.center,
                style: BrandText.title(
                  size: 15,
                  weight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.step});

  final int number;
  final ForensicGuideStep step;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Brand.hairline,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: BrandText.title(size: 13, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                step.title,
                style: BrandText.title(
                  size: 15.5,
                  color: cs.onSurface,
                ).copyWith(height: Brand.displayHeight(1.3)),
              ),
              const SizedBox(height: 2),
              Text(
                step.detail,
                style: BrandText.body(
                  size: 13.5,
                  color: cs.onSurfaceVariant,
                ).copyWith(height: Brand.bodyHeight(1.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
