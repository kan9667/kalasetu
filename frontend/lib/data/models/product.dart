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

  @HiveField(6)
  final String imageUrl;

  @HiveField(7)
  final String category;

  @HiveField(8)
  final List<String> tags;

  @HiveField(9)
  final ProductStatus status;

  @HiveField(10)
  final DateTime createdAt;

  Product({
    required this.id,
    required this.title,
    this.titleHi = '',
    required this.description,
    this.descriptionHi = '',
    required this.price,
    required this.imageUrl,
    required this.category,
    this.tags = const [],
    this.status = ProductStatus.draft,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Product copyWith({
    String? id,
    String? title,
    String? titleHi,
    String? description,
    String? descriptionHi,
    double? price,
    String? imageUrl,
    String? category,
    List<String>? tags,
    ProductStatus? status,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      title: title ?? this.title,
      titleHi: titleHi ?? this.titleHi,
      description: description ?? this.description,
      descriptionHi: descriptionHi ?? this.descriptionHi,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
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
      'imageUrl': imageUrl,
      'category': category,
      'tags': tags,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
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
      imageUrl: json['imageUrl'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      status: ProductStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ProductStatus.draft,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
