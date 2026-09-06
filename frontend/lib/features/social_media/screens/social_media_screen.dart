import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_image.dart';
import '../providers/social_media_provider.dart';

class SocialMediaScreen extends ConsumerStatefulWidget {
  final SocialMediaArgs args;

  const SocialMediaScreen({super.key, required this.args});

  @override
  ConsumerState<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends ConsumerState<SocialMediaScreen> {
  final _captionController = TextEditingController();
  final _hashtagController = TextEditingController();
  String? _lastDraftId;

  @override
  void dispose() {
    _captionController.dispose();
    _hashtagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialMediaProvider(widget.args));
    final notifier = ref.read(socialMediaProvider(widget.args).notifier);

    if (state.draft != null && state.draft!.draftId != _lastDraftId) {
      _lastDraftId = state.draft!.draftId;
      _captionController.text = state.draft!.caption;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('social_media_helper'.tr()),
        actions: [
          TextButton.icon(
            onPressed: state.isSaving || state.draft == null
                ? null
                : () async {
                    final saved = await notifier.save();
                    if (context.mounted && saved) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('social_draft_saved'.tr())),
                      );
                    }
                  },
            icon: const Icon(Icons.save),
            label: Text('save'.tr()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: AppColors.turmericLight.withValues(alpha: 0.35),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.turmericDark),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text('social_draft_notice'.tr())),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.args.allImages.length > 1)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.args.allImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final image = widget.args.allImages[index];
                  final selected = image == state.selectedImageUrl;
                  return InkWell(
                    onTap: state.isLoading ? null : () => notifier.generateForImage(image),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected ? AppColors.terracotta : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: AppImage(imageUrl: image, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (state.selectedImageUrl.isNotEmpty)
            SizedBox(height: 240, child: AppImage(imageUrl: state.selectedImageUrl, fit: BoxFit.cover)),
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.errorMessage != null)
            _ErrorPanel(message: state.errorMessage!, onRetry: notifier.regenerate)
          else if (state.draft != null) ...[
            Text('caption_label'.tr(), style: AppTextStyles.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _captionController,
              minLines: 4,
              maxLines: 8,
              onChanged: notifier.updateCaption,
              decoration: InputDecoration(hintText: 'caption_hint'.tr()),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('hashtags_label_social'.tr(), style: AppTextStyles.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in state.hashtags)
                  InputChip(label: Text(tag), onDeleted: () => notifier.removeHashtag(tag)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _hashtagController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'add_hashtag_hint'.tr(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    notifier.addHashtag(_hashtagController.text);
                    _hashtagController.clear();
                  },
                ),
              ),
              onSubmitted: (value) {
                notifier.addHashtag(value);
                _hashtagController.clear();
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: state.isLoading ? null : notifier.regenerate,
                  icon: const Icon(Icons.refresh),
                  label: Text('regenerate_btn'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await notifier.copyToClipboard();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('social_copied'.tr())),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: Text('copy'.tr()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}