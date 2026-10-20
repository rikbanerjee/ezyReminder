import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';
import '../../main.dart'
    show Palette, Reminder, ReminderRepository, ShoppingRepository;
import '../shopping/shopping_list_sheet.dart';
import '../../shared/widgets/compact_date_time_picker.dart';
import 'home_repository.dart';
import '../add/today_add_flow.dart' show AddFlowNav;

class HouseholdPage extends StatefulWidget {
  const HouseholdPage({
    super.key,
    required this.reminders,
    required this.repository,
    this.openId,
    this.onSettings,
  });
  final ReminderRepository reminders;
  final HouseholdRepository repository;
  final String? openId;
  final VoidCallback? onSettings;
  @override
  State<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends State<HouseholdPage>
    with WidgetsBindingObserver {
  List<Reminder> shopping = [];
  List<HomeMaintenance> maintenance = [];
  List<Map<String, dynamic>> records = [];
  final listName = TextEditingController();
  String? error;
  String? listError;
  String historyCategory = 'all';
  String section = 'care';
  bool loading = true, adding = false;
  int generation = 0;
  String? openedId;
  StreamSubscription<void>? subscription;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = widget.reminders.changes.listen((_) => reload());
    reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
  }

  @override
  void didUpdateWidget(covariant HouseholdPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openId != widget.openId) reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    listName.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final request = ++generation;
    try {
      final reminders = await widget.reminders.load();
      final items = await widget.repository.load();
      final history = await widget.repository.history();
      if (!mounted || request != generation) return;
      setState(() {
        shopping = reminders
            .where(
              (r) =>
                  r.contextSlug == 'shopping' &&
                  r.status != 'done' &&
                  r.status != 'cancelled',
            )
            .toList();
        maintenance = items;
        records = history;
        error = null;
        loading = false;
      });
      if (widget.openId != null && openedId != widget.openId) {
        final matches = items.where((m) => m.id == widget.openId);
        openedId = widget.openId;
        if (matches.isNotEmpty) {
          setState(
            () => section = homeTemplate(matches.first.category).section,
          );
          await edit(matches.first.category, matches.first);
        }
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          error = 'Could not load Home. Check your connection and pull down to retry.';
          loading = false;
        });
      }
    }
  }

  Future<void> addList() async {
    if (adding) return;
    final title = listName.text.trim();
    if (title.isEmpty) {
      setState(() => listError = 'Give your shopping list a name.');
      return;
    }
    setState(() {
      adding = true;
      listError = null;
    });
    try {
      final contexts = await widget.reminders.contexts();
      final context = contexts.firstWhere((c) => c.slug == 'shopping');
      final id = await widget.reminders.save(
        title: title,
        notes: null,
        dueAt: null,
        contextId: context.id,
        isOrder: false,
        channels: [],
      );
      if (id == null) throw StateError('No list returned');
      if (!mounted) return;
      listName.clear();
      await reload();
      final matches = shopping.where((r) => r.id == id);
      if (mounted && matches.isNotEmpty) await openShopping(matches.first);
    } catch (_) {
      if (mounted) {
        setState(() => listError = 'Could not create list. Try again.');
      }
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> openShopping(Reminder reminder) async {
    if (widget.reminders is! ShoppingRepository) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 300),
        curve: EzyDesignTokens.sheetCurve,
        reverseCurve: EzyDesignTokens.sheetCurve,
      ),
      builder: (_) => ShoppingListSheet(
        reminder: reminder,
        repository: widget.reminders as ShoppingRepository,
        changes: widget.reminders.changes,
      ),
    );
    if (mounted) await reload();
  }

  Future<void> edit(String category, [HomeMaintenance? item]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: const Duration(milliseconds: 300),
              reverseDuration: const Duration(milliseconds: 300),
              curve: EzyDesignTokens.sheetCurve,
              reverseCurve: EzyDesignTokens.sheetCurve,
            ),
      builder: (_) => MaintenanceEditor(
        repository: widget.repository,
        category: category,
        item: item,
      ),
    );
    if (mounted) await reload();
  }

  Widget card(Widget child) {
    final p = Theme.of(context).extension<Palette>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
        boxShadow: dark
            ? [EzyDesignTokens.darkCardShadow]
            : [EzyDesignTokens.lightCardShadow],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<Palette>()!;
    final categories = homeCategories.entries
        .where((c) => homeTemplate(c.key).section == section)
        .toList();
    final history = records
        .where(
          (r) =>
              homeTemplate(r['category'] as String).section == section &&
              (historyCategory == 'all' ||
                  homeCategory(r['category'] as String) == historyCategory),
        )
        .toList();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Home',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.onSettings != null)
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: widget.onSettings,
                    icon: const Icon(CupertinoIcons.gear),
                  ),
              ],
            ),
            Text(
              'A little less to remember, in the sections you need.',
              style: TextStyle(color: p.secondary),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in homeSections.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.value['label'] as String),
                        selected: section == entry.key,
                        onSelected: (_) => setState(() {
                          section = entry.key;
                          historyCategory = 'all';
                        }),
                        selectedColor:
                            (entry.key == 'groceries'
                                    ? p.contexts[3]
                                    : p.contexts[2])
                                .withValues(alpha: .14),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (loading) const LinearProgressIndicator(),
            if (section == 'groceries') ...[
              const Text(
                'GROCERY & SHOPPING LISTS',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: listName,
                      decoration: InputDecoration(
                        labelText: 'New shopping list',
                        hintText: 'Weekly groceries',
                        errorText: listError,
                      ),
                      onSubmitted: (_) => addList(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create shopping list',
                    onPressed: adding ? null : addList,
                    icon: Icon(
                      CupertinoIcons.add_circled_solid,
                      color: p.contexts[3],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in shopping)
                card(
                  ListTile(
                    title: Text(r.title),
                    subtitle: const Text('Open checklist'),
                    leading: Icon(CupertinoIcons.cart, color: p.contexts[3]),
                    trailing: const Icon(CupertinoIcons.chevron_right),
                    onTap: () => openShopping(r),
                  ),
                ),
              if (!loading && shopping.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Make a grocery list, then check off items as you shop.',
                  ),
                ),
            ] else ...[
              Text(
                (homeSections[section]!['heading'] as String).toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              for (final category in categories)
                card(
                  Column(
                    children: [
                      ListTile(
                        title: Text(
                          category.value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(homeTemplate(category.key).text('hint')),
                        leading: Icon(switch (category.key) {
                          'car' => CupertinoIcons.car,
                          'hvac' => CupertinoIcons.wind,
                          'dryer' => CupertinoIcons.arrow_2_circlepath,
                          'battery' => CupertinoIcons.battery_charging,
                          'bill' => CupertinoIcons.doc_plaintext,
                          'study' => CupertinoIcons.book,
                          _ => CupertinoIcons.wrench,
                        }, color: p.contexts[2]),
                        trailing: IconButton(
                          tooltip: 'Add ${category.value}',
                          onPressed: error != null
                              ? null
                              : () => edit(category.key),
                          icon: Icon(CupertinoIcons.add, color: p.contexts[2]),
                        ),
                      ),
                      for (final item
                          in (maintenance
                              .where(
                                (m) =>
                                    m.category == category.key &&
                                    m.status != 'done' &&
                                    m.status != 'cancelled',
                              )
                              .toList()
                            ..sort(
                              (a, b) => (a.due ?? DateTime(9999)).compareTo(
                                b.due ?? DateTime(9999),
                              ),
                            )))
                        ListTile(
                          title: Text(item.title),
                          subtitle: Text(
                            '${homeTaskSummary(item.category, item.asset, item.details)} · ${item.due == null ? 'No date' : MaterialLocalizations.of(context).formatMediumDate(item.due!)} · ${homeRepeatValue(item) == 'off' ? 'One time' : homeRepeatLabel(homeRepeatValue(item))}',
                            style: TextStyle(
                              color: item.due?.isBefore(DateTime.now()) == true
                                  ? Theme.of(context).colorScheme.error
                                  : p.secondary,
                            ),
                          ),
                          trailing: const Icon(CupertinoIcons.chevron_right),
                          onTap: () => edit(category.key, item),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '${(homeSections[section]!['history'] as String).toUpperCase()} · ${history.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (categories.length > 1)
                DropdownButton<String>(
                  isExpanded: true,
                  value: historyCategory,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All home care'),
                    ),
                    ...categories.map(
                      (c) =>
                          DropdownMenuItem(value: c.key, child: Text(c.value)),
                    ),
                  ],
                  onChanged: (v) => setState(() => historyCategory = v!),
                ),
              if (history.isEmpty)
                Text(homeSections[section]!['empty'] as String),
              for (final record in history)
                card(
                  ListTile(
                    title: Text(record['title'] as String),
                    subtitle: Text(
                      '${homeTaskSummary(record['category'] as String, record['asset'] as String, Map<String, dynamic>.from(record['details'] as Map? ?? const {}))} · ${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(record['serviced_at'] as String).toLocal())}\n${[for (final field in homeTemplate(record['category'] as String).fields)
                        if ((record['details'] as Map?)?[field['key']] != null) "${field['label']}: ${(record['details'] as Map)[field['key']]}"].join(' · ')}\n${record['notes']}',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class MaintenanceEditor extends StatefulWidget {
  const MaintenanceEditor({
    super.key,
    required this.repository,
    required this.category,
    this.item,
    this.flow,
    this.onSaved,
  });
  final HouseholdRepository repository;
  final String category;
  final HomeMaintenance? item;

  /// Hosted by Today's Add flow: Back/Close go through the flow.
  final AddFlowNav? flow;
  final ValueChanged<String?>? onSaved;
  @override
  State<MaintenanceEditor> createState() => _MaintenanceEditorState();
}

class _MaintenanceEditorState extends State<MaintenanceEditor> {
  final form = GlobalKey<FormState>();
  HomeTaskTemplate get template => homeTemplate(widget.category);
  late final title = TextEditingController(
    text: widget.item?.title ?? template.text('title'),
  );
  late final asset = TextEditingController(text: widget.item?.asset ?? '');
  late final notes = TextEditingController(text: widget.item?.notes ?? '');
  late final details = <String, TextEditingController>{
    for (final f in template.fields)
      f['key'] as String: TextEditingController(
        text: widget.item?.details[f['key']] as String? ?? '',
      ),
  };
  final recordNotes = TextEditingController();
  late DateTime? due = widget.item?.due;
  DateTime completed = DateTime.now();
  late String repeat = homeRepeatValue(widget.item);
  late bool apns = (widget.item?.data['channels'] as List? ?? []).contains(
    'apns',
  );
  bool recording = false, pending = false, dirty = false;
  String? error, dateError;
  @override
  void initState() {
    super.initState();
    for (final c in [title, asset, notes, ...details.values]) {
      c.addListener(() => dirty = true);
    }
  }

  @override
  void dispose() {
    title.dispose();
    asset.dispose();
    notes.dispose();
    recordNotes.dispose();
    for (final c in details.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? validateDetail(String key, String? raw) {
    final v = raw?.trim() ?? '';
    if (v.length > 1000) return 'Keep this under 1,000 characters';
    if (template.section == 'bills') {
      if (key == 'amount' &&
          v.isNotEmpty &&
          !RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(v)) {
        return 'Enter an amount such as 85.50';
      }
      if (key == 'currency') {
        if (details['amount']!.text.trim().isNotEmpty && v.isEmpty) {
          return 'Choose the currency for this amount';
        }
        if (v.isNotEmpty && !RegExp(r'^[A-Z]{3}$').hasMatch(v.toUpperCase())) {
          return 'Use a three-letter currency, such as USD';
        }
      }
    }
    return null;
  }

  Future<void> save() async {
    if (pending || !form.currentState!.validate()) return;
    if ((!recording && due == null) ||
        (recording && completed.isAfter(DateTime.now()))) {
      setState(
        () => dateError = recording
            ? 'Choose ${template.text('recordDate').toLowerCase()} that is now or earlier'
            : template.text('dueError'),
      );
      return;
    }
    setState(() {
      pending = true;
      error = null;
      dateError = null;
    });
    try {
      if (recording) {
        await widget.repository.record({
          'p_id': widget.item!.id,
          'p_expected_updated_at': widget.item!.data['updated_at'],
          'p_serviced_at': completed.toUtc().toIso8601String(),
          'p_notes': recordNotes.text,
        });
      } else {
        final id = await widget.repository.save({
          'p_id': widget.item?.id,
          'p_title': title.text.trim(),
          'p_notes': notes.text,
          'p_due_at': due!.toUtc().toIso8601String(),
          'p_category': homeCategory(widget.category),
          'p_asset': asset.text,
          'p_repeat_months': repeat.startsWith('m')
              ? int.parse(repeat.substring(1))
              : null,
          'p_repeat_days': repeat.startsWith('d')
              ? int.parse(repeat.substring(1))
              : null,
          'p_details': {
            for (final entry in details.entries)
              if (entry.value.text.trim().isNotEmpty)
                entry.key: entry.key == 'currency'
                    ? entry.value.text.trim().toUpperCase()
                    : entry.value.text.trim(),
          },
          'p_channels': apns ? ['email', 'apns'] : ['email'],
        });
        dirty = false;
        widget.onSaved?.call(id ?? widget.item?.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save. Check your connection; refresh if this reminder changed on another device.',
        );
      }
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<Palette>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final value = recording ? completed : due;
    final dates = MaterialLocalizations.of(context);
    final dateLabel = value == null
        ? 'Choose date'
        : '${dates.formatMediumDate(value)} · ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
    return PopScope(
      canPop: widget.flow != null || !pending,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            dark
                ? EzyDesignTokens.darkSheetShadow
                : EzyDesignTokens.lightSheetShadow,
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (widget.flow != null)
                        IconButton(
                          tooltip: 'Back',
                          onPressed: pending
                              ? null
                              : () => widget.flow!.back(dirty),
                          icon: const Icon(
                            CupertinoIcons.chevron_left,
                            size: 20,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          template.text(recording ? 'recordTitle' : 'label'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: pending
                            ? null
                            : widget.flow != null
                            ? () => widget.flow!.close(dirty)
                            : () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                    ],
                  ),
                  if (recording) ...[
                    Text(
                      widget.item!.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextFormField(
                      controller: recordNotes,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: template.text('recordNotes'),
                        hintText: template.text('recordPlaceholder'),
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: template.text('taskLabel'),
                        hintText: template.text('taskPlaceholder'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? '${template.text('taskLabel')} required'
                          : null,
                    ),
                    TextFormField(
                      controller: asset,
                      decoration: InputDecoration(
                        labelText: template.text('assetLabel'),
                        hintText: template.text('assetPlaceholder'),
                      ),
                    ),
                    for (final f in template.fields)
                      TextFormField(
                        controller: details[f['key']],
                        keyboardType: f['input'] == 'decimal'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        textCapitalization: f['input'] == 'currency'
                            ? TextCapitalization.characters
                            : TextCapitalization.none,
                        decoration: InputDecoration(
                          labelText: f['label'] as String,
                          hintText: f['placeholder'] as String,
                        ),
                        validator: (v) => validateDetail(f['key'] as String, v),
                      ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: pending
                        ? null
                        : () async {
                            final selected = await CompactDateTimePicker.show(
                              context,
                              initial: value ?? DateTime.now(),
                            );
                            if (selected != null && mounted) {
                              setState(() {
                                if (recording) {
                                  completed = selected;
                                } else {
                                  due = selected;
                                  dirty = true;
                                }
                                dateError = null;
                              });
                            }
                          },
                    child: Text(
                      '${template.text(recording ? 'recordDate' : 'dueLabel')}: $dateLabel',
                    ),
                  ),
                  if (dateError != null)
                    Text(
                      dateError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (!recording) ...[
                    DropdownButtonFormField<String>(
                      initialValue: repeat,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: template.text('repeatLabel'),
                      ),
                      items: [
                        for (final v in {...template.repeatOptions, repeat})
                          DropdownMenuItem(
                            value: v,
                            child: Text(homeRepeatLabel(v)),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        repeat = v!;
                        dirty = true;
                      }),
                    ),
                    TextFormField(
                      controller: notes,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: template.text('notesLabel'),
                        hintText: template.text('notesPlaceholder'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Email reminders on · Personal quiet hours apply.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Also send to my registered iPhone'),
                      value: apns,
                      onChanged: (v) => setState(() {
                        apns = v!;
                        dirty = true;
                      }),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        homeRepeatValue(widget.item) == 'off'
                            ? 'This completes the reminder and keeps a ${template.text('recordNoun')} record.'
                            : template.section == 'bills' ||
                                  template.section == 'study'
                            ? 'The next reminder follows its ${homeRepeatLabel(homeRepeatValue(widget.item)).toLowerCase()} schedule from the current due date.'
                            : 'The next reminder repeats ${homeRepeatLabel(homeRepeatValue(widget.item)).toLowerCase()} after this ${template.text('recordNoun')}.',
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: pending ? null : save,
                    child: Text(
                      pending
                          ? 'Saving…'
                          : recording
                          ? template.text('recordSave')
                          : 'Save reminder',
                    ),
                  ),
                  if (widget.item != null &&
                      !recording &&
                      widget.item!.status != 'done')
                    OutlinedButton(
                      onPressed: pending
                          ? null
                          : () => setState(() {
                              recording = true;
                              error = null;
                              dateError = null;
                            }),
                      child: Text(template.text('recordAction')),
                    ),
                  if (recording)
                    TextButton(
                      onPressed: pending
                          ? null
                          : () => setState(() => recording = false),
                      child: const Text('Back to reminder'),
                    ),
                  if (widget.item != null && !recording)
                    TextButton(
                      onPressed: pending
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete reminder?'),
                                  content: Text(
                                    'Saved ${template.text('recordNoun')} records will remain.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !mounted) return;
                              setState(() => pending = true);
                              try {
                                await widget.repository.delete(widget.item!.id);
                                if (mounted) Navigator.pop(this.context);
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () =>
                                        error = 'Could not delete. Try again.',
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => pending = false);
                              }
                            },
                      child: Text(
                        'Delete reminder',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
