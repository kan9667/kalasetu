import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/connectivity_pill.dart';
import '../../../core/providers/app_providers.dart';

class Step3AiReviewWidget extends ConsumerStatefulWidget {
  const Step3AiReviewWidget({super.key});

  @override
  ConsumerState<Step3AiReviewWidget> createState() => _Step3AiReviewWidgetState();
}

class _Step3AiReviewWidgetState extends ConsumerState<Step3AiReviewWidget> {
  final TextEditingController _customTagController = TextEditingController();
  int _selectedLanguageIndex = 0; // 0 for EN, 1 for HI

  @override
  void dispose() {
    _customTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;

    // If Step 2 finished while offline, there's no listing yet. The moment
    // connectivity comes back, kick off generation automatically so the
    // user doesn't have to do anything else.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final nowOnline = next.value == true;
      if (!wasOffline || !nowOnline) return;

      final current = ref.read(addProductFlowProvider);
      if (current.titleEn.isEmpty && !current.isAiProcessing) {
        String localeCode = 'en';
        try {
          localeCode = context.locale.languageCode;
        } catch (_) {}
        ref.read(addProductFlowProvider.notifier).generateAiListing(localeCode);
      }
    });

    if (draft.isAiProcessing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.terracotta),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Generating your bilingual listing...',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.terracotta,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // No listing yet and no internet to generate one — wait it out.
    if (!isOnline && draft.titleEn.isEmpty) {
      return const _OfflineWaitingView();
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.originalImagePath.isNotEmpty) ...[
            SizedBox(
              height: 240,
              child: draft.isEnhanced && draft.enhancedImagePath.isNotEmpty
                  ? _BeforeAfterSlider(
                      beforePath: draft.originalImagePath,
                      afterPath: draft.enhancedImagePath,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(draft.originalImagePath),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  ref.read(addProductFlowProvider.notifier).startRetakePhoto();
                },
                icon: const Icon(Icons.camera_alt_outlined, size: 18, color: Color(0xFF8C533E)),
                label: const Text(
                  'Retake Photo',
                  style: TextStyle(color: Color(0xFF8C533E), fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFC86D51), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('ai_review_title'.tr(), style: AppTextStyles.headlineMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ai_review_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF7A6E63)),
          ),
          const SizedBox(height: 16),

          // Bilingual Toggle Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEBE3D5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedLanguageIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedLanguageIndex == 0 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedLanguageIndex == 0
                            ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'tab_english'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedLanguageIndex == 0 ? const Color(0xFFC86D51) : const Color(0xFF7A6E63),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedLanguageIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedLanguageIndex == 1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedLanguageIndex == 1
                            ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'tab_hindi'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedLanguageIndex == 1 ? const Color(0xFFC86D51) : const Color(0xFF7A6E63),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            initialValue: _selectedLanguageIndex == 0 ? draft.titleEn : draft.titleHi,
            key: ValueKey('title_$_selectedLanguageIndex'),
            decoration: InputDecoration(
              labelText: 'product_title_label'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFFFAF7F2),
            ),
            onChanged: (val) {
              if (_selectedLanguageIndex == 0) {
                ref.read(addProductFlowProvider.notifier).updateListingDetails(titleEn: val);
              } else {
                ref.read(addProductFlowProvider.notifier).updateListingDetails(titleHi: val);
              }
            },
          ),
          const SizedBox(height: 14),

          TextFormField(
            initialValue: _selectedLanguageIndex == 0 ? draft.descriptionEn : draft.descriptionHi,
            key: ValueKey('desc_$_selectedLanguageIndex'),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'product_desc_label'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFFFAF7F2),
            ),
            onChanged: (val) {
              if (_selectedLanguageIndex == 0) {
                ref.read(addProductFlowProvider.notifier).updateListingDetails(descriptionEn: val);
              } else {
                ref.read(addProductFlowProvider.notifier).updateListingDetails(descriptionHi: val);
              }
            },
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: draft.tags.map((tag) {
              return Chip(
                label: Text('#$tag', style: const TextStyle(fontSize: 13, color: Color(0xFF4A3E35))),
                backgroundColor: const Color(0xFFEBE3D5),
                deleteIconColor: const Color(0xFF7A6E63),
                onDeleted: () => ref.read(addProductFlowProvider.notifier).removeTag(tag),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTagController,
                  decoration: InputDecoration(
                    hintText: 'add_custom_tag_hint'.tr(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFFFAF7F2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_customTagController.text.trim().isNotEmpty) {
                    ref.read(addProductFlowProvider.notifier).addTag(_customTagController.text.trim());
                    _customTagController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC86D51),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  minimumSize: Size.zero,
                ),
                child: Text('add'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                flex: 6,
                child: ElevatedButton.icon(
                  onPressed: () => ref.read(addProductFlowProvider.notifier).nextStep(),
                  icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  label: Text(
                    'looks_good'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC86D51),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (!isOnline) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("You're offline — reconnect to regenerate the listing.")),
                      );
                      return;
                    }
                    final lang = _selectedLanguageIndex == 0 ? 'en' : 'hi';
                    ref.read(addProductFlowProvider.notifier).generateAiListing(lang);
                  },
                  icon: Icon(Icons.refresh, color: isOnline ? const Color(0xFF4A3E35) : const Color(0xFFB3A99A), size: 18),
                  label: Text(
                    'regenerate_btn'.tr(),
                    style: TextStyle(
                      color: isOnline ? const Color(0xFF4A3E35) : const Color(0xFFB3A99A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isOnline ? const Color(0xFFD6C7B2) : const Color(0xFFE8E0D3)),
                    backgroundColor: const Color(0xFFF7F2EA),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _OfflineWaitingView extends StatelessWidget {
  const _OfflineWaitingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0xFFF3EDE2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF8C533E)),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              "You're offline",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3F342B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Your photo and description are saved on this device. We'll generate "
              "your AI listing automatically the moment you're back online — no need to redo anything.",
              style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF7A6E63)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            const ConnectivityPill(),
          ],
        ),
      ),
    );
  }
}

