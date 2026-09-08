import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/motifs/empty_craft_state.dart';
import '../../../core/widgets/motifs/craft_category_badge.dart';
import '../../../core/widgets/speaker_affordance.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../services/label_maker_service.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(filteredOrdersProvider);
    final selectedFilter = ref.watch(selectedOrderFilterProvider);

    return AppScaffold(
      title: 'my_orders_title'.tr(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter pills (smooth horizontal scrolling matching kalasetu-redesign-v3.html)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              left: AppSpacing.screenPadding,
              right: 32,
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
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
                      dotColor: _statusDotColor(status),
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
                      vertical: AppSpacing.xs,
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

  Color _statusDotColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.newOrder:  return AppColors.terracotta;
      case OrderStatus.packed:    return AppColors.gold;
      case OrderStatus.shipped:   return AppColors.success;
      case OrderStatus.delivered: return AppColors.success;
      case OrderStatus.cancelled: return AppColors.inkSoft;
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: dotColor != null
          ? Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: selected ? Colors.white : dotColor,
                shape: BoxShape.circle,
              ),
            )
          : null,
      label: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: selected ? AppColors.textOnPrimary : AppColors.inkSoft,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: EdgeInsets.only(
        left: dotColor != null ? 2 : 6,
        right: 8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      backgroundColor: AppColors.cardSurface,
      selectedColor: AppColors.terracotta,
      side: BorderSide(
        color: selected ? AppColors.terracotta : AppColors.line,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Order order;
  final VoidCallback onTap;
  final VoidCallback onStatusAdvance;

  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onStatusAdvance,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  final AppTtsService _tts = AppTtsService();

  @override
  void initState() {
    super.initState();
    _tts.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  // A short spoken summary of the order — enough for an artisan to identify
  // it by ear from a list, without reading. Not every field on the card,
  // just what identifies and matters: what, who, where, how much, status.
  Future<void> _speakSummary() async {
    if (_tts.isSpeaking) {
      await _tts.stop();
      return;
    }
    final order = widget.order;
    final isHindi = context.locale.languageCode == 'hi';
    final lead = TtsPageGuides.orderCardLead
        .forLanguage(context.locale.languageCode);

    // Built in the app language rather than always in English: the status
    // label is already translated, so an English carrier sentence around a
    // Hindi word — read by whichever single voice is selected — mispronounces
    // one half or the other whichever way it is spoken.
    final summary = isHindi
        ? '${order.productTitle} का ऑर्डर, ${order.buyerCity} से '
            '${order.buyerName} की ओर से। राशि '
            '${order.amount.toStringAsFixed(0)} रुपये। स्थिति: '
            '${order.status.labelKey.tr()}।'
        : 'Order for ${order.productTitle}, from ${order.buyerName} in '
            '${order.buyerCity}. Amount: ${order.amount.toStringAsFixed(0)} '
            'rupees. Status: ${order.status.labelKey.tr()}.';

    final result = await _tts.speak(
      lead + summary,
      languageCode: context.locale.languageCode,
    );

    if (result == TtsResult.voiceUnavailable && mounted) {
      final opened = await _tts.openVoiceDownloadScreen();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please download the voice from phone settings'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final onTap = widget.onTap;
    final onStatusAdvance = widget.onStatusAdvance;
    final canAdvance = order.status.next != null;

    return Dismissible(
      key: ValueKey('${order.id}_${order.status}'),
      direction: canAdvance ? DismissDirection.startToEnd : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.itemSpacing),
        decoration: BoxDecoration(
          color: AppColors.terracottaLight,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.arrow_forward, color: AppColors.terracottaDark),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Mark as ${order.status.next?.labelKey.tr() ?? ''}',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.terracottaDark),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        onStatusAdvance();
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.itemSpacing),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: AppColors.line,
            width: 1.0,
          ),
          boxShadow: AppElevation.cardShadow,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 46x46 Thumbnail matching mockup
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.parchmentDeep,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: order.productImagePath.isNotEmpty
                      ? AppImage(
                          imageUrl: order.productImagePath,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        )
                      : _buildCategoryThumb(order.productCategory),
                ),
                const SizedBox(width: 12),

                // Card body
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Product name + Status flag
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              order.productTitle,
                              style: AppTextStyles.headlineSmall.copyWith(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          SpeakerAffordance.compact(
                            isSpeaking: _tts.isSpeaking,
                            onTap: _speakSummary,
                          ),
                          const SizedBox(width: 4),
                          _StatusBadge(status: order.status),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // Meta row: User + Location
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 13,
                            color: AppColors.inkSoft,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              order.buyerName,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.inkSoft,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.inkFaint,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              order.buyerCity,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.inkSoft,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Price row: Price x Quantity + Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '₹${order.amount.toStringAsFixed(0)}',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.terracottaDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                                if (order.quantity > 1) ...[
                                  const TextSpan(text: ' '),
                                  TextSpan(
                                    text: '× ${order.quantity}',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.inkSoft,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            _formatDate(order.placedAt),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.inkFaint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryThumb(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('pot') || cat.contains('clay') || cat.contains('ceramic')) {
      return CustomPaint(
        size: const Size(22, 22),
        painter: CraftCategoryIcons.pottery(color: AppColors.terracottaDark),
      );
    }
    if (cat.contains('silk') || cat.contains('saree') || cat.contains('textile') || cat.contains('cloth')) {
      return CustomPaint(
        size: const Size(22, 22),
        painter: CraftCategoryIcons.textile(color: AppColors.terracottaDark),
      );
    }
    if (cat.contains('wood') || cat.contains('toy') || cat.contains('carv')) {
      return CustomPaint(
        size: const Size(22, 22),
        painter: CraftCategoryIcons.woodwork(color: AppColors.terracottaDark),
      );
    }
    if (cat.contains('jewel') || cat.contains('metal') || cat.contains('brass')) {
      return CustomPaint(
        size: const Size(22, 22),
        painter: CraftCategoryIcons.jewelry(color: AppColors.terracottaDark),
      );
    }
    return const Icon(Icons.brush, size: 22, color: AppColors.terracottaDark);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}';
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
            status.labelKey.tr(),
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

class _EmptyOrders extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EmptyCraftState(
      title: 'no_orders_title'.tr(),
      subtitle: 'no_orders_desc'.tr(),
    );
  }
}
