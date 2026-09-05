import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
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
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      String localeCode = 'hi';
      try {
        localeCode = context.locale.languageCode;
      } catch (_) {}

      // User stopped mic: turn icon to tick first, then transition to replay
      setState(() {
        _isRecording = false;
        _showCheckmark = true;
      });

      final path = await _recorder.stop();
      if (path != null) {
        final audioFile = File(path);
        await ref.read(addProductFlowProvider.notifier).queueVoiceRecording(audioFile);

        // Immediately trigger real voice pipeline transcription in the background
        unawaited(ref.read(addProductFlowProvider.notifier).transcribeVoiceDirectly(
          audioFile,
          languageCode: localeCode,
        ));
      }

      // Show the tick checkmark for 1.2s then transition to replay
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

    // If image is already enhanced or offline or no image, proceed directly
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

    // Advance to Step 3 immediately — the full-screen AI loading screen
    // (driven by draft.isAiProcessing) takes over from here. We no longer
    // show a local spinner on this button first and wait for enhancement
    // to finish before switching screens; enhancement now runs in the
    // background while the full-screen loader is already showing.
    ref.read(addProductFlowProvider.notifier).nextStep();

    try {
      // 1. Await image enhancement from the backend (single request)
      await ref.read(addProductFlowProvider.notifier).enhanceProductImageAndWait();

      // 2. Submit remaining tasks (voice transcription queue / listing draft)
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
                      ? 1.0 + (_pulseController.value * 0.15)
                      : (_showCheckmark ? 1.05 : 1.0);

                  Color circleColor;
                  IconData iconData;
                  String labelText;

                  if (_isRecording) {
                    circleColor = const Color(0xFFB34A38);
                    iconData = Icons.stop_rounded;
                    labelText = 'stop_recording'.tr();
                  } else if (_showCheckmark) {
                    circleColor = const Color(0xFF2E7D32); // Vibrant green tick
                    iconData = Icons.check_circle_rounded;
                    labelText = 'Recorded!';
                  } else if (hasAudio) {
                    circleColor = const Color(0xFF4A3E35); // Artisan deep slate
                    iconData = _isPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded;
                    labelText = _isPlayingAudio ? 'Playing...' : 'Tap to replay';
                  } else {
                    circleColor = const Color(0xFFC86D51); // Terracotta brand
                    iconData = Icons.mic;
                    labelText = 'tap_to_speak'.tr();
                  }

                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: circleColor,
                        boxShadow: [
                          BoxShadow(
                            color: circleColor.withValues(alpha: 0.35),
                            blurRadius: _isRecording ? 18 : 8,
                            spreadRadius: _isRecording ? 6 : 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconData,
                            size: 44,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              labelText,
                              style: const TextStyle(
                                fontSize: 12,
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
              style: const TextStyle(
                color: Color(0xFFB34A38),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          // Re-record button displayed once recording exists
          if (hasAudio && !_isRecording && !_showCheckmark) ...[
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: _rerecord,
                icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFFC86D51)),
                label: const Text(
                  'Re-record voice description',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC86D51),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC86D51)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A6E63),
                    fontWeight: FontWeight.w500,
                  ),
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

          if (draft.voiceTranscript.isNotEmpty &&
              draft.transcriptionConfidence < _kLowConfidenceThreshold) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF4E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6CD9A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB07D2B), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Some words might need review. You can edit the text above.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5A4D41)),
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