import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart' show Palette;
import '../../core/theme/tokens.g.dart';
import '../../shared/widgets/compact_date_time_picker.dart';
import '../focus/focus_controller.dart';
import '../focus/focus_models.dart';
import '../focus/focus_widgets.dart';
import '../add/today_add_flow.dart' show AddFlowNav, sideGigAddKinds;
import 'sidegig_repository.dart';

const gigSections = {
  'overview': 'Overview',
  'work': 'Work',
  'orders': 'Ship Queue',
  'followups': 'Follow-ups',
  'payments': 'Payments',
};
String gigSectionFor(GigItem r) => r.kind == 'order'
    ? 'orders'
    : r.kind == 'payment'
    ? 'payments'
    : r.kind == 'followup'
    ? 'followups'
    : 'work';
String gigError(Object e) => e is PostgrestException
    ? e.message
    : e.toString().replaceFirst('Bad state: ', '');

class SideGigPage extends StatefulWidget {
  const SideGigPage({
    super.key,
    required this.repository,
    required this.focus,
    this.openId,
    this.onSettings,
    this.onEditLegacy,
    this.onCreateWork,
  });
  final GigRepository repository;
  final FocusController focus;
  final String? openId;
  final VoidCallback? onSettings;
  final Future<void> Function(String id)? onEditLegacy;
  final Future<void> Function(bool order)? onCreateWork;
  @override
  State<SideGigPage> createState() => SideGigPageState();
}

