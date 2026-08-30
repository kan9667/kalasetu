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
  }) : createdAt = createdAt ?? DateTime.now();

  /// All captured photos in order (primary first), for the review screen's
  /// thumbnail strip. Skips empty entries.
  List<String> get allPhotoPaths =>
      [photoPath, ...additionalPhotoPaths].where((p) => p.isNotEmpty).toList();

  /// What should actually be displayed — the enhanced photo if we have one,
  /// otherwise the original capture.
  String get displayPhotoPath =>
      aiEnhancedPhotoPath.isNotEmpty ? aiEnhancedPhotoPath : photoPath;

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
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleHi: json['titleHi'] as String? ?? '',
      description: json['description'] as String? ?? '',
      descriptionHi: json['descriptionHi'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      photoPath: json['photoPath'] as String? ?? (json['imageUrl'] as String? ?? ''),
      category: json['category'] as String? ?? 'General',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      status: ProductStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ProductStatus.draft,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      additionalPhotoPaths: (json['additionalPhotoPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      aiEnhancedPhotoPath: json['aiEnhancedPhotoPath'] as String? ?? '',
    );
  }
}