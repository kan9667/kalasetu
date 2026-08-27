import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/providers/app_providers.dart';

class Step2DescribeWidget extends ConsumerStatefulWidget {
  const Step2DescribeWidget({super.key});

  @override
  ConsumerState<Step2DescribeWidget> createState() => _Step2DescribeWidgetState();
}

class _Step2DescribeWidgetState extends ConsumerState<Step2DescribeWidget>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  late AnimationController _pulseController;
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording and process STT
      setState(() => _isRecording = false);
      String localeCode = 'en';
      try {
        localeCode = context.locale.languageCode;
      } catch (_) {}
      await ref.read(addProductFlowProvider.notifier).processVoiceRecording(
            audioPath: 'mock_audio_rec.mp3',
            languageCode: localeCode,
          );
      final draft = ref.read(addProductFlowProvider);
      _textController.text = draft.voiceTranscript;
    } else {
      // Start recording
      setState(() => _isRecording = true);
    }
  }

  Future<void> _playReplayAudio() async {
    try {
      setState(() => _isPlayingAudio = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('listening'.tr())),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _isPlayingAudio = false);
    } catch (e) {
      if (mounted) setState(() => _isPlayingAudio = false);
    }
  }

  void _onNext() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(addProductFlowProvider.notifier).setManualDescription(text);
    }
    // Generate AI listing draft before advancing to step 3
    String localeCode = 'en';
    try {
      localeCode = context.locale.languageCode;
    } catch (_) {}
    ref.read(addProductFlowProvider.notifier).generateAiListing(localeCode);
    ref.read(addProductFlowProvider.notifier).nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);

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
                'Transcribing audio & analyzing craft details...',
                style: AppTextStyles.headlineMedium.copyWith(color: AppColors.terracotta),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('describe_title'.tr(), style: AppTextStyles.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'describe_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Tap to Record Mic Button
          Center(
            child: GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _isRecording ? 1.0 + (_pulseController.value * 0.15) : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? AppColors.error : AppColors.terracotta,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? AppColors.error : AppColors.terracotta)
                                .withValues(alpha: 0.4),
                            blurRadius: _isRecording ? 20 : 10,
                            spreadRadius: _isRecording ? 8 : 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            size: 48,
                            color: AppColors.textOnPrimary,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _isRecording ? 'stop_recording'.tr() : 'tap_to_speak'.tr(),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (_isRecording) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'recording'.tr(),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // Side-by-side First-Class Text Input
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  'or_type_description'.tr(),
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          TextField(
            controller: _textController,
            maxLines: 4,
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: 'type_desc_hint'.tr(),
              labelText: 'transcript_label'.tr(),
              alignLabelWithHint: true,
            ),
            onChanged: (val) {
              ref.read(addProductFlowProvider.notifier).setManualDescription(val);
            },
          ),

          if (draft.voiceTranscript.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'replay_audio'.tr(),
                    type: AppButtonType.outlined,
                    icon: _isPlayingAudio ? Icons.volume_up : Icons.play_arrow,
                    onPressed: _playReplayAudio,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: 're_record'.tr(),
                    type: AppButtonType.secondary,
                    icon: Icons.refresh,
                    onPressed: () {
                      _textController.clear();
                      ref.read(addProductFlowProvider.notifier).processVoiceRecording(
                            audioPath: '',
                            languageCode: context.locale.languageCode,
                          );
                    },
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          AppButton(
            label: 'sounds_right'.tr(),
            icon: Icons.arrow_forward,
            onPressed: _onNext,
          ),
        ],
      ),
    );
  }
}
