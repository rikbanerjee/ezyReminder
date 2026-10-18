part of 'focus_widgets.dart';

/// Saved-session summary handed from the review mode to the "Session saved" mode.
class _AfterInfo {
  const _AfterInfo({
    required this.reminderId,
    required this.title,
    required this.contextSlug,
    required this.outcome,
    required this.minutes,
    required this.next,
  });
  final String? reminderId;
  final String title, contextSlug, outcome, next;
  final int minutes;
}

const _outcomes = [
  ('finished', 'Finished what I planned'),
  ('progress', 'Made progress'),
  ('interrupted', 'Got interrupted'),
];

/// The one Focus sheet: 20px top corners, `shadow-sheet`, drag handle; modes
/// swap inside it. Each mode keeps its own draft State, so Realtime refreshes
/// (which rebuild this widget) never discard what the person typed.
class _FocusSheet extends StatefulWidget {
  const _FocusSheet({
    required this.controller,
    required this.route,
    required this.notify,
  });
  final FocusController controller;
  final _Route route;
  final FocusNotify notify;
  @override
  State<_FocusSheet> createState() => _FocusSheetState();
}

class _FocusSheetState extends State<_FocusSheet> {
  late _Route route = widget.route;
  final scroll = ScrollController();
  String? _sessionId;
  bool _up = false;

