import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalasetu/features/orders/screens/my_orders_screen.dart';
import 'package:kalasetu/features/orders/providers/orders_provider.dart';
import 'package:kalasetu/features/orders/models/order.dart';

void main() {
  testWidgets('My Orders filter chips hug text tightly and default to New tab', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MyOrdersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial filter is OrderStatus.newOrder
    final container = ProviderScope.containerOf(tester.element(find.byType(MyOrdersScreen)));
    expect(container.read(selectedOrderFilterProvider), OrderStatus.newOrder);

    // Find ChoiceChips
    final newChipFinder = find.widgetWithText(ChoiceChip, 'order_status_new');
    final deliveredChipFinder = find.widgetWithText(ChoiceChip, 'order_status_delivered');
    final cancelledChipFinder = find.widgetWithText(ChoiceChip, 'order_status_cancelled');

    expect(newChipFinder, findsOneWidget);
    expect(deliveredChipFinder, findsOneWidget);
    expect(cancelledChipFinder, findsOneWidget);

    // Get rendered sizes
    final newSize = tester.getSize(newChipFinder);
    final deliveredSize = tester.getSize(deliveredChipFinder);
    final cancelledSize = tester.getSize(cancelledChipFinder);

    // Verify that "New" is significantly narrower than "Delivered" and "Cancelled"
    // (e.g. New ~ 152 vs Delivered ~ 190)
    expect(newSize.width, lessThan(deliveredSize.width));
    expect(newSize.width, lessThan(cancelledSize.width));

    // ChoiceChip selected state check: 'New' is selected initially
    final ChoiceChip newChip = tester.widget(newChipFinder);
    expect(newChip.selected, isTrue);

    final ChoiceChip deliveredChip = tester.widget(deliveredChipFinder);
    expect(deliveredChip.selected, isFalse);

    // Scroll to and tap Delivered chip to switch filter
    await tester.ensureVisible(deliveredChipFinder);
    await tester.pumpAndSettle();
    await tester.tap(deliveredChipFinder);
    await tester.pumpAndSettle();

    expect(container.read(selectedOrderFilterProvider), OrderStatus.delivered);
    final ChoiceChip updatedDeliveredChip = tester.widget(deliveredChipFinder);
    expect(updatedDeliveredChip.selected, isTrue);
  });
}
