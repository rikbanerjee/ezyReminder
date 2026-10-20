import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';
import '../../main.dart'
    show Palette, Reminder, ShoppingItem, ShoppingRepository;

class ShoppingListSheet extends StatefulWidget {
  const ShoppingListSheet({
    super.key,
    required this.reminder,
    required this.repository,
    required this.changes,
  });
  final Reminder reminder;
  final ShoppingRepository repository;
  final Stream<void> changes;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet>
    with WidgetsBindingObserver {
  late final title = TextEditingController(text: widget.reminder.title);
  late final itemInput = TextEditingController();
  final focus = FocusNode();
  final pending = <String>{};
  final deletedPending = <String>{};
  StreamSubscription<void>? subscription;
  List<ShoppingItem> items = [];
  bool loading = true;
  bool titleDirty = false;
  bool savingTitle = false;
  bool mergingTitle = false;
  String? titleError;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    title.addListener(() {
      if (!mergingTitle) titleDirty = true;
    });
    subscription = widget.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    title.dispose();
    itemInput.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++generation;
    try {
      final remote = await widget.repository.loadShoppingItems(
        widget.reminder.id,
      );
      if (!mounted || request != generation) return;
      setState(() {
        final localPending = items
            .where(
              (i) => pending.contains(i.id) && !deletedPending.contains(i.id),
            )
            .toList();
        final merged = <String, ShoppingItem>{};
        for (final item in remote) {
          if (!deletedPending.contains(item.id) && !pending.contains(item.id)) {
            merged[item.id] = item;
          }
        }
        for (final item in localPending) {
          merged[item.id] = item;
        }
        items = merged.values.toList();
        if (!titleDirty && !savingTitle) {
          unawaited(_refreshTitle());
        }
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = 'Could not load list items. Pull down to retry.';
        });
      }
    }
  }

  Future<void> _refreshTitle() async {
    try {
      final remoteTitle = await widget.repository.loadShoppingListTitle(
        widget.reminder.id,
      );
      if (!mounted || titleDirty || savingTitle || remoteTitle == null) return;
      if (title.text != remoteTitle) {
        mergingTitle = true;
        title.value = title.value.copyWith(
          text: remoteTitle,
          selection: TextSelection.collapsed(offset: remoteTitle.length),
        );
        mergingTitle = false;
      }
    } catch (_) {
      // Keep the current title visible if a background refresh cannot reach the server.
    }
  }

  Future<void> _add() async {
    final label = itemInput.text.trim();
    if (label.isEmpty) return;
    itemInput.clear();
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      pending.add(tempId);
      items = [
        ...items,
        ShoppingItem(
          id: tempId,
          label: label,
          checked: false,
          position: items.length,
        ),
      ];
    });
    try {
      final id = await widget.repository.addShoppingItem(
        widget.reminder.id,
        label,
      );
      if (!mounted) return;
      setState(() {
        pending.remove(tempId);
        items = items
            .map(
              (item) => item.id == tempId
                  ? ShoppingItem(
                      id: id,
                      label: item.label,
                      checked: false,
                      position: item.position,
                    )
                  : item,
            )
            .toList();
      });
      unawaited(_reload());
      focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.remove(tempId);
        items.removeWhere((item) => item.id == tempId);
      });
      unawaited(_reload());
      itemInput.text = label;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add item: $e')));
    }
  }

  Future<void> _toggle(ShoppingItem item) async {
    if (pending.contains(item.id)) return;
    final index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    setState(() {
      pending.add(item.id);
      items[index] = ShoppingItem(
        id: item.id,
        label: item.label,
        checked: !item.checked,
        position: item.position,
      );
    });
    try {
      await widget.repository.setShoppingItemChecked(item.id, !item.checked);
      if (mounted) {
        setState(() => pending.remove(item.id));
        unawaited(_reload());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.remove(item.id);
      });
      unawaited(_reload());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update item: $e')));
    }
  }

  Future<void> _delete(ShoppingItem item) async {
    if (pending.contains(item.id)) return;
    final index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    setState(() {
      pending.add(item.id);
      deletedPending.add(item.id);
      items.removeAt(index);
    });
    try {
      await widget.repository.deleteShoppingItem(item.id);
      if (mounted) {
        setState(() {
          pending.remove(item.id);
          deletedPending.remove(item.id);
        });
        unawaited(_reload());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pending.remove(item.id);
        deletedPending.remove(item.id);
      });
      unawaited(_reload());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete item: $e')));
    }
  }

  Future<bool> _saveTitle() async {
    if (!titleDirty) return true;
    if (savingTitle) return false;
    if (title.text.trim().isEmpty) {
      setState(() => titleError = 'List name is required.');
      return false;
    }
    setState(() => savingTitle = true);
    try {
      while (mounted && titleDirty) {
        final value = title.text.trim();
        if (value.isEmpty) {
          titleError = 'List name is required.';
          break;
        }
        await widget.repository.renameShoppingList(widget.reminder.id, value);
        if (title.text.trim() == value) {
          titleDirty = false;
          titleError = null;
        }
      }
    } catch (e) {
      if (mounted) {
        titleError = 'Could not save list name: $e';
      }
    } finally {
      if (mounted) setState(() => savingTitle = false);
    }
    return mounted && !titleDirty;
  }

  Future<void> _finish() async {
    if (savingTitle || !await _saveTitle() || !mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<Palette>()!;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<Object?>(
      canPop: !titleDirty && !savingTitle,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish());
      },
      child: DraggableScrollableSheet(
        initialChildSize: .72,
        minChildSize: .48,
        maxChildSize: .96,
        expand: false,
        builder: (context, scroll) => Material(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(EzyDesignTokens.sheetRadius),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(EzyDesignTokens.sheetRadius),
              ),
              boxShadow: [palette.sheetShadow],
            ),
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.secondary.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: title,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    titleDirty = true;
                    if (titleError != null || !savingTitle) {
                      setState(() {
                        titleError = null;
                      });
                    }
                  },
                  onSubmitted: (_) => unawaited(_saveTitle()),
                  onEditingComplete: () => unawaited(_saveTitle()),
                  style: TextStyle(
                    fontSize: EzyDesignTokens.screenTitleFontSize,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'List name',
                    border: InputBorder.none,
                    errorText: titleError,
                    suffixIcon: savingTitle
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('shopping-add-input'),
                  controller: itemInput,
                  focusNode: focus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(CupertinoIcons.add),
                    suffixIcon: IconButton(
                      tooltip: 'Add item',
                      onPressed: _add,
                      icon: const Icon(CupertinoIcons.arrow_up_circle_fill),
                    ),
                    hintText: '+ Add item…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (error != null)
                  TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(CupertinoIcons.refresh),
                    label: Text(error!),
                  )
                else if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Your list is ready. Add the first item above.',
                      style: TextStyle(color: palette.secondary),
                    ),
                  )
                else
                  ...items.map(
                    (item) => Container(
                      constraints: const BoxConstraints(minHeight: 54),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: palette.hairline.withValues(alpha: .7),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Checkbox(
                              value: item.checked,
                              onChanged: pending.contains(item.id)
                                  ? null
                                  : (_) => _toggle(item),
                              activeColor: palette.contexts[3],
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: pending.contains(item.id)
                                  ? null
                                  : () => _toggle(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    decoration: item.checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: item.checked
                                        ? palette.secondary
                                        : palette.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete ${item.label}',
                            onPressed: pending.contains(item.id)
                                ? null
                                : () => _delete(item),
                            icon: Icon(
                              CupertinoIcons.trash,
                              color: palette.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: savingTitle ? null : _finish,
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
