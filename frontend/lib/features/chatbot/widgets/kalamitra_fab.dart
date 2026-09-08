import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../screens/chatbot_sheet.dart';

class KalaMitraFab extends StatelessWidget {
  const KalaMitraFab({super.key});

  @override
  Widget build(BuildContext context) {
    final isHi = context.locale.languageCode == 'hi';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [AppColors.terracotta, AppColors.terracottaDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.terracotta.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => ChatbotSheet.show(context),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/kalamitra_logo.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.mustard,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.smart_toy_outlined,
                          color: AppColors.charcoal,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isHi ? 'कला-मित्र' : 'KalaMitra',
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
