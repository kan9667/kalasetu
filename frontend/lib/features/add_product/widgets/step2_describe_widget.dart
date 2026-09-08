import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cycling_guidance_cue.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/offline_sync/models/queue_item.dart';

const double _kLowConfidenceThreshold = 0.75;

class Step2DescribeWidget extends ConsumerStatefulWidget {
  const Step2DescribeWidget({super.key});

  @override
  ConsumerState<Step2DescribeWidget> createState() => _Step2DescribeWidgetState();
}

class _Step2DescribeWidgetState extends ConsumerState<Step2DescribeWidget>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _showCheckmark = false;
  late AnimationController _pulseController;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _textFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    final draft = ref.read(addProductFlowProvider);
    if (draft.voiceTranscript.isNotEmpty) {
      _textController.text = draft.voiceTranscript;
    } else if (draft.manualDescription.isNotEmpty) {
      _textController.text = draft.manualDescription;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _showCheckmark = true;
      });

      final path = await _recorder.stop();
      if (path != null) {
        final audioFile = File(path);
        await ref.read(addProductFlowProvider.notifier).queueVoiceRecording(audioFile);

        // Immediately trigger real voice pipeline transcription in the background with language auto-detection
        unawaited(ref.read(addProductFlowProvider.notifier).transcribeVoiceDirectly(
          audioFile,
          languageCode: 'auto',
        ));
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        setState(() {
          _showCheckmark = false;
        });
      }
    } else {
      if (_isPlayingAudio) {
        await _audioPlayer.stop();
        setState(() => _isPlayingAudio = false);
      }
      if (!await _recorder.hasPermission()) return;
      final appDir = await getApplicationDocumentsDirectory();
      final recordingDir = Directory('${appDir.path}/offline_sync_recordings');
      await recordingDir.create(recursive: true);
      final path = '${recordingDir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _showCheckmark = false;
      });
    }
  }

  Future<void> _togglePlayAudio() async {
    try {
      final draft = ref.read(addProductFlowProvider);
      final localAudioPath = draft.recordedAudioPath;

      if (localAudioPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No recorded audio to replay'.tr())),
        );
        return;
      }

      if (_isPlayingAudio) {
        await _audioPlayer.stop();
        setState(() => _isPlayingAudio = false);
        return;
      }

      setState(() => _isPlayingAudio = true);

      final player = _audioPlayer;
      await player.setFilePath(localAudioPath);
      await player.play();
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _isPlayingAudio = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isPlayingAudio = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to play recording: $e')),
        );
      }
    }
  }

  List<GuidanceCue> get _describeCues => [
    GuidanceCue(
      text: 'describe_cue_1'.tr(),
      icon: Icons.mic_none_outlined,
    ),
    GuidanceCue(
      text: 'describe_cue_2'.tr(),
      icon: Icons.texture_rounded,
    ),
    GuidanceCue(
      text: 'describe_cue_3'.tr(),
      icon: Icons.handyman_outlined,
    ),
    GuidanceCue(
      text: 'describe_cue_4'.tr(),
      icon: Icons.scale_outlined,
    ),
    GuidanceCue(
      text: 'describe_cue_5'.tr(),
      icon: Icons.auto_stories_outlined,
    ),
  ];

  Future<void> _rerecord() async {
    if (_isPlayingAudio) {
      await _audioPlayer.stop();
      setState(() => _isPlayingAudio = false);
    }
    _textController.clear();
    setState(() {
      _showCheckmark = false;
      _isRecording = false;
    });
    ref.read(addProductFlowProvider.notifier).clearVoiceRecording();
  }

  Future<void> _onNext() async {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(addProductFlowProvider.notifier).setManualDescription(text);
    }
    final isOnline = ref.read(connectivityProvider).value ?? true;
    String localeCode = 'en';
    try {
      localeCode = context.locale.languageCode;
    } catch (_) {}

    final draft = ref.read(addProductFlowProvider);

    if (!isOnline ||
        draft.originalImagePath.isEmpty ||
        (draft.isEnhanced &&
            draft.enhancedImagePath.isNotEmpty &&
            draft.enhancedImagePath != draft.originalImagePath)) {
      ref.read(addProductFlowProvider.notifier).submitForAiProcessing(
        isOnline,
        languageCode: localeCode,
      );
      ref.read(addProductFlowProvider.notifier).nextStep();
      return;
    }

    ref.read(addProductFlowProvider.notifier).nextStep();

    try {
      await ref.read(addProductFlowProvider.notifier).enhanceProductImageAndWait();
      ref.read(addProductFlowProvider.notifier).submitForAiProcessing(
        isOnline,
        languageCode: localeCode,
      );
    } catch (e) {
      debugPrint('[Step2] Error waiting for image enhancement: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AddProductDraft>(addProductFlowProvider, (previous, next) {
      if (next.voiceTranscript.isNotEmpty &&
          (previous == null || previous.voiceTranscript != next.voiceTranscript)) {
        _textController.text = next.voiceTranscript;
      }
    });

    final draft = ref.watch(addProductFlowProvider);
    final hasAudio = draft.recordedAudioPath.isNotEmpty;

    if (_textController.text.isEmpty && draft.voiceTranscript.isNotEmpty) {
      _textController.text = draft.voiceTranscript;
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('describe_title'.tr(), style: AppTextStyles.headlineLarge),
          const SizedBox(height: 4),
          Text(
            'describe_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),

          // Central interactive recording / check / replay circle
          Center(
            child: GestureDetector(
              onTap: () {
                if (_isRecording) {
                  _toggleRecording();
                } else if (_showCheckmark) {
                  // Transitioning
                } else if (hasAudio) {
                  _togglePlayAudio();
                } else {
                  _toggleRecording();
                }
              },
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _isRecording
                      ? 1.0 + (_pulseController.value * 0.12)
                      : (_showCheckmark ? 1.05 : 1.0);

                  Color circleColor;
                  Color shadowColor;
                  IconData iconData;
                  String labelText;

                  if (_isRecording) {
                    circleColor = AppColors.error;
                    shadowColor = AppColors.error;
                    iconData = Icons.stop_rounded;
                    labelText = 'stop_recording'.tr();
                  } else if (_showCheckmark) {
                    circleColor = AppColors.success;
                    shadowColor = AppColors.successLight;
                    iconData = Icons.check_circle_rounded;
                    labelText = 'recorded_success'.tr();
                  } else if (hasAudio) {
                    circleColor = AppColors.ink;
                    shadowColor = AppColors.inkFaint;
                    iconData = _isPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded;
                    labelText = _isPlayingAudio ? 'audio_playing'.tr() : 'tap_to_replay'.tr();
                  } else {
                    circleColor = AppColors.terracotta;
                    shadowColor = AppColors.terracottaLight;
                    iconData = Icons.mic;
                    labelText = 'tap_to_speak'.tr();
                  }

                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: circleColor,
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor.withValues(alpha: 0.4),
                            blurRadius: _isRecording ? 20 : 10,
                            spreadRadius: _isRecording ? 6 : 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconData,
                            size: 42,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              labelText,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          if (hasAudio && !_isRecording && !_showCheckmark) ...[
            const SizedBox(height: 16),
            Center(
              child: AppButton(
                label: 'rerecord_voice_desc'.tr(),
                icon: Icons.refresh_rounded,
                type: AppButtonType.outlined,
                onPressed: _rerecord,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Divider with "or type description" label
          Row(
            children: [
              const Expanded(child: DottedBorderBox.divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'or_type_description'.tr(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Expanded(child: DottedBorderBox.divider()),
            ],
          ),

          const SizedBox(height: 16),

          // Guidance prompt cycling cues
          CyclingGuidanceCue(
            headerTitle: 'what_to_mention'.tr().toUpperCase(),
            headerIcon: Icons.lightbulb_outline,
            spokenIntro: 'step2_tts_intro'.tr(),
            cues: _describeCues,
            isPaused: _isRecording || _isPlayingAudio || _textFocusNode.hasFocus,
            onCueChanged: (cue) {},
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            maxLines: 4,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'type_desc_hint'.tr(),
              labelText: 'transcript_label'.tr(),
              labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                borderSide: const BorderSide(color: AppColors.terracotta, width: 1.5),
              ),
              filled: true,
              fillColor: AppColors.cardSurface,
            ),
            onChanged: (val) {
              ref.read(addProductFlowProvider.notifier).setManualDescription(val);
            },
          ),

          if (draft.voiceTranscript.isNotEmpty &&
              draft.transcriptionConfidence < _kLowConfidenceThreshold) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.goldLight,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.goldDark, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Some words might need review. You can edit the text above.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.goldDark),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          AppButton(
            label: 'sounds_right'.tr(),
            icon: Icons.arrow_forward,
            onPressed: () {
              final currentDraft = ref.read(addProductFlowProvider);
              final hasManualDescription = _textController.text.trim().isNotEmpty ||
                  currentDraft.manualDescription.isNotEmpty;
              final hasRecordedAudio = currentDraft.recordedAudioPath.isNotEmpty;
              final hasTranscript = currentDraft.voiceTranscript.isNotEmpty;
              final voiceReady = hasRecordedAudio ||
                  hasTranscript ||
                  currentDraft.voiceQueueItemId == null ||
                  currentDraft.voiceQueueStatus == QueueStatus.completed;
              if (hasManualDescription || voiceReady) {
                _onNext();
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}