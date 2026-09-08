import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/services/social_sharing_service.dart';
import '../providers/social_media_provider.dart';

/// Shows the 2-step Social Media Launchpad bottom sheet.
Future<void> showSocialMediaLaunchpadSheet(
   BuildContext context,
   SocialMediaArgs args,
) {
   return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SocialMediaLaunchpadSheet(args: args),
   );
}

class SocialMediaLaunchpadSheet extends ConsumerStatefulWidget {
   final SocialMediaArgs args;

   const SocialMediaLaunchpadSheet({super.key, required this.args});

   @override
   ConsumerState<SocialMediaLaunchpadSheet> createState() =>
         _SocialMediaLaunchpadSheetState();
}

class _SocialMediaLaunchpadSheetState
      extends ConsumerState<SocialMediaLaunchpadSheet> {
   int _step = 1; // 1: Channel selection, 2: Channel view & share
   final _captionController = TextEditingController();
   String? _lastLoadedDraftId;
   String? _lastLoadedChannel;
   String? _lastLoadedCaption;
   bool _isActionInProgress = false;

   @override
   void dispose() {
      _captionController.dispose();
      super.dispose();
   }

   void _syncCaptionFromState(SocialMediaState state) {
      if (state.draft == null) return;

      final draft = state.draft!;
      final channel = state.currentChannel;

      if (draft.draftId != _lastLoadedDraftId ||
            channel != _lastLoadedChannel ||
            (!state.isEdited && draft.caption != _lastLoadedCaption)) {
         _lastLoadedDraftId = draft.draftId;
         _lastLoadedChannel = channel;
         _lastLoadedCaption = draft.caption;

         if (channel == 'whatsapp') {
            _captionController.text = draft.caption;
         } else {
            final tags = state.hashtags.isNotEmpty
                  ? '\n\n${state.hashtags.join(' ')}'
                  : '';
            _captionController.text = '${draft.caption}$tags';
         }
      }
   }

   @override
   Widget build(BuildContext context) {
      final state = ref.watch(socialMediaProvider(widget.args));
      final notifier = ref.read(socialMediaProvider(widget.args).notifier);
      final sharingService = ref.read(socialSharingServiceProvider);

      _syncCaptionFromState(state);

      return Container(
         constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
         ),
         decoration: const BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
         ),
         child: SafeArea(
            top: false,
            child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                  // Drag handle
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                     child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                           color: AppColors.inkFaint.withValues(alpha: 0.4),
                           borderRadius: BorderRadius.circular(3),
                        ),
                     ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Header bar
                  _buildHeader(context, state),
                  const Divider(height: 1, color: AppColors.line),

                  // Dynamic Step Content
                  Flexible(
                     child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.screenPadding),
                        child: _step == 1
                              ? _buildStep1ChannelSelection(context, state, notifier)
                              : _buildStep2ChannelDetail(
                                    context,
                                    state,
                                    notifier,
                                    sharingService,
                                 ),
                     ),
                  ),
               ],
            ),
         ),
      );
   }

   Widget _buildHeader(BuildContext context, SocialMediaState state) {
      String title;
      if (_step == 1) {
         title = 'social_media_launchpad'.tr(args: [], gender: null);
         if (title == 'social_media_launchpad') {
            title = 'Social Media Launchpad';
         }
      } else {
         switch (state.currentChannel) {
            case 'whatsapp':
               title = 'WhatsApp Share';
               break;
            case 'instagram':
               title = 'Instagram Post';
               break;
            case 'facebook':
               title = 'Facebook Post';
               break;
            default:
               title = 'Social Share';
         }
      }

      return Padding(
         padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: AppSpacing.xs,
         ),
         child: Row(
            children: [
               if (_step == 2)
                  IconButton(
                     icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
                     onPressed: () => setState(() => _step = 1),
                     tooltip: 'back'.tr(),
                  ),
               Expanded(
                  child: Text(
                     title,
                     style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                     ),
                  ),
               ),
               IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.inkSoft),
                  onPressed: () => Navigator.of(context).pop(),
               ),
            ],
         ),
      );
   }

   //        Step 1: Channel Selection                                                                                                                                           

   Widget _buildStep1ChannelSelection(
      BuildContext context,
      SocialMediaState state,
      SocialMediaNotifier notifier,
   ) {
      final title = widget.args.title.isNotEmpty
            ? widget.args.title
            : 'Handcrafted Product';
      final category = widget.args.category.isNotEmpty
            ? widget.args.category
            : 'Craft';

      return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            // Product Summary Banner
            Container(
               padding: const EdgeInsets.all(AppSpacing.sm),
               decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
               ),
               child: Row(
                  children: [
                     ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                           width: 56,
                           height: 56,
                           child: state.selectedImageUrl.isNotEmpty
                                 ? AppImage(
                                       imageUrl: state.selectedImageUrl,
                                       fit: BoxFit.cover,
                                    )
                                 : Container(
                                       color: AppColors.parchmentDeep,
                                       child: const Icon(Icons.image, color: AppColors.inkFaint),
                                    ),
                        ),
                     ),
                     const SizedBox(width: AppSpacing.sm),
                     Expanded(
                        child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                              Text(
                                 title,
                                 style: AppTextStyles.labelLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Container(
                                 padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                 ),
                                 decoration: BoxDecoration(
                                    color: AppColors.terracottaLight.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(6),
                                 ),
                                 child: Text(
                                    category,
                                    style: AppTextStyles.caption.copyWith(
                                       color: AppColors.terracottaDark,
                                       fontWeight: FontWeight.w700,
                                       fontSize: 11,
                                    ),
                                 ),
                              ),
                           ],
                        ),
                     ),
                  ],
               ),
            ),
            const SizedBox(height: AppSpacing.md),

            Text(
               'Select where you want to share:',
               style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
               ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 1. WhatsApp Card
            _buildChannelOptionCard(
               title: 'WhatsApp',
               subtitle: 'Direct 1-tap share with photo and prefilled message',
               brandColor: const Color(0xFF25D366),
               icon: Icons.chat_rounded,
               onTap: () {
                  _lastLoadedDraftId = null;
                  _lastLoadedCaption = null;
                  notifier.selectChannel('whatsapp');
                  setState(() => _step = 2);
               },
            ),
            const SizedBox(height: AppSpacing.sm),

            // 2. Instagram Card
            _buildChannelOptionCard(
               title: 'Instagram',
               subtitle: 'Storytelling caption & hashtags + photo save',
               brandColor: const Color(0xFFE1306C),
               icon: Icons.camera_alt_rounded,
               onTap: () {
                  _lastLoadedDraftId = null;
                  _lastLoadedCaption = null;
                  notifier.selectChannel('instagram');
                  setState(() => _step = 2);
               },
            ),
            const SizedBox(height: AppSpacing.sm),

            // 3. Facebook Card
            _buildChannelOptionCard(
               title: 'Facebook',
               subtitle: 'Community post & hashtags + photo save',
               brandColor: const Color(0xFF1877F2),
               icon: Icons.thumb_up_alt_rounded,
               onTap: () {
                  _lastLoadedDraftId = null;
                  _lastLoadedCaption = null;
                  notifier.selectChannel('facebook');
                  setState(() => _step = 2);
               },
            ),
         ],
      );
   }

   Widget _buildChannelOptionCard({
      required String title,
      required String subtitle,
      required Color brandColor,
      required IconData icon,
      required VoidCallback onTap,
   }) {
      return InkWell(
         onTap: onTap,
         borderRadius: BorderRadius.circular(16),
         child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
               color: AppColors.cardSurface,
               borderRadius: BorderRadius.circular(16),
               border: Border.all(color: AppColors.line),
            ),
            child: Row(
               children: [
                  Container(
                     width: 44,
                     height: 44,
                     decoration: BoxDecoration(
                        color: brandColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                     ),
                     child: Icon(icon, color: brandColor, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                     child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Text(
                              title,
                              style: AppTextStyles.labelLarge.copyWith(
                                 fontWeight: FontWeight.w700,
                                 color: AppColors.ink,
                              ),
                           ),
                           const SizedBox(height: 2),
                           Text(
                              subtitle,
                              style: AppTextStyles.caption.copyWith(
                                 color: AppColors.inkSoft,
                                 fontSize: 12,
                              ),
                           ),
                        ],
                     ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                     Icons.arrow_forward_ios_rounded,
                     size: 14,
                     color: AppColors.inkFaint,
                  ),
               ],
            ),
         ),
      );
   }

   //        Step 2: Channel Detail & Sharing                                                                                                                      

   Widget _buildStep2ChannelDetail(
      BuildContext context,
      SocialMediaState state,
      SocialMediaNotifier notifier,
      SocialSharingService sharingService,
   ) {
      final isWhatsApp = state.currentChannel == 'whatsapp';
      final platformName = isWhatsApp
            ? 'WhatsApp'
            : (state.currentChannel == 'facebook' ? 'Facebook' : 'Instagram');

      return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            // Optional Multi-image Carousel
            if (widget.args.allImages.length > 1) ...[
               SizedBox(
                  height: 60,
                  child: ListView.separated(
                     scrollDirection: Axis.horizontal,
                     itemCount: widget.args.allImages.length,
                     separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                     itemBuilder: (context, index) {
                        final image = widget.args.allImages[index];
                        final selected = image == state.selectedImageUrl;
                        return InkWell(
                           onTap: state.isLoading
                                 ? null
                                 : () => notifier.generateForImage(
                                          image,
                                          channel: state.currentChannel,
                                       ),
                           child: Container(
                              width: 60,
                              decoration: BoxDecoration(
                                 borderRadius: BorderRadius.circular(8),
                                 border: Border.all(
                                    color: selected
                                          ? AppColors.terracotta
                                          : Colors.transparent,
                                    width: 2.5,
                                 ),
                              ),
                              child: ClipRRect(
                                 borderRadius: BorderRadius.circular(6),
                                 child: AppImage(imageUrl: image, fit: BoxFit.cover),
                              ),
                           ),
                        );
                     },
                  ),
               ),
               const SizedBox(height: AppSpacing.sm),
            ],

            // Loading State
            if (state.isLoading) ...[
               const SizedBox(height: 36),
               Center(
                  child: Column(
                     children: [
                        const CircularProgressIndicator(color: AppColors.terracotta),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                           'Generating $platformName caption with AI...',
                           style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.inkSoft,
                           ),
                        ),
                     ],
                  ),
               ),
               const SizedBox(height: 36),
            ] else if (state.errorMessage != null) ...[
               // Error State
               Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                     color: AppColors.cardSurface,
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                     children: [
                        const Icon(
                           Icons.error_outline,
                           color: AppColors.error,
                           size: 32,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                           state.errorMessage!,
                           textAlign: TextAlign.center,
                           style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.ink,
                           ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                           onPressed: () {
                              _lastLoadedCaption = null;
                              notifier.regenerate();
                           },
                           icon: const Icon(Icons.refresh, color: AppColors.terracotta),
                           label: const Text(
                              'Try Again',
                              style: TextStyle(color: AppColors.terracotta),
                           ),
                        ),
                     ],
                  ),
               ),
            ] else if (state.draft != null) ...[
               // Caption Editor Header Row
               Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     Text(
                        isWhatsApp ? 'WhatsApp Message' : 'Caption & Hashtags',
                        style: AppTextStyles.labelLarge.copyWith(
                           fontWeight: FontWeight.w700,
                           color: AppColors.ink,
                        ),
                     ),
                     TextButton.icon(
                        onPressed: state.isLoading || _isActionInProgress
                              ? null
                              : () {
                                    _lastLoadedCaption = null;
                                    notifier.regenerate();
                                 },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Regenerate'),
                        style: TextButton.styleFrom(
                           foregroundColor: AppColors.terracotta,
                           visualDensity: VisualDensity.compact,
                        ),
                     ),
                  ],
               ),
               const SizedBox(height: 4),

               // Caption TextField
               TextField(
                  controller: _captionController,
                  minLines: isWhatsApp ? 3 : 5,
                  maxLines: 8,
                  onChanged: (val) => notifier.updateCaption(val),
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                  decoration: InputDecoration(
                     filled: true,
                     fillColor: AppColors.cardSurface,
                     hintText: 'Craft caption...',
                     border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.line),
                     ),
                     enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.line),
                     ),
                     focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                           color: AppColors.terracotta,
                           width: 1.5,
                        ),
                     ),
                  ),
               ),
               const SizedBox(height: AppSpacing.md),

               //        Platform-Specific Action Buttons                                                                                              
               if (isWhatsApp) ...[
                  // WhatsApp Direct Share Button
                  SizedBox(
                     width: double.infinity,
                     height: 50,
                     child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF25D366),
                           foregroundColor: Colors.white,
                           elevation: 0,
                           shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                           ),
                        ),
                        onPressed: _isActionInProgress
                              ? null
                              : () async {
                                    if (state.isEdited) {
                                       notifier.save();
                                    }
                                    setState(() => _isActionInProgress = true);
                                    try {
                                       await sharingService.shareToWhatsApp(
                                          imagePathOrUrl: state.selectedImageUrl,
                                          caption: _captionController.text,
                                       );
                                    } catch (e) {
                                       if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                             SnackBar(
                                                content: Text('Sharing failed: $e'),
                                             ),
                                          );
                                       }
                                    } finally {
                                       if (mounted) {
                                          setState(() => _isActionInProgress = false);
                                       }
                                    }
                                 },
                        icon: _isActionInProgress
                              ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                       strokeWidth: 2,
                                       color: Colors.white,
                                    ),
                                 )
                              : const Icon(Icons.send_rounded),
                        label: Text(
                           'Share to WhatsApp',
                           style: AppTextStyles.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                           ),
                        ),
                     ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                     child: Text(
                        'Opens WhatsApp with the photo attached and caption pre-filled.',
                        style: AppTextStyles.caption.copyWith(
                           color: AppColors.inkSoft,
                           fontSize: 11.5,
                        ),
                        textAlign: TextAlign.center,
                     ),
                  ),
               ] else ...[
                  // Instagram / Facebook: Copy Caption & Save Image
                  Row(
                     children: [
                        // Copy Button
                        Expanded(
                           child: SizedBox(
                              height: 48,
                              child: OutlinedButton.icon(
                                 style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.terracotta,
                                    side: const BorderSide(color: AppColors.terracotta),
                                    shape: RoundedRectangleBorder(
                                       borderRadius: BorderRadius.circular(12),
                                    ),
                                 ),
                                 onPressed: () async {
                                    if (state.isEdited) {
                                       notifier.save();
                                    }
                                    await Clipboard.setData(
                                       ClipboardData(text: _captionController.text),
                                    );
                                    if (context.mounted) {
                                       ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                             content: Text(
                                                'Caption copied! Don\'t forget to save the photo before you open $platformName.',
                                             ),
                                             duration: const Duration(seconds: 4),
                                          ),
                                       );
                                    }
                                 },
                                 icon: const Icon(Icons.copy_rounded, size: 18),
                                 label: Text(
                                    'Copy Caption',
                                    style: AppTextStyles.labelMedium.copyWith(
                                       fontWeight: FontWeight.w700,
                                       color: AppColors.terracotta,
                                    ),
                                 ),
                              ),
                           ),
                        ),
                        const SizedBox(width: AppSpacing.sm),

                        // Save Image Button
                        Expanded(
                           child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                 style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.terracotta,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                       borderRadius: BorderRadius.circular(12),
                                    ),
                                 ),
                                 onPressed: _isActionInProgress
                                       ? null
                                       : () async {
                                             setState(() => _isActionInProgress = true);
                                             try {
                                                await sharingService.saveImageToGallery(
                                                   state.selectedImageUrl,
                                                );
                                                if (context.mounted) {
                                                   ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                         content: Text('Photo saved to your Gallery!'),
                                                      ),
                                                   );
                                                }
                                             } catch (e) {
                                                if (context.mounted) {
                                                   ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                         content: Text('Could not save photo: $e'),
                                                      ),
                                                   );
                                                }
                                             } finally {
                                                if (mounted) {
                                                   setState(() => _isActionInProgress = false);
                                                }
                                             }
                                          },
                                 icon: _isActionInProgress
                                       ? const SizedBox(
                                             width: 18,
                                             height: 18,
                                             child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                             ),
                                          )
                                       : const Icon(Icons.download_rounded, size: 18),
                                 label: Text(
                                    'Save Image',
                                    style: AppTextStyles.labelMedium.copyWith(
                                       fontWeight: FontWeight.w700,
                                       color: Colors.white,
                                    ),
                                 ),
                              ),
                           ),
                        ),
                     ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Optional App Switch Convenience
                  Center(
                     child: TextButton.icon(
                        onPressed: () => sharingService.openApp(state.currentChannel),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: Text('Open $platformName'),
                        style: TextButton.styleFrom(
                           foregroundColor: AppColors.inkSoft,
                           visualDensity: VisualDensity.compact,
                        ),
                     ),
                  ),
               ],
            ],
         ],
      );
   }
}