import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/social_draft.dart';
import '../../../data/services/social_media_service.dart';

class SocialMediaArgs {
  final String? listingId;
  final String? draftKey;
  final String source;
  final List<String> allImages;
  final String title;
  final String category;
  final List<String> materials;
  final String description;

  const SocialMediaArgs({
    this.listingId,
    this.draftKey,
    required this.source,
    required this.allImages,
    this.title = '',
    this.category = '',
    this.materials = const [],
    this.description = '',
  });
}

class SocialMediaState {
  final String selectedImageUrl;
  final SocialDraft? draft;
  final List<String> hashtags;
  final bool isLoading;
  final bool isSaving;
  final bool isEdited;
  final String? errorMessage;

  const SocialMediaState({
    this.selectedImageUrl = '',
    this.draft,
    this.hashtags = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isEdited = false,
    this.errorMessage,
  });

  SocialMediaState copyWith({
    String? selectedImageUrl,
    SocialDraft? draft,
    List<String>? hashtags,
    bool? isLoading,
    bool? isSaving,
    bool? isEdited,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SocialMediaState(
      selectedImageUrl: selectedImageUrl ?? this.selectedImageUrl,
      draft: draft ?? this.draft,
      hashtags: hashtags ?? this.hashtags,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isEdited: isEdited ?? this.isEdited,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final socialMediaServiceProvider = Provider<SocialMediaService>((ref) {
  return HttpSocialMediaService();
});

final socialMediaProvider = StateNotifierProvider.family<
    SocialMediaNotifier, SocialMediaState, SocialMediaArgs>((ref, args) {
  return SocialMediaNotifier(ref.watch(socialMediaServiceProvider), args);
});

class SocialMediaNotifier extends StateNotifier<SocialMediaState> {
  final SocialMediaService _service;
  final SocialMediaArgs args;

  SocialMediaNotifier(this._service, this.args)
      : super(SocialMediaState(
          selectedImageUrl: args.allImages.isEmpty ? '' : args.allImages.first,
        )) {
    if (state.selectedImageUrl.isNotEmpty) {
      _loadOrGenerate(state.selectedImageUrl);
    }
  }

  Future<void> _loadOrGenerate(String imageUrl) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final normalizedImageUrl = await _normalizeImage(imageUrl);
      try {
        final saved = await _service.loadDraftForImage(
          listingId: args.listingId,
          draftKey: args.draftKey,
          imageUrl: normalizedImageUrl,
        );
        if (saved != null) {
          state = state.copyWith(
            selectedImageUrl: normalizedImageUrl,
            draft: saved,
            hashtags: saved.hashtags,
            isLoading: false,
            isEdited: false,
            clearError: true,
          );
          return;
        }
      } catch (_) {
        // A lookup failure should not prevent first-time generation.
      }
      await generateForImage(normalizedImageUrl);
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(error));
    }
  }

  Future<String> _normalizeImage(String imageUrl) async {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    if (File(imageUrl).existsSync()) {
      return _service.uploadImage(imageUrl);
    }
    return imageUrl;
  }

  Future<void> generateForImage(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    final normalizedImageUrl = await _normalizeImage(imageUrl);
    state = state.copyWith(selectedImageUrl: normalizedImageUrl, isLoading: true, clearError: true);
    try {
      final draft = args.listingId != null
          ? await _service.generateForListing(
              listingId: args.listingId!,
              imageUrl: normalizedImageUrl,
              title: args.title,
              category: args.category,
              materials: args.materials,
              description: args.description,
              source: args.source,
            )
          : await _service.generateForDraft(
              draftKey: args.draftKey ?? '',
              imageUrl: normalizedImageUrl,
              title: args.title,
              category: args.category,
              materials: args.materials,
              description: args.description,
            );
      state = state.copyWith(
        draft: draft,
        hashtags: draft.hashtags,
        isLoading: false,
        isEdited: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(error));
    }
  }

  void updateCaption(String caption) {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(draft: draft.copyWith(caption: caption), isEdited: true);
  }

  void removeHashtag(String hashtag) {
    updateHashtags(state.hashtags.where((tag) => tag != hashtag).toList());
  }

  void addHashtag(String hashtag) {
    final normalized = hashtag.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return;
    final tag = normalized.startsWith('#') ? normalized : '#$normalized';
    if (!state.hashtags.contains(tag)) updateHashtags([...state.hashtags, tag]);
  }

  void updateHashtags(List<String> hashtags) {
    state = state.copyWith(hashtags: hashtags, isEdited: true);
  }

  Future<void> regenerate() => generateForImage(state.selectedImageUrl);

  Future<bool> save() async {
    final draft = state.draft;
    if (draft == null) return false;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final saved = await _service.saveDraft(
        draftId: draft.draftId,
        caption: draft.caption,
        hashtags: state.hashtags,
        editedByUser: state.isEdited,
      );
      state = state.copyWith(draft: saved, isSaving: false, isEdited: false);
      return true;
    } catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: _messageFor(error));
      return false;
    }
  }

  Future<void> copyToClipboard() async {
    final draft = state.draft;
    if (draft == null) return;
    await Clipboard.setData(ClipboardData(text: '${draft.caption}\n\n${state.hashtags.join(' ')}'));
  }

  String _messageFor(Object error) {
    if (error is SocialMediaRateLimitException) return error.message;
    if (error is SocialMediaGenerationException) return error.message;
    if (error is SocialMediaNetworkException) return error.message;
    return 'Unable to generate this draft. Please try again.';
  }
}