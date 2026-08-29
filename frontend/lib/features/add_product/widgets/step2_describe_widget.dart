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
import '../../../core/providers/app_providers.dart';
import '../../../core/offline_sync/models/queue_item.dart';

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
  final AudioRecorder _recorder = AudioRecorder();
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
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording and persist the file through the offline queue.
      setState(() => _isRecording = false);
      final path = await _recorder.stop();
      if (path != null) {
        await ref.read(addProductFlowProvider.notifier).queueVoiceRecording(File(path));
      }
    } else {
      if (!await _recorder.hasPermission()) return;
      final appDir = await getApplicationDocumentsDirectory();
      final recordingDir = Directory('${appDir.path}/offline_sync_recordings');
      await recordingDir.create(recursive: true);
      final path = '${recordingDir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() => _isRecording = true);
    }
  }

  Future<void> _playReplayAudio() async {
    try {
      final draft = ref.read(addProductFlowProvider);
      final localAudioPath = draft.recordedAudioPath;

      if (localAudioPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No recorded audio to replay'.tr())),
        );
        return;
      }

      setState(() => _isPlayingAudio = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('listening'.tr())),
      );

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

  void _onNext() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(addProductFlowProvider.notifier).setManualDescription(text);
    }
    final draft = ref.read(addProductFlowProvider);
    final hasManualDescription = text.isNotEmpty || draft.manualDescription.isNotEmpty;
    final hasRecordedAudio = draft.recordedAudioPath.isNotEmpty;
    final hasTranscript = draft.voiceTranscript.isNotEmpty;
    final voiceReady = hasRecordedAudio || hasTranscript || draft.voiceQueueItemId == null ||
        draft.voiceQueueStatus == QueueStatus.completed;
    if (hasManualDescription || voiceReady) {
      ref.read(addProductFlowProvider.notifier).nextStep();
    }
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
                      ref.read(addProductFlowProvider.notifier).clearVoiceRecording();
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
            onPressed: () {
              final draft = ref.read(addProductFlowProvider);
              final hasManualDescription = _textController.text.trim().isNotEmpty ||
                  draft.manualDescription.isNotEmpty;
              final hasRecordedAudio = draft.recordedAudioPath.isNotEmpty;
              final hasTranscript = draft.voiceTranscript.isNotEmpty;
              final voiceReady = hasRecordedAudio || hasTranscript ||
                  draft.voiceQueueItemId == null || draft.voiceQueueStatus == QueueStatus.completed;
              if (hasManualDescription || voiceReady) {
                _onNext();
              }
            },
          ),
        ],
      ),
    );
  }
}
