// lib/screens/scan/apk_scan_screen.dart
//
// "Check an app file" — the user picks an APK (e.g. one they downloaded outside
// Google Play, the real Android sideload malware vector) and OrbGuard inspects it
// without installing it. Scoped: only the picked file is read.

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/security/apk_file_scanner.dart';

class ApkScanScreen extends StatefulWidget {
  const ApkScanScreen({super.key});

  @override
  State<ApkScanScreen> createState() => _ApkScanScreenState();
}

class _ApkScanScreenState extends State<ApkScanScreen> {
  bool _scanning = false;
  bool _ran = false;
  List<ApkScanResult> _results = const [];

  Future<void> _pickAndScan() async {
    setState(() => _scanning = true);
    final results = await ApkFileScannerService.instance.pickAndScan();
    if (!mounted) return;
    setState(() {
      _results = results;
      _scanning = false;
      _ran = true;
    });
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'CRITICAL':
        return AppColors.severityCritical;
      case 'HIGH':
        return AppColors.severityHigh;
      case 'MEDIUM':
        return AppColors.severityMedium;
      case 'CLEAN':
        return AppColors.accentInk;
      default:
        return AppColors.severityInfo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Check an app file',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Downloaded an app outside Google Play? Pick the .apk file and '
            'OrbGuard will inspect it — without installing it — for spyware-style '
            'permissions, a debug signature, or an app pretending to be one you '
            'already have.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Only the file you pick is read. Nothing is uploaded.',
            style: BrandText.body(color: AppColors.accentInk, size: 12),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: _scanning ? 'Scanning…' : 'Choose an APK to check',
            isLoading: _scanning,
            onPressed: _scanning ? null : _pickAndScan,
          ),
          const SizedBox(height: 24),
          if (_ran && _results.isEmpty)
            _emptyState(context)
          else
            ..._results.map((r) => _resultCard(context, r)),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) => GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No APK selected. Pick a .apk file to check it.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 13),
          ),
        ),
      );

  Widget _resultCard(BuildContext context, ApkScanResult r) {
    final color = _severityColor(r.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DuotoneIcon(
                    r.failed
                        ? 'info_circle'
                        : (r.isClean ? 'shield_check' : 'warning'),
                    size: 22,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.fileName.isEmpty ? r.path : r.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.title(
                          color: context.colors.onSurface, size: 15),
                    ),
                  ),
                  Text(
                    r.failed ? 'ERROR' : r.severity,
                    style: BrandText.label(color: color, size: 12),
                  ),
                ],
              ),
              if (r.failed) ...[
                const SizedBox(height: 8),
                Text(r.error!,
                    style: BrandText.body(
                        color: context.colors.onSurfaceVariant, size: 12)),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '${r.packageName}  ·  v${r.versionName}  ·  '
                  '${r.permissionCount} permissions',
                  style: BrandText.body(
                      color: context.colors.onSurfaceVariant, size: 12),
                ),
                if (r.isClean) ...[
                  const SizedBox(height: 10),
                  Text('No risk signals found in this file.',
                      style:
                          BrandText.body(color: AppColors.accentInk, size: 13)),
                ],
                ...r.findings.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.title,
                            style: BrandText.title(
                                color: _severityColor(f.severity), size: 13)),
                        const SizedBox(height: 2),
                        Text(f.detail,
                            style: BrandText.body(
                                color: context.colors.onSurfaceVariant,
                                size: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
