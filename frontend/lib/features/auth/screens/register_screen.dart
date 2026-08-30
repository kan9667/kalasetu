import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
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

  String _selectedCraft = 'Terracotta Pottery';
  String _selectedState = 'Delhi';

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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _clusterController.dispose();
    _experienceController.dispose();
    _pehchanController.dispose();
    super.dispose();
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
        preferredLanguage: context.locale.languageCode,
      );

      ref.read(authStateProvider.notifier).registerWithDetails(profile);
      context.goNamed(
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
        title: Text(
          'register_title'.tr(),
          style: AppTextStyles.headlineMedium,
        ),
        centerTitle: true,
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
                        decoration: BoxDecoration(
                          color: AppColors.terracotta,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1,
                          color: Colors.white,
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

                // 7. Pehchan ID / Artisan Card (Optional)
                TextFormField(
                  controller: _pehchanController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'pehchan_id_label'.tr(),
                    hintText: 'pehchan_id_hint'.tr(),
                    prefixIcon: const Icon(Icons.verified_user_outlined),
                    helperText: 'pehchan_id_desc'.tr(),
                    helperMaxLines: 2,
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
