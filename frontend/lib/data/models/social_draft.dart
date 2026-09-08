/// Data model for an AI-generated social-media caption + hashtag draft.
class SocialDraft {
  final String draftId;
  final String caption;
  final List<String> hashtags;

  const SocialDraft({
    required this.draftId,
    required this.caption,
    required this.hashtags,
  });

  factory SocialDraft.fromJson(Map<String, dynamic> json) {
    return SocialDraft(
      draftId: json['draft_id'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      hashtags:
          (json['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'draft_id': draftId,
        'caption': caption,
        'hashtags': hashtags,
      };

  SocialDraft copyWith({
    String? draftId,
    String? caption,
    List<String>? hashtags,
  }) {
    return SocialDraft(
      draftId: draftId ?? this.draftId,
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
    );
  }
}
