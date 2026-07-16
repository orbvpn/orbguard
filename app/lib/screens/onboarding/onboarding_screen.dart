import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

/// First-run onboarding — three calm steps that set the anti-surveillance value,
/// explain the checkup honestly, and reassure on privacy, then hand off to the
/// app. Shown once (gated by `SettingsProvider.hasSeenOnboarding`).
class OnboardingScreen extends StatefulWidget {
  /// Called when the user finishes or skips — marks onboarding complete.
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final String icon;
  final String title;
  final String body;
  const _OnboardingPage(this.icon, this.title, this.body);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      'eye_closed',
      "Know if you're\nbeing watched.",
      'OrbGuard checks your phone for the ways someone could be spying on you — '
          'spyware, stalkerware, scam messages, and hidden network tricks.',
    ),
    _OnboardingPage(
      'magnifer_bug',
      'One tap.\nA clear answer.',
      'Run a checkup anytime. OrbGuard names every check as it runs, and tells '
          "you honestly what it finds — and what your phone won't let any app see.",
    ),
    _OnboardingPage(
      'shield_keyhole',
      'Private\nby design.',
      "Everything runs on your phone — we can't see your data. You're always in "
          'control of what OrbGuard can access.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text('Skip',
                      style: BrandText.label(color: cs.onSurfaceVariant)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _OnboardingPageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? AppColors.accent
                        : cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: BrandButton(
                label: _isLast ? 'Get started' : 'Next',
                expand: true,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  const _OnboardingPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withAlpha(28),
              border: Border.all(color: AppColors.accent.withAlpha(70), width: 2),
            ),
            child: Center(
              child: DuotoneIcon(page.icon, size: 56, color: AppColors.accentInk),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: BrandText.display(color: cs.onSurface, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 16),
          ),
        ],
      ),
    );
  }
}
