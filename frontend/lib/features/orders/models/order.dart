/// Represents the fulfilment status of an artisan order.
enum OrderStatus { newOrder, packed, shipped, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  String get labelKey {
    switch (this) {
      case OrderStatus.newOrder:   return 'order_status_new';
      case OrderStatus.packed:     return 'order_status_packed';
      case OrderStatus.shipped:    return 'order_status_shipped';
      case OrderStatus.delivered:  return 'order_status_delivered';
      case OrderStatus.cancelled:  return 'order_status_cancelled';
    }
  }

  /// Returns the next logical status, or null if terminal.
  OrderStatus? get next {
    switch (this) {
      case OrderStatus.newOrder:  return OrderStatus.packed;
      case OrderStatus.packed:    return OrderStatus.shipped;
      case OrderStatus.shipped:   return OrderStatus.delivered;
      case OrderStatus.delivered: return null;
      case OrderStatus.cancelled: return null;
    }
  }
}

class Order {
  final String id;
  final String productTitle;
  final String? productTitleHi;
  final String productCategory;
  final String productImagePath;
  final String buyerName;
  final String buyerLocation;
  final double amount;
  final int quantity;
  final OrderStatus status;
  final DateTime placedAt;
  final DateTime? shippedAt;
  final String? trackingId;

  const Order({
    required this.id,
    required this.productTitle,
    this.productTitleHi,
    required this.productCategory,
    required this.productImagePath,
    required this.buyerName,
    required this.buyerLocation,
    required this.amount,
    required this.quantity,
    required this.status,
    required this.placedAt,
    this.shippedAt,
    this.trackingId,
  });

  String get buyerCity => buyerLocation.isNotEmpty
      ? buyerLocation.split(',').last.trim()
      : 'India';

  Order copyWith({
    String? id,
    String? productTitle,
    String? productTitleHi,
    String? productCategory,
    String? productImagePath,
    String? buyerName,
    String? buyerLocation,
    double? amount,
    int? quantity,
    OrderStatus? status,
    DateTime? placedAt,
    DateTime? shippedAt,
    String? trackingId,
  }) {
    return Order(
      id: id ?? this.id,
      productTitle: productTitle ?? this.productTitle,
      productCategory: productCategory ?? this.productCategory,
      productImagePath: productImagePath ?? this.productImagePath,
      buyerName: buyerName ?? this.buyerName,
      buyerLocation: buyerLocation ?? this.buyerLocation,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      status: status ?? this.status,
      placedAt: placedAt ?? this.placedAt,
      shippedAt: shippedAt ?? this.shippedAt,
      trackingId: trackingId ?? this.trackingId,
    );
  }
}
