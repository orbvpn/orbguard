// Notification Discipline settings screen.
//
// Surfaces the [NotificationPolicy] settings (critical-only, weekly summary
// + weekday) plus a calm, honest explanation of what actually earns a
// notification — no fear-driven copy, no promo language. Self-contained:
// owns its own [NotificationPolicy] instance and persistence; the parent
// links to this screen from Settings and gates the real notification send
// path behind `NotificationPolicy.shouldNotify` (see that file's header for
// the intended wiring).

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../services/notifications/notification_policy.dart';

/// Settings screen for Phase 3.4 notification discipline: lets the user see
/// — and tighten or relax — the rules that gate every real-time alert, plus
/// configure the single opt-in weekly summary.
class NotificationDisciplineScreen extends StatefulWidget {
  const NotificationDisciplineScreen({super.key});

  @override
  State<NotificationDisciplineScreen> createState() =>
      _NotificationDisciplineScreenState();
}

class _NotificationDisciplineScreenState
    extends State<NotificationDisciplineScreen> {
  final NotificationPolicy _policy = NotificationPolicy();

  bool _loading = true;
  bool _criticalOnly = true;
  bool _weeklySummaryEnabled = true;
  int _summaryWeekday = DateTime.monday;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _policy.load();
    if (!mounted) return;
    setState(() {
      _criticalOnly = _policy.criticalOnly;
      _weeklySummaryEnabled = _policy.weeklySummaryEnabled;
      _summaryWeekday = _policy.summaryWeekday;
      _loading = false;
    });
  }

  Future<void> _setCriticalOnly(bool value) async {
    setState(() => _criticalOnly = value);
    await _policy.setCriticalOnly(value);
  }

  Future<void> _setWeeklySummaryEnabled(bool value) async {
    setState(() => _weeklySummaryEnabled = value);
    await _policy.setWeeklySummaryEnabled(value);
  }

  Future<void> _setSummaryWeekday(int weekday) async {
    setState(() => _summaryWeekday = weekday);
    await _policy.setSummaryWeekday(weekday);
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Notification Discipline',
      body: _loading
          ? Center(
              child:
                  CircularProgressIndicator(color: AppColors.accentInk),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _buildHeaderNote(context),
                const SizedBox(height: 24),
                _buildSectionLabel(context, 'Alert rules'),
                GlassCard(
                  padding: EdgeInsets.zero,
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    secondary: DuotoneIcon(
                      'danger_triangle',
                      color: _criticalOnly
                          ? AppColors.accentInk
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                    title: Text(
                      'Critical alerts only',
                      style: BrandText.title(color: Brand.text),
                    ),
                    subtitle: Text(
                      _criticalOnly
                          ? 'Only the single most severe tier notifies you. '
                              'Turn off to also allow high-severity alerts '
                              'through the same rare + actionable filter.'
                          : 'High-severity and critical alerts can both '
                              'reach you — still rare, actionable, and '
                              'capped at once a day.',
                      style: BrandText.body(color: Brand.text2, size: 12.5),
                    ),
                    value: _criticalOnly,
                    onChanged: _setCriticalOnly,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionLabel(context, 'Weekly summary'),
                GlassCard(
                  padding: EdgeInsets.zero,
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: DuotoneIcon(
                          'calendar',
                          color: _weeklySummaryEnabled
                              ? AppColors.accentInk
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                          size: 24,
                        ),
                        title: Text(
                          'Weekly summary',
                          style: BrandText.title(color: Brand.text),
                        ),
                        subtitle: Text(
                          'One digest a week, on the day you choose below. '
                          'Never more than one.',
                          style:
                              BrandText.body(color: Brand.text2, size: 12.5),
                        ),
                        value: _weeklySummaryEnabled,
                        onChanged: _setWeeklySummaryEnabled,
                      ),
                      if (_weeklySummaryEnabled) ...[
                        Divider(height: 1, color: Brand.border),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: _WeekdayPicker(
                            selected: _summaryWeekday,
                            onChanged: _setSummaryWeekday,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildExplainerCard(context),
              ],
            ),
    );
  }

  Widget _buildHeaderNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentInk.withAlpha(20),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon('shield_check', color: AppColors.accentInk, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "We only alert you when it's rare, serious, and something "
              'you can act on. No promos. Ever.',
              style: BrandText.body(color: AppColors.accentInk, size: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: BrandText.label(color: Brand.text2)),
    );
  }

  Widget _buildExplainerCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon('info_circle',
                  color: AppColors.secondaryInk, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What actually earns a notification',
                  style: BrandText.title(color: Brand.text, size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final point in _explainerPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuotoneIcon('check_circle',
                      color: AppColors.accentInk, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point,
                      style:
                          BrandText.body(color: cs.onSurfaceVariant, size: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Everything else — routine scans, minor findings, general '
            'updates — stays quiet. Check them anytime in the app.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          ),
        ],
      ),
    );
  }

  static const List<String> _explainerPoints = [
    "It's high-severity or critical — never routine.",
    "It's something you can act on right now.",
    "We haven't already alerted for this topic in the last 24 hours.",
    "We haven't sent any other alert today.",
  ];
}

/// Compact 7-day segmented picker (Mon..Sun) for the weekly-summary day.
/// Mirrors [ThemeModeSelector]'s "only the active segment takes lime" rule.
class _WeekdayPicker extends StatelessWidget {
  final int selected; // DateTime.monday..DateTime.sunday
  final ValueChanged<int> onChanged;

  const _WeekdayPicker({required this.selected, required this.onChanged});

  static const List<String> _labels = [
    'Mo',
    'Tu',
    'We',
    'Th',
    'Fr',
    'Sa',
    'Su',
  ];

  static const List<String> _fullNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(7, (index) {
        final weekday = index + 1; // DateTime.monday == 1
        final isSelected = weekday == selected;
        final color = isSelected ? Brand.navActive : cs.onSurfaceVariant;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 6 ? 0 : 6),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: _fullNames[index],
              child: GestureDetector(
                onTap: () => onChanged(weekday),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? Brand.navActivePill : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                    border: Border.all(
                      color: isSelected
                          ? Brand.navActive.withValues(alpha: 0.45)
                          : Colors.transparent,
                      width: GlassTheme.borderWidth,
                    ),
                  ),
                  child: Text(
                    _labels[index],
                    style: TextStyle(
                      fontFamily: Brand.fontMono,
                      color: color,
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
