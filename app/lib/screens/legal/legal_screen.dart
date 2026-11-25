// lib/screens/legal/legal_screen.dart
//
// Renders the OrbGuard Terms of Service / Privacy Policy in-app (GlassPage), with
// a link out to the hosted, always-current copy. Used from Settings → Legal and
// from the sign-in acceptance line.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../legal/legal_documents.dart';
import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/glass_app_bar.dart';

enum LegalDoc { terms, privacy }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  bool get _isTerms => doc == LegalDoc.terms;

  String get _title => _isTerms ? LegalDocs.termsTitle : LegalDocs.privacyTitle;
  String get _body => _isTerms ? LegalDocs.terms : LegalDocs.privacy;
  String get _hostedUrl => _isTerms ? LegalDocs.termsUrl : LegalDocs.privacyUrl;

  Future<void> _openHosted() async {
    final uri = Uri.parse(_hostedUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: _title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SelectableText(
            _body.trim(),
            style: BrandText.body(
              color: context.colors.onSurface,
              size: 13,
            ).copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          Text(
            'The current version of this document is also published online.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 12),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _openHosted,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              _isTerms
                  ? 'Open Terms of Service on the web'
                  : 'Open Privacy Policy on the web',
              style: BrandText.title(color: AppColors.accentInk, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
