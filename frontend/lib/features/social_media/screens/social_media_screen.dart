import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/social_media_provider.dart';
import '../widgets/social_media_launchpad_sheet.dart';

/// Full-screen fallback wrapper for the Social Media Launchpad sheet.
/// Ensures route compatibility if navigated to via GoRouter directly.
class SocialMediaScreen extends StatelessWidget {
  final SocialMediaArgs args;

  const SocialMediaScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: SocialMediaLaunchpadSheet(args: args),
      ),
    );
  }
}