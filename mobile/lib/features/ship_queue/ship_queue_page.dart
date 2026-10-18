import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';
import '../../main.dart';
import '../shipping/carrier_fields.dart';

class ShipQueuePage extends StatefulWidget {
  const ShipQueuePage({
    super.key,
    required this.repository,
    required this.onNewOrder,
    required this.onEditOrder,
  });
  final ShippingRepository repository;
  final Future<void> Function() onNewOrder;
  final Future<void> Function(String reminderId) onEditOrder;
  @override
  State<ShipQueuePage> createState() => _ShipQueuePageState();
}

class _ShipQueuePageState extends State<ShipQueuePage>
    with WidgetsBindingObserver {
  List<OrderDetails> orders = [];
  bool loading = true;
  bool showShipped = false;
  final expanded = <String>{};
  final tracking = <String, TextEditingController>{};
  final carrier = <String, TextEditingController>{};
  final pending = <String>{};
  final followed = <String>{};
  String? error;
  StreamSubscription<void>? _changes;
  int _refreshGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository is ReminderRepository) {
      _changes = (widget.repository as ReminderRepository).changes.listen(
        (_) => refresh(),
      );
    }
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    for (final c in tracking.values) {
      c.dispose();
    }
    for (final c in carrier.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final data = await widget.repository.loadOrders();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        orders = data;
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          loading = false;
          error = 'Could not load orders. Pull down to try again.';
        });
      }
    }
  }

  DateTime? _date(OrderDetails o) {
    final s = o.shipBy;
    if (s == null) return null;
    final parts = s.split('-').map(int.parse).toList();
    return DateTime.utc(parts[0], parts[1], parts[2]);
  }

  int? _days(OrderDetails o) {
    final d = _date(o);
    if (d == null) return null;
    final n = DateTime.now();
    final today = DateTime.utc(n.year, n.month, n.day);
    return d.difference(today).inDays;
  }

  List<OrderDetails> get pendingOrders =>
      orders.where((o) => !o.shipped).toList()..sort((a, b) {
        final x = _days(a), y = _days(b);
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
  List<OrderDetails> get shippedOrders =>
      orders
          .where(
            (o) =>
                o.shipped &&
                DateTime.tryParse(o.shippedAt!)?.isAfter(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ) ==
                    true,
          )
          .toList()
        ..sort(
          (a, b) =>
              DateTime.parse(b.shippedAt!)
                  .compareTo(DateTime.parse(a.shippedAt!)),
        );
  Future<void> ship(OrderDetails o) async {
    if (pending.contains(o.reminderId)) return;
    final invalidTracking = trackingError(
      tracking[o.reminderId]!.text,
      carrier[o.reminderId]!.text,
    );
    if (invalidTracking != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(invalidTracking)));
      return;
    }
    setState(() => pending.add(o.reminderId));
    try {
      await widget.repository.markShipped(
        o.reminderId,
        tracking[o.reminderId]!.text.trim(),
        carrier[o.reminderId]!.text.trim(),
      );
      await refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Shipped ✓ — remind me to follow up?'),
          action: SnackBarAction(
            label: '+3d follow-up',
            onPressed: () => followUp(o),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        await refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not confirm shipment. Refresh to check its status.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => pending.remove(o.reminderId));
    }
  }

  Future<void> followUp(OrderDetails o) async {
    if (followed.contains(o.reminderId)) return;
    setState(() => followed.add(o.reminderId));
    try {
      await widget.repository.createFollowUp(o.reminderId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Follow-up scheduled')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => followed.remove(o.reminderId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create follow-up.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = pendingOrders;
    final history = shippedOrders;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ship Queue (${queue.length})',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () async {
                  await widget.onNewOrder();
                  await refresh();
                },
                tooltip: 'New order',
                icon: const Icon(CupertinoIcons.add),
              ),
            ],
          ),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(error!),
              ),
            )
          else if (queue.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Nothing to ship. Create an order reminder.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...queue.map(_row),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => showShipped = !showShipped),
              icon: Icon(
                showShipped
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
              ),
              label: Text('SHIPPED THIS WEEK (${history.length})'),
            ),
            if (showShipped) ...history.map(_row),
          ],
        ],
      ),
    );
  }

  Widget _row(OrderDetails o) {
    final day = _days(o);
    final trackingController = tracking.putIfAbsent(
      o.reminderId,
      () => TextEditingController(text: o.trackingNumber ?? ''),
    );
    final carrierController = carrier.putIfAbsent(
      o.reminderId,
      () => TextEditingController(text: o.carrier ?? ''),
    );
    final danger = day != null && day < 0 && !o.shipped;
    final shippedDate = o.shipped
        ? DateTime.tryParse(o.shippedAt!)?.toLocal()
        : null;
    final shipParts = o.shipBy?.split('-');
    final dateText = o.shipped
        ? 'Shipped ${shippedDate?.month}/${shippedDate?.day}'
        : day == null
        ? 'No ship-by date'
        : day < 0
        ? '${-day}d overdue to ship'
        : day == 0
        ? 'Ship by today'
        : day == 1
        ? 'Ship by tomorrow'
        : 'Ship by ${shipParts?[1]}/${shipParts?[2]}';
    final p = Theme.of(context).extension<Palette>()!;
    final accent = switch (o.contextSlug) {
      'side_gig' || 'side-gig' || 'sidegig' => p.contexts[1],
      'social' => p.contexts[2],
      'shopping' => p.contexts[3],
      _ => p.contexts[0],
    };
    final isExpanded = expanded.contains(o.reminderId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(EzyDesignTokens.rowRadius),
        border: Border.all(color: p.hairline),
        boxShadow: [p.cardShadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${o.orderRef?.isNotEmpty == true ? o.orderRef : o.title}${o.recipientName?.isNotEmpty == true ? ' · ${o.recipientName}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit order',
                  onPressed: () => widget.onEditOrder(o.reminderId),
                  icon: const Icon(CupertinoIcons.pencil, size: 18),
                ),
                Flexible(
                  child: Text(
                    dateText,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${o.carrier ?? 'no carrier set'}${o.trackingNumber == null ? '' : ' · ${o.trackingNumber}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!o.shipped && isExpanded) ...[
              const SizedBox(height: 10),
              CarrierField(
                controller: carrierController,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              TrackingField(
                controller: trackingController,
                carrier: carrierController.text,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: pending.contains(o.reminderId)
                      ? null
                      : () => ship(o),
                  child: Text(
                    pending.contains(o.reminderId) ? 'Saving…' : 'Confirm',
                  ),
                ),
              ),
            ] else if (!o.shipped)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => expanded.add(o.reminderId)),
                  child: const Text('Mark shipped'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
