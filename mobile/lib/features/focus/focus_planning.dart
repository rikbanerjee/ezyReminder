part of 'focus_widgets.dart';

// Planning views: occurrence sheet, "Work on this", Focus times list + editor.

// ---------------------------------------------------------------------------
// Occurrence sheet: ordered tasks, Start per task, Skip
// ---------------------------------------------------------------------------

class _OccurrenceView extends StatelessWidget {
  const _OccurrenceView({super.key, required this.sheet, required this.occurrenceKey});
  final _FocusSheetState sheet;
  final String occurrenceKey;
  FocusController get c => sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final occurrences = c.state?.occurrences(c.now) ?? const <FocusOccurrence>[];
    final o = occurrences.where((x) => x.key == occurrenceKey).firstOrNull;
    if (o == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader('Focus time', sheet.close),
          const _Note('Nothing planned here.', size: 14),
        ],
      );
    }
    final running = c.session != null;
    final label = (o.time?.label ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(o.name, sheet.close),
        _CtxLine(
          o.contextSlug,
          suffix: '${focusShortDate(o.localDate)}${label.isEmpty ? '' : ' · $label'}',
        ),
        _Note(
          '${o.tasks.length} task${o.tasks.length > 1 ? 's' : ''} · ${o.sum} min planned',
          top: 6,
          size: 13,
        ),
        if (o.overBudget)
          _Note('${o.sum} min planned for ${o.budget} min available', top: 3, size: 13),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            label: 'Planned tasks in order',
            container: true,
            child: Column(
              children: [
                for (var i = 0; i < o.tasks.length; i++) ...[
                  if (i > 0) Divider(height: .5, thickness: .5, color: t.hairline),
                  _TaskRow(
                    index: i + 1,
                    assignment: o.tasks[i],
                    sheet: sheet,
                    running: running,
                    last: o.tasks.length == 1,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'A session is already in progress. ',
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
                _Btn(
                  'Open it',
                  () => sheet.go(const _Route(_Mode.session)),
                  style: _BS.ghost,
                ),
                Text(
                  ' before starting another.',
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ],
            ),
          )
        else
          const _Note('Skip leaves the reminder as it is. Nothing starts on its own.'),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.index,
    required this.assignment,
    required this.sheet,
    required this.running,
    required this.last,
  });
  final int index;
  final FocusAssignment assignment;
  final _FocusSheetState sheet;
  final bool running, last;
  FocusController get c => sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final a = assignment;
    final reminder = c.reminderById(a.reminderId);
    final due = (reminder?.deadline ?? a.deadline).label(c.timezone);
    final step = c.nextStepFor(a.reminderId);
    final busy = c.busy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 8, top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.bg, shape: BoxShape.circle),
                child: Text(
                  '$index',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.text2),
                ),
              ),
              Expanded(
                child: Text(
                  reminder?.title ?? a.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Note('${a.plannedMinutes} min${due.isEmpty ? '' : ' · $due'}', top: 2, size: 13),
                if (step != null) _Note('Next: $step', top: 2, size: 13),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Btn(
                      'Start ${a.plannedMinutes} min',
                      running || busy
                          ? null
                          : () async {
                              if (await c.startAssigned(a) && sheet.mounted) {
                                if (context.mounted) _announce(context, 'Focus started, ${a.plannedMinutes} minutes');
                                sheet.go(const _Route(_Mode.session));
                              }
                            },
                      key: ValueKey('occ-start-${a.id}'),
                    ),
                    _Btn(
                      'Skip',
                      busy
                          ? null
                          : () async {
                              final ok = await c.skipWork(a);
                              if (!ok || !sheet.mounted) return;
                              final still = c.state
                                      ?.occurrences(c.now)
                                      .any((x) => x.tasks.any((y) => y.id != a.id) && x.key == sheet.route.occurrenceKey) ??
                                  false;
                              if (!still) {
                                sheet.toast('Skipped · your reminder is unchanged');
                                sheet.close();
                              }
                            },
                      style: _BS.ghost,
                      key: ValueKey('occ-skip-${a.id}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Work on this: plan a reminder into a Focus time or another day
// ---------------------------------------------------------------------------

class _PlanTarget {
  const _PlanTarget({
    required this.localDate,
    required this.startTime,
    required this.startsAt,
    this.time,
  });
  final String localDate, startTime;
  final DateTime startsAt;
  final FocusTimeItem? time;
  String get name => focusOccurrenceName(localDate, startTime);
}

class _PlanView extends StatefulWidget {
  const _PlanView({super.key, required this.sheet, required this.reminder});
  final _FocusSheetState sheet;
  final FocusReminder reminder;
  @override
  State<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<_PlanView> {
  final custom = TextEditingController();
  String? sel; // option key | 'other' | 'none' | null
  String mins = '15';
  bool pickOpen = false, tried = false;
  String? otherDate;
  String otherTime = '18:30';
  FocusController get c => widget.sheet.c;
  FocusReminder get r => widget.reminder;

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  _PlanTarget? _target(List<FocusPlanOption> options) {
    if (sel == 'other') {
      final d = otherDate;
      if (d == null) return null;
      return _PlanTarget(
        localDate: d,
        startTime: otherTime,
        startsAt: focusOccurrenceStart(d, otherTime, c.timezone),
      );
    }
    final o = options.where((x) => x.key == sel).firstOrNull;
    return o == null
        ? null
        : _PlanTarget(
            localDate: o.localDate,
            startTime: focusTimeHm(o.startTime),
            startsAt: o.startsAt,
            time: o.time,
          );
  }

  Future<void> _save(List<FocusPlanOption> options) async {
    final current = c.assignmentFor(r.id);
    if (sel == 'none') {
      if (current != null && !await c.skipWork(current)) return;
      if (!mounted) return;
      widget.sheet.toast('Left unscheduled');
      widget.sheet.close();
      return;
    }
    final target = _target(options);
    final minutes = _minutesFrom(mins, custom.text);
    if (target == null || minutes == null) {
      setState(() => tried = true);
      return;
    }
    final key = 'plan:${r.id}:${target.time?.id}:${target.localDate}:${target.startTime}:$minutes';
    final ok = await c.mutate(
      () => c.repository.assign(
        FocusAssignRequest(
          id: c.intentId(key),
          reminder: r,
          localDate: target.localDate,
          startTime: target.startTime,
          plannedMinutes: minutes,
          focusTimeId: target.time?.id,
        ),
      ),
    );
    if (!mounted || !ok) return;
    c.settle(key);
    widget.sheet.toast('Planned for ${target.name}${current != null ? ' (moved)' : ''}');
    widget.sheet.close();
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final state = c.state;
    final options = state?.planOptions(r.contextSlug, c.now) ?? const <FocusPlanOption>[];
    final target = _target(options);
    final current = c.assignmentFor(r.id);
    final minutes = _minutesFrom(mins, custom.text);
    final deadline = r.deadline;
    final warn = target != null && deadline.exists && deadline.isBefore(target.startsAt, c.timezone);
    final today = focusLocalDate(c.now, c.timezone);
    final others = target?.time == null
        ? const <FocusAssignment>[]
        : [
            for (final a in state!.assignments)
              if (a.planned &&
                  a.focusTimeId == target!.time!.id &&
                  a.localDate == target.localDate &&
                  a.reminderId != r.id)
                a,
          ];
    final used = others.fold<int>(0, (s, a) => s + a.plannedMinutes) + (minutes ?? 0);
    final otherSecondary = otherDate != null && !pickOpen
        ? '${focusShortDate(otherDate!)} · ${focusTime12(otherTime)}'
        : 'Choose a date and time';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader('Work on this', widget.sheet.close),
        _ReminderBlock(
          slug: r.contextSlug,
          title: r.title,
          deadline: deadline,
          timezone: c.timezone,
          isOrder: r.isOrder,
        ),
        if (current != null)
          _Inset(
            'Currently planned',
            '${focusOccurrenceName(current.localDate, current.startTime)} · ${current.plannedMinutes} min. Choosing another time moves it.',
          ),
        const _Sub('When'),
        Semantics(
          label: 'When',
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in options)
                _Choice(
                  key: ValueKey('plan-opt-${o.key}'),
                  title: o.name,
                  secondary: o.secondary,
                  selected: sel == o.key,
                  slug: r.contextSlug,
                  onTap: () => setState(() {
                    sel = o.key;
                    pickOpen = false;
                  }),
                ),
              _Choice(
                key: const ValueKey('plan-other'),
                title: 'Pick another day',
                secondary: otherSecondary,
                selected: sel == 'other',
                slug: r.contextSlug,
                trailing: Icon(
                  pickOpen ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_right,
                  size: 14,
                  color: t.text2,
                ),
                onTap: () => setState(() {
                  sel = 'other';
                  pickOpen = !pickOpen;
                }),
              ),
              if (sel == 'other' && pickOpen)
                _DayPicker(
                  today: today,
                  selected: otherDate,
                  time: otherTime,
                  onDay: (d) => setState(() => otherDate = d),
                  onTime: (v) => otherTime = v,
                  onOk: () => setState(() => pickOpen = false),
                ),
              _Choice(
                key: const ValueKey('plan-none'),
                title: 'Keep unscheduled',
                secondary: 'No focus time for now',
                selected: sel == 'none',
                slug: r.contextSlug,
                onTap: () => setState(() {
                  sel = 'none';
                  pickOpen = false;
                }),
              ),
            ],
          ),
        ),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "You haven't set up a ${_contextName(r.contextSlug)} focus time yet. ",
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
                InkWell(
                  onTap: () => widget.sheet.go(const _Route(_Mode.times)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      widthFactor: 1,
                      child: Text(
                        'Set my focus times',
                        key: const ValueKey('plan-set-times'),
                        style: TextStyle(
                          fontSize: 12,
                          color: t.text2,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (target != null) ...[
          const _Sub('Planned minutes'),
          _MinuteChips(
            values: const ['10', '15', '25', 'custom'],
            selected: mins,
            slug: r.contextSlug,
            onSelect: (v) => setState(() {
              mins = v;
              tried = false;
            }),
            keyPrefix: 'plan-min',
          ),
          if (mins == 'custom')
            _MinutesField(
              key: const ValueKey('plan-custom-minutes'),
              controller: custom,
              label: 'Planned minutes, 1 to 180',
              showLabel: false,
              invalid: tried && minutes == null,
              onChanged: () => setState(() {}),
            ),
          if (target.time != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (others.isNotEmpty)
                    'Also planned here: ${others.map((a) => '${a.title} · ${a.plannedMinutes} min').join(', ')}.',
                  '${others.length + 1} task${others.isNotEmpty ? 's' : ''} · $used min planned${used > target.time!.budgetMinutes ? ' — $used min planned for ${target.time!.budgetMinutes} min available' : ''}',
                ].join('\n'),
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
            ),
        ],
        if (warn)
          _Warn(
            'This is after the ${deadline.isShipBy ? 'ship-by' : 'due'} time',
            '${deadline.label(c.timezone)}. Your deadline stays the same.',
            actions: [
              _Btn(
                'Choose an earlier time',
                () {
                  setState(() {
                    sel = null;
                    pickOpen = false;
                  });
                  if (widget.sheet.scroll.hasClients) widget.sheet.scroll.jumpTo(0);
                },
                style: _BS.outline,
                key: const ValueKey('plan-earlier'),
              ),
              _Btn(
                'Plan it anyway',
                c.busy ? null : () => _save(options),
                key: const ValueKey('plan-anyway'),
              ),
            ],
          )
        else ...[
          if (tried && target == null && sel != 'none')
            _Err(
              sel == 'other'
                  ? 'Choose a day and time, then tap OK.'
                  : "Choose when you'd like to work on this.",
            ),
          const SizedBox(height: 16),
          _Btn(
            c.busy ? 'Saving…' : 'Save plan',
            c.busy ? null : () => _save(options),
            block: true,
            key: const ValueKey('plan-save'),
          ),
        ],
      ],
    );
  }
}

/// Inline month grid (past days disabled) + time wheel + explicit OK, shown
/// below the "Pick another day" row.
class _DayPicker extends StatefulWidget {
  const _DayPicker({
    required this.today,
    required this.selected,
    required this.time,
    required this.onDay,
    required this.onTime,
    required this.onOk,
  });
  final String today, time;
  final String? selected;
  final ValueChanged<String> onDay, onTime;
  final VoidCallback onOk;
  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  late int year, month;
  bool err = false;

  @override
  void initState() {
    super.initState();
    final p = (widget.selected ?? widget.today).split('-').map(int.parse).toList();
    year = p[0];
    month = p[1];
  }

  String _key(int y, int m, int d) =>
      '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final first = DateTime.utc(year, month, 1);
    final days = DateTime.utc(year, month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first grid
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(height: 44),
      for (var d = 1; d <= days; d++)
        Builder(
          builder: (context) {
            final key = _key(year, month, d);
            final past = key.compareTo(widget.today) < 0;
            final on = widget.selected == key;
            return Semantics(
              label: '${_months[month - 1]} $d',
              button: true,
              selected: on,
              enabled: !past,
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('plan-day-$key'),
                borderRadius: BorderRadius.circular(12),
                onTap: past
                    ? null
                    : () {
                        setState(() => err = false);
                        widget.onDay(key);
                      },
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? t.text : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$d',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                      color: on
                          ? t.bg
                          : past
                          ? t.text.withValues(alpha: .3)
                          : t.text,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox(height: 44));
    }
    final prevEnd = _key(year, month, 0 + 1).compareTo(widget.today) <= 0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: prevEnd
                    ? null
                    : () => setState(() {
                        month -= 1;
                        if (month < 1) {
                          month = 12;
                          year -= 1;
                        }
                      }),
                icon: const Icon(CupertinoIcons.chevron_left, size: 18),
              ),
              Expanded(
                child: Text(
                  '${_months[month - 1]} $year',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => setState(() {
                  month += 1;
                  if (month > 12) {
                    month = 1;
                    year += 1;
                  }
                }),
                icon: const Icon(CupertinoIcons.chevron_right, size: 18),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ExcludeSemantics(
                        child: Text(
                          d,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Table(
            children: [
              for (var i = 0; i < cells.length; i += 7)
                TableRow(children: cells.sublist(i, i + 7)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              'Time',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text2),
            ),
          ),
          _TimeWheel(time: widget.time, onChanged: widget.onTime),
          if (err) const _Err('Choose a day first.'),
          const SizedBox(height: 8),
          _Btn(
            'OK',
            () {
              if (widget.selected == null) {
                setState(() => err = true);
                return;
              }
              widget.onOk();
            },
            block: true,
            key: const ValueKey('plan-picker-ok'),
          ),
        ],
      ),
    );
  }
}

/// Time-of-day wheel producing "HH:MM".
class _TimeWheel extends StatelessWidget {
  const _TimeWheel({required this.time, required this.onChanged});
  final String time;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = time.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    return SizedBox(
      height: 132,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: DateTime(2000, 1, 1, p[0], p.length > 1 ? p[1] : 0),
        use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        onDateTimeChanged: (v) => onChanged(
          '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Focus times: list and editor
// ---------------------------------------------------------------------------

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.undo});
  final String text;
  final Future<void> Function()? undo;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.hairline),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            if (undo != null)
              _Btn('Undo', () => unawaited(undo!()), style: _BS.ghost, key: const ValueKey('focus-notice-undo')),
          ],
        ),
      ),
    );
  }
}

