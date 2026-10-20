import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.g.dart';
import 'focus_controller.dart';
import 'focus_models.dart';
import 'focus_repository.dart';

part 'focus_ui.dart';
part 'focus_sheet.dart';
part 'focus_planning.dart';

// ---------------------------------------------------------------------------
// Entry points. One sheet at a time; modes swap inside the open sheet.
// ---------------------------------------------------------------------------

/// Where the sheet starts. The session and review modes are chosen from the
/// controller when a session exists.
enum _Mode {
  choose,
  setup,
  session,
  review,
  after,
  occurrence,
  plan,
  times,
  timeEdit,
}

class _Route {
  const _Route(
    this.mode, {
    this.reminder,
    this.assignment,
    this.occurrenceKey,
    this.time,
    this.after,
    this.fromSettings = false,
    this.notice,
    this.undo,
  });
  final _Mode mode;
  final FocusReminder? reminder;
  final FocusAssignment? assignment;
  final String? occurrenceKey;
  final FocusTimeItem? time;
  final _AfterInfo? after;
  final bool fromSettings;

  /// One-line confirmation shown at the top of the Focus times list
  /// ("Focus time saved", "… archived" with Undo). Never a timed toast, so it
  /// cannot hide behind the sheet scrim or leave timers behind.
  final String? notice;
  final Future<void> Function()? undo;
}

/// Host callback for transient messages shown after a sheet closes.
typedef FocusNotify = void Function(String message);

Future<void> _openSheet(
  BuildContext context,
  FocusController controller,
  _Route route,
) async {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void notify(String message) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .4),
    constraints: const BoxConstraints(maxWidth: 448),
    sheetAnimationStyle: AnimationStyle(
      duration: reduced ? Duration.zero : EzyDesignTokens.sheetDuration,
      reverseDuration: reduced ? Duration.zero : EzyDesignTokens.sheetDuration,
      curve: reduced ? Curves.linear : EzyDesignTokens.sheetCurve,
      reverseCurve: reduced ? Curves.linear : EzyDesignTokens.sheetCurve,
    ),
    builder: (_) =>
        _FocusSheet(controller: controller, route: route, notify: notify),
  );
}

/// Session (or review) when one exists; otherwise setup for [reminder], or the
/// "Today's focus" chooser. [assignment] binds the start to planned work.
Future<void> openFocus(
  BuildContext context,
  FocusController controller, {
  FocusReminder? reminder,
  FocusAssignment? assignment,
}) {
  final session = controller.session;
  final _Mode mode = session != null
      ? (session.awaitingFinish(controller.now) ? _Mode.review : _Mode.session)
      : reminder != null
      ? _Mode.setup
      : _Mode.choose;
  return _openSheet(
    context,
    controller,
    _Route(mode, reminder: reminder, assignment: assignment),
  );
}

/// "Work on this": plan a reminder into a Focus time or another day.
Future<void> openWorkOnThis(
  BuildContext context,
  FocusController controller,
  FocusReminder reminder,
) => _openSheet(context, controller, _Route(_Mode.plan, reminder: reminder));

/// Focus times list and editor (Today "Manage", Settings → Focus).
Future<void> openFocusTimes(
  BuildContext context,
  FocusController controller, {
  bool fromSettings = false,
}) => _openSheet(
  context,
  controller,
  _Route(_Mode.times, fromSettings: fromSettings),
);

/// The occurrence sheet: ordered tasks with Start / Skip per task.
Future<void> openFocusOccurrence(
  BuildContext context,
  FocusController controller,
  FocusOccurrence occurrence,
) => _openSheet(
  context,
  controller,
  _Route(_Mode.occurrence, occurrenceKey: occurrence.key),
);

// ---------------------------------------------------------------------------
// Today: focus card, missed recovery card, "Your focus times".
// ---------------------------------------------------------------------------

class FocusCard extends StatelessWidget {
  const FocusCard({
    super.key,
    required this.controller,
    this.activeOnly = false,
  });
  final FocusController controller;

