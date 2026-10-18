import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';
import 'focus_controller.dart';
import 'focus_models.dart';

Color _accent(BuildContext context, String slug) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return slug == 'work'
      ? (dark ? EzyDesignTokens.darkWork : EzyDesignTokens.lightWork)
      : (dark ? EzyDesignTokens.darkSidegig : EzyDesignTokens.lightSidegig);
}

BoxShadow _shadow(BuildContext context, {bool sheet = false}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return sheet
      ? (dark
            ? EzyDesignTokens.darkSheetShadow
            : EzyDesignTokens.lightSheetShadow)
      : (dark
            ? EzyDesignTokens.darkCardShadow
            : EzyDesignTokens.lightCardShadow);
}

String _time(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
String _due(DateTime date) {
  final local = date.toLocal();
  return '${local.month}/${local.day} · ${local.hour % 12 == 0 ? 12 : local.hour % 12}:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
}

Future<void> openFocus(
  BuildContext context,
  FocusController controller, {
  FocusReminder? reminder,
}) async {
  final reduced = MediaQuery.disableAnimationsOf(context);
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
    builder: (_) => _FocusSheet(controller: controller, reminder: reminder),
  );
}

class FocusCard extends StatelessWidget {
  const FocusCard({
    super.key,
    required this.controller,
    this.activeOnly = false,
  });
  final FocusController controller;
  final bool activeOnly;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final session = controller.session;
      if (activeOnly && session == null) return const SizedBox.shrink();
      final highlight = controller.state?.highlight;
      final reminder = controller.reminders
          .where((r) => r.id == highlight?.reminderId)
          .firstOrNull;
      final colors = Theme.of(context).colorScheme;
      final accent = _accent(
        context,
        session?.contextSlug ?? highlight?.contextSlug ?? 'work',
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "TODAY'S FOCUS",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [_shadow(context)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.error != null) ...[
                    Text(
                      controller.error!,
                      style: TextStyle(color: colors.error),
                    ),
                    TextButton(
                      onPressed: controller.busy ? null : controller.reload,
                      child: const Text('Retry loading Focus'),
                    ),
                  ] else if (controller.loading)
                    const Text('Loading focus…')
                  else if (session != null) ...[
                    Text(
                      '${session.contextSlug == 'work' ? 'Work' : 'Side Gig'} · ${session.awaitingFinish(controller.now)
                          ? 'Time is up'
                          : session.paused
                          ? 'Paused'
                          : 'In focus'}',
                      style: TextStyle(color: accent, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          label: 'Focus time remaining',
                          child: Text(
                            _time(session.remainingSeconds(controller.now)),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => openFocus(context, controller),
                          child: Text(
                            session.awaitingFinish(controller.now)
                                ? 'Review session'
                                : 'Open session',
                          ),
                        ),
                      ],
                    ),
                  ] else if (highlight != null) ...[
                    Text(
                      highlight.contextSlug == 'work' ? 'Work' : 'Side Gig',
                      style: TextStyle(color: accent, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reminder?.title ?? highlight.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (reminder?.dueAt != null)
                      Text(
                        'Due ${_due(reminder!.dueAt!)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    if (reminder == null)
                      const Text(
                        'This reminder is no longer available for focus. Choose another reminder.',
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: reminder == null
                              ? null
                              : () => openFocus(
                                  context,
                                  controller,
                                  reminder: reminder,
                                ),
                          child: const Text('Start focus'),
                        ),
                        TextButton(
                          onPressed: () => openFocus(context, controller),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      'What matters most today?',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose one Work or Side Gig reminder.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => openFocus(context, controller),
                      icon: const Icon(CupertinoIcons.scope),
                      label: const Text('Choose a reminder'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _FocusSheet extends StatefulWidget {
  const _FocusSheet({required this.controller, this.reminder});
  final FocusController controller;
  final FocusReminder? reminder;
  @override
  State<_FocusSheet> createState() => _FocusSheetState();
}

class _FocusSheetState extends State<_FocusSheet> {
  late String mode = widget.controller.session != null
      ? (widget.controller.session!.awaitingFinish(widget.controller.now)
            ? 'review'
            : 'session')
      : widget.reminder != null
      ? 'setup'
      : 'choose';
  late FocusReminder? selected = widget.reminder;
  final custom = TextEditingController(text: '25');
  final intent = TextEditingController();
  final nextStep = TextEditingController();
  String duration = '25', query = '';
  String? outcome, previousStep, stepError, startId;
  bool attempted = false;
  String? _sessionId;
  int _stepGeneration = 0;
  FocusController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _sessionId = c.session?.id;
    c.addListener(_changed);
    if (selected != null) unawaited(_loadStep());
  }

  void _changed() {
    if (!mounted) return;
    if (c.session?.id != _sessionId) {
      _sessionId = c.session?.id;
      outcome = null;
      attempted = false;
      nextStep.clear();
      if (c.session != null) {
        mode = c.session!.awaitingFinish(c.now) ? 'review' : 'session';
      } else if (mode == 'session' || mode == 'review') {
        mode = 'choose';
      }
    }
    setState(() {});
  }

  Future<void> _loadStep() async {
    final generation = ++_stepGeneration;
    setState(() {
      previousStep = null;
      stepError = null;
    });
    try {
      final step = await c.repository.latestNextStep(selected!.id);
      if (mounted && generation == _stepGeneration) {
        setState(() => previousStep = step);
      }
    } catch (_) {
      if (mounted && generation == _stepGeneration) {
        setState(() => stepError = 'Could not load your last next step.');
      }
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    custom.dispose();
    intent.dispose();
    nextStep.dispose();
    super.dispose();
  }

  Widget _button(String text, VoidCallback action, {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: primary
            ? FilledButton.tonal(
                onPressed: c.busy ? null : action,
                child: Text(text),
              )
            : OutlinedButton(
                onPressed: c.busy ? null : action,
                child: Text(text),
              ),
      );
  @override
  Widget build(BuildContext context) {
    final session = c.session;
    final colors = Theme.of(context).colorScheme;
    final accent = _accent(
      context,
      session?.contextSlug ?? selected?.contextSlug ?? 'work',
    );
    final minutes = int.tryParse(duration == 'custom' ? custom.text : duration);
    final valid = minutes != null && minutes >= 1 && minutes <= 180;
    final target = session?.title ?? selected?.title;
    final title = switch (mode) {
      'choose' => "Today's focus",
      'setup' => 'Start focus',
      'review' => 'How did it go?',
      _ => 'Focus session',
    };
    final content = <Widget>[
      Center(
        child: Container(
          width: 36,
          height: 5,
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Close focus',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(CupertinoIcons.xmark),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (c.error != null) ...[
        Text(c.error!, style: TextStyle(color: colors.error)),
        _button('Retry loading Focus', () => unawaited(c.reload())),
      ],
      if (mode != 'choose' && target != null) ...[
        Text(
          (session?.contextSlug ?? selected?.contextSlug) == 'work'
              ? 'Work'
              : 'Side Gig',
          style: TextStyle(fontSize: 13, color: accent),
        ),
        Text(
          target,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
      ],
    ];
    if (mode == 'choose') {
      final candidates = c.reminders
          .where(
            (r) =>
                r.eligible &&
                r.title.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
      content.addAll([
        const Text('One reminder for today. Its deadline stays the same.'),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search Work and Side Gig reminders',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        for (final r in candidates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              CupertinoIcons.circle_fill,
              size: 8,
              color: _accent(context, r.contextSlug),
            ),
            title: Text(r.title),
            subtitle: Text(r.contextName),
            trailing: const Icon(CupertinoIcons.chevron_right),
            onTap: c.busy || c.error != null
                ? null
                : () async {
                    if (await c.mutate(() => c.repository.highlight(r.id)) &&
                        context.mounted) {
                      Navigator.pop(context);
                    }
                  },
          ),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Add a Work or Side Gig reminder to choose your focus.',
            ),
          ),
      ]);
    } else if (mode == 'setup') {
      content.addAll([
        if (previousStep != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last next step',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(previousStep!),
              ],
            ),
          ),
        if (stepError != null) ...[
          Text(stepError!),
          _button('Retry next step', () => unawaited(_loadStep())),
        ],
        const SizedBox(height: 12),
        const Text('How long?'),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['10', '25', '50', 'custom'])
              ChoiceChip(
                label: Text(value == 'custom' ? 'Custom' : '$value min'),
                selected: duration == value,
                selectedColor: accent.withValues(alpha: .18),
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  duration = value;
                  startId = null;
                }),
              ),
          ],
        ),
        if (duration == 'custom')
          TextField(
            controller: custom,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Minutes (1–180)',
              errorText: valid ? null : 'Choose a whole number from 1 to 180.',
            ),
            onChanged: (_) => setState(() => startId = null),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: intent,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'What would you like to finish? (optional)',
          ),
          onChanged: (_) => startId = null,
        ),
        _button(c.busy ? 'Starting…' : 'Start now', () async {
          if (!valid) {
            setState(() => attempted = true);
            return;
          }
          startId ??= newFocusId();
          final saved = await c.mutate(
            () => c.repository.start(
              startId!,
              selected!,
              minutes,
              intent.text.trim().isEmpty ? null : intent.text.trim(),
            ),
          );
          if (mounted && saved) {
            setState(() {
              mode = 'session';
              startId = null;
            });
          }
        }, primary: true),
      ]);
    } else if (session != null) {
      final expired = session.awaitingFinish(c.now);
      content.addAll([
        if (session.intendedOutcome != null) Text(session.intendedOutcome!),
        const SizedBox(height: 12),
        Center(
          child: Semantics(
            label: 'Focus time remaining',
            child: Text(
              _time(session.remainingSeconds(c.now)),
              style: const TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Center(
          child: Text(
            expired
                ? 'Time is up. Ready to review?'
                : session.paused
                ? 'Paused'
                : 'One thing at a time.',
          ),
        ),
        const SizedBox(height: 16),
        if (mode == 'session') ...[
          if (!expired)
            _button(
              session.paused ? 'Resume' : 'Pause',
              () => unawaited(
                c.mutate(
                  () => session.paused
                      ? c.repository.resume(session)
                      : c.repository.pause(session),
                ),
              ),
            ),
          _button(
            expired ? 'Review session' : 'End session',
            () => setState(() => mode = 'review'),
            primary: true,
          ),
        ] else ...[
          const Text('How did this session go?'),
          for (final choice in [
            ('finished', 'Finished what I planned'),
            ('progress', 'Made progress'),
            ('interrupted', 'Got interrupted'),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  backgroundColor: outcome == choice.$1
                      ? accent.withValues(alpha: .18)
                      : null,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => setState(() => outcome = choice.$1),
                child: Text(choice.$2),
              ),
            ),
          if (attempted && outcome == null)
            Text(
              'Choose how your session went.',
              style: TextStyle(color: colors.error),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: nextStep,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Next step for next time (optional)',
            ),
          ),
          const Text(
            'This saves your session. Your reminder stays as it is.',
            style: TextStyle(fontSize: 12),
          ),
          _button(c.busy ? 'Saving…' : 'Save session', () async {
            setState(() => attempted = true);
            if (outcome == null) return;
            final saved = await c.mutate(
              () => c.repository.finish(
                session,
                outcome!,
                nextStep.text.trim().isEmpty ? null : nextStep.text.trim(),
              ),
            );
            if (context.mounted && saved) Navigator.pop(context);
          }, primary: true),
          if (!expired)
            _button('Back to session', () => setState(() => mode = 'session')),
        ],
      ]);
    }
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [_shadow(context, sheet: true)],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
        ),
      ),
    );
  }
}
