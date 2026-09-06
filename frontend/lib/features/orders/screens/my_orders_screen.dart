import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../services/label_maker_service.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  // TODO: batch label selection - reintroduce when multi-select workflow is finalized

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(filteredOrdersProvider);
    final selectedFilter = ref.watch(selectedOrderFilterProvider);

    return AppScaffold(
      title: 'my_orders_title'.tr(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter chips (smooth horizontal scrolling, tight hugging, no clipping mask)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              left: AppSpacing.screenPadding,
              right: 32,
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilterChip(
                  label: 'order_filter_all'.tr(),
                  selected: selectedFilter == null,
                  onTap: () => ref.read(selectedOrderFilterProvider.notifier).state = null,
                ),
                const SizedBox(width: AppSpacing.sm),
                ...OrderStatus.values.map((status) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _FilterChip(
                      label: status.labelKey.tr(),
                      selected: selectedFilter == status,
                      color: _statusColor(status),
                      onTap: () => ref.read(selectedOrderFilterProvider.notifier).state = status,
                    ),
                  );
                }),
              ],
            ),
          ),

          // Orders list
          Expanded(
            child: orders.isEmpty
                ? _EmptyOrders()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _OrderCard(
                        order: order,
                        onTap: () {
                          context.pushNamed(
                            AppRouteConstants.orderDetail,
                            pathParameters: {'orderId': order.id},
                            extra: order,
                          );
                        },
                        onStatusAdvance: () {
                          final next = order.status.next;
                          if (next != null) {
                            ref.read(ordersProvider.notifier).updateStatus(order.id, next);
                            LabelMakerService.invalidateCache(order.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Status updated to ${next.labelKey.tr()}',
                                ),
                                backgroundColor: AppColors.terracotta,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.newOrder:  return AppColors.terracotta;
      case OrderStatus.packed:    return AppColors.turmericDark;
      case OrderStatus.shipped:   return AppColors.terracottaDark;
      case OrderStatus.delivered: return AppColors.forestGreenDark;
      case OrderStatus.cancelled: return AppColors.error;
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.terracotta;
    return ChoiceChip(
      label: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: selected ? activeColor : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: activeColor.withValues(alpha: 0.15),
      side: BorderSide(
        color: selected ? activeColor : AppColors.border.withValues(alpha: 0.4),
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  final VoidCallback onStatusAdvance;

  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onStatusAdvance,
  });

  @override
  Widget build(BuildContext context) {
    final canAdvance = order.status.next != null;

    return Dismissible(
      key: ValueKey('${order.id}_${order.status}'),
      direction: canAdvance ? DismissDirection.startToEnd : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.terracotta.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.arrow_forward, color: AppColors.terracotta),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Mark as ${order.status.next?.labelKey.tr() ?? ''}',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.terracotta),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        onStatusAdvance();
        return false; // Don't actually remove the card — just update
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: AppColors.divider,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Status color bar
                Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _statusColor(order.status),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.productTitle,
                              style: AppTextStyles.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _StatusBadge(status: order.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            order.buyerName,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 2),
                          Text(
                            order.buyerLocation,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '₹${order.amount.toStringAsFixed(0)}',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.terracotta,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (order.quantity > 1) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '× ${order.quantity}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _formatDate(order.placedAt),
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}';
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.newOrder:  return AppColors.terracotta;
      case OrderStatus.packed:    return AppColors.turmericDark;
      case OrderStatus.shipped:   return AppColors.terracottaDark;
      case OrderStatus.delivered: return AppColors.forestGreenDark;
      case OrderStatus.cancelled: return AppColors.error;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case OrderStatus.newOrder:
        bg = AppColors.terracotta.withValues(alpha: 0.15);
        fg = AppColors.terracottaDark;
        icon = Icons.auto_awesome;
        break;
      case OrderStatus.packed:
        bg = AppColors.turmericLight.withValues(alpha: 0.3);
        fg = AppColors.turmericDark;
        icon = Icons.inventory_2_outlined;
        break;
      case OrderStatus.shipped:
        bg = AppColors.terracottaDark.withValues(alpha: 0.12);
        fg = AppColors.terracottaDark;
        icon = Icons.local_shipping_outlined;
        break;
      case OrderStatus.delivered:
        bg = AppColors.forestGreenLight.withValues(alpha: 0.2);
        fg = AppColors.forestGreenDark;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.cancelled:
        bg = AppColors.error.withValues(alpha: 0.12);
        fg = AppColors.error;
        icon = Icons.cancel_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            status.labelKey.tr(),
            style: AppTextStyles.labelSmall.copyWith(color: fg, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 56,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('no_orders_title'.tr(), style: AppTextStyles.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'no_orders_desc'.tr(),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
