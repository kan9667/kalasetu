import 'package:hive/hive.dart';

part 'product.g.dart';

@HiveType(typeId: 1)
enum ProductStatus {
  @HiveField(0)
  live,
  @HiveField(1)
  pendingSync,
  @HiveField(2)
  draft,
  @HiveField(3)
  sold,
  @HiveField(4)
  soldOut,
  @HiveField(5)
  listingRemoved,
  @HiveField(6)
  awaitingApproval,
  @HiveField(7)
  approved,
  @HiveField(8)
  published,
  @HiveField(9)
  superseded,
  @HiveField(10)
  rejected,
  @HiveField(11)
  legacyUnverified,
  @HiveField(12)
  pendingApprovalSync,
  @HiveField(13)
  pendingUnpublishSync,
}

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String titleHi;

  @HiveField(3)
  final String description;

  @HiveField(4)
  final String descriptionHi;

  @HiveField(5)
  final double price;

  /// The primary photo — the first one captured, or the AI-enhanced
  /// version of it once available. Local file path (camera/gallery),
  /// not a network URL.
  @HiveField(6)
  final String photoPath;

  @HiveField(7)
  final String category;

  @HiveField(8)
  final List<String> tags;

  @HiveField(9)
  final ProductStatus status;

  @HiveField(10)
  final DateTime createdAt;

  /// Up to 2 additional angles beyond [photoPath] — spec allows 3 photos
  /// total per listing.
  @HiveField(11)
  final List<String> additionalPhotoPaths;

  /// Set once ImageEnhancementService.enhance() has run on [photoPath].
  /// Empty string means "not enhanced yet" — display falls back to
  /// [photoPath] in that case.
  @HiveField(12)
  final String aiEnhancedPhotoPath;

  /// Timestamp of the last status update (e.g. marked sold out, removed listing, relisted)
  @HiveField(13)
  final DateTime? statusUpdatedAt;

  /// Optional restock quantity entered when an item was marked sold out
  @HiveField(14)
  final int? restockQuantity;

  /// Context or note for the current status change
  @HiveField(15)
  final String? statusReason;

  @HiveField(16)
  final int revision;

  @HiveField(17)
  final int? approvedRevision;

  @HiveField(18)
  final DateTime? approvedAt;

  @HiveField(19)
  final String? approvedByArtisanId;

  @HiveField(20)
  final DateTime? publishedAt;

  @HiveField(21)
  final String? contentHash;

  @HiveField(22)
  final String? mediaId;

  @HiveField(23)
  final double? floorPrice;

  @HiveField(24)
  final double? materialsCost;

  @HiveField(25)
  final double? laborHours;

  @HiveField(26)
  final double? hourlyRate;

  @HiveField(27)
  final double? transportCost;

  @HiveField(28)
  final double? otherOverhead;

  Product({
    required this.id,
    required this.title,
    this.titleHi = '',
    required this.description,
    this.descriptionHi = '',
    required this.price,
    required this.photoPath,
    required this.category,
    this.tags = const [],
    this.status = ProductStatus.draft,
    DateTime? createdAt,
    this.additionalPhotoPaths = const [],
    this.aiEnhancedPhotoPath = '',
    this.statusUpdatedAt,
    this.restockQuantity,
    this.statusReason,
    this.revision = 1,
    this.approvedRevision,
    this.approvedAt,
    this.approvedByArtisanId,
    this.publishedAt,
    this.contentHash,
    this.mediaId,
    this.floorPrice,
    this.materialsCost,
    this.laborHours,
    this.hourlyRate,
    this.transportCost,
    this.otherOverhead,
  }) : createdAt = createdAt ?? DateTime.now();

  /// All captured photos in order (primary first), for the review screen's
  /// thumbnail strip. Skips empty entries.
  List<String> get allPhotoPaths =>
      [photoPath, ...additionalPhotoPaths].where((p) => p.isNotEmpty).toList();

  /// What should actually be displayed — the enhanced photo if we have one,
  /// otherwise the original capture.
  String get displayPhotoPath =>
      aiEnhancedPhotoPath.isNotEmpty ? aiEnhancedPhotoPath : photoPath;

  bool get isPublished =>
      status == ProductStatus.published || status == ProductStatus.live;

  bool get isNonLive =>
      status == ProductStatus.soldOut ||
      status == ProductStatus.listingRemoved ||
      status == ProductStatus.sold;

  Product copyWith({
    String? id,
    String? title,
    String? titleHi,
    String? description,
    String? descriptionHi,
    double? price,
    String? photoPath,
    String? category,
    List<String>? tags,
    ProductStatus? status,
    DateTime? createdAt,
    List<String>? additionalPhotoPaths,
    String? aiEnhancedPhotoPath,
    DateTime? statusUpdatedAt,
    int? restockQuantity,
    String? statusReason,
    int? revision,
    int? approvedRevision,
    DateTime? approvedAt,
    String? approvedByArtisanId,
    DateTime? publishedAt,
    String? contentHash,
    String? mediaId,
    double? floorPrice,
    double? materialsCost,
    double? laborHours,
    double? hourlyRate,
    double? transportCost,
    double? otherOverhead,
    bool clearApprovalMetadata = false,
  }) {
    return Product(
      id: id ?? this.id,
      title: title ?? this.title,
      titleHi: titleHi ?? this.titleHi,
      description: description ?? this.description,
      descriptionHi: descriptionHi ?? this.descriptionHi,
      price: price ?? this.price,
      photoPath: photoPath ?? this.photoPath,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      additionalPhotoPaths: additionalPhotoPaths ?? this.additionalPhotoPaths,
      aiEnhancedPhotoPath: aiEnhancedPhotoPath ?? this.aiEnhancedPhotoPath,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      restockQuantity: restockQuantity ?? this.restockQuantity,
      statusReason: statusReason ?? this.statusReason,
      revision: revision ?? this.revision,
      approvedRevision: clearApprovalMetadata ? null : (approvedRevision ?? this.approvedRevision),
      approvedAt: clearApprovalMetadata ? null : (approvedAt ?? this.approvedAt),
      approvedByArtisanId: clearApprovalMetadata ? null : (approvedByArtisanId ?? this.approvedByArtisanId),
      publishedAt: clearApprovalMetadata ? null : (publishedAt ?? this.publishedAt),
      contentHash: contentHash ?? this.contentHash,
      mediaId: mediaId ?? this.mediaId,
      floorPrice: floorPrice ?? this.floorPrice,
      materialsCost: materialsCost ?? this.materialsCost,
      laborHours: laborHours ?? this.laborHours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      transportCost: transportCost ?? this.transportCost,
      otherOverhead: otherOverhead ?? this.otherOverhead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'titleHi': titleHi,
      'description': description,
      'descriptionHi': descriptionHi,
      'price': price,
      'photoPath': photoPath,
      'category': category,
      'tags': tags,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'additionalPhotoPaths': additionalPhotoPaths,
      'aiEnhancedPhotoPath': aiEnhancedPhotoPath,
      'statusUpdatedAt': statusUpdatedAt?.toIso8601String(),
      'restockQuantity': restockQuantity,
      'statusReason': statusReason,
      'revision': revision,
      'approvedRevision': approvedRevision,
      'approvedAt': approvedAt?.toIso8601String(),
      'approvedByArtisanId': approvedByArtisanId,
      'publishedAt': publishedAt?.toIso8601String(),
      'contentHash': contentHash,
      'mediaId': mediaId,
      'floorPrice': floorPrice,
      'materialsCost': materialsCost,
      'laborHours': laborHours,
      'hourlyRate': hourlyRate,
      'transportCost': transportCost,
      'otherOverhead': otherOverhead,
    };
  }

  Map<String, dynamic> toBackendJson({String? artisanId}) {
    return {
      if (id.isNotEmpty) 'id': id,
      if (artisanId != null && artisanId.isNotEmpty) 'artisan_id': artisanId,
      'title': title,
      'title_hi': titleHi,
      'description': description,
      'description_hi': descriptionHi,
      'price': price,
      'category': category,
      'tags': tags,
      'status': 'draft', // INVARIANT: client mutations are always draft
      if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
      if (materialsCost != null) 'materials': materialsCost,
      if (laborHours != null) 'labor_hours': laborHours,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (transportCost != null) 'transport': transportCost,
      if (otherOverhead != null) 'overhead': otherOverhead,
    };
  }

  Map<String, dynamic> toBackendUpdateJson({int? expectedRevision}) {
    return {
      'title': title,
      'title_hi': titleHi,
      'description': description,
      'description_hi': descriptionHi,
      'price': price,
      'category': category,
      'tags': tags,
      'expected_revision': ?expectedRevision,
      if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
      if (materialsCost != null) 'materials': materialsCost,
      if (laborHours != null) 'labor_hours': laborHours,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (transportCost != null) 'transport': transportCost,
      if (otherOverhead != null) 'overhead': otherOverhead,
    };
  }

  static ProductStatus parseStatus(String? val) {
    if (val == null) return ProductStatus.draft;
    switch (val) {
      case 'live':
        return ProductStatus.live;
      case 'pendingSync':
      case 'pending_sync':
        return ProductStatus.pendingSync;
      case 'pendingApprovalSync':
      case 'pending_approval_sync':
        return ProductStatus.pendingApprovalSync;
      case 'pendingUnpublishSync':
      case 'pending_unpublish_sync':
        return ProductStatus.pendingUnpublishSync;
      case 'draft':
        return ProductStatus.draft;
      case 'sold':
        return ProductStatus.sold;
      case 'soldOut':
      case 'sold_out':
        return ProductStatus.soldOut;
      case 'listingRemoved':
      case 'listing_removed':
        return ProductStatus.listingRemoved;
      case 'awaitingApproval':
      case 'awaiting_approval':
        return ProductStatus.awaitingApproval;
      case 'approved':
        return ProductStatus.approved;
      case 'published':
        return ProductStatus.published;
      case 'superseded':
        return ProductStatus.superseded;
      case 'rejected':
        return ProductStatus.rejected;
      case 'legacyUnverified':
      case 'legacy_unverified':
        return ProductStatus.legacyUnverified;
      default:
        return ProductStatus.draft;
    }
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleHi: json['titleHi'] as String? ?? (json['title_hi'] as String? ?? ''),
      description: json['description'] as String? ?? '',
      descriptionHi: json['descriptionHi'] as String? ?? (json['description_hi'] as String? ?? ''),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      photoPath: json['photoPath'] as String? ??
          (json['image_url'] as String? ?? (json['imageUrl'] as String? ?? '')),
      category: (json['category'] as String?)?.trim().isNotEmpty == true
          ? (json['category'] as String).trim()
          : 'Handicraft',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      status: parseStatus(json['status'] as String?),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'] as String) ?? DateTime.now())
          : (json['createdAt'] != null
              ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
              : DateTime.now()),
      additionalPhotoPaths: (json['additionalPhotoPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      aiEnhancedPhotoPath: json['aiEnhancedPhotoPath'] as String? ?? '',
      statusUpdatedAt: json['statusUpdatedAt'] != null
          ? DateTime.tryParse(json['statusUpdatedAt'] as String)
          : (json['updated_at'] != null
              ? DateTime.tryParse(json['updated_at'] as String)
              : null),
      restockQuantity: json['restockQuantity'] as int?,
      statusReason: json['statusReason'] as String?,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      approvedRevision: (json['approved_revision'] as num?)?.toInt() ??
          (json['approvedRevision'] as num?)?.toInt(),
      approvedAt: json['approved_at'] != null
          ? DateTime.tryParse(json['approved_at'] as String)
          : (json['approvedAt'] != null
              ? DateTime.tryParse(json['approvedAt'] as String)
              : null),
      approvedByArtisanId: json['approved_by_artisan_id'] as String? ??
          json['approvedByArtisanId'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : (json['publishedAt'] != null
              ? DateTime.tryParse(json['publishedAt'] as String)
              : null),
      contentHash: json['content_hash'] as String? ?? json['contentHash'] as String?,
      mediaId: json['media_id'] as String? ?? json['mediaId'] as String?,
      floorPrice: (json['floor_price'] as num?)?.toDouble() ??
          (json['floorPrice'] as num?)?.toDouble(),
      materialsCost: (json['materials'] as num?)?.toDouble() ??
          (json['materials_cost'] as num?)?.toDouble() ??
          (json['materialsCost'] as num?)?.toDouble(),
      laborHours: (json['labor_hours'] as num?)?.toDouble() ??
          (json['laborHours'] as num?)?.toDouble(),
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ??
          (json['hourlyRate'] as num?)?.toDouble(),
      transportCost: (json['transport'] as num?)?.toDouble() ??
          (json['transport_cost'] as num?)?.toDouble() ??
          (json['transportCost'] as num?)?.toDouble(),
      otherOverhead: (json['overhead'] as num?)?.toDouble() ??
          (json['other_overhead'] as num?)?.toDouble() ??
          (json['otherOverhead'] as num?)?.toDouble(),
    );
  }
}