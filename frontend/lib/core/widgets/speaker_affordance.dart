import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// The "Tap to hear" pill / icon used across the app to trigger read-back
/// via [AppTtsService]. One definition, reused everywhere, so every screen's
/// speaker button looks and behaves the same way.
///
/// Two shapes:
///  - [SpeakerAffordance] (pill, icon + label) — for a single clear header,
///    e.g. Photo Tips, Packaging Suggestions.
///  - [SpeakerAffordance.compact] (icon only) — for repeated per-item spots
///    where a full label would crowd the layout, e.g. an order card or a
///    notification row.
class SpeakerAffordance extends StatelessWidget {
  final bool isSpeaking;
  final VoidCallback onTap;
  final bool compact;
  final String? label;
  final String? stopLabel;

  const SpeakerAffordance({
    super.key,
    required this.isSpeaking,
    required this.onTap,
    this.label,
    this.stopLabel,
  }) : compact = false;

  const SpeakerAffordance.compact({
    super.key,
    required this.isSpeaking,
    required this.onTap,
    this.label,
    this.stopLabel,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label ?? 'tap_to_hear'.tr();
    final effectiveStopLabel = stopLabel ?? 'stop_audio'.tr();

    final icon = isSpeaking
        ? Icons.stop_circle_outlined
        : Icons.volume_up_rounded;

    if (compact) {
      return Semantics(
        button: true,
        label: isSpeaking ? effectiveStopLabel : effectiveLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: AppColors.terracottaDark),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.terracotta.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(
            color: AppColors.terracotta.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.terracottaDark),
            const SizedBox(width: 4),
            Text(
              isSpeaking ? effectiveStopLabel : effectiveLabel,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.terracottaDark,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A brief inline notice for when the device has no voice installed for the
/// current language. Pairs with [AppTtsService.openVoiceDownloadScreen] —
/// shown only when speak() actually reports the voice is missing, never
/// pre-emptively.
class VoiceUnavailableNotice extends StatelessWidget {
  final VoidCallback onDownload;

  const VoiceUnavailableNotice({super.key, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: Colors.orange.shade800),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Voice not installed for this language',
              style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
            ),
          ),
          TextButton(
            onPressed: onDownload,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Download', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