class SideGigPageState extends State<SideGigPage> with WidgetsBindingObserver {
  GigDashboard? data;
  String? error;
  bool loading = true, closed = false;
  String section = 'overview';
  String? openedId;
  final scroll = ScrollController();
  final positions = <String, double>{};
  StreamSubscription<void>? subscription;
  Timer? debounce;
  int generation = 0;
  Palette get p => Theme.of(context).extension<Palette>()!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = widget.repository.changes.listen((_) {
      debounce?.cancel();
      debounce = Timer(
        const Duration(milliseconds: 120),
        () => unawaited(reload()),
      );
    });
    widget.focus.addListener(focusChanged);
    unawaited(reload());
  }

  String? lastSessionId;
  void focusChanged() {
    final id = widget.focus.session?.id;
    if (lastSessionId != id) {
      lastSessionId = id;
      unawaited(reload());
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SideGigPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openId != widget.openId) unawaited(reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    debounce?.cancel();
    widget.focus.removeListener(focusChanged);
    scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final gen = ++generation;
    try {
      final fresh = await widget.repository.load();
      if (!mounted || gen != generation) return;
      setState(() {
        data = fresh;
        loading = false;
        error = null;
      });
      final id = widget.openId;
      if (id != null && id != openedId) {
        final row = fresh.items
            .where((r) => r.id == id || r.text('reminder_id') == id)
            .firstOrNull;
        if (row != null) {
          openedId = id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(detail(row));
          });
        }
      }
    } catch (_) {
      if (mounted && gen == generation) {
        setState(() {
          loading = false;
          error = 'Could not refresh Side Gig. Your last loaded commitments are still shown.';
        });
      }
    }
  }

  void navigate(String next) {
    if (scroll.hasClients) positions[section] = scroll.offset;
    setState(() {
      section = next;
      closed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.jumpTo(
          (positions[next] ?? 0).clamp(0, scroll.position.maxScrollExtent),
        );
      }
    });
  }

  String date(String? raw) {
    if (raw == null || raw.isEmpty) return 'No date';
    final d = raw.length == 10
        ? DateTime.parse('${raw}T12:00:00Z')
        : DateTime.parse(raw);
    final day = raw.length == 10
        ? raw
        : focusLocalDate(d, data?.timezone ?? 'UTC');
    if (day == data?.localDate) return 'Today';
    if (data != null && day == addLocalDays(data!.localDate, 1)) {
      return 'Tomorrow';
    }
    final parts = day.split('-');
    final label =
        '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][int.parse(parts[1]) - 1]} ${int.parse(parts[2])}';
    if (raw.length == 10) return label;
    return '$label · ${focusTime12(focusLocalParts(d, data?.timezone ?? 'UTC').time)}';
  }

  String due(GigItem r) => r.status == 'cancelled'
      ? 'Cancelled'
      : r.kind == 'payment' && r.status == 'received'
      ? 'Received ${date(r.text('received_on'))}'
      : r.kind == 'followup' && r.status == 'resolved'
      ? 'Response recorded'
      : r.kind == 'order'
      ? r.text('shipped_at') != null
            ? 'Shipped ${date(r.text('shipped_at'))}'
            : r.text('ship_by') == null
            ? 'No ship-by date'
            : 'Ship by ${date(r.text('ship_by'))}'
      : r.text('due_at') == null
      ? 'No deadline'
      : '${r.kind == 'payment'
            ? 'Expected'
            : r.kind == 'followup'
            ? 'Check in'
            : 'Due'} ${date(r.text('due_at'))}';
  Widget card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.hairline),
      boxShadow: [p.cardShadow],
    ),
    child: Material(
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget heading(String text, {String? target, String label = 'View all'}) =>
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8, left: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                  color: p.secondary,
                ),
              ),
            ),
            if (target != null)
              TextButton(
                onPressed: () => navigate(target),
                child: Text(
                  '$label ›',
                  style: TextStyle(fontSize: 13, color: p.secondary),
                ),
              ),
          ],
        ),
      );
  Widget btn(String text, VoidCallback? onTap, {bool primary = false}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: primary ? p.text : p.surface,
            foregroundColor: primary
                ? Theme.of(context).scaffoldBackgroundColor
                : p.text,
            side: BorderSide(color: primary ? p.text : p.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onPressed: onTap,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
  Widget inset(String label, String value) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: p.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );
  Widget row(GigItem r) => InkWell(
    onTap: () => detail(r),
    child: Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.hairline, width: .5)),
      ),
      child: Row(
        children: [
          Icon(
            switch (r.kind) {
              'order' => CupertinoIcons.cube_box,
              'followup' => CupertinoIcons.chat_bubble,
              'payment' => CupertinoIcons.creditcard,
              _ => CupertinoIcons.checkmark_circle,
            },
            size: 20,
            color: r.kind == 'order' ? p.contexts[1] : p.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.kind == 'order' && r.text('reference')?.trim().isNotEmpty == true ? 'Ref ${r.text('reference')!.trim()} · ' : ''}${r.text('person')?.isNotEmpty == true ? '${r.text('person')} · ' : ''}${due(r)}${r.waiting ? ' · Waiting' : ''}${r.text('context_slug') != 'sidegig' ? ' · ${r.text('context_slug')}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        r.open &&
                            (r.dueDate(data?.timezone ?? 'UTC') ?? '9999')
                                    .compareTo(data?.localDate ?? '') <
                                0
                        ? Theme.of(context).colorScheme.error
                        : p.secondary,
                  ),
                ),
                if (section == 'work' &&
                    r.text('next_step')?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Next: ${r.text('next_step')}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                if (section == 'work' &&
                    widget.focus.assignmentFor(r.id) != null)
                  Text(
                    'Planned: ${focusOccurrenceName(widget.focus.assignmentFor(r.id)!.localDate, widget.focus.assignmentFor(r.id)!.startTime)}',
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
              ],
            ),
          ),
          if (r.kind == 'payment')
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                r.text('amount') != null
                    ? '${r.text('currency')} ${r.text('amount')}'
                    : 'Amount not set',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (r.kind == 'order' && widget.onEditLegacy != null)
            IconButton(
              tooltip: 'Edit order',
              onPressed: () async {
                await widget.onEditLegacy!(r.id);
                await reload();
              },
              icon: Icon(CupertinoIcons.pencil, size: 18, color: p.secondary),
            )
          else
            Icon(CupertinoIcons.chevron_right, size: 14, color: p.secondary),
        ],
      ),
    ),
  );
  Widget entry(String target, String title, String subtitle) => ListTile(
    minVerticalPadding: 12,
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 13, color: p.secondary),
    ),
    trailing: Icon(CupertinoIcons.chevron_right, size: 14, color: p.secondary),
    onTap: () => navigate(target),
  );
  Widget empty(String title, String message, {String? kind}) => card([
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(CupertinoIcons.briefcase, size: 32, color: p.contexts[1]),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.secondary),
            ),
          ),
          if (kind != null)
            SizedBox(
              width: double.infinity,
              child: btn(
                kind == 'work'
                    ? 'Add a task'
                    : kind == 'order'
                    ? 'Add an order'
                    : kind == 'payment'
                    ? 'Add expected payment'
                    : 'Add a follow-up',
                () => form(kind: kind),
                primary: true,
              ),
            ),
        ],
      ),
    ),
  ]);
  List<Widget> overview() {
    final d = data!, rows = d.items;
    final focus = widget.focus;
    final plannedIds =
        focus.state?.assignments.map((a) => a.reminderId).toSet() ?? {};
    final eligible = rows.where((r) => r.eligible).toList();
    final recent =
        eligible.where((r) => r.text('last_worked_at') != null).toList()..sort(
          (a, b) =>
              b.text('last_worked_at')!.compareTo(a.text('last_worked_at')!),
        );
    final resume =
        recent.firstOrNull ??
        eligible
            .where((r) => r.id == focus.state?.highlight?.reminderId)
            .firstOrNull ??
        eligible.where((r) => plannedIds.contains(r.id)).firstOrNull ??
        d.resume;
    final orders =
        rows
            .where(
              (r) =>
                  r.kind == 'order' && r.open && r.text('shipped_at') == null,
            )
            .toList()
          ..sort(d.compare);
    final upcoming = focus.upcoming
        .where((o) => o.contextSlug == 'sidegig')
        .firstOrNull;
    return [
      heading('Needs attention'),
      card(
        d.attention.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Nothing needs your attention today.',
                    style: TextStyle(color: p.secondary, fontSize: 14),
                  ),
                ),
              ]
            : d.attention.take(3).map(row).toList(),
      ),
      if (d.attention.length > 3)
        TextButton(
          onPressed: () => search(attentionOnly: true),
          child: Text('See all ${d.attention.length} commitments'),
        ),
      if (focus.session != null)
        FocusCard(controller: focus, activeOnly: true)
      else if (resume != null) ...[
        heading(
          'Pick up where you left off',
          target: 'work',
          label: 'Choose work',
        ),
        card([
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '● ${resume.text('initiative') ?? 'Side Gig'}',
                  style: TextStyle(fontSize: 13, color: p.secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  resume.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  due(resume),
                  style: TextStyle(fontSize: 13, color: p.secondary),
                ),
                if (resume.text('next_step')?.isNotEmpty == true)
                  inset(
                    resume.text('next_step_source') == 'session'
                        ? 'Next step from last time'
                        : 'Next step',
                    resume.text('next_step')!,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    btn(
                      'Start ${focus.assignmentFor(resume.id)?.plannedMinutes ?? resume.minutes} min',
                      focus.busy ? null : () => start(resume),
                      primary: true,
                    ),
                    btn(
                      'Plan a time',
                      () =>
                          openWorkOnThis(context, focus, resume.focusReminder),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ] else
        empty(
          'Make room for your next step.',
          'Add something you want to move forward. Clients, orders and payments can come later.',
          kind: 'work',
        ),
      if (upcoming != null) ...[
        heading('Your next focus time'),
        card([
          ListTile(
            onTap: () => openFocusOccurrence(context, focus, upcoming),
            title: Text(
              upcoming.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${upcoming.tasks.first.title}\n${upcoming.tasks.length} tasks · ${upcoming.sum} min planned${upcoming.overBudget ? '\n${upcoming.sum} minutes planned for ${upcoming.budget} minutes available. Choose what fits.' : ''}',
              style: TextStyle(fontSize: 13, color: p.secondary),
            ),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
          ),
        ]),
      ],
      heading('Ship Queue', target: 'orders', label: 'Open queue'),
      card(
        orders.isEmpty
            ? [entry('orders', 'Ship Queue', 'Orders, when you need them.')]
            : [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.cube_box,
                        color: p.contexts[1],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Ready to move',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${orders.length} open orders',
                        style: TextStyle(fontSize: 13, color: p.secondary),
                      ),
                    ],
                  ),
                ),
                ...orders.take(2).map(row),
              ],
      ),
      heading('Keep the loop closed'),
      card([
        entry(
          'followups',
          'Follow-ups',
          '${rows.where((r) => r.kind == 'followup' && r.open).length} open follow-ups',
        ),
        entry(
          'payments',
          'Payments',
          '${rows.where((r) => r.kind == 'payment' && r.open).length} expected payments',
        ),
      ]),
    ];
  }

  List<Widget> sectionBody() {
    final kind = section == 'orders'
        ? 'order'
        : section == 'payments'
        ? 'payment'
        : section == 'followups'
        ? 'followup'
        : 'work';
    final rows =
        data!.items
            .where(
              (r) =>
                  (section == 'work'
                      ? r.work && r.text('context_slug') == 'sidegig'
                      : r.kind == kind) &&
                  (closed
                      ? (r.kind == 'order'
                            ? r.text('shipped_at') != null
                            : [
                                'done',
                                'resolved',
                                'received',
                                'cancelled',
                              ].contains(r.status))
                      : (r.kind == 'order'
                            ? r.text('shipped_at') == null
                            : r.open)),
            )
            .toList()
          ..sort(data!.compare);
    final totals = gigMoney(rows.where((r) => r.status != 'cancelled'));
    return [
      if (widget.focus.session != null)
        FocusCard(controller: widget.focus, activeOnly: true),
      Row(
        children: [
          Expanded(
            child: Text(
              gigSections[section]!,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: () => form(kind: kind),
            icon: const Icon(CupertinoIcons.add, size: 15),
            label: Text(
              'Add ${kind == 'order'
                  ? 'order'
                  : kind == 'work'
                  ? 'task'
                  : ''}',
            ),
          ),
        ],
      ),
      Text(switch (section) {
        'orders' =>
          'Every order, from a shipping promise to a recorded shipment.',
        'payments' =>
          'Remember money you expect and record it when it arrives.',
        'followups' => 'Remember what you’re waiting for and when to check in.',
        _ =>
          'Client commitments and the small steps that move your gig forward.',
      }, style: TextStyle(color: p.secondary, fontSize: 13)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final value in [false, true])
            ChoiceChip(
              showCheckmark: false,
              selected: closed == value,
              onSelected: (_) => setState(() => closed = value),
              label: Text(
                section == 'orders'
                    ? value
                          ? 'Shipped'
                          : 'To ship'
                    : section == 'payments'
                    ? value
                          ? 'Received / cancelled'
                          : 'Expected'
                    : section == 'followups'
                    ? value
                          ? 'Resolved / cancelled'
                          : 'To follow up'
                    : value
                    ? 'Completed'
                    : 'Open',
              ),
              backgroundColor: p.surface,
              selectedColor: p.surface,
              side: BorderSide(color: p.hairline),
              labelStyle: TextStyle(
                color: closed == value ? p.text : p.secondary,
                fontSize: 13,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (section == 'payments' && rows.isNotEmpty)
        card([
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  closed ? 'Recorded received' : 'Still expected',
                  style: TextStyle(color: p.secondary, fontSize: 13),
                ),
                for (final total in totals.totals)
                  Text(
                    total,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  '${rows.length} payments${totals.unknown > 0 ? ' · ${totals.unknown} without an amount' : ''}',
                  style: TextStyle(fontSize: 12, color: p.secondary),
                ),
              ],
            ),
          ),
        ]),
      if (rows.isEmpty)
        empty(
          closed
              ? 'Your history will appear here.'
              : section == 'orders'
              ? 'A clear place for every order.'
              : section == 'followups'
              ? 'Nothing to chase right now.'
              : section == 'payments'
              ? 'Keep expected payments in view.'
              : 'What would you like to move forward?',
          'Start with one commitment. Extra details are optional.',
          kind: closed ? null : kind,
        )
      else
        card([
          for (final r in rows) ...[
            row(r),
            if (section == 'orders')
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.text('carrier') ?? 'Carrier not set'} · ${r.text('tracking') ?? 'No tracking added'}',
                      style: TextStyle(color: p.secondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (r.text('shipped_at') == null)
                      r.open
                          ? btn(
                              'Mark shipped',
                              () => form(item: r, action: 'ship'),
                              primary: true,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'This reminder is ${r.status}, with no shipment recorded.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                                btn(
                                  'Reopen for shipping',
                                  () => form(item: r, action: 'reopen_order'),
                                ),
                              ],
                            ),
                  ],
                ),
              ),
          ],
        ]),
      Text(
        section == 'orders'
            ? 'Shipping records fulfillment. Payments stay separate. Orders from other contexts remain visible and labelled.'
            : section == 'payments'
            ? 'Manually recorded payments. No bank connection or payment processing.'
            : section == 'followups'
            ? 'Record contact after you reach out elsewhere. No message is sent.'
            : 'Waiting work stays visible and is left out of focus suggestions.',
        style: TextStyle(fontSize: 12, color: p.secondary),
      ),
    ];
  }

  Future<void> start(GigItem r) async {
    final f = widget.focus;
    if (f.session != null) {
      await openFocus(context, f);
      return;
    }
    final assignment = f.assignmentFor(r.id);
    final ok = assignment == null
        ? await f.startReminder(
            r.focusReminder,
            r.minutes,
            intent: r.text('next_step'),
          )
        : await f.startAssigned(assignment, intent: r.text('next_step'));
    if (mounted) {
      if (ok) {
        await openFocus(context, f);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(f.error ?? 'Could not start focus')),
        );
      }
    }
  }

  Future<Object?> showSheet(String title, Widget body) =>
      showModalBottomSheet<Object?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .4),
        sheetAnimationStyle: AnimationStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : EzyDesignTokens.sheetDuration,
          curve: EzyDesignTokens.sheetCurve,
        ),
        builder: (ctx) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .86,
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [p.sheetShadow],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 14),
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(CupertinoIcons.xmark, size: 18),
                    ),
                  ],
                ),
                Material(color: p.surface, child: body),
              ],
            ),
          ),
        ),
      );
  Future<void> add() async {
    final kind = await showSheet(
      'Add to Side Gig',
      Column(
        children: [
          for (final entry in sideGigAddKinds.entries)
            InkWell(
              onTap: () => Navigator.pop(context, entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value[0],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            entry.value[1],
                            style: TextStyle(fontSize: 13, color: p.secondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: p.secondary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (mounted && kind is String) await form(kind: kind);
  }

  Future<void> follow(GigItem r, {bool block = false}) async {
    final exists = data!.items
        .where(
          (f) =>
              f.kind == 'followup' &&
              f.open &&
              (r.kind == 'payment'
                  ? f.text('related_payment_id') == r.id
                  : f.text('related_id') == r.text('reminder_id')),
        )
        .firstOrNull;
    if (exists != null) {
      await detail(exists);
      return;
    }
    await form(
      kind: 'followup',
      seed: {
        'title': 'Follow up: ${r.title}',
        'person': r.text('person') ?? '',
        'related_id': r.kind != 'payment' && r.text('context_slug') == 'sidegig'
            ? r.text('reminder_id')
            : null,
        'related_payment_id': r.kind == 'payment' ? r.id : null,
        'block_work': block,
      },
    );
  }

  Future<void> form({
    String? kind,
    GigItem? item,
    String? action,
    Map<String, dynamic>? seed,
  }) async {
    if (item == null &&
        action == null &&
        (kind == 'work' || kind == 'order') &&
        widget.onCreateWork != null) {
      await widget.onCreateWork!(kind == 'order');
      if (mounted) {
        await reload();
        await widget.focus.reload();
        if (mounted) navigate(kind == 'order' ? 'orders' : 'work');
      }
      return;
    }
    final current = data;
    if (current == null) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .4),
      sheetAnimationStyle: AnimationStyle(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : EzyDesignTokens.sheetDuration,
        curve: EzyDesignTokens.sheetCurve,
      ),
      builder: (_) => GigFormSheet(
        repository: widget.repository,
        dashboard: current,
        kind: kind ?? item?.kind ?? 'work',
        item: item,
        action:
            action ??
            (kind == 'work' || kind == 'order'
                ? 'save_work'
                : item?.work == true
                ? 'save_work'
                : 'save_${kind ?? item?.kind}'),
        seed: seed,
      ),
    );
    if (!mounted || result != true) return;
    await reload();
    await widget.focus.reload();
    if (!mounted) return;
    if (action == 'ship' && item != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Shipment recorded. Payment stays separate.'),
          action: SnackBarAction(
            label: 'Add follow-up',
            onPressed: () => follow(item),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to Side Gig')));
    }
    if (action == null && kind != null) {
      navigate(
        kind == 'order'
            ? 'orders'
            : kind == 'payment'
            ? 'payments'
            : kind == 'followup'
            ? 'followups'
            : 'work',
      );
    }
  }

  Future<void> search({bool attentionOnly = false}) async {
    final picked = await showSheet(
      attentionOnly ? 'Needs attention' : 'Search Side Gig',
      _GigSearch(
        items: attentionOnly ? data?.attention ?? [] : data?.items ?? [],
        searchable: !attentionOnly,
      ),
    );
    if (mounted && picked is GigItem) await detail(picked);
  }

  Future<void> detail(GigItem r) async {
    Widget option(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: btn(label, () => Navigator.pop(context, value)),
    );
    final related = data!.items
        .where(
          (x) => x.id == (r.text('related_payment_id') ?? r.text('related_id')),
        )
        .firstOrNull;
    final command = await showSheet(
      'Commitment details',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '● Side Gig · ${r.kind}',
            style: TextStyle(color: p.secondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            r.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            r.text('person') ?? r.text('initiative') ?? '',
            style: TextStyle(color: p.secondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Text(
            '${due(r)}\nStatus: ${r.waiting ? 'Waiting' : r.status}',
            style: const TextStyle(fontSize: 13),
          ),
          if (r.kind == 'payment')
            Text(
              '${r.text('currency') ?? ''} ${r.text('amount') ?? 'Amount not set'}${r.text('received_on') != null ? '\nReceived ${date(r.text('received_on'))}' : ''}',
            ),
          if (r.kind == 'order')
            Text(
              '${r.text('reference') ?? ''}\n${r.text('carrier') ?? 'Carrier not set'} · ${r.text('tracking') ?? 'No tracking added'}',
            ),
          if (r.text('last_contact_at') != null)
            Text(
              'Last contact: ${date(r.text('last_contact_at'))}',
              style: TextStyle(color: p.secondary, fontSize: 13),
            ),
          if (r.text('next_step')?.isNotEmpty == true)
            inset(
              r.text('next_step_source') == 'session'
                  ? 'Next step from last time'
                  : 'Next step',
              r.text('next_step')!,
            ),
          if (r.text('notes')?.isNotEmpty == true)
            inset('Notes', r.text('notes')!),
          if (related != null) option('Related: ${related.title}', 'related'),
          if (r.eligible) ...[
            option(
              widget.focus.session != null
                  ? 'Open current session'
                  : 'Start ${r.minutes} min',
              'focus',
            ),
            option('Work on this', 'plan'),
          ],
          if (r.kind == 'order') ...[
            option(
              r.text('shipped_at') != null
                  ? 'Edit carrier / tracking'
                  : 'Mark shipped',
              r.text('shipped_at') != null ? 'shipping' : 'ship',
            ),
            option('Add / view buyer follow-up', 'follow'),
          ],
          if (r.kind == 'work' && r.open) ...[
            option('Mark task done', 'complete'),
            option(
              r.waiting ? 'View / add follow-up' : 'Waiting for someone',
              'wait',
            ),
            option('Add a follow-up', 'follow'),
          ],
          if (r.kind == 'followup' && r.open) ...[
            option('Record follow-up', 'contact'),
            option('Response received', 'resolve'),
          ],
          if (r.kind == 'payment' && r.open) ...[
            option('Record received', 'receive'),
            option('Add / view follow-up', 'follow'),
          ],
          if (r.open) option('Edit details', 'edit'),
          if (!r.work && r.open) option('Cancel commitment', 'cancel'),
          if (r.data['activity'] is List) ...[
            heading('History'),
            for (final a in r.data['activity'] as List)
              Text(
                '${a['action']} · ${date(a['happened_at'] as String?)}${a['notes'] != null ? ' · ${a['notes']}' : ''}',
                style: TextStyle(fontSize: 13, color: p.secondary),
              ),
          ],
        ],
      ),
    );
    if (!mounted || command == null) return;
    if (command == 'focus') {
      await start(r);
    } else if (command == 'plan') {
      await openWorkOnThis(context, widget.focus, r.focusReminder);
    } else if (command == 'related') {
      await detail(related!);
    } else if (command == 'follow' || command == 'wait') {
      await follow(r, block: command == 'wait' && !r.waiting);
    } else if (command == 'edit' && r.text('context_slug') != 'sidegig') {
      await widget.onEditLegacy?.call(r.id);
      await reload();
    } else {
      await form(
        item: r,
        action: command == 'edit'
            ? (r.work ? 'save_work' : 'save_${r.kind}')
            : command as String,
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Side Gig',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search Side Gig',
                    onPressed: () => search(),
                    icon: const Icon(CupertinoIcons.search),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: widget.onSettings,
                    icon: const Icon(CupertinoIcons.gear),
                  ),
                ],
              ),
              Text(
                'Your work. Your own pace.',
                style: TextStyle(color: p.secondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final entry in gigSections.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 8),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            backgroundColor: section == entry.key
                                ? p.contexts[1].withValues(alpha: .1)
                                : p.surface,
                            foregroundColor: section == entry.key
                                ? p.text
                                : p.secondary,
                            side: BorderSide(
                              color: section == entry.key
                                  ? p.contexts[1]
                                  : p.hairline,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () => navigate(entry.key),
                          child: Text(entry.value),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (error != null)
                  card([
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 13,
                            ),
                          ),
                          btn('Retry loading', reload),
                        ],
                      ),
                    ),
                  ]),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (data != null)
                  ...(section == 'overview' ? overview() : sectionBody()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
              boxShadow: [
                Theme.of(context).brightness == Brightness.dark
                    ? EzyDesignTokens.darkFloatShadow
                    : EzyDesignTokens.lightFloatShadow,
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: data == null ? null : add,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.add, color: p.contexts[1], size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add to Side Gig',
                        style: TextStyle(fontSize: 15, color: p.secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GigSearch extends StatefulWidget {
  const _GigSearch({required this.items, required this.searchable});
  final List<GigItem> items;
  final bool searchable;
  @override
  State<_GigSearch> createState() => _GigSearchState();
}

class _GigSearchState extends State<_GigSearch> {
  String query = '';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.searchable)
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Find a commitment',
            hintText: 'Title, client, order reference…',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
      for (final r in widget.items.where(
        (r) => '${r.title} ${r.text('person')} ${r.text('reference')}'
            .toLowerCase()
            .contains(query.toLowerCase()),
      ))
        ListTile(
          title: Text(r.title),
          subtitle: Text(r.text('person') ?? r.kind),
          onTap: () => Navigator.pop(context, r),
        ),
    ],
  );
}

class GigFormSheet extends StatefulWidget {
  const GigFormSheet({
    super.key,
    required this.repository,
    required this.dashboard,
    required this.kind,
    required this.action,
    this.item,
    this.seed,
    this.contexts,
    this.contextId,
    this.onContextChanged,
    this.initiallyDirty = false,
    this.flow,
    this.onSaved,
  });
  final GigRepository repository;
  final GigDashboard dashboard;
  final String kind, action;
  final GigItem? item;
  final Map<String, dynamic>? seed;
  final List<({String id, String name})>? contexts;
  final String? contextId;
  final void Function(String id, Map<String, dynamic> draft)? onContextChanged;
  final bool initiallyDirty;

  /// Hosted by Today's Add flow: Back/Close go through the flow.
  final AddFlowNav? flow;

  /// The saved record ID and its kind (`order` when a task became an order).
  final void Function(String id, String kind)? onSaved;
  @override
  State<GigFormSheet> createState() => _GigFormSheetState();
}

class _GigFormSheetState extends State<GigFormSheet> {
  final fields = <String, TextEditingController>{};
  final dates = <String, String?>{};
  bool order = false,
      details = false,
      unblock = true,
      resolveFollowup = false,
      busy = false,
      dirty = false,
      discard = false;
  String? error;
  late final String id;
  String? operation, payloadKey;
  double? dragY;
  Palette get p => Theme.of(context).extension<Palette>()!;
  bool get save => widget.action.startsWith('save_');
  bool get work => widget.kind == 'work' || widget.kind == 'order';
  @override
  void initState() {
    super.initState();
    final r = widget.item, seed = widget.seed ?? {};
    id = r?.id ?? newFocusId();
    order = widget.kind == 'order';
    details =
        (r?.text('person') ?? seed['person']?.toString() ?? '').isNotEmpty ||
        (r?.text('initiative') ?? seed['initiative']?.toString() ?? '')
            .isNotEmpty;
    for (final key in [
      'title',
      'notes',
      'person',
      'initiative',
      'next_step',
      'reference',
      'amount',
      'currency',
      'carrier',
      'tracking',
      'minutes',
    ]) {
      fields[key] = TextEditingController(
        text:
            r?.text(key) ??
            seed[key]?.toString() ??
            (key == 'currency'
                ? 'USD'
                : key == 'minutes'
                ? '15'
                : ''),
      );
      fields[key]!.addListener(() => dirty = true);
    }
    dates['due_at'] = r?.text('due_at') ?? seed['due_at'] as String?;
    dates['ship_by'] = r?.text('ship_by') ?? seed['ship_by'] as String?;
    dirty = widget.initiallyDirty;
    dates['received_on'] = widget.dashboard.localDate;
    if (widget.action == 'contact') {
      dates['due_at'] = null;
      fields['notes']!.clear();
      dirty = false;
    }
    if (widget.action == 'receive') {
      fields['notes']!.clear();
      dirty = false;
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void close() {
    if (busy) return;
    if (widget.flow != null) {
      widget.flow!.close(dirty);
      return;
    }
    if (dirty) {
      setState(() => discard = true);
    } else {
      Navigator.pop(context);
    }
  }

  Widget input(
    String key,
    String label, {
    bool multiline = false,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      key: ValueKey('gig-field-$key'),
      controller: fields[key],
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? null : 1,
      maxLength: key == 'next_step'
          ? 500
          : key == 'title'
          ? 180
          : null,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : multiline
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.hairline),
        ),
      ),
      style: const TextStyle(fontSize: 15),
    ),
  );
  Widget button(String label, VoidCallback? action, {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 44),
            backgroundColor: primary ? p.text : p.surface,
            foregroundColor: primary
                ? Theme.of(context).scaffoldBackgroundColor
                : p.text,
            side: BorderSide(color: primary ? p.text : p.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
          ),
          onPressed: action,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
  Widget date(String key, String label, {bool optional = false}) {
    final raw = dates[key];
    String display = 'Choose date';
    DateTime? local;
    if (raw != null) {
      final parts = raw.length == 10
          ? (date: raw, time: '09:00')
          : focusLocalParts(DateTime.parse(raw), widget.dashboard.timezone);
      local = DateTime.parse('${parts.date}T${parts.time}');
      display =
          '${parts.date}${raw.length > 10 ? ' · ${focusTime12(parts.time)}' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          button(display, () async {
            final now = focusLocalParts(
              DateTime.now(),
              widget.dashboard.timezone,
            );
            final value = await CompactDateTimePicker.show(
              context,
              initial: local ?? DateTime.parse('${now.date}T09:00'),
            );
            if (value != null && mounted) {
              final day =
                  '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
              setState(() {
                dates[key] = key == 'ship_by' || key == 'received_on'
                    ? day
                    : focusOccurrenceStart(
                        day,
                        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
                        widget.dashboard.timezone,
                      ).toUtc().toIso8601String();
                dirty = true;
              });
            }
          }),
          if (optional && raw != null)
            TextButton(
              onPressed: () => setState(() {
                dates[key] = null;
                dirty = true;
              }),
              child: const Text('Clear date'),
            ),
          Text(
            widget.dashboard.timezone,
            style: TextStyle(fontSize: 11, color: p.secondary),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> snapshot() => {
    for (final entry in fields.entries) entry.key: entry.value.text,
    'due_at': dates['due_at'],
    'ship_by': dates['ship_by'],
    'is_order': order,
    if (widget.seed?['channels'] != null) 'channels': widget.seed!['channels'],
  };

  Future<void> submit() async {
    if (busy) return;
    setState(() => error = null);
    final payload = <String, dynamic>{};
    String text(String key) => fields[key]!.text.trim();
    try {
      if (save) {
        if (text('title').isEmpty) throw StateError('Title is required.');
        payload.addAll({
          'title': text('title'),
          'notes': text('notes'),
          'person': text('person'),
          'reference': text('reference'),
          'due_at': dates['due_at'],
        });
        if (work) {
          final minutes = int.tryParse(text('minutes'));
          if (minutes == null || minutes < 1 || minutes > 180) {
            throw StateError('Choose a whole number of minutes from 1 to 180.');
          }
          payload.addAll({
            'is_order': order,
            'ship_by': dates['ship_by'],
            'carrier': text('carrier'),
            'tracking': text('tracking'),
            'initiative': text('initiative'),
            'next_step': text('next_step'),
            'minutes': minutes,
            if (widget.seed?['channels'] case final List channels
                when channels.isNotEmpty)
              'channels': channels,
          });
        } else {
          if (dates['due_at'] == null) {
            throw StateError('Choose a date, then tap OK.');
          }
          payload.addAll({
            'related_id':
                widget.item?.text('related_id') ?? widget.seed?['related_id'],
            'related_payment_id':
                widget.item?.text('related_payment_id') ??
                widget.seed?['related_payment_id'],
            'block_work': widget.seed?['block_work'] ?? false,
          });
          if (widget.kind == 'payment') {
            if (text('amount').isNotEmpty &&
                !RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(text('amount'))) {
              throw StateError(
                'Enter a positive amount with up to two decimal places.',
              );
            }
            payload.addAll({
              'amount': text('amount').isEmpty ? null : text('amount'),
              'currency': text('currency').toUpperCase(),
            });
          }
        }
      } else if (widget.action == 'ship' || widget.action == 'shipping') {
        payload.addAll({
          'carrier': text('carrier'),
          'tracking': text('tracking'),
        });
      } else if (widget.action == 'contact') {
        final due = DateTime.tryParse(dates['due_at'] ?? '');
        if (due == null || !due.isAfter(DateTime.now())) {
          throw StateError('Choose a future check-in time.');
        }
        payload.addAll({'due_at': dates['due_at'], 'notes': text('notes')});
      } else if (widget.action == 'receive') {
        payload.addAll({
          'received_on': dates['received_on'],
          'notes': text('notes'),
          'resolve_followup': resolveFollowup,
        });
      } else if (widget.action == 'resolve') {
        payload['unblock'] = unblock;
      }
      final key = jsonEncode(payload);
      if (key != payloadKey) {
        operation = newFocusId();
        payloadKey = key;
      }
      setState(() => busy = true);
      await widget.repository.mutate(operation!, widget.action, id, payload);
      if (mounted) {
        dirty = false;
        widget.onSaved?.call(
          id,
          widget.action == 'save_work'
              ? (order ? 'order' : 'work')
              : widget.kind,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = gigError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = save
        ? widget.item != null
              ? 'Edit details'
              : (widget.seed?['block_work'] == true)
              ? 'Waiting for someone'
              : widget.kind == 'work'
              ? 'New task'
              : widget.kind == 'order'
              ? 'New order'
              : widget.kind == 'payment'
              ? 'Expected payment'
              : 'New follow-up'
        : switch (widget.action) {
            'ship' => 'Mark shipped',
            'shipping' => 'Shipping details',
            'receive' => 'Record payment received',
            'contact' => 'Record follow-up',
            'resolve' => 'Response received',
            'complete' => 'Complete task',
            'reopen_order' => 'Reopen for shipping',
            _ => 'Cancel commitment',
          };
    return PopScope(
      canPop: widget.flow != null || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.flow == null) close();
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [p.sheetShadow],
        ),
        child: Material(
          color: p.surface,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) => dragY = d.globalPosition.dy,
                  onVerticalDragEnd: (_) {
                    dragY = null;
                  },
                  onVerticalDragUpdate: (d) {
                    if (dragY != null && d.globalPosition.dy - dragY! > 100) {
                      dragY = null;
                      close();
                    }
                  },
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      margin: const EdgeInsets.only(top: 8, bottom: 14),
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (widget.flow != null)
                      IconButton(
                        tooltip: 'Back',
                        onPressed: busy ? null : () => widget.flow!.back(dirty),
                        icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      icon: const Icon(CupertinoIcons.xmark, size: 18),
                    ),
                  ],
                ),
                if (widget.contexts != null && widget.onContextChanged != null)
                  DropdownButtonFormField<String>(
                    initialValue: widget.contextId,
                    decoration: const InputDecoration(
                      labelText: 'Context',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in widget.contexts!)
                        DropdownMenuItem(
                          key: ValueKey('context-option-${c.id}'),
                          value: c.id,
                          child: Text(c.name),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (id) {
                            if (id != null && id != widget.contextId) {
                              widget.onContextChanged!(id, snapshot());
                            }
                          },
                  )
                else
                  Text(
                    '● Side Gig',
                    style: TextStyle(color: p.contexts[1], fontSize: 13),
                  ),
                if (!save)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.item?.title ?? '',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (save) ...[
                  input('title', 'What do you need to remember?'),
                  date(
                    'due_at',
                    work
                        ? 'Deadline (optional)'
                        : widget.kind == 'payment'
                        ? 'Expected by'
                        : 'Next follow-up',
                    optional: work,
                  ),
                  if (work) ...[
                    if (widget.item?.text('shipped_at') == null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'This is an order',
                          style: TextStyle(fontSize: 14),
                        ),
                        activeThumbColor: p.contexts[1],
                        value: order,
                        onChanged: (v) => setState(() {
                          order = v;
                          dirty = true;
                        }),
                      ),
                    if (order) ...[
                      input('reference', 'Order reference (optional)'),
                      input('person', 'Recipient (optional)'),
                      date('ship_by', 'Ship by (optional)', optional: true),
                      Text(
                        'Without a reminder time, we’ll remind you at 9 AM on the ship-by day.',
                        style: TextStyle(fontSize: 12, color: p.secondary),
                      ),
                      input('carrier', 'Carrier (optional)'),
                      input('tracking', 'Tracking (optional)'),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const ValueKey('gig-details-toggle'),
                      title: const Text(
                        'Add client or initiative details',
                        style: TextStyle(fontSize: 14),
                      ),
                      activeThumbColor: p.contexts[1],
                      value: details,
                      onChanged: (v) => setState(() => details = v),
                    ),
                    if (details) ...[
                      if (!order) input('person', 'Client / buyer (optional)'),
                      input('initiative', 'Initiative (optional)'),
                    ],
                    input(
                      'next_step',
                      'Next small step (optional)',
                      multiline: true,
                    ),
                    input('minutes', 'Usually takes (minutes)', number: true),
                  ] else ...[
                    input('person', 'Person or business (optional)'),
                    if (widget.kind == 'payment') ...[
                      Row(
                        children: [
                          Expanded(
                            child: input(
                              'amount',
                              'Amount (optional)',
                              number: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 90,
                            child: input('currency', 'Currency'),
                          ),
                        ],
                      ),
                      input('reference', 'Reference (optional)'),
                    ],
                  ],
                  input('notes', 'Notes (optional)', multiline: true),
                ] else if (widget.action == 'ship' ||
                    widget.action == 'shipping') ...[
                  input('carrier', 'Carrier (optional)'),
                  input('tracking', 'Tracking number (optional)'),
                  const SizedBox(height: 12),
                  Text(
                    widget.action == 'ship'
                        ? 'Confirm after handing the order to the carrier. Payment stays separate.'
                        : 'Changing tracking keeps the original shipment date.',
                    style: TextStyle(color: p.secondary, fontSize: 13),
                  ),
                ] else if (widget.action == 'contact') ...[
                  input('notes', 'What happened? (optional)', multiline: true),
                  date('due_at', 'Next check-in'),
                  Text(
                    'Records contact made elsewhere. No message is sent.',
                    style: TextStyle(color: p.secondary, fontSize: 13),
                  ),
                ] else if (widget.action == 'receive') ...[
                  date('received_on', 'Received on'),
                  input('notes', 'Receipt note (optional)', multiline: true),
                  if (widget.dashboard.items.any(
                    (r) =>
                        r.open &&
                        r.text('related_payment_id') == widget.item?.id,
                  ))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Also resolve this payment’s follow-up',
                      ),
                      value: resolveFollowup,
                      onChanged: (v) => setState(() {
                        resolveFollowup = v ?? false;
                        dirty = true;
                      }),
                    ),
                  Text(
                    'Record the full payment after it arrives. No money is moved.',
                    style: TextStyle(color: p.secondary, fontSize: 13),
                  ),
                ] else if (widget.action == 'resolve') ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Make the related work ready to start'),
                    value: unblock,
                    onChanged: (v) => setState(() {
                      unblock = v ?? false;
                      dirty = true;
                    }),
                  ),
                  Text(
                    'The related task stays open.',
                    style: TextStyle(color: p.secondary, fontSize: 13),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.action == 'complete'
                          ? 'Complete this task. Payments and follow-ups stay separate.'
                          : widget.action == 'reopen_order'
                          ? 'Reopen this reminder so its shipment can be recorded.'
                          : 'Cancel this commitment and stop its reminders. History is retained.',
                      style: TextStyle(color: p.secondary, fontSize: 14),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                button(
                  busy
                      ? 'Saving…'
                      : save
                      ? 'Save'
                      : widget.action == 'ship'
                      ? 'Confirm shipped'
                      : widget.action == 'receive'
                      ? 'Confirm received'
                      : widget.action == 'contact'
                      ? 'Save follow-up'
                      : widget.action == 'resolve'
                      ? 'Resolve follow-up'
                      : widget.action == 'complete'
                      ? 'Mark task done'
                      : widget.action == 'reopen_order'
                      ? 'Reopen for shipping'
                      : widget.action == 'cancel'
                      ? 'Cancel commitment'
                      : 'Save shipping details',
                  busy ? null : submit,
                  primary: true,
                ),
                if (discard) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Discard these changes?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  button(
                    'Keep editing',
                    () => setState(() => discard = false),
                    primary: true,
                  ),
                  button('Discard', () {
                    dirty = false;
                    Navigator.pop(context);
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
