import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/services/social_sharing_service.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../providers/social_media_provider.dart';

/// Shows the 2-step Social Media Launchpad bottom sheet with Mehrab scalloped top.
Future<void> showSocialMediaLaunchpadSheet(
   BuildContext context,
   SocialMediaArgs args,
) {
   return showMehrabBottomSheet<void>(
      context: context,
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
      final _ = Localizations.maybeLocaleOf(context);
      final state = ref.watch(socialMediaProvider(widget.args));
      final notifier = ref.read(socialMediaProvider(widget.args).notifier);
      final sharingService = ref.read(socialSharingServiceProvider);

      _syncCaptionFromState(state);

      return Container(
         constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
         ),
         child: SafeArea(
            top: false,
            child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
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

   String _t(
      BuildContext context,
      String key, {
      String? fallbackEn,
      String? fallbackHi,
      Map<String, String>? namedArgs,
   }) {
      final trValue = namedArgs != null ? key.tr(namedArgs: namedArgs) : key.tr();
      if (trValue != key && trValue.isNotEmpty) {
         return trValue;
      }
      final lang = Localizations.localeOf(context).languageCode;
      String text = (lang == 'hi' ? fallbackHi : fallbackEn) ?? fallbackEn ?? key;
      if (namedArgs != null) {
         namedArgs.forEach((k, v) {
            text = text.replaceAll('{$k}', v);
         });
      }
      return text;
   }

   String _resolveCategory(BuildContext context, String rawCategory) {
      if (rawCategory.isEmpty || rawCategory == 'craft_category_handicraft') {
         return _t(
            context,
            'craft_category_handicraft',
            fallbackEn: 'Handicraft',
            fallbackHi: 'हस्तशिल्प',
         );
      }
      final translated = rawCategory.tr();
      if (translated != rawCategory && translated.isNotEmpty) {
         return translated;
      }
      return rawCategory;
   }

   Widget _buildHeader(BuildContext context, SocialMediaState state) {
      String title;
      if (_step == 1) {
         title = _t(context, 'social_media_launchpad', fallbackEn: 'Social Media Launchpad', fallbackHi: 'सोशल मीडिया लॉन्चपैड');
      } else {
         switch (state.currentChannel) {
            case 'whatsapp':
               title = _t(context, 'whatsapp_share_title', fallbackEn: 'Share on WhatsApp', fallbackHi: 'व्हाट्सएप पर साझा करें');
               break;
            case 'instagram':
               title = _t(context, 'instagram_post_title', fallbackEn: 'Post on Instagram', fallbackHi: 'इंस्टाग्राम पर पोस्ट करें');
               break;
            case 'facebook':
               title = _t(context, 'facebook_post_title', fallbackEn: 'Post on Facebook', fallbackHi: 'फेसबुक पर पोस्ट करें');
               break;
            default:
               title = _t(context, 'social_share_title', fallbackEn: 'Social Media Share', fallbackHi: 'सोशल मीडिया शेयर');
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
                     tooltip: _t(context, 'back', fallbackEn: 'Back', fallbackHi: 'वापस'),
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

   // ─── Step 1: Channel Selection ──────────────────────────────────────────────

   Widget _buildStep1ChannelSelection(
      BuildContext context,
      SocialMediaState state,
      SocialMediaNotifier notifier,
   ) {
      final title = widget.args.title.isNotEmpty
            ? widget.args.title
            : _t(
                  context,
                  'handcrafted_product',
                  fallbackEn: 'Handcrafted Product',
                  fallbackHi: 'हस्तनिर्मित उत्पाद',
               );
      final category = _resolveCategory(context, widget.args.category);

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
               _t(context, 'select_share_channel', fallbackEn: 'Select where you want to share:', fallbackHi: 'चुनें कि आप कहाँ साझा करना चाहते हैं:'),
               style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
               ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 1. WhatsApp Card
            _buildChannelOptionCard(
               title: 'WhatsApp',
               subtitle: _t(context, 'whatsapp_channel_desc', fallbackEn: 'Send photo & details directly to customer', fallbackHi: 'ग्राहक को फोटो और विवरण भेजें'),
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
               subtitle: _t(context, 'instagram_channel_desc', fallbackEn: 'Copy caption & tags, save photo to gallery', fallbackHi: 'कैप्शन व हैशटैग कॉपी करें और फोटो सहेजें'),
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
               subtitle: _t(context, 'facebook_channel_desc', fallbackEn: 'Copy post copy & share to your audience', fallbackHi: 'कैप्शन कॉपी करें और पोस्ट साझा करें'),
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
                           _t(
                              context,
                              'generating_caption_ai',
                              fallbackEn: 'Generating {platform} caption with KalaMitra AI...',
                              fallbackHi: 'कला-मित्र AI द्वारा {platform} कैप्शन तैयार किया जा रहा है...',
                              namedArgs: {'platform': platformName},
                           ),
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
                           label: Text(
                              _t(context, 'try_again_btn', fallbackEn: 'Try Again', fallbackHi: 'पुनः प्रयास करें'),
                              style: const TextStyle(color: AppColors.terracotta),
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
                        isWhatsApp ? _t(context, 'whatsapp_message_label', fallbackEn: 'WhatsApp Message', fallbackHi: 'व्हाट्सएप संदेश') : _t(context, 'caption_and_hashtags_label', fallbackEn: 'Caption & Hashtags', fallbackHi: 'कैप्शन और हैशटैग'),
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
                        label: Text(_t(context, 'regenerate_btn', fallbackEn: 'Regenerate', fallbackHi: 'पुनः बनाएं')),
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
                     hintText: _t(context, 'craft_caption_hint', fallbackEn: 'Edit your post caption here...', fallbackHi: 'यहाँ अपना पोस्ट कैप्शन संपादित करें...'),
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

               // ─── Platform-Specific Action Buttons ─────────────────────────
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
                                                content: Text(
                                                   _t(
                                                      context,
                                                      'sharing_failed_snack',
                                                      fallbackEn: 'Could not share: {error}',
                                                      fallbackHi: 'साझा नहीं किया जा सका: {error}',
                                                      namedArgs: {'error': e.toString()},
                                                   ),
                                                ),
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
                           _t(context, 'share_to_whatsapp', fallbackEn: 'Share to WhatsApp', fallbackHi: 'व्हाट्सएप पर शेयर करें'),
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
                        _t(context, 'share_to_whatsapp_sub', fallbackEn: 'KalaSetu does not send messages automatically. WhatsApp will open for you to choose a recipient and confirm.', fallbackHi: 'कलासेतु स्वचालित रूप से संदेश नहीं भेजता है। व्हाट्सएप खुलेगा ताकि आप प्राप्तकर्ता चुन सकें और पुष्टि कर सकें।'),
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
                                                _t(
                                                   context,
                                                   'caption_copied_snack',
                                                   fallbackEn: 'Caption copied! Open {platform} to paste and share.',
                                                   fallbackHi: 'कैप्शन कॉपी हो गया! पेस्ट और शेयर करने के लिए {platform} खोलें।',
                                                   namedArgs: {'platform': platformName},
                                                ),
                                             ),
                                             duration: const Duration(seconds: 4),
                                          ),
                                       );
                                    }
                                 },
                                 icon: const Icon(Icons.copy_rounded, size: 18),
                                 label: Text(
                                    _t(context, 'copy_caption_btn', fallbackEn: 'Copy Caption', fallbackHi: 'कैप्शन कॉपी करें'),
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
                                                      SnackBar(
                                                         content: Text(_t(context, 'photo_saved_snack', fallbackEn: 'Photo saved to your gallery!', fallbackHi: 'फ़ोटो आपकी गैलरी में सहेजी गई!')),
                                                      ),
                                                   );
                                                }
                                             } catch (e) {
                                                if (context.mounted) {
                                                   ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                         content: Text(
                                                            _t(
                                                               context,
                                                               'photo_save_failed_snack',
                                                               fallbackEn: 'Could not save photo: {error}',
                                                               fallbackHi: 'फ़ोटो सहेजी नहीं जा सकी: {error}',
                                                               namedArgs: {'error': e.toString()},
                                                            ),
                                                         ),
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
                                    _t(context, 'save_image_btn', fallbackEn: 'Save Image', fallbackHi: 'फ़ोटो सहेजें'),
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
                        label: Text(
                           _t(
                              context,
                              'open_platform_btn',
                              fallbackEn: 'Open {platform}',
                              fallbackHi: '{platform} खोलें',
                              namedArgs: {'platform': platformName},
                           ),
                        ),
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