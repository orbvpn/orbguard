// Privacy Protection Screen
//
// Two honest surfaces, and nothing that implies monitoring the OS does not
// allow:
//  1. Trackers   — the real backend catalogue of known trackers, shown as an
//                  informational reference (OrbGuard does not block traffic on
//                  this device). Real empty/error states, never a fabricated
//                  list.
//  2. Camera & Mic — an honest explanation that iOS/Android do not expose other
//                  apps' camera or microphone access to third-party apps, so
//                  OrbGuard cannot monitor it, plus a pointer to the OS's own
//                  privacy indicators and per-app permission settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/privacy_provider.dart';

class PrivacyProtectionScreen extends StatefulWidget {
  const PrivacyProtectionScreen({super.key});

  @override
  State<PrivacyProtectionScreen> createState() =>
      _PrivacyProtectionScreenState();
}

class _PrivacyProtectionScreenState extends State<PrivacyProtectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrivacyProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PrivacyProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Privacy Protection',
          tabs: [
            GlassTab(
              label: 'Trackers',
              iconPath: 'chart_square',
              content: provider.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentInk))
                  : _buildTrackersTab(provider),
            ),
            GlassTab(
              label: 'Camera & Mic',
              iconPath: 'camera',
              content: _buildCameraMicTab(),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Trackers tab — the real backend catalogue (informational reference).
  // ---------------------------------------------------------------------------

  Widget _buildTrackersTab(PrivacyProvider provider) {
    // Honest failure: surface the real load error, never a fabricated list.
    if (provider.trackersLoadError != null) {
      return _buildUnavailableState(
        icon: AppIcons.forbidden,
        title: 'Tracker Catalogue Unavailable',
        message: provider.trackersLoadError!,
      );
    }

    if (provider.trackers.isEmpty) {
      return _buildUnavailableState(
        icon: AppIcons.chartSquare,
        title: 'No Trackers in Catalogue',
        message: 'The backend returned no known trackers. This reference list '
            'will populate once the catalogue is available.',
      );
    }

    final groupedTrackers = <String, List<TrackerInfo>>{};
    for (final tracker in provider.trackers) {
      groupedTrackers.putIfAbsent(tracker.category, () => []).add(tracker);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Honest informational header — a reference catalogue, NOT active
        // blocking. Nothing here is enforced on-device.
        GlassCard(
          margin: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassSvgIconBox(icon: AppIcons.infoCircle, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${provider.trackers.length} known trackers',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A reference list of tracking SDKs and analytics services '
                      'OrbGuard recognizes. This is informational — OrbGuard '
                      'does not intercept or block network traffic on this '
                      'device.',
                      style: TextStyle(
                          color: context.colors.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...groupedTrackers.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassSectionHeader(title: entry.key),
              ...entry.value.map(_buildTrackerCard),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTrackerCard(TrackerInfo tracker) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSvgIconBox(
            icon: AppIcons.chartSquare,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  tracker.company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.onSurfaceVariant, fontSize: 12),
                ),
                if (tracker.dataTypes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Collects: ${tracker.dataTypes.join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          context.colors.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera & Mic tab — honest "cannot monitor on-device" explanation.
  // ---------------------------------------------------------------------------

  Widget _buildCameraMicTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassSvgIconBox(
                        icon: AppIcons.camera, color: AppColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Camera & mic monitoring isn't possible on-device",
                        style: TextStyle(
                          color: context.colors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "iOS and Android deliberately do not expose other apps' "
                  'camera or microphone use to third-party apps like OrbGuard. '
                  'No API lets one app see when another app turns on the camera '
                  'or mic, so OrbGuard cannot monitor this — and does not '
                  'pretend to.',
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'The same applies to other apps’ clipboard, location, '
                  'and contacts access — the OS keeps that private to each app.',
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Use your device's built-in privacy tools",
            style: TextStyle(
              color: context.colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildGuidanceCard(
            icon: AppIcons.eye,
            title: 'Watch the on-screen indicators',
            body: 'A green dot (camera) or orange dot (microphone) appears in '
                'the status bar whenever an app is using them. iOS and '
                'Android 12+ both show these.',
          ),
          _buildGuidanceCard(
            icon: AppIcons.settings,
            title: 'Review per-app permissions',
            body: 'Open Settings > Privacy & Security (iOS) or Settings > '
                'Privacy > Permission manager (Android) to see and revoke which '
                'apps can use your camera and microphone.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceCard({
    required String icon,
    required String title,
    required String body,
  }) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSvgIconBox(icon: icon, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared honest empty/unavailable state.
  // ---------------------------------------------------------------------------

  Widget _buildUnavailableState({
    required String icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(
              icon,
              size: 64,
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.colors.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
