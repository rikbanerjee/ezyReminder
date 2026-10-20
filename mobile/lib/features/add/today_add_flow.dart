import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../main.dart' show Palette;
import '../home/home_repository.dart';

/// Today's Add flow (DESIGN.md §5.1, mirrors web `lib/add-flow.ts`): a
/// doorway into the existing organized creation forms. Steps are strings:
/// `root` · `sidegig` · `gig:<kind>` · `home` · `home:<section>` ·
/// `task:<category>` · `list:shopping` · `list:groceries` · `form:work` ·
/// `form:social`.
const addDestinations = [
  (key: 'work', label: 'Work', description: 'A work task or follow-up'),
  (
    key: 'sidegig',
    label: 'Side Gig',
    description: 'Tasks, orders, follow-ups and expected payments',
  ),
  (
    key: 'home',
    label: 'Home',
    description: 'Home care, groceries, bills and study',
  ),
  (key: 'social', label: 'Social', description: 'A personal reminder'),
  (key: 'shopping', label: 'Shopping', description: 'A shopping checklist'),
];
const sideGigAddKinds = {
  'work': ['Task', 'A client deliverable or a small next step'],
  'order': ['Order', 'Recipient, ship-by date and tracking'],
  'followup': ['Follow-up', 'A reply or update to remember'],
  'payment': ['Expected payment', 'Money to collect and when to check in'],
};

bool isAddForm(String step) => RegExp(r'^(gig|task|list|form):').hasMatch(step);
String addStepFor(String destination) => switch (destination) {
  'sidegig' || 'home' => destination,
  'shopping' => 'list:shopping',
  _ => 'form:$destination',
};
List<String> homeCategoriesIn(String section) => [
  for (final key in homeCategories.keys)
    if (homeTemplate(key).section == section) key,
];
String homeSectionStep(String section) {
  if (section == 'groceries') return 'list:groceries';
  final categories = homeCategoriesIn(section);
  return categories.length == 1 ? 'task:${categories.first}' : 'home:$section';
}

String? addStepParent(String step) {
  if (step == 'root') return null;
  if (step.startsWith('gig:')) return 'sidegig';
  if (step == 'list:groceries' || step.startsWith('home:')) return 'home';
  if (step.startsWith('task:')) {
    final section = homeTemplate(step.substring(5)).section;
    return homeCategoriesIn(section).length == 1 ? 'home' : 'home:$section';
  }
  return 'root';
}

/// What a hosted form saved: `kind` is the Side Gig kind or Home category.
typedef AddSaved = ({String destination, String kind, String id});
String addConfirmation(AddSaved saved) => switch (saved.destination) {
  'sidegig' => switch (saved.kind) {
    'order' => 'Order added to Ship Queue',
    'followup' => 'Follow-up added to Side Gig',
    'payment' => 'Expected payment added to Side Gig',
    _ => 'Task added to Side Gig',
  },
  'home' => '${homeTemplate(saved.kind).text('noun')} added to Home',
  'work' => 'Work reminder added to Today',
  _ => 'Reminder added to Today',
};

/// Navigation a hosted form uses instead of popping the whole flow itself.
/// Both report whether the form has unsaved input.
class AddFlowNav {
  const AddFlowNav({required this.back, required this.close});
  final ValueChanged<bool> back, close;
}

/// One bottom sheet for the whole flow. Visited forms stay mounted offstage,
/// so Back returns to the chooser and keeps what was typed. A form saves
/// through its usual repository call and then pops this sheet.
class TodayAddFlow extends StatefulWidget {
  const TodayAddFlow({
    super.key,
    required this.reminderForm,
    required this.gigForm,
    required this.homeForm,
  });

  /// `work`, `social` or `shopping`.
  final Widget Function(String slug, AddFlowNav nav) reminderForm;
  final Widget Function(String kind, AddFlowNav nav) gigForm;
  final Widget Function(String category, AddFlowNav nav) homeForm;
  @override
  State<TodayAddFlow> createState() => _TodayAddFlowState();
}

class _TodayAddFlowState extends State<TodayAddFlow> {
  String step = 'root';
  final forms = <String, Widget>{};
  final dirty = <String>{};

  void go(String next) {
    setState(() {
      step = next;
      if (isAddForm(next)) forms.putIfAbsent(next, () => formFor(next));
    });
  }