  /// Only show a running/paused session (used by the All tab).
  final bool activeOnly;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      if (activeOnly && c.session == null) return const SizedBox.shrink();
      final missed = activeOnly || !c.planning ? const <MissedFocusItem>[] : c.missedItems;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHead("Today's focus"),
            _TodayCard(controller: c, host: context),
            if (missed.isNotEmpty)
              _MissedCard(
                controller: c,
                host: context,
                item: missed.first,
                more: missed.length - 1,
              ),
            if (!activeOnly && c.planning && c.state != null)
              _FocusTimesSection(controller: c),
          ],
        ),
      );
    },
  );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.controller, required this.host});
  final FocusController controller;

  /// Context of the FocusCard itself. A sub-card can disappear when its action
  /// succeeds (the missed card, for instance), so sheets open from here.
  final BuildContext host;
  FocusController get c => controller;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    if (c.state == null) {
      return _Card(
        child: c.error != null
            ? _ErrorBlock(controller: c)
            : Text('Loading focus…', style: TextStyle(color: t.text2)),
      );
    }
    final kind = c.cardKind;
    final body = switch (kind) {
      FocusCardKind.running ||
      FocusCardKind.paused ||
      FocusCardKind.timeUp => _sessionBody(context, kind),
      FocusCardKind.highlight => _highlightBody(context),
      FocusCardKind.upNext => _upNextBody(context),
      FocusCardKind.empty => _emptyBody(context),
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (c.error != null) _ErrorBlock(controller: c),
        ],
      ),
    );
  }

  Widget _sessionBody(BuildContext context, FocusCardKind kind) {
    final t = _T(context);
    final s = c.session!;
    final label = switch (kind) {
      FocusCardKind.timeUp => 'Time is up',
      FocusCardKind.paused => 'Paused',
      _ => 'In focus',
    };
    final up = kind == FocusCardKind.timeUp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CtxLine(s.contextSlug, suffix: label),
        const SizedBox(height: 6),
        Text(
          s.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        if (up)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('How did it go?', style: TextStyle(fontSize: 13, color: t.text2)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Focus time remaining',
                child: Text(
                  _mmss(s.remainingSeconds(c.now)),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: kind == FocusCardKind.paused ? t.text2 : t.text,
                  ),
                ),
              ),
            ),
            _Btn(
              up ? 'Review session' : 'Open session',
              () => openFocus(context, c),
              style: up ? _BS.primary : _BS.outline,
            ),
          ],
        ),
      ],
    );
  }

  Widget _startRow(BuildContext context, int minutes, VoidCallback start, VoidCallback chip) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: _Btn(
              c.busy ? 'Starting…' : 'Start $minutes min',
              c.busy ? null : start,
              block: true,
              key: const ValueKey('focus-card-start'),
            ),
          ),
          const SizedBox(width: 8),
          _Btn(
            '$minutes min',
            chip,
            style: _BS.duration,
            semanticLabel: 'Change length, currently $minutes minutes',
            key: const ValueKey('focus-card-duration'),
          ),
        ],
      ),
    );
  }

  Widget _highlightBody(BuildContext context) {
    final reminder = c.reminderById(c.state!.highlight!.reminderId)!;
    final due = reminder.deadline.label(c.timezone);
    final step = c.nextStepFor(reminder.id);
    final minutes = c.preferredMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _CtxLine(reminder.contextSlug)),
            Transform.translate(
              offset: const Offset(10, 0),
              child: _Btn(
                'Change',
                () => openFocus(context, c),
                style: _BS.ghost,
                key: const ValueKey('focus-card-change'),
              ),
            ),
          ],
        ),
        Text(
          reminder.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        if (due.isNotEmpty) _Note(due, top: 3, size: 13),
        if (step != null) _Inset('Next step from last time', step),
        _startRow(
          context,
          minutes,
          () async {
                        if (await c.startReminder(reminder, minutes) && host.mounted) {
              _announce(host, 'Focus started, $minutes minutes');
              unawaited(openFocus(host, c));
            }
          },
          () => openFocus(context, c, reminder: reminder),
        ),
      ],
    );
  }

  Widget _upNextBody(BuildContext context) {
    final o = c.upcoming.first;
    final a = o.tasks.first;
    final reminder = c.reminderById(a.reminderId);
    final due = (reminder?.deadline ?? a.deadline).label(c.timezone);
    final step = c.nextStepFor(a.reminderId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CtxLine(a.contextSlug, label: 'Up next', suffix: o.name),
        const SizedBox(height: 6),
        Text(
          reminder?.title ?? a.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        _Note(
          '${_contextName(a.contextSlug)} · ${a.plannedMinutes} min planned · ${focusShortDate(o.localDate)}',
          top: 3,
          size: 13,
        ),
        if (due.isNotEmpty) _Note(due, top: 3, size: 13),
        if (step != null) _Inset('Next step from last time', step),
        _startRow(
          context,
          a.plannedMinutes,
          () async {
                        if (await c.startAssigned(a) && host.mounted) {
              _announce(host, 'Focus started, ${a.plannedMinutes} minutes');
              unawaited(openFocus(host, c));
            }
          },
          () {
            if (reminder != null) {
              unawaited(openFocus(context, c, reminder: reminder, assignment: a));
            }
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: const Offset(-10, 0),
            child: _Btn(
              "Make today's focus",
              reminder == null || c.busy
                  ? null
                  : () => unawaited(c.mutate(() => c.repository.highlight(reminder.id))),
              style: _BS.ghost,
              key: const ValueKey('focus-make-today'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'What would you like to move forward?',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const _Note('Choose one Work or Side Gig reminder.', top: 3, size: 13),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Btn(
              'Choose a reminder',
              () => openFocus(context, c),
              key: const ValueKey('focus-choose'),
            ),
            if (c.planning)
              _Btn(
                'Set my focus times',
                () => openFocusTimes(context, c),
                style: _BS.ghost,
                key: const ValueKey('focus-set-times'),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.controller});
  final FocusController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Err(controller.error!),
      Align(
        alignment: Alignment.centerLeft,
        child: _Btn(
          'Retry loading Focus',
          controller.busy ? null : () => unawaited(controller.reload()),
          style: _BS.ghost,
        ),
      ),
    ],
  );
}

class _MissedCard extends StatelessWidget {
  const _MissedCard({
    required this.controller,
    required this.host,
    required this.item,
    required this.more,
  });
  final FocusController controller;
  final BuildContext host;
  final MissedFocusItem item;
  final int more;
  FocusController get c => controller;

  static void _toast(ScaffoldMessengerState? messenger, String message) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final a = item.assignment, o = item.occurrence;
    final reminder = c.reminderById(a.reminderId);
    final nextDate = nextWeekdayAfter(a.localDate, focusIsoWeekday(a.localDate));
    final busy = c.busy;
    final active = c.session != null;
    return _Card(
      label: 'Missed focus time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text(
                  "Didn't get to this?",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (more > 0)
                Text(
                  '+$more more',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reminder?.title ?? a.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ExcludeSemantics(child: _Dot(a.contextSlug)),
                Text(
                  '${o.name} · ${focusShortDate(a.localDate)} · ${a.plannedMinutes} min planned',
                  style: TextStyle(fontSize: 13, color: t.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Btn(
                    'Start now',
                    busy
                        ? null
                        : () async {
                            if (active) {
                              unawaited(openFocus(context, c));
                              return;
                            }
                                                        if (await c.startAssigned(a) && host.mounted) {
                              _announce(host, 'Focus started, ${a.plannedMinutes} minutes');
                              unawaited(openFocus(host, c));
                            }
                          },
                    block: true,
                    key: const ValueKey('missed-start'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Btn(
                    'Next ${o.weekdayName}',
                    busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.maybeOf(context);
                            if (await c.moveToNextWeekday(item)) {
                              _toast(
                                messenger,
                                'Planned for ${o.name} (${focusShortDate(nextDate)})',
                              );
                            }
                          },
                    style: _BS.outline,
                    block: true,
                    key: const ValueKey('missed-next'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Btn(
                    'Choose another time',
                    reminder == null || busy
                        ? null
                        : () => openWorkOnThis(context, c, reminder),
                    style: _BS.outline,
                    block: true,
                    key: const ValueKey('missed-other'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Btn(
                    'Leave unscheduled',
                    busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.maybeOf(context);
                            if (await c.skipWork(a)) _toast(messenger, 'Left unscheduled');
                          },
                    style: _BS.ghost,
                    block: true,
                    key: const ValueKey('missed-leave'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusTimesSection extends StatelessWidget {
  const _FocusTimesSection({required this.controller});
  final FocusController controller;
  FocusController get c => controller;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final live = c.hasFocusTimes;
    // The empty card already offers "Set my focus times".
    if (!live && c.cardKind == FocusCardKind.empty) return const SizedBox.shrink();
    final occurrences = c.upcoming.take(3).toList();
    Widget row(String left, String right, VoidCallback onTap, {Key? key}) => InkWell(
      key: key,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(left, style: const TextStyle(fontSize: 15))),
              Text(right, style: TextStyle(fontSize: 15, color: t.text2)),
            ],
          ),
        ),
      ),
    );
    final Widget body;
    if (!live) {
      body = row('Set my focus times', '›', () => openFocusTimes(context, c),
          key: const ValueKey('focus-times-set'));
    } else if (occurrences.isEmpty) {
      body = row('Nothing planned yet', 'Manage ›', () => openFocusTimes(context, c),
          key: const ValueKey('focus-times-empty'));
    } else {
      body = Column(
        children: [
          for (var i = 0; i < occurrences.length; i++) ...[
            if (i > 0) Divider(height: .5, thickness: .5, color: t.hairline),
            _OccurrenceRow(
              occurrence: occurrences[i],
              onTap: () => openFocusOccurrence(context, c, occurrences[i]),
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHead(
            'Your focus times',
            trailing: live
                ? _Btn(
                    'Manage ›',
                    () => openFocusTimes(context, c),
                    style: _BS.ghost,
                    key: const ValueKey('focus-times-manage'),
                  )
                : null,
          ),
          _Card(padding: EdgeInsets.zero, child: body),
        ],
      ),
    );
  }
}

class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({required this.occurrence, required this.onTap});
  final FocusOccurrence occurrence;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final o = occurrence;
    final first = o.tasks.first;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ExcludeSemantics(child: _Dot(o.contextSlug)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    _Note('${first.title} · ${first.plannedMinutes} min', top: 2, size: 13),
                    if (o.tasks.length > 1)
                      _Note('${o.tasks.length} tasks · ${o.sum} min planned', top: 2, size: 13),
                    if (o.overBudget)
                      _Note('${o.sum} min planned for ${o.budget} min available', top: 2),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${focusMonthDay(o.localDate)} ›',
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