class _TimesView extends StatelessWidget {
  const _TimesView({super.key, required this.sheet, required this.fromSettings});
  final _FocusSheetState sheet;
  final bool fromSettings;
  FocusController get c => sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final times = c.focusTimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader('Your focus times', sheet.close),
        if (sheet.route.notice != null)
          _Notice(sheet.route.notice!, undo: sheet.route.undo),
        if (times.isEmpty)
          const _Note(
            'Pick the weekly times you can focus, then plan reminders into them. Nothing starts on its own.',
            top: 6,
            size: 14,
          )
        else
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < times.length; i++) ...[
                  if (i > 0) Divider(height: .5, thickness: .5, color: t.hairline),
                  InkWell(
                    key: ValueKey('focus-time-${times[i].id}'),
                    onTap: () => sheet.go(
                      _Route(_Mode.timeEdit, time: times[i], fromSettings: fromSettings),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            ExcludeSemantics(child: _Dot(times[i].contextSlug)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(times[i].title, style: const TextStyle(fontSize: 15)),
                                  _Note(times[i].summary, top: 2, size: 13),
                                ],
                              ),
                            ),
                            Text('›', style: TextStyle(fontSize: 13, color: t.text2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        _TimezoneNote(
          prefix: 'Times use your account timezone, ${c.timezone}. ',
          onTap: () {
            sheet.close();
            if (!fromSettings) sheet.toast('Account timezone lives in Settings');
          },
        ),
        const SizedBox(height: 16),
        _Btn(
          'Add a focus time',
          () => sheet.go(_Route(_Mode.timeEdit, fromSettings: fromSettings)),
          block: true,
          key: const ValueKey('focus-add-time'),
        ),
      ],
    );
  }
}

class _TimezoneNote extends StatelessWidget {
  const _TimezoneNote({required this.prefix, required this.onTap});
  final String prefix;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(prefix, style: TextStyle(fontSize: 12, color: t.text2)),
          InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                widthFactor: 1,
                child: Text(
                  'Change in Settings',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEditView extends StatefulWidget {
  const _TimeEditView({
    super.key,
    required this.sheet,
    required this.time,
    required this.fromSettings,
  });
  final _FocusSheetState sheet;
  final FocusTimeItem? time;
  final bool fromSettings;
  @override
  State<_TimeEditView> createState() => _TimeEditViewState();
}

class _TimeEditViewState extends State<_TimeEditView> {
  static const _days = [
    (1, 'Mon', 'Monday'),
    (2, 'Tue', 'Tuesday'),
    (3, 'Wed', 'Wednesday'),
    (4, 'Thu', 'Thursday'),
    (5, 'Fri', 'Friday'),
    (6, 'Sat', 'Saturday'),
    (7, 'Sun', 'Sunday'),
  ];
  late final String id = widget.time?.id ?? newFocusId();
  late final label = TextEditingController(text: widget.time?.label ?? '');
  late final custom = TextEditingController(
    text: widget.time == null ? '' : '${widget.time!.budgetMinutes}',
  );
  late List<int> days = [...?widget.time?.weekdays];
  late String time = widget.time == null ? '09:00' : focusTimeHm(widget.time!.startTime);
  late String mins = widget.time == null ? '30' : _presetFor(widget.time!.budgetMinutes, const ['15', '30', '60']);
  late String? ctx = widget.time?.contextSlug;
  bool timeOpen = false, saving = false;
  String? daysErr, minsErr, ctxErr;
  FocusController get c => widget.sheet.c;

  @override
  void dispose() {
    label.dispose();
    custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = _minutesFrom(mins, custom.text);
    setState(() {
      daysErr = days.isEmpty ? 'Choose at least one day.' : null;
      minsErr = minutes == null ? _minutesError : null;
      ctxErr = ctx == null ? 'Choose Work or Side Gig.' : null;
    });
    if (days.isEmpty || minutes == null || ctx == null) return;
    final draft = FocusTimeDraft(
      id: id,
      label: label.text,
      contextSlug: ctx!,
      weekdays: ([...days]..sort()),
      startTime: '$time:00',
      budgetMinutes: minutes,
    );
    final ok = await c.mutate(() => c.repository.saveFocusTime(draft));
    if (!mounted || !ok) return;
    _announce(context, 'Focus time saved');
    widget.sheet.go(_Route(_Mode.times, fromSettings: widget.fromSettings, notice: 'Focus time saved'));
  }

  Future<void> _archive() async {
    final existing = widget.time!;
    final ok = await c.mutate(() => c.repository.archiveFocusTime(existing.id));
    if (!mounted || !ok) return;
    final sheet = widget.sheet;
    final restore = FocusTimeDraft(
      // An archived time cannot be revived server-side, so Undo recreates it.
      id: newFocusId(),
      label: existing.label,
      contextSlug: existing.contextSlug,
      weekdays: existing.weekdays,
      startTime: existing.startTime,
      budgetMinutes: existing.budgetMinutes,
    );
    sheet.go(
      _Route(
        _Mode.times,
        fromSettings: widget.fromSettings,
        notice: 'Focus time archived · planned work stays',
        undo: () async {
          final restored = await c.mutate(() => c.repository.saveFocusTime(restore));
          if (restored && sheet.mounted) {
            sheet.go(_Route(_Mode.times, fromSettings: widget.fromSettings, notice: 'Focus time restored'));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final accentSlug = ctx ?? 'work';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(
          widget.time == null ? 'New focus time' : 'Edit focus time',
          widget.sheet.close,
          onBack: () => widget.sheet.go(_Route(_Mode.times, fromSettings: widget.fromSettings)),
        ),
        const _Sub('Name', optional: true),
        Semantics(
          label: 'Name (optional)',
          textField: true,
          child: TextField(
            key: const ValueKey('focus-time-name'),
            controller: label,
            maxLength: 40,
            style: const TextStyle(fontSize: 15),
            decoration: _fieldDecoration(context, hint: 'e.g. Shop time'),
          ),
        ),
        const _Sub('Days'),
        Semantics(
          label: 'Days',
          container: true,
          child: Row(
            children: [
              for (var i = 0; i < _days.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _Chip(
                    _days[i].$2,
                    days.contains(_days[i].$1),
                    () => setState(() {
                      days.contains(_days[i].$1)
                          ? days.remove(_days[i].$1)
                          : days.add(_days[i].$1);
                      daysErr = null;
                    }),
                    slug: accentSlug,
                    radius: 12,
                    padding: 0,
                    expand: true,
                    semanticLabel: _days[i].$3,
                    key: ValueKey('focus-day-${_days[i].$1}'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (daysErr != null) _Err(daysErr!),
        const _Sub('Time'),
        Align(
          alignment: Alignment.centerLeft,
          child: _Chip(
            focusTime12(time),
            timeOpen,
            () => setState(() => timeOpen = !timeOpen),
            slug: null,
            leading: Icon(CupertinoIcons.clock, size: 14, color: t.text2),
            semanticLabel: 'Start time, ${focusTime12(time)}',
            key: const ValueKey('focus-time-chip'),
          ),
        ),
        if (timeOpen)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TimeWheel(time: time, onChanged: (v) => setState(() => time = v)),
                _Btn(
                  'OK',
                  () => setState(() => timeOpen = false),
                  block: true,
                  key: const ValueKey('focus-time-ok'),
                ),
              ],
            ),
          ),
        _TimezoneNote(
          prefix: 'Account timezone: ${c.timezone}. ',
          onTap: () {
            widget.sheet.close();
            if (!widget.fromSettings) widget.sheet.toast('Account timezone lives in Settings');
          },
        ),
        const _Sub('I usually have'),
        _MinuteChips(
          values: const ['15', '30', '60', 'custom'],
          selected: mins,
          slug: accentSlug,
          onSelect: (v) => setState(() {
            mins = v;
            minsErr = null;
          }),
          keyPrefix: 'focus-have',
        ),
        if (mins == 'custom')
          _MinutesField(
            key: const ValueKey('focus-have-custom'),
            controller: custom,
            label: 'Minutes available, 1 to 180',
            showLabel: false,
            invalid: minsErr != null,
            onChanged: () => setState(() => minsErr = null),
          )
        else if (minsErr != null)
          _Err(minsErr!),
        const _Sub('For'),
        Semantics(
          label: 'For',
          container: true,
          child: Row(
            children: [
              for (final slug in const ['work', 'sidegig']) ...[
                if (slug == 'sidegig') const SizedBox(width: 8),
                Expanded(
                  child: _Chip(
                    _contextName(slug),
                    ctx == slug,
                    () => setState(() {
                      ctx = slug;
                      ctxErr = null;
                    }),
                    slug: slug,
                    radius: 12,
                    expand: true,
                    leading: ExcludeSemantics(child: _Dot(slug)),
                    key: ValueKey('focus-for-$slug'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (ctxErr != null) _Err(ctxErr!),
        const _Note("Changes apply to future choices. Work you've already planned keeps its time.", top: 6),
        const SizedBox(height: 16),
        _Btn(
          c.busy ? 'Saving…' : 'Save focus time',
          c.busy ? null : _save,
          block: true,
          key: const ValueKey('focus-time-save'),
        ),
        if (widget.time != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _Btn(
              'Archive',
              c.busy ? null : _archive,
              style: _BS.ghost,
              danger: true,
              block: true,
              key: const ValueKey('focus-time-archive'),
            ),
          ),
      ],
    );
  }
}