  Widget formFor(String key) {
    final nav = AddFlowNav(
      back: (isDirty) {
        isDirty ? dirty.add(key) : dirty.remove(key);
        final parent = addStepParent(key);
        if (parent != null) go(parent);
      },
      close: (isDirty) => close(isDirty ? {...dirty, key} : dirty),
    );
    if (key.startsWith('gig:')) return widget.gigForm(key.substring(4), nav);
    if (key.startsWith('task:')) return widget.homeForm(key.substring(5), nav);
    return widget.reminderForm(
      key.startsWith('list:') ? 'shopping' : key.substring(5),
      nav,
    );
  }

  Future<void> close(Set<String> drafts) async {
    if (drafts.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Discard what you’ve entered?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  String get title => switch (step) {
    'root' => 'What would you like to add?',
    'sidegig' => 'Add to Side Gig',
    'home' => 'Add to Home',
    _ => homeSections[step.substring(5)]!['label'] as String,
  };

  Widget row(
    IconData icon,
    Color color,
    String label,
    String description,
    String next,
  ) {
    final p = Theme.of(context).extension<Palette>()!;
    return InkWell(
      key: ValueKey('add-choice-$next'),
      onTap: () => go(next),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(fontSize: 13, color: p.secondary),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 14, color: p.secondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget chooser() {
    final p = Theme.of(context).extension<Palette>()!;
    final parent = addStepParent(step);
    const destinationIcons = {
      'work': CupertinoIcons.briefcase,
      'sidegig': CupertinoIcons.bag,
      'home': CupertinoIcons.house,
      'social': CupertinoIcons.person_2,
      'shopping': CupertinoIcons.cart,
    };
    const sectionIcons = {
      'care': CupertinoIcons.house,
      'groceries': CupertinoIcons.cart,
      'bills': CupertinoIcons.doc_text,
      'study': CupertinoIcons.book,
    };
    const categoryIcons = {
      'car': CupertinoIcons.car_detailed,
      'hvac': CupertinoIcons.wind,
      'dryer': CupertinoIcons.arrow_2_circlepath,
      'battery': CupertinoIcons.battery_25,
      'other': CupertinoIcons.wrench,
    };
    final destinationColors = {
      'work': p.contexts[0],
      'sidegig': p.contexts[1],
      'home': p.contexts[2],
      'social': p.contexts[2],
      'shopping': p.contexts[3],
    };
    final rows = switch (step) {
      'root' => [
        for (final d in addDestinations)
          row(
            destinationIcons[d.key]!,
            destinationColors[d.key]!,
            d.label,
            d.description,
            addStepFor(d.key),
          ),
      ],
      'sidegig' => [
        for (final e in sideGigAddKinds.entries)
          row(
            e.key == 'order' ? CupertinoIcons.cube_box : CupertinoIcons.circle,
            p.contexts[1],
            e.value[0],
            e.value[1],
            'gig:${e.key}',
          ),
      ],
      'home' => [
        for (final e in homeSections.entries)
          row(
            sectionIcons[e.key] ?? CupertinoIcons.house,
            e.key == 'groceries' ? p.contexts[3] : p.contexts[2],
            e.value['label'] as String,
            e.value['hint'] as String,
            homeSectionStep(e.key),
          ),
      ],
      _ => [
        for (final key in homeCategoriesIn(step.substring(5)))
          row(
            categoryIcons[key] ?? CupertinoIcons.wrench,
            p.contexts[2],
            homeTemplate(key).text('label'),
            homeTemplate(key).text('hint'),
            'task:$key',
          ),
      ],
    };
    return Container(
      key: const ValueKey('add-chooser'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                  if (parent != null)
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => go(parent),
                      icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                    ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => close(dirty),
                    icon: const Icon(CupertinoIcons.xmark, size: 18),
                  ),
                ],
              ),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // System back steps back; the visible form keeps its draft offstage.
      // A form can't report its state here, so its draft counts as unsaved.
      if (isAddForm(step)) dirty.add(step);
      final parent = addStepParent(step);
      if (parent == null) {
        close(dirty);
      } else {
        go(parent);
      }
    },
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (!isAddForm(step)) chooser(),
        for (final entry in forms.entries)
          Offstage(
            key: ValueKey('add-form-${entry.key}'),
            offstage: entry.key != step,
            child: TickerMode(
              enabled: entry.key == step,
              child: ExcludeFocus(
                excluding: entry.key != step,
                child: entry.value,
              ),
            ),
          ),
      ],
    ),
  );
}