/// Draggable before/after image comparison. Drag or tap anywhere across the
/// widget to move the divider; the left side shows [beforePath], the right
/// side shows [afterPath].
class _BeforeAfterSlider extends StatefulWidget {
  final String beforePath;
  final String afterPath;

  const _BeforeAfterSlider({required this.beforePath, required this.afterPath});

  @override
  State<_BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<_BeforeAfterSlider> {
  double _sliderPosition = 0.5;

  void _updatePosition(Offset localPosition, double width) {
    setState(() {
      _sliderPosition = (localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFFF3EDE2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final handleX = _sliderPosition * width;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => _updatePosition(details.localPosition, width),
              onTapDown: (details) => _updatePosition(details.localPosition, width),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(File(widget.afterPath), fit: BoxFit.cover),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _LeftEdgeClipper(width: handleX),
                      child: Image.file(File(widget.beforePath), fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    left: handleX - 1,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(width: 2, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: handleX - 18,
                    top: height / 2 - 18,
                    child: IgnorePointer(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                        ),
                        child: const Icon(Icons.drag_indicator, size: 18, color: Color(0xFF3F342B)),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IgnorePointer(
                      child: _SliderLabel(text: 'Before', dimmed: _sliderPosition < 0.15),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: _SliderLabel(text: 'After', dimmed: _sliderPosition > 0.85),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Text(
                        '← Drag to compare →',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                          shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeftEdgeClipper extends CustomClipper<Rect> {
  final double width;
  _LeftEdgeClipper({required this.width});

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(covariant _LeftEdgeClipper oldClipper) => oldClipper.width != width;
}

class _SliderLabel extends StatelessWidget {
  final String text;
  final bool dimmed;

  const _SliderLabel({required this.text, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}