import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../services/label_maker_service.dart';

class OrdersNotifier extends StateNotifier<List<Order>> {
  OrdersNotifier() : super(_mockOrders());

  static List<Order> _mockOrders() {
    final now = DateTime.now();
    return [
      Order(
        id: 'ORD-1001',
        productTitle: 'Terracotta Water Pot (Matka)',
        productCategory: 'Pottery',
        productImagePath: '',
        buyerName: 'Priya Sharma',
        buyerLocation: 'Delhi',
        amount: 850,
        quantity: 2,
        status: OrderStatus.newOrder,
        placedAt: now.subtract(const Duration(hours: 3)),
      ),
      Order(
        id: 'ORD-1002',
        productTitle: 'Block-Print Kota Saree',
        productCategory: 'Textiles',
        productImagePath: '',
        buyerName: 'Ananya Iyer',
        buyerLocation: 'Chennai',
        amount: 2200,
        quantity: 1,
        status: OrderStatus.packed,
        placedAt: now.subtract(const Duration(days: 1)),
      ),
      Order(
        id: 'ORD-1003',
        productTitle: 'Dhokra Brass Elephant',
        productCategory: 'Metalwork',
        productImagePath: '',
        buyerName: 'Ravi Kumar',
        buyerLocation: 'Bangalore',
        amount: 1450,
        quantity: 1,
        status: OrderStatus.shipped,
        placedAt: now.subtract(const Duration(days: 3)),
        shippedAt: now.subtract(const Duration(days: 1)),
        trackingId: 'TRK-78924635',
      ),
      Order(
        id: 'ORD-1004',
        productTitle: 'Warli Tribal Painting',
        productCategory: 'Paintings',
        productImagePath: '',
        buyerName: 'Meera Desai',
        buyerLocation: 'Mumbai',
        amount: 3500,
        quantity: 1,
        status: OrderStatus.delivered,
        placedAt: now.subtract(const Duration(days: 7)),
        shippedAt: now.subtract(const Duration(days: 5)),
        trackingId: 'TRK-45678123',
      ),
      Order(
        id: 'ORD-1005',
        productTitle: 'Channapatna Wooden Toy Set',
        productCategory: 'Woodwork',
        productImagePath: '',
        buyerName: 'Suresh Nair',
        buyerLocation: 'Kochi',
        amount: 680,
        quantity: 3,
        status: OrderStatus.newOrder,
        placedAt: now.subtract(const Duration(hours: 8)),
      ),
      Order(
        id: 'ORD-1006',
        productTitle: 'Meenakari Silver Earrings',
        productCategory: 'Jewelry',
        productImagePath: '',
        buyerName: 'Fatima Ansari',
        buyerLocation: 'Jaipur',
        amount: 1100,
        quantity: 1,
        status: OrderStatus.cancelled,
        placedAt: now.subtract(const Duration(days: 2)),
      ),
      Order(
        id: 'ORD-1007',
        productTitle: 'Blue Pottery Vase',
        productCategory: 'Pottery',
        productImagePath: '',
        buyerName: 'Arjun Mehta',
        buyerLocation: 'Ahmedabad',
        amount: 1950,
        quantity: 1,
        status: OrderStatus.packed,
        placedAt: now.subtract(const Duration(hours: 30)),
      ),
    ];
  }

  void updateStatus(String orderId, OrderStatus newStatus) {
    state = [
      for (final order in state)
        if (order.id == orderId) order.copyWith(status: newStatus) else order,
    ];
    // Invalidate cached packaging label whenever order status changes
    LabelMakerService.invalidateCache(orderId);
  }
}

final ordersProvider =
    StateNotifierProvider<OrdersNotifier, List<Order>>((ref) {
  return OrdersNotifier();
});

/// Currently selected filter chip (defaults to OrderStatus.newOrder at start of session, null = show all).
final selectedOrderFilterProvider = StateProvider<OrderStatus?>((ref) => OrderStatus.newOrder);

/// Filtered list of orders based on [selectedOrderFilterProvider].
final filteredOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersProvider);
  final filter = ref.watch(selectedOrderFilterProvider);
  if (filter == null) return orders;
  return orders.where((o) => o.status == filter).toList();
});

/// Map of order count per OrderStatus (and null for all orders).
final orderCountsByStatusProvider = Provider<Map<OrderStatus?, int>>((ref) {
  final orders = ref.watch(ordersProvider);
  final counts = <OrderStatus?, int>{null: orders.length};
  for (final status in OrderStatus.values) {
    counts[status] = orders.where((o) => o.status == status).length;
  }
  return counts;
});
