import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../widgets/packaging_suggestions_sheet.dart';
import '../widgets/label_preview_sheet.dart';
import '../services/label_maker_service.dart';

class OrderDetailScreen extends ConsumerWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live state so UI updates when status changes
    final liveOrder = ref.watch(ordersProvider).firstWhere(
          (o) => o.id == order.id,
          orElse: () => order,
        );

    return AppScaffold(
      title: 'order_detail_title'.tr(),
      showNotificationBell: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order ID + status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              liveOrder.id,
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: AppColors.terracotta,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Placed ${_formatFull(liveOrder.placedAt)}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(status: liveOrder.status),
                    ],
                  ),
                  if (liveOrder.trackingId != null) ...[
                    const Divider(height: 20, color: AppColors.divider),
                    Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.terracotta),
                        const SizedBox(width: AppSpacing.xs),
                        Text('tracking_id'.tr(), style: AppTextStyles.bodySmall),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          liveOrder.trackingId!,
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.charcoal),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Product info
            _SectionCard(
              label: 'Product',
              children: [
                _DetailRow(label: liveOrder.productTitle, value: liveOrder.productCategory),
                _DetailRow(label: 'Quantity', value: '${liveOrder.quantity} unit${liveOrder.quantity > 1 ? 's' : ''}'),
                _DetailRow(
                  label: 'Amount',
                  value: '₹${liveOrder.amount.toStringAsFixed(0)}',
                  valueStyle: AppTextStyles.headlineSmall.copyWith(color: AppColors.terracotta),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Buyer info
            _SectionCard(
              label: 'buyer_name'.tr(),
              children: [
                _DetailRow(label: liveOrder.buyerName, value: liveOrder.buyerLocation),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Status timeline
            _StatusTimeline(currentStatus: liveOrder.status),

            const SizedBox(height: AppSpacing.xl),

            // Action buttons
            if (liveOrder.status.next != null) ...[
              AppButton(
                label: '${'update_status'.tr()}: ${liveOrder.status.next!.labelKey.tr()}',
                icon: Icons.arrow_forward,
                onPressed: () {
                  final next = liveOrder.status.next!;
                  ref.read(ordersProvider.notifier).updateStatus(liveOrder.id, next);
                  LabelMakerService.invalidateCache(liveOrder.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Status updated to ${next.labelKey.tr()}'),
                      backgroundColor: AppColors.terracotta,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            AppButton(
              label: 'packaging_suggestions_title'.tr(),
              icon: Icons.inventory_2_outlined,
              type: AppButtonType.outlined,
              onPressed: () => showPackagingSuggestionsSheet(
                context,
                category: liveOrder.productCategory,
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            AppButton(
              label: 'label_maker_title'.tr(),
              icon: Icons.print_outlined,
              type: AppButtonType.outlined,
              onPressed: () => showLabelPreviewSheet(context, order: liveOrder),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  String _formatFull(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _SectionCard extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _SectionCard({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _DetailRow({required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: AppTextStyles.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: valueStyle ?? AppTextStyles.labelMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
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
        bg = AppColors.terracotta.withOpacity(0.15);
        fg = AppColors.terracottaDark;
        icon = Icons.auto_awesome;
        break;
      case OrderStatus.packed:
        bg = AppColors.turmericLight.withOpacity(0.3);
        fg = AppColors.turmericDark;
        icon = Icons.inventory_2_outlined;
        break;
      case OrderStatus.shipped:
        bg = AppColors.terracottaDark.withOpacity(0.12);
        fg = AppColors.terracottaDark;
        icon = Icons.local_shipping_outlined;
        break;
      case OrderStatus.delivered:
        bg = AppColors.forestGreenLight.withOpacity(0.2);
        fg = AppColors.forestGreenDark;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.cancelled:
        bg = AppColors.error.withOpacity(0.12);
        fg = AppColors.error;
        icon = Icons.cancel_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.labelKey.tr(),
            style: AppTextStyles.labelSmall.copyWith(color: fg, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final OrderStatus currentStatus;
  const _StatusTimeline({required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final allStatuses = [
      OrderStatus.newOrder,
      OrderStatus.packed,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];

    final currentIdx = allStatuses.indexOf(currentStatus);
    final isCancelled = currentStatus == OrderStatus.cancelled;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORDER TIMELINE',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isCancelled)
            Row(
              children: [
                const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Order Cancelled',
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.error),
                ),
              ],
            )
          else
            Row(
              children: List.generate(allStatuses.length * 2 - 1, (i) {
                if (i.isOdd) {
                  // Connector line
                  final stepIdx = i ~/ 2;
                  final isDone = stepIdx < currentIdx;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: isDone ? AppColors.terracotta : AppColors.surfaceVariant,
                    ),
                  );
                } else {
                  final stepIdx = i ~/ 2;
                  final isDone = stepIdx <= currentIdx;
                  final isCurrent = stepIdx == currentIdx;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isDone ? AppColors.terracotta : AppColors.surfaceVariant,
                          shape: BoxShape.circle,
                          border: isCurrent
                              ? Border.all(color: AppColors.terracottaDark, width: 2)
                              : null,
                        ),
                        child: Icon(
                          isDone ? Icons.check : Icons.circle_outlined,
                          color: isDone ? Colors.white : AppColors.textTertiary,
                          size: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        allStatuses[stepIdx].labelKey.tr(),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isDone ? AppColors.terracotta : AppColors.textTertiary,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                }
              }),
            ),
        ],
      ),
    );
  }
}
