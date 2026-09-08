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

String _tr(BuildContext context, String key, {Map<String, String>? namedArgs, String? fallback}) {
  final easy = EasyLocalization.of(context);
  final isHi = (Localizations.maybeLocaleOf(context)?.languageCode ??
          easy?.locale.languageCode) ==
      'hi';
  String res;
  try {
    if (easy != null) {
      res = key.tr(context: context, namedArgs: namedArgs);
    } else {
      res = key.tr(namedArgs: namedArgs);
    }
  } catch (_) {
    res = key;
  }
  if (isHi && fallback != null && (res == key || res.isEmpty)) {
    return fallback;
  }
  return res;
}

String _trStatus(BuildContext context, OrderStatus status) {
  final fallback = switch (status) {
    OrderStatus.newOrder => 'नया',
    OrderStatus.packed => 'पैक किया',
    OrderStatus.shipped => 'भेजा गया',
    OrderStatus.delivered => 'वितरित',
    OrderStatus.cancelled => 'रद्द किया',
  };
  return _tr(context, status.labelKey, fallback: fallback);
}

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

    final isHi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';

    return AppScaffold(
      title: _tr(context, 'order_detail_title', fallback: 'ऑर्डर विवरण'),
      showNotificationBell: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order ID + status hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
                boxShadow: AppElevation.cardShadow,
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
                                color: AppColors.terracottaDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tr(
                                context,
                                'order_placed_on',
                                namedArgs: {
                                  'date': _formatFull(context, liveOrder.placedAt),
                                },
                                fallback: 'दिनांक ${_formatFull(context, liveOrder.placedAt)} को दिया गया',
                              ),
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(status: liveOrder.status),
                    ],
                  ),
                  if (liveOrder.trackingId != null) ...[
                    const Divider(height: 24, color: AppColors.line),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: AppColors.terracotta,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _tr(context, 'tracking_id', fallback: 'ट्रैकिंग आईडी'),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          liveOrder.trackingId!,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.ink,
                          ),
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
              label: _tr(context, 'product_label', fallback: 'उत्पाद'),
              children: [
                _DetailRow(
                  label: (isHi && liveOrder.productTitleHi != null)
                      ? liveOrder.productTitleHi!
                      : liveOrder.productTitle,
                  value: _localizedCategory(context, liveOrder.productCategory),
                ),
                _DetailRow(
                  label: _tr(context, 'quantity_label', fallback: 'मात्रा'),
                  value: liveOrder.quantity == 1
                      ? _tr(context, 'quantity_unit_singular', fallback: '1 नग')
                      : _tr(
                          context,
                          'quantity_unit_plural',
                          namedArgs: {'count': '${liveOrder.quantity}'},
                          fallback: '${liveOrder.quantity} नग',
                        ),
                ),
                _DetailRow(
                  label: _tr(context, 'amount_label', fallback: 'राशि'),
                  value: '₹${liveOrder.amount.toStringAsFixed(0)}',
                  valueStyle: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.terracottaDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Buyer info
            _SectionCard(
              label: _tr(context, 'buyer_name', fallback: 'खरीदार'),
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
                label: '${_tr(context, 'update_status', fallback: 'स्थिति बदलें')}: ${_trStatus(context, liveOrder.status.next!)}',
                icon: Icons.arrow_forward,
                onPressed: () {
                  final next = liveOrder.status.next!;
                  ref.read(ordersProvider.notifier).updateStatus(liveOrder.id, next);
                  LabelMakerService.invalidateCache(liveOrder.id);
                  final nextStatusLabel = _trStatus(context, next);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_tr(
                        context,
                        'status_updated_to',
                        namedArgs: {'status': nextStatusLabel},
                        fallback: 'स्थिति बदलकर $nextStatusLabel की गई',
                      )),
                      backgroundColor: AppColors.terracotta,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            AppButton(
              label: _tr(context, 'packaging_suggestions_title', fallback: 'पैकेजिंग सुझाव'),
              icon: Icons.inventory_2_outlined,
              type: AppButtonType.secondary,
              onPressed: () => showPackagingSuggestionsSheet(
                context,
                category: liveOrder.productCategory,
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            AppButton(
              label: _tr(context, 'label_maker_title', fallback: 'पार्सल लेबल बनाएं'),
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

  String _formatFull(BuildContext context, DateTime dt) {
    final isHi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final enMonths = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hiMonths = [
      'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
      'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर',
    ];
    final m = isHi ? hiMonths[dt.month - 1] : enMonths[dt.month - 1];
    return '${dt.day} $m ${dt.year}';
  }

  String _localizedCategory(BuildContext context, String cat) {
    final isHi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    if (!isHi) return cat;
    final lower = cat.toLowerCase();
    if (lower.contains('pottery') || lower.contains('clay') || lower.contains('ceramic')) {
      return _tr(context, 'filter_pottery', fallback: 'मिट्टी के बर्तन');
    } else if (lower.contains('textile') || lower.contains('saree') || lower.contains('silk') || lower.contains('fabric') || lower.contains('handloom')) {
      return _tr(context, 'filter_textiles', fallback: 'कपड़े व वस्त्र');
    } else if (lower.contains('jewel') || lower.contains('silver') || lower.contains('gold') || lower.contains('brass')) {
      return _tr(context, 'filter_jewelry', fallback: 'आभूषण');
    } else if (lower.contains('wood') || lower.contains('toy') || lower.contains('bamboo') || lower.contains('cane')) {
      return _tr(context, 'filter_woodwork', fallback: 'काष्ठकला');
    } else if (lower.contains('paint') || lower.contains('art')) {
      return _tr(context, 'filter_paintings', fallback: 'चित्रकला');
    }
    return cat;
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
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppElevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.inkFaint,
              letterSpacing: 1,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: valueStyle ??
                  AppTextStyles.labelMedium.copyWith(color: AppColors.ink),
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
        bg = AppColors.statusActionBg;
        fg = AppColors.statusActionFg;
        icon = Icons.auto_awesome;
        break;
      case OrderStatus.packed:
        bg = AppColors.statusPendingBg;
        fg = AppColors.statusPendingFg;
        icon = Icons.inventory_2_outlined;
        break;
      case OrderStatus.shipped:
        bg = AppColors.statusSuccessBg;
        fg = AppColors.statusSuccessFg;
        icon = Icons.local_shipping_outlined;
        break;
      case OrderStatus.delivered:
        bg = AppColors.statusSuccessBg;
        fg = AppColors.statusSuccessFg;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.cancelled:
        bg = AppColors.line;
        fg = AppColors.inkSoft;
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
          const SizedBox(width: 4),
          Text(
            _trStatus(context, status),
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
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
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppElevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(context, 'order_timeline_title', fallback: 'ऑर्डर स्थिति'),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.inkFaint,
              letterSpacing: 1,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isCancelled)
            Row(
              children: [
                const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _tr(context, 'order_cancelled_title', fallback: 'ऑर्डर रद्द'),
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.error),
                ),
              ],
            )
          else
            Row(
              children: List.generate(allStatuses.length * 2 - 1, (i) {
                if (i.isOdd) {
                  // Connector line with tanka stitch
                  final stepIdx = i ~/ 2;
                  final isDone = stepIdx < currentIdx;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: isDone ? AppColors.success : AppColors.line,
                    ),
                  );
                } else {
                  final stepIdx = i ~/ 2;
                  final isDone = stepIdx < currentIdx;
                  final isCurrent = stepIdx == currentIdx;

                  Color dotBg;
                  Color dotFg;
                  BoxBorder? dotBorder;
                  List<BoxShadow>? dotShadow;

                  if (isCurrent) {
                    dotBg = AppColors.terracotta;
                    dotFg = AppColors.textOnPrimary;
                    dotShadow = const [
                      BoxShadow(
                        color: AppColors.terracottaLight,
                        spreadRadius: 4,
                      ),
                    ];
                  } else if (isDone) {
                    dotBg = AppColors.success;
                    dotFg = AppColors.textOnPrimary;
                  } else {
                    dotBg = AppColors.cardSurface;
                    dotFg = AppColors.inkFaint;
                    dotBorder = Border.all(color: AppColors.line, width: 1.5);
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: dotBg,
                          shape: BoxShape.circle,
                          border: dotBorder,
                          boxShadow: dotShadow,
                        ),
                        child: Icon(
                          isDone
                              ? Icons.check
                              : (isCurrent ? Icons.circle : Icons.circle_outlined),
                          color: dotFg,
                          size: isCurrent ? 10 : 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 65,
                        child: Text(
                          _trStatus(context, allStatuses[stepIdx]),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isCurrent
                                ? AppColors.terracottaDark
                                : (isDone ? AppColors.success : AppColors.inkFaint),
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
