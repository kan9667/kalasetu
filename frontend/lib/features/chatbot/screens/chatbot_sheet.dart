import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/speaker_affordance.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../../../data/models/chat_message.dart';
import '../providers/chat_provider.dart';

class ChatbotSheet extends ConsumerStatefulWidget {
  const ChatbotSheet({super.key});

  /// Helper static method to display the Chatbot as a modal bottom sheet with scalloped Mehrab border.
  static Future<void> show(BuildContext context) {
    return showMehrabBottomSheet(
      context: context,
      builder: (context) => const ChatbotSheet(),
    );
  }

  @override
  ConsumerState<ChatbotSheet> createState() => _ChatbotSheetState();
}

class _ChatbotSheetState extends ConsumerState<ChatbotSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Voice recording state (Whisper STT)
  final AudioRecorder _recorder = AudioRecorder();
  late AnimationController _pulseController;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;

  // Repeats a KalaMitra reply on tap. One shared engine for the whole
  // conversation — only one message plays at a time — tracked by message id
  // so the correct bubble's icon reflects playback state.
  final AppTtsService _tts = AppTtsService();
  String? _speakingMessageId;

  /// Any Devanagari character marks the reply as Hindi for voice selection.
  static final RegExp _devanagari = RegExp(r'[ऀ-ॿ]');

  /// Resolves active language across EasyLocalization, UserProfile, and standard Flutter locale.
  String _getLanguage() {
    final easyLocale = EasyLocalization.of(context)?.locale.languageCode;
    if (easyLocale != null && easyLocale.isNotEmpty) {
      return easyLocale;
    }
    final profileLang = ref.read(userProfileProvider).preferredLanguage;
    if (profileLang.isNotEmpty) {
      return profileLang;
    }
    return Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _tts.onStateChanged = () {
      if (!_tts.isSpeaking && mounted) setState(() => _speakingMessageId = null);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final lang = _getLanguage();
        ref.read(chatNotifierProvider.notifier).syncLanguage(lang.isNotEmpty ? lang : 'en');
      }
    });
  }

  Future<void> _speakMessage(ChatMessageModel msg) async {
    if (_speakingMessageId == msg.id) {
      await _tts.stop();
      setState(() => _speakingMessageId = null);
      return;
    }

    final text = msg.text.replaceAll('*', '');

    // KalaMitra answers in the language of the *question*, not the app
    // language — ask in Hindi inside an English-locale app and the reply comes
    // back in Hindi. Picking the voice from the app locale would then read
    // Devanagari with the English voice and produce nothing intelligible, so
    // the script of the reply itself decides.
    final result = await _tts.speak(
      text,
      languageCode: _devanagari.hasMatch(text)
          ? 'hi'
          : context.locale.languageCode,
    );

    if (result == TtsResult.spoke) {
      setState(() => _speakingMessageId = msg.id);
    } else if (result == TtsResult.voiceUnavailable && mounted) {
      final opened = await _tts.openVoiceDownloadScreen();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('voice_download_settings_hint'.tr()),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    _tts.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final langCode = context.locale.languageCode;
    ref.read(chatNotifierProvider.notifier).sendMessage(text, languageCode: langCode);
    _textController.clear();
    _scrollToBottom();
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        final isHi = _getLanguage() == 'hi';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isHi
                  ? 'माइक्रोफ़ोन की अनुमति आवश्यक है।'
                  : 'Microphone permission is required.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final recordingDir = Directory('${appDir.path}/chat_voice_recordings');
      await recordingDir.create(recursive: true);
      final path =
          '${recordingDir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordDuration++;
          });
        }
      });
      _pulseController.repeat(reverse: true);
    } catch (e) {
      debugPrint('[ChatbotSheet] Failed to start voice recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    final langCode = context.locale.languageCode;
    _recordTimer?.cancel();
    _recordTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordDuration = 0;
      });

      if (path != null && path.isNotEmpty) {
        ref.read(chatNotifierProvider.notifier).sendVoiceMessage(
              path,
              languageCode: langCode,
              currentScreen: 'chatbot_sheet',
            );
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('[ChatbotSheet] Error stopping voice recording: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordDuration = 0;
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    try {
      await _recorder.stop();
    } catch (_) {}

    setState(() {
      _isRecording = false;
      _recordDuration = 0;
    });
  }

  void _handleSuggestedTap(String query) {
    final langCode = context.locale.languageCode;
    ref.read(chatNotifierProvider.notifier).sendMessage(query, languageCode: langCode);
    _scrollToBottom();
  }

  IconData _getDestinationIcon(ChatActionModel action) {
    if (action.isStatusUpdate) return Icons.check_circle_rounded;
    if (action.isCatalogueFilter) return Icons.filter_alt_outlined;
    if (action.isSyncPending) return Icons.sync_rounded;
    switch (action.destination) {
      case 'add_product':
        return Icons.add_photo_alternate;
      case 'catalogue':
        return Icons.grid_view;
      case 'my_stats':
        return Icons.bar_chart;
      case 'profile':
        return Icons.person;
      case 'language_settings':
        return Icons.translate;
      case 'notifications':
        return Icons.notifications_outlined;
      case 'social_media':
        return Icons.share;
      default:
        return Icons.arrow_forward;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final isHi = _getLanguage() == 'hi';

    // Auto-scroll on new message
    ref.listen<ChatState>(chatNotifierProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.88,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.cardSurface,
              border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.terracotta.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.terracotta.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/kalamitra_logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.smart_toy_outlined, color: AppColors.terracotta, size: 22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Title & Persona
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'kalamitra_title'.tr(),
                            style: AppTextStyles.headlineSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'AI Guide',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'kalamitra_subtitle'.tr(),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Refresh chat
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.inkSoft, size: 20),
                  tooltip: 'kalamitra_reset'.tr(),
                  onPressed: () {
                    ref.read(chatNotifierProvider.notifier).clearChat(
                      EasyLocalization.of(context)?.locale.languageCode ?? 'en',
                    );
                  },
                ),
                // Close button
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.ink, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // ── Quick Topics Horizontal Bar ───────────────────────────────────
          if (chatState.quickTopics.isNotEmpty)
            Container(
              height: 46,
              color: AppColors.parchmentDeep.withValues(alpha: 0.4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
                itemCount: chatState.quickTopics.length,
                itemBuilder: (context, index) {
                  final topic = chatState.quickTopics[index];
                  final label = (isHi ? topic['label_hi'] : topic['label']) ?? topic['label'] ?? '';
                  final query = (isHi ? topic['query_hi'] : topic['query']) ?? topic['query'] ?? label;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      backgroundColor: AppColors.cardSurface,
                      side: const BorderSide(color: AppColors.line, width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      labelPadding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        label,
                        style: AppTextStyles.labelSmall.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onPressed: () => _handleSuggestedTap(query),
                    ),
                  );
                },
              ),
            ),

          // ── Message History ───────────────────────────────────────────────
          Expanded(
            child: Container(
              color: AppColors.parchment,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == chatState.messages.length && chatState.isLoading) {
                    return _buildTypingIndicator();
                  }

                  final msg = chatState.messages[index];
                  return _buildMessageItem(msg);
                },
              ),
            ),
          ),

          // ── Bottom Input Bar ──────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: 8,
              bottom: 8 + keyboardHeight,
            ),
            decoration: const BoxDecoration(
              color: AppColors.cardSurface,
              border: Border(top: BorderSide(color: AppColors.line, width: 1)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: _isRecording
                  ? _buildRecordingBar(isHi)
                  : Row(
                      children: [
                        // Voice recording button (Whisper STT)
                        _buildMicButton(isHi),
                        const SizedBox(width: AppSpacing.sm),
                        // Text input field
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.parchment,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.line,
                              ),
                            ),
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _handleSend(),
                              decoration: InputDecoration(
                                hintText: 'kalamitra_hint'.tr(),
                                hintStyle: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Send text button
                        Container(
                          decoration: const BoxDecoration(
                            color: AppColors.terracotta,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.send_rounded,
                              color: AppColors.cardSurface,
                              size: 20,
                            ),
                            onPressed: _handleSend,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton(bool isHi) {
    return Tooltip(
      message: isHi ? 'बोलकर पूछें (व्हिस्पर)' : 'Speak your question (Whisper)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _startRecording,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.terracottaLight.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.terracotta.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.mic_none_rounded,
              color: AppColors.terracotta,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar(bool isHi) {
    final minutes = (_recordDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordDuration % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Pulsing Red Recording Dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(
                    alpha: 0.4 + (_pulseController.value * 0.6),
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(
                        alpha: 0.4 * _pulseController.value,
                      ),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          // Timer & Status Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isHi ? 'आवाज़ रिकॉर्ड हो रही है...' : 'Listening to your voice...',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$minutes:$seconds • ${isHi ? "बोलने के बाद टिक दबाएं" : "Tap checkmark when finished"}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Cancel recording
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 22),
            tooltip: isHi ? 'रद्द करें' : 'Cancel',
            onPressed: _cancelRecording,
          ),
          const SizedBox(width: 4),
          // Stop and transcribe / send
          GestureDetector(
            onTap: _stopRecordingAndSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.terracotta,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.cream,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessageModel msg) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.terracotta,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.cardSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant Message
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.terracotta.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/kalamitra_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.terracotta,
                  child: const Center(
                    child: Icon(Icons.smart_toy_outlined, color: AppColors.cardSurface, size: 16),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: AppColors.line),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.text.replaceAll('*', ''),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.normal,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SpeakerAffordance.compact(
                          isSpeaking: _speakingMessageId == msg.id,
                          onTap: () => _speakMessage(msg),
                        ),
                      ),
                      // ── Action Card ───────────────────────────────────────
                      if (msg.action != null) ...[
                        const SizedBox(height: 12),
                        _buildActionCard(msg, msg.action!),
                      ],
                    ],
                  ),
                ),
                // ── Suggested Follow-up Chips ─────────────────────────────
                if (msg.suggestedQueries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: msg.suggestedQueries.map((q) {
                      return InkWell(
                        onTap: () => _handleSuggestedTap(q),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.terracotta.withValues(alpha: 0.35)),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.shadow,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.terracotta),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  q.replaceAll('*', ''),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(ChatMessageModel msg, ChatActionModel action) {
    final isStatus = action.isStatusUpdate;
    final isSync = action.isSyncPending;
    final isFilter = action.isCatalogueFilter;
    final icon = _getDestinationIcon(action);

    final lang = EasyLocalization.of(context)?.locale.languageCode ?? 'en';
    final isHi = lang == 'hi';

    String subtitle;
    if (isStatus) {
      subtitle = action.isUndone
          ? (isHi ? 'स्थिति पहले जैसी कर दी गई' : 'Status restored to previous')
          : (isHi ? 'कैटलॉग में सीधे अपडेट किया गया' : 'Updated directly in your catalogue');
    } else if (isSync) {
      subtitle = action.isExecuted
          ? (isHi ? 'सिंक पूरा हुआ • कैटलॉग देखें' : 'Sync completed • Tap to open catalogue')
          : (isHi ? 'लंबित उत्पाद सिंक करने के लिए टैप करें' : 'Tap to sync pending products now');
    } else if (isFilter) {
      subtitle = isHi ? 'फ़िल्टर किए गए उत्पाद देखने के लिए टैप करें' : 'Tap to view filtered products';
    } else {
      subtitle = isHi ? 'सीधे इस स्क्रीन पर जाने के लिए टैप करें' : 'Tap to jump directly to this screen';
    }

    final bool isSuccessGreen = isStatus && !action.isUndone;

    return Container(
      decoration: BoxDecoration(
        color: isSuccessGreen
            ? AppColors.successLight
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccessGreen
              ? AppColors.success
              : AppColors.terracotta.withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isSuccessGreen ? AppColors.success : AppColors.terracotta).withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(chatNotifierProvider.notifier).executeAction(context, action);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSuccessGreen ? AppColors.success : AppColors.terracotta,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.cardSurface, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.label.replaceAll('*', ''),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSuccessGreen ? AppColors.forestGreenDark : AppColors.terracottaDark,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Show Undo button for status update if not yet undone
                if (isStatus && !action.isUndone && action.updatedProductId != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      ref.read(chatNotifierProvider.notifier).undoProductStatusUpdate(
                            msg.id,
                            action.updatedProductId!,
                            action.previousStatus ?? 'live',
                          );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.terracotta, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.undo_rounded, size: 14, color: AppColors.terracotta),
                          const SizedBox(width: 4),
                          Text(
                            context.locale.languageCode == 'hi' ? 'वापस लें' : 'Undo',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.terracotta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.terracotta),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.terracotta.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/kalamitra_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.terracotta,
                  child: const Center(
                    child: Icon(Icons.smart_toy_outlined, color: AppColors.cream, size: 16),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.oak.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: AppColors.terracotta,
        shape: BoxShape.circle,
      ),
    );
  }
}
