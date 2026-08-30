import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/providers/app_providers.dart';

const double _kLowConfidenceThreshold = 0.75;

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
    final isOnline = ref.read(connectivityProvider).value ?? true;
    if (isOnline) {
      String localeCode = 'en';
      try {
        localeCode = context.locale.languageCode;
      } catch (_) {}
      ref.read(addProductFlowProvider.notifier).generateAiListing(localeCode);
    }
    // If offline, we skip generation here — Step 3 will detect there's no
    // listing yet and wait for connectivity to come back on its own.
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

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('describe_title'.tr(), style: AppTextStyles.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'describe_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF7A6E63)),
          ),
          const SizedBox(height: 20),

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
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? const Color(0xFFB34A38) : const Color(0xFFC86D51),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? const Color(0xFFB34A38) : const Color(0xFFC86D51))
                                .withOpacity(0.35),
                            blurRadius: _isRecording ? 18 : 8,
                            spreadRadius: _isRecording ? 6 : 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            size: 42,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isRecording ? 'stop_recording'.tr() : 'tap_to_speak'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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
            const SizedBox(height: 12),
            Text(
              'recording'.tr(),
              style: const TextStyle(
                color: Color(0xFFB34A38),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 20),

          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE2D7C7))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'or_type_description'.tr(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A6E63), fontWeight: FontWeight.w500),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE2D7C7))),
            ],
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _textController,
            maxLines: 4,
            style: const TextStyle(fontSize: 15, color: Color(0xFF3F342B)),
            decoration: InputDecoration(
              hintText: 'type_desc_hint'.tr(),
              labelText: 'transcript_label'.tr(),
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFFFAF7F2),
            ),
            onChanged: (val) {
              ref.read(addProductFlowProvider.notifier).setManualDescription(val);
            },
          ),

          if (draft.voiceTranscript.isNotEmpty && draft.transcriptionConfidence < _kLowConfidenceThreshold) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF4E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6CD9A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFB07D2B), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Some words might need review. You can edit the text above.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5A4D41)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (draft.voiceTranscript.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Replay',
                    type: AppButtonType.outlined,
                    icon: _isPlayingAudio ? Icons.volume_up : Icons.play_arrow,
                    onPressed: _playReplayAudio,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Re-record',
                    type: AppButtonType.secondary,
                    icon: Icons.refresh,
                    onPressed: () {
                      _textController.clear();
                      String localeCode = 'en';
                      try {
                        localeCode = context.locale.languageCode;
                      } catch (_) {}
                      ref.read(addProductFlowProvider.notifier).processVoiceRecording(
                            audioPath: '',
                            languageCode: localeCode,
                          );
                    },
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _onNext,
            icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            label: Text(
              'sounds_right'.tr(),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC86D51),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}