import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/language_picker.dart';
import '../../../data/models/user_profile.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _clusterController = TextEditingController();
  final _experienceController = TextEditingController();
  final _pehchanController = TextEditingController();

  // Bank Details Controllers
  final _bankAccountHolderController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  final _bankIfscController = TextEditingController();
  final _bankNameController = TextEditingController();

  // Pehchan Card Photo Upload
  final ImagePicker _imagePicker = ImagePicker();
  File? _pehchanImageFile;
  bool _isPickingPehchanPhoto = false;

  String _selectedCraft = 'Terracotta Pottery';
  String _selectedState = 'Delhi';
  bool _isHelpCueDismissed = false;

  static const List<String> _craftCategories = [
    'Terracotta Pottery',
    'Handloom & Textiles',
    'Woodwork & Carving',
    'Tribal & Handmade Jewelry',
    'Folk Paintings & Art',
    'Metalcraft & Brassware',
    'Leather & Jutti Craft',
    'Bamboo, Cane & Jute',
    'Stone Carving',
    'Other Craft',
  ];

  static const List<String> _indianStates = [
    'Andhra Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Delhi',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jammu & Kashmir',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Tamil Nadu',
    'Telangana',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Other',
  ];

  final AppTtsService _tts = AppTtsService();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _clusterController.dispose();
    _experienceController.dispose();
    _pehchanController.dispose();
    _bankAccountHolderController.dispose();
    _bankAccountNumberController.dispose();
    _bankIfscController.dispose();
    _bankNameController.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _pickPehchanPhoto(ImageSource source) async {
    setState(() => _isPickingPehchanPhoto = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked != null) {
        setState(() {
          _pehchanImageFile = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('[RegisterScreen] Error picking Pehchan photo: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingPehchanPhoto = false);
      }
    }
  }

  void _removePehchanPhoto() {
    setState(() {
      _pehchanImageFile = null;
    });
  }

  void _handleRegister() {
    if (_formKey.currentState?.validate() ?? false) {
      final phone = _phoneController.text.trim();
      final profile = UserProfile(
        id: '',
        name: _nameController.text.trim(),
        phone: phone,
        craftType: _selectedCraft,
        locationCluster: _clusterController.text.trim(),
        state: _selectedState,
        experienceYears: _experienceController.text.trim().isNotEmpty
            ? _experienceController.text.trim()
            : null,
        pehchanId: _pehchanController.text.trim().isNotEmpty
            ? _pehchanController.text.trim()
            : null,
        preferredLanguage: EasyLocalization.of(context)?.locale.languageCode ?? 'en',
      );

      ref.read(authStateProvider.notifier).registerWithDetails(profile);
      context.pushNamed(
        AppRouteConstants.otp,
        queryParameters: {
          'phone': phone,
          'isNewUser': 'true',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = EasyLocalization.of(context)?.locale;
    final screenPadding = AppSpacing.getScreenPadding(context);
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 480;

    return AppScaffold(
      showConnectivityPill: false,
      rawAppBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(AppRouteConstants.signIn);
            }
          },
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: LanguagePicker(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Banner Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.terracotta.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: AppColors.terracotta.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: const BoxDecoration(
                          color: AppColors.terracotta,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1,
                          color: AppColors.textOnPrimary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'register_title'.tr(),
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: AppColors.terracotta,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'register_subtitle'.tr(),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (!_isHelpCueDismissed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.cardSurface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.support_agent,
                            color: AppColors.terracottaDark,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: InkWell(
                            onTap: () => context.pushNamed(AppRouteConstants.ngoAuth),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'registration_help_cue_title'.tr(),
                                          style: AppTextStyles.labelMedium.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12,
                                        color: AppColors.inkSoft,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'registration_help_cue_body'.tr(),
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.inkSoft,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        // TTS affordance button — the help text is already
                        // translated in 4 languages; this was only ever
                        // showing it back as a snackbar, never actually
                        // speaking it.
                        IconButton(
                          icon: Icon(
                            _tts.isSpeaking
                                ? Icons.stop_circle_outlined
                                : Icons.volume_up_outlined,
                            size: 20,
                            color: AppColors.terracotta,
                          ),
                          tooltip: _tts.isSpeaking ? 'stop_audio'.tr() : 'tap_to_hear'.tr(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () async {
                            if (_tts.isSpeaking) {
                              await _tts.stop();
                              if (mounted) setState(() {});
                              return;
                            }
                            // The on-screen cue only says "ask someone to help
                            // you". Spoken, that is a dead end — so the read-
                            // back walks through which fields are required and
                            // which can be skipped, and keeps the ask-for-help
                            // line as the closing fallback.
                            final helpText = 'registration_help_cue_body'.tr();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(helpText),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            final result = await _tts.speak(
                              TtsPageGuides.register
                                  .forLanguage(context.locale.languageCode),
                              languageCode: context.locale.languageCode,
                            );
                            if (mounted) setState(() {});
                            if (result == TtsResult.voiceUnavailable && mounted) {
                              await _tts.openVoiceDownloadScreen();
                            }
                          },
                        ),
                        // Dismiss button
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.inkSoft,
                          ),
                          tooltip: 'Dismiss',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            setState(() => _isHelpCueDismissed = true);
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // 1. Full Name
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: '${'full_name_label'.tr()} *',
                    hintText: 'full_name_hint'.tr(),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'full_name_required'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // 2. Phone Number
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: InputDecoration(
                    labelText: '${'phone_label'.tr()} *',
                    hintText: 'phone_hint'.tr(),
                    prefixIcon: const Icon(Icons.phone_outlined),
                    prefixText: '+91 ',
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'phone_required'.tr();
                    }
                    if (value.trim().length < 10) {
                      return 'phone_invalid'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // 3. Primary Craft Type Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedCraft,
                  decoration: InputDecoration(
                    labelText: '${'craft_type_label'.tr()} *',
                    prefixIcon: const Icon(Icons.palette_outlined),
                  ),
                  items: _craftCategories.map((craft) {
                    return DropdownMenuItem<String>(
                      value: craft,
                      child: Text(
                        craft,
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCraft = val);
                    }
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // 4. Cluster / Town Location
                TextFormField(
                  controller: _clusterController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: '${'cluster_location_label'.tr()} *',
                    hintText: 'cluster_location_hint'.tr(),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'cluster_location_required'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // 5. State Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedState,
                  decoration: InputDecoration(
                    labelText: '${'state_label'.tr()} *',
                    prefixIcon: const Icon(Icons.map_outlined),
                  ),
                  items: _indianStates.map((stateName) {
                    return DropdownMenuItem<String>(
                      value: stateName,
                      child: Text(
                        stateName,
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedState = val);
                    }
                  },
                ),

                const SizedBox(height: AppSpacing.md),

                // 6. Experience in Years (Optional)
                TextFormField(
                  controller: _experienceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'experience_label'.tr(),
                    hintText: 'experience_hint'.tr(),
                    prefixIcon: const Icon(Icons.history_edu_outlined),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // 7. Pehchan ID / Artisan Card Section (Optional)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.line),
                    boxShadow: AppElevation.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.terracotta.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.terracotta,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'pehchan_id_label'.tr(),
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: AppColors.terracotta,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      // Helper-note banner (pink/terracotta banner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.terracotta.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(
                            color: AppColors.terracotta.withValues(alpha: 0.2),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppColors.cardSurface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.card_membership_outlined,
                                color: AppColors.terracottaDark,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${'pehchan_id_desc'.tr()} ${'pehchan_photo_desc'.tr()}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.inkSoft,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Text input for Pehchan ID
                      TextFormField(
                        controller: _pehchanController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'pehchan_id_label'.tr(),
                          hintText: 'pehchan_id_hint'.tr(),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Photo capture/upload section
                      if (_pehchanImageFile == null)
                        DottedBorderBox(
                          width: double.infinity,
                          backgroundColor: AppColors.parchmentDeep.withValues(alpha: 0.5),
                          radius: AppRadii.card,
                          borderColor: AppColors.dottedBorder,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: AppColors.cardSurface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 18,
                                      color: AppColors.terracotta,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      'pehchan_photo_label'.tr(),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      label: 'take_photo'.tr(),
                                      icon: Icons.camera_alt,
                                      type: AppButtonType.outlined,
                                      isCompact: true,
                                      isLoading: _isPickingPehchanPhoto,
                                      onPressed: () => _pickPehchanPhoto(ImageSource.camera),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: AppButton(
                                      label: 'upload_gallery'.tr(),
                                      icon: Icons.photo_library,
                                      type: AppButtonType.outlined,
                                      isCompact: true,
                                      isLoading: _isPickingPehchanPhoto,
                                      onPressed: () => _pickPehchanPhoto(ImageSource.gallery),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.parchmentDeep.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                                child: SizedBox(
                                  height: 140,
                                  width: double.infinity,
                                  child: Image.file(
                                    _pehchanImageFile!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppColors.terracotta,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'pehchan_photo_attached'.tr(),
                                      style: AppTextStyles.labelMedium.copyWith(
                                        color: AppColors.ink,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _pickPehchanPhoto(ImageSource.camera),
                                    icon: const Icon(Icons.refresh, size: 16, color: AppColors.terracotta),
                                    label: Text(
                                      'change_photo'.tr(),
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.terracotta,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.inkSoft),
                                    tooltip: 'remove_photo'.tr(),
                                    onPressed: _removePehchanPhoto,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // 8. Bank Details Section (Optional)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.line),
                    boxShadow: AppElevation.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.terracotta.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_outlined,
                              color: AppColors.terracotta,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'bank_details_title'.tr(),
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    color: AppColors.terracotta,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'bank_details_subtitle'.tr(),
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      // Helper-note banner (yellow/gold banner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.goldLight,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppColors.cardSurface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                color: AppColors.goldDark,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'bank_details_desc'.tr(),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.inkSoft,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 1. Account Holder Name
                      TextFormField(
                        controller: _bankAccountHolderController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'bank_account_holder_label'.tr(),
                          hintText: 'bank_account_holder_hint'.tr(),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 2. Account Number
                      TextFormField(
                        controller: _bankAccountNumberController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'bank_account_number_label'.tr(),
                          hintText: 'bank_account_number_hint'.tr(),
                          prefixIcon: const Icon(Icons.pin_outlined),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 3. IFSC Code
                      TextFormField(
                        controller: _bankIfscController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'bank_ifsc_label'.tr(),
                          hintText: 'bank_ifsc_hint'.tr(),
                          prefixIcon: const Icon(Icons.confirmation_number_outlined),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 4. Bank Name
                      TextFormField(
                        controller: _bankNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'bank_name_label'.tr(),
                          hintText: 'bank_name_hint'.tr(),
                          prefixIcon: const Icon(Icons.account_balance_outlined),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Submit Button
                AppButton(
                  label: 'create_account_btn'.tr(),
                  icon: Icons.how_to_reg,
                  onPressed: _handleRegister,
                  isCompact: isCompact,
                ),

                const SizedBox(height: AppSpacing.md),

                // Sign In Link
                Center(
                  child: TextButton(
                    onPressed: () {
                      context.goNamed(AppRouteConstants.signIn);
                    },
                    child: Text(
                      'sign_in_link_btn'.tr(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.terracotta,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}