  /// True while a review save is in flight or just succeeded, so the session
  /// ending does not bounce the sheet back to the chooser.
  bool finishing = false;
  FocusController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sessionId = c.session?.id;
    _up = c.session?.awaitingFinish(c.now) ?? false;
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    scroll.dispose();
    super.dispose();
  }

  void go(_Route next) {
    c.clearError();
    setState(() => route = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void close() => Navigator.of(context).pop();

  void toast(String message) => widget.notify(message);

  void _changed() {
    if (!mounted) return;
    final session = c.session;
    final up = session?.awaitingFinish(c.now) ?? false;
    if (up && !_up) _announce(context, 'Time is up. How did it go?');
    _up = up;
    if (session?.id != _sessionId) {
      _sessionId = session?.id;
      final inSessionFlow = const {
        _Mode.choose,
        _Mode.setup,
        _Mode.session,
        _Mode.review,
      }.contains(route.mode);
      if (session != null && inSessionFlow) {
        route = _Route(up ? _Mode.review : _Mode.session);
      } else if (session == null &&
          !finishing &&
          (route.mode == _Mode.session || route.mode == _Mode.review)) {
        route = const _Route(_Mode.choose);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final view = switch (route.mode) {
      _Mode.choose => _ChooseView(key: const ValueKey('choose'), sheet: this),
      _Mode.setup => _SetupView(
        key: ValueKey('setup-${route.reminder?.id}'),
        sheet: this,
        reminder: route.reminder!,
        assignment: route.assignment,
      ),
      _Mode.session => _SessionView(key: const ValueKey('session'), sheet: this),
      _Mode.review => _ReviewView(key: const ValueKey('review'), sheet: this),
      _Mode.after => _AfterView(
        key: const ValueKey('after'),
        sheet: this,
        info: route.after!,
      ),
      _Mode.occurrence => _OccurrenceView(
        key: ValueKey('occ-${route.occurrenceKey}'),
        sheet: this,
        occurrenceKey: route.occurrenceKey!,
      ),
      _Mode.plan => _PlanView(
        key: ValueKey('plan-${route.reminder?.id}'),
        sheet: this,
        reminder: route.reminder!,
      ),
      _Mode.times => _TimesView(
        key: const ValueKey('times'),
        sheet: this,
        fromSettings: route.fromSettings,
      ),
      _Mode.timeEdit => _TimeEditView(
        key: ValueKey('time-edit-${route.time?.id ?? 'new'}'),
        sheet: this,
        time: route.time,
        fromSettings: route.fromSettings,
      ),
    };
    final showError = c.error != null && route.mode != _Mode.review;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [t.sheetShadow],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showError) ...[
                      // Shown above the view so a failed write is never silent.
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _Err(c.error!),
                      ),
                    ],
                    view,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Handle + title row. [back] adds the "‹ Back" button for views with a parent list.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.title, this.onClose, {this.onBack});
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 5,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: t.hairline,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Row(
          children: [
            if (onBack != null)
              Transform.translate(
                offset: const Offset(-10, 0),
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(CupertinoIcons.chevron_back, color: t.text2),
                ),
              ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(10, 0),
              child: IconButton(
                tooltip: 'Close focus',
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(CupertinoIcons.xmark, size: 20, color: t.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Reminder summary block: context line, title, deadline.
class _ReminderBlock extends StatelessWidget {
  const _ReminderBlock({
    required this.slug,
    required this.title,
    required this.deadline,
    required this.timezone,
    this.isOrder = false,
  });
  final String slug, title, timezone;
  final FocusDeadline deadline;
  final bool isOrder;
  @override
  Widget build(BuildContext context) {
    final due = deadline.label(timezone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CtxLine(slug, suffix: isOrder ? 'Order' : null),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        if (due.isNotEmpty) _Note(due, top: 3, size: 13),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Choose a reminder (sets today's focus)
// ---------------------------------------------------------------------------

class _ChooseView extends StatefulWidget {
  const _ChooseView({super.key, required this.sheet});
  final _FocusSheetState sheet;
  @override
  State<_ChooseView> createState() => _ChooseViewState();
}

class _ChooseViewState extends State<_ChooseView> {
  String query = '';
  FocusController get c => widget.sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final candidates = [
      for (final r in c.reminders)
        if (r.eligible && r.title.toLowerCase().contains(query.toLowerCase())) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader("Today's focus", widget.sheet.close),
        Text(
          'One reminder for today. Its deadline stays the same.',
          style: TextStyle(fontSize: 14, color: t.text2),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Search Work and Side Gig reminders',
          textField: true,
          child: TextField(
            key: const ValueKey('focus-search'),
            style: const TextStyle(fontSize: 15),
            decoration: _fieldDecoration(context, hint: 'Search reminders…'),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: candidates.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    query.isEmpty
                        ? 'Add a Work or Side Gig reminder to choose your focus.'
                        : 'No matching reminders.',
                    style: TextStyle(fontSize: 14, color: t.text2),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < candidates.length; i++) ...[
                      if (i > 0) Divider(height: .5, thickness: .5, color: t.hairline),
                      InkWell(
                        key: ValueKey('focus-choose-${candidates[i].id}'),
                        onTap: c.busy || c.error != null && c.state == null
                            ? null
                            : () async {
                                final r = candidates[i];
                                final ok = await c.mutate(
                                  () => c.repository.highlight(r.id),
                                );
                                if (ok && context.mounted) {
                                  _announce(context, "Today's focus set");
                                  widget.sheet.toast("Today's focus set");
                                  widget.sheet.close();
                                }
                              },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                ExcludeSemantics(child: _Dot(candidates[i].contextSlug)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidates[i].title,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        candidates[i].contextName,
                                        style: TextStyle(fontSize: 12, color: t.text2),
                                      ),
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
        if (c.session != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _Btn(
              'Open current session',
              () => widget.sheet.go(const _Route(_Mode.session)),
              style: _BS.outline,
              block: true,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Setup ("Focus on this"): length, next step, intended outcome
// ---------------------------------------------------------------------------

class _SetupView extends StatefulWidget {
  const _SetupView({
    super.key,
    required this.sheet,
    required this.reminder,
    this.assignment,
  });
  final _FocusSheetState sheet;
  final FocusReminder reminder;
  final FocusAssignment? assignment;
  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  late final custom = TextEditingController();
  final intent = TextEditingController();
  late String duration;
  String? previousStep, stepError;
  bool tried = false;
  int _stepGeneration = 0;
  FocusController get c => widget.sheet.c;

  @override
  void initState() {
    super.initState();
    final m = widget.assignment?.plannedMinutes ?? c.preferredMinutes;
    duration = _presetFor(m, const ['10', '25', '50']);
    custom.text = '$m';
    unawaited(_loadStep());
  }

  @override
  void dispose() {
    custom.dispose();
    intent.dispose();
    super.dispose();
  }

  Future<void> _loadStep() async {
    final generation = ++_stepGeneration;
    setState(() => stepError = null);
    try {
      final step = await c.repository.latestNextStep(widget.reminder.id);
      if (mounted && generation == _stepGeneration) {
        setState(() => previousStep = (step ?? '').trim().isEmpty ? null : step);
      }
    } catch (_) {
      if (mounted && generation == _stepGeneration) {
        setState(() => stepError = 'Could not load your last next step.');
      }
    }
  }

  Future<void> _start() async {
    final minutes = _minutesFrom(duration, custom.text);
    if (minutes == null) {
      setState(() => tried = true);
      return;
    }
    final r = widget.reminder;
    final a = widget.assignment;
    final text = intent.text.trim();
    final ok = a != null
        ? await c.startAssigned(a, minutes: minutes)
        : await c.startReminder(r, minutes, intent: text.isEmpty ? null : text);
    if (!mounted) return;
    if (ok) {
      unawaited(c.rememberMinutes(minutes));
      _announce(context, 'Focus started, $minutes minutes');
      widget.sheet.go(const _Route(_Mode.session));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final minutes = _minutesFrom(duration, custom.text);
    final bad = tried && minutes == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader('Focus on this', widget.sheet.close),
        _ReminderBlock(
          slug: r.contextSlug,
          title: r.title,
          deadline: r.deadline,
          timezone: c.timezone,
          isOrder: r.isOrder,
        ),
        if (previousStep != null) _Inset('Next step from last time', previousStep!),
        if (stepError != null) ...[
          _Err(stepError!),
          Align(
            alignment: Alignment.centerLeft,
            child: _Btn('Retry next step', () => unawaited(_loadStep()), style: _BS.ghost),
          ),
        ],
        const _Sub('How long?'),
        _MinuteChips(
          values: const ['10', '25', '50', 'custom'],
          selected: duration,
          slug: r.contextSlug,
          onSelect: (v) => setState(() {
            duration = v;
            tried = false;
          }),
          keyPrefix: 'focus-setup',
        ),
        if (duration == 'custom')
          _MinutesField(
            key: const ValueKey('focus-custom-minutes'),
            controller: custom,
            invalid: bad,
            onChanged: () => setState(() {}),
          ),
        if (c.hasPreferences && minutes != null && minutes != c.preferredMinutes)
          _Note('Starting with $minutes min saves it as your usual length.'),
        if (widget.assignment == null) ...[
          const _Sub('What could you finish in 10–15 minutes?', optional: true),
          Semantics(
            label: 'What could you finish in 10–15 minutes? (optional)',
            textField: true,
            child: TextField(
              key: const ValueKey('focus-intent'),
              controller: intent,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 15),
              decoration: _fieldDecoration(
                context,
                hint: 'A small, clear outcome…',
                filledBg: true,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Btn(
          c.busy ? 'Starting…' : 'Start now',
          c.busy ? null : _start,
          block: true,
          key: const ValueKey('focus-setup-start'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Session: task + next step, quiet countdown
// ---------------------------------------------------------------------------

class _SessionView extends StatelessWidget {
  const _SessionView({super.key, required this.sheet});
  final _FocusSheetState sheet;
  FocusController get c => sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final s = c.session;
    if (s == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader('Focus session', sheet.close),
          _Note('No session in progress.', size: 14),
        ],
      );
    }
    final up = s.awaitingFinish(c.now);
    final paused = s.paused && !up;
    final intent = (s.intendedOutcome ?? '').trim();
    final step = c.nextStepFor(s.reminderId);
    final aim = intent.isNotEmpty
        ? ('Your focus', intent)
        : step != null
        ? ('Next step', step)
        : null;
    final remaining = s.remainingSeconds(c.now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(up ? 'Time is up' : paused ? 'Paused' : 'In focus', sheet.close),
        _CtxLine(s.contextSlug),
        const SizedBox(height: 6),
        Text(
          s.title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
          ),
        ),
        if (aim != null) _FocusBlock(aim.$1, aim.$2, s.contextSlug),
        const SizedBox(height: 22),
        Center(
          child: Semantics(
            label: 'Focus time remaining',
            child: Opacity(
              opacity: paused ? .55 : 1,
              child: Text(
                _mmss(remaining),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: up ? FontWeight.w600 : FontWeight.w300,
                  letterSpacing: 1,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: up ? t.text : t.text2,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 18),
          child: Center(
            child: Text(
              up
                  ? 'Time is up. Ready to review?'
                  : paused
                  ? 'Paused'
                  : 'One thing at a time.',
              style: TextStyle(fontSize: 14, color: t.text2),
            ),
          ),
        ),
        if (up)
          _Btn(
            'Review session',
            () => sheet.go(const _Route(_Mode.review)),
            block: true,
            key: const ValueKey('focus-review'),
          )
        else
          Row(
            children: [
              Expanded(
                child: _Btn(
                  paused ? 'Resume' : 'Pause',
                  c.busy
                      ? null
                      : () async {
                          final ok = await c.mutate(
                            () => paused
                                ? c.repository.resume(s)
                                : c.repository.pause(s),
                          );
                          if (ok && context.mounted) {
                            _announce(context, paused ? 'Session resumed' : 'Session paused');
                          }
                        },
                  block: true,
                  leading: Icon(
                    paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
                    size: 14,
                  ),
                  key: const ValueKey('focus-pause'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Btn(
                  'End session',
                  () => sheet.go(const _Route(_Mode.review)),
                  style: _BS.outline,
                  block: true,
                  key: const ValueKey('focus-end'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Review: outcome + "Where will you start next time?"
// ---------------------------------------------------------------------------

class _ReviewView extends StatefulWidget {
  const _ReviewView({super.key, required this.sheet});
  final _FocusSheetState sheet;
  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView> {
  final next = TextEditingController();
  String? outcome;
  bool tried = false, failed = false;
  FocusController get c => widget.sheet.c;

  @override
  void dispose() {
    next.dispose();
    super.dispose();
  }

  int _minutes(FocusSession s) => ((s.durationMinutes * 60 - s.remainingSeconds(c.now)) / 60)
      .round()
      .clamp(1, 180);

  Future<void> _save() async {
    setState(() => tried = true);
    final session = c.session;
    if (outcome == null) return;
    if (session == null) {
      widget.sheet.close();
      return;
    }
    final text = next.text.trim();
    final info = _AfterInfo(
      reminderId: session.reminderId,
      title: session.title,
      contextSlug: session.contextSlug,
      outcome: outcome!,
      minutes: _minutes(session),
      next: text,
    );
    widget.sheet.finishing = true;
    setState(() => failed = false);
    final ok = await c.mutate(
      () => c.repository.finish(c.session ?? session, outcome!, text.isEmpty ? null : text),
    );
    if (!mounted) return;
    if (ok) {
      _announce(context, 'Session saved');
      widget.sheet.go(_Route(_Mode.after, after: info));
      widget.sheet.finishing = false;
    } else {
      widget.sheet.finishing = false;
      setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final s = c.session;
    if (s == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader('How did it go?', widget.sheet.close),
          _Note('No session in progress.', size: 14),
        ],
      );
    }
    final up = s.awaitingFinish(c.now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader('How did it go?', widget.sheet.close),
        _CtxLine(s.contextSlug, suffix: '${_minutes(s)} min'),
        const SizedBox(height: 6),
        Text(
          s.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Semantics(
          label: 'Session outcome',
          container: true,
          child: Column(
            children: [
              for (final choice in _outcomes)
                _Choice(
                  key: ValueKey('focus-outcome-${choice.$1}'),
                  title: choice.$2,
                  selected: outcome == choice.$1,
                  slug: s.contextSlug,
                  onTap: () => setState(() {
                    outcome = choice.$1;
                    tried = false;
                  }),
                ),
            ],
          ),
        ),
        if (tried && outcome == null) const _Err('Choose how the session went.'),
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(
            'Where will you start next time?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text),
          ),
        ),
        Semantics(
          label: 'Where will you start next time?',
          textField: true,
          child: TextField(
            key: const ValueKey('focus-next-step'),
            controller: next,
            maxLength: 1000,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontSize: 15),
            decoration: _fieldDecoration(
              context,
              hint: 'A small, clear next action…',
              filledBg: true,
            ),
          ),
        ),
        const _Note('Optional. It appears on your card when you come back.', top: 6),
        if (failed)
          _Warn(
            "Couldn't save your session",
            c.error == null
                ? 'Your answers are still here.'
                : '${c.error} Your answers are still here.',
            actions: [
              _Btn('Retry', c.busy ? null : _save, key: const ValueKey('focus-retry-save')),
            ],
          ),
        const _Note('This saves your session. Your reminder stays as it is.', top: 12),
        const SizedBox(height: 12),
        _Btn(
          c.busy ? 'Saving…' : 'Save session',
          c.busy ? null : _save,
          block: true,
          key: const ValueKey('focus-save-session'),
        ),
        if (!up)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _Btn(
              'Back to session',
              () => widget.sheet.go(const _Route(_Mode.session)),
              style: _BS.ghost,
              block: true,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// After save: continue / choose another focus time / done (+ Mark reminder done)
// ---------------------------------------------------------------------------

class _AfterView extends StatelessWidget {
  const _AfterView({super.key, required this.sheet, required this.info});
  final _FocusSheetState sheet;
  final _AfterInfo info;
  FocusController get c => sheet.c;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    final reminder = c.reminderById(info.reminderId);
    final label = _outcomes.firstWhere((o) => o.$1 == info.outcome).$2;
    final canPlan = reminder != null && c.planning && c.hasFocusTimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader('Session saved', sheet.close),
        Center(
          child: Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(t.social.withValues(alpha: .16), t.surface),
            ),
            child: Icon(CupertinoIcons.checkmark_alt, color: t.social, size: 28),
          ),
        ),
        Text(
          info.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$label · ${info.minutes} min',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: t.text2),
          ),
        ),
        if (info.next.isNotEmpty) _Inset('Next time', info.next),
        const SizedBox(height: 16),
        if (reminder != null)
          _Btn(
            c.busy ? 'Starting…' : 'Continue for 10 min',
            c.busy
                ? null
                : () async {
                    if (await c.startReminder(reminder, 10) && context.mounted) {
                      _announce(context, 'Focus started, 10 minutes');
                      sheet.go(const _Route(_Mode.session));
                    }
                  },
            block: true,
            key: const ValueKey('focus-continue'),
          ),
        if (canPlan) ...[
          const SizedBox(height: 8),
          _Btn(
            'Choose another focus time',
            () => sheet.go(_Route(_Mode.plan, reminder: reminder)),
            style: _BS.outline,
            block: true,
            key: const ValueKey('focus-another'),
          ),
        ],
        const SizedBox(height: 8),
        _Btn(
          "I'm done for now",
          sheet.close,
          style: reminder == null ? _BS.primary : _BS.ghost,
          block: true,
          key: const ValueKey('focus-done'),
        ),
        if (reminder != null && info.outcome == 'finished')
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.hairline, width: .5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Note(
                  'Your reminder is still open. Finishing it is a separate step.',
                  top: 0,
                ),
                const SizedBox(height: 10),
                _Btn(
                  reminder.isOrder ? 'Mark shipped' : 'Mark reminder done',
                  () {
                    final id = reminder.id;
                    sheet.close();
                    if (reminder.isOrder) {
                      unawaited(c.onOpenReminder?.call(id));
                    } else {
                      unawaited(c.onMarkDone?.call(id));
                    }
                  },
                  style: _BS.outline,
                  block: true,
                  key: const ValueKey('focus-mark-done'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
