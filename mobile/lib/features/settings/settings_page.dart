import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';
import '../../core/util/device_timezone.dart';
import '../../core/util/quiet_hours.dart';
import '../focus/focus_controller.dart';
import '../focus/focus_widgets.dart';
import 'settings_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.onSignOut,
    required this.onDeleted,
    required this.onChanged,
    this.focusController,
  });

  /// Focus planning (migrations 0015/0016). Null or unavailable hides Settings → Focus.
  final FocusController? focusController;
  final SettingsRepository repository;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onDeleted;
  final VoidCallback onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _QuietDraft {
  _QuietDraft({required this.start, required this.end});

  String start;
  String end;
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  SettingsData? data;
  bool loading = true;
  String? loadError;
  String timezoneDraft = '';
  late final TextEditingController _timezoneController =
      TextEditingController();
  bool timezoneDirty = false;
  String? timezoneError;
  bool savingTimezone = false;
  String? deviceZone;
  bool followDevice = false;
  int _timezoneRevision = 0;
  bool signingOut = false;
  bool deleting = false;
  bool confirmingDelete = false;
  String? accountError;
  final Map<String, _QuietDraft> _quietDrafts = {};
  final Set<String> _dirtyQuiet = {};
  final Set<String> _savingQuiet = {};
  final Map<String, String> _quietErrors = {};
  StreamSubscription<void>? _changes;
  int _loadGeneration = 0;
  final Map<String, int> _quietSaveGeneration = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.repository.changes.listen((_) => _load());
    _load();
    unawaited(_loadDeviceZone());
  }

  Future<void> _loadDeviceZone() async {
    final zone = await DeviceTimezone.read();
    final follows = await DeviceTimezone.follows();
    if (!mounted) return;
    setState(() {
      deviceZone = zone;
      followDevice = zone != null && follows;
    });
    _catchUpWithDevice();
  }

  /// Following the iPhone, but the account still has another zone.
  void _catchUpWithDevice() {
    final zone = deviceZone;
    if (followDevice &&
        zone != null &&
        !savingTimezone &&
        data != null &&
        data!.timezone != zone) {
      unawaited(_saveTimezone(zone: zone, follow: true));
    }
  }

  Future<void> _setFollowDevice(bool value) async {
    setState(() => followDevice = value);
    if (value) {
      await _saveTimezone(zone: deviceZone, follow: true);
    } else {
      await DeviceTimezone.setFollows(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _timezoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (data == null && mounted) setState(() => loading = true);
    try {
      final latest = await widget.repository.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        data = latest;
        if (!timezoneDirty) {
          timezoneDraft = latest.timezone;
          _timezoneController.value = TextEditingValue(
            text: latest.timezone,
            selection: TextSelection.collapsed(offset: latest.timezone.length),
          );
        }
        for (final context in latest.contexts) {
          if (_dirtyQuiet.contains(context.id)) continue;
          _quietDrafts[context.id] = _QuietDraft(
            start: context.quietHours.start ?? '',
            end: context.quietHours.end ?? '',
          );
        }
        final currentIds = latest.contexts.map((item) => item.id).toSet();
        _quietDrafts.removeWhere((id, _) => !currentIds.contains(id));
        _dirtyQuiet.removeWhere((id) => !currentIds.contains(id));
        _quietErrors.removeWhere((id, _) => !currentIds.contains(id));
        loading = false;
        loadError = null;
      });
      _catchUpWithDevice();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        loading = false;
        loadError = 'Could not load settings. Check your connection and retry.';
      });
    }
  }

  /// Saving a zone by hand stops following the iPhone; [follow] keeps it.
  Future<void> _saveTimezone({String? zone, bool follow = false}) async {
    final value = zone ?? timezoneDraft.trim();
    if (!isValidTimeZone(value)) {
      setState(
        () => timezoneError =
            'Enter a valid IANA time zone, such as America/New_York.',
      );
      return;
    }
    final submittedRevision = _timezoneRevision;
    setState(() {
      savingTimezone = true;
      timezoneError = null;
      timezoneDirty = true;
    });
    try {
      await widget.repository.saveTimezone(value);
      if (!mounted) return;
      _loadGeneration++;
      setState(() {
        if (_timezoneRevision == submittedRevision) {
          timezoneDraft = value;
          _timezoneController.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
          timezoneDirty = false;
        }
        savingTimezone = false;
        if (data != null) data = data!.copyWith(timezone: value);
        if (deviceZone != null) followDevice = follow;
      });
      if (deviceZone != null) await DeviceTimezone.setFollows(follow);
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        savingTimezone = false;
        timezoneDirty = true;
        if (follow) followDevice = false;
        timezoneError = 'Could not save time zone: $error';
      });
    }
  }

  _QuietDraft _draftFor(SettingsContext context) => _quietDrafts.putIfAbsent(
    context.id,
    () => _QuietDraft(
      start: context.quietHours.start ?? '',
      end: context.quietHours.end ?? '',
    ),
  );

  Future<void> _pickTime(SettingsContext context, {required bool start}) async {
    final draft = _draftFor(context);
    final existing = start ? draft.start : draft.end;
    final parsed = _parseTime(existing);
    final picked = await showTimePicker(
      context: contextFor(context),
      initialTime: parsed ?? const TimeOfDay(hour: 21, minute: 0),
      helpText: start ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final current = _draftFor(context);
      if (start) {
        current.start = _formatTime(picked);
      } else {
        current.end = _formatTime(picked);
      }
      _dirtyQuiet.add(context.id);
      _quietErrors.remove(context.id);
    });
  }

  BuildContext contextFor(SettingsContext _) => context;

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _displayTime(String value) {
    final parsed = _parseTime(value);
    return parsed?.format(context) ?? 'Not set';
  }

  Future<void> _saveQuietHours(SettingsContext item) async {
    final draft = _draftFor(item);
    final generation = (_quietSaveGeneration[item.id] ?? 0) + 1;
    _quietSaveGeneration[item.id] = generation;
    setState(() {
      _savingQuiet.add(item.id);
      _quietErrors.remove(item.id);
    });
    try {
      await widget.repository.saveQuietHours(
        item.id,
        start: draft.start.isEmpty ? '' : draft.start,
        end: draft.end.isEmpty ? '' : draft.end,
      );
      if (!mounted || _quietSaveGeneration[item.id] != generation) return;
      _loadGeneration++;
      setState(() {
        _savingQuiet.remove(item.id);
        _dirtyQuiet.remove(item.id);
        if (data != null) {
          final updated = data!.contexts
              .map(
                (context) => context.id == item.id
                    ? context.copyWith(
                        quietHours: QuietHours(
                          start: draft.start,
                          end: draft.end,
                        ),
                      )
                    : context,
              )
              .toList();
          data = data!.copyWith(contexts: updated);
        }
      });
      widget.onChanged();
    } catch (error) {
      if (!mounted || _quietSaveGeneration[item.id] != generation) return;
      setState(() {
        _savingQuiet.remove(item.id);
        _dirtyQuiet.add(item.id);
        _quietErrors[item.id] = 'Could not save quiet hours: $error';
      });
    }
  }

  Future<void> _clearQuietHours(SettingsContext item) async {
    setState(() {
      _draftFor(item)
        ..start = ''
        ..end = '';
      _dirtyQuiet.add(item.id);
    });
    await _saveQuietHours(item);
  }

  Future<void> _signOut() async {
    if (signingOut || deleting || confirmingDelete) return;
    setState(() {
      signingOut = true;
      accountError = null;
    });
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        setState(() {
          signingOut = false;
          accountError = 'Could not sign out: $error';
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (deleting || signingOut || confirmingDelete) return;
    setState(() => confirmingDelete = true);
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account and its data. Type DELETE to confirm.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('delete-account-confirmation'),
                controller: controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Type DELETE',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-delete-account'),
              onPressed: controller.text == 'DELETE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => confirmingDelete = false);
      return;
    }
    setState(() {
      confirmingDelete = false;
      deleting = true;
      accountError = null;
    });
    try {
      await widget.repository.deleteAccount();
      if (!mounted) return;
      await widget.onDeleted();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        setState(() {
          deleting = false;
          accountError = 'Could not delete account: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark
        ? EzyDesignTokens.darkBackground
        : EzyDesignTokens.lightBackground;
    final surface = dark
        ? EzyDesignTokens.darkSurface
        : EzyDesignTokens.lightSurface;
    final hairline = dark
        ? EzyDesignTokens.darkHairline
        : EzyDesignTokens.lightHairline;
    final text = dark ? EzyDesignTokens.darkText : EzyDesignTokens.lightText;
    final secondary = dark
        ? EzyDesignTokens.darkText2
        : EzyDesignTokens.lightText2;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      body: loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : loadError != null && data == null
          ? _loadFailure(theme)
          : SafeArea(
              top: false,
              child: ListView(
                key: const ValueKey('settings-list'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (loadError != null) _inlineError(theme, loadError!),
                  _sectionLabel('GENERAL', secondary),
                  _group(surface, hairline, [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        'Time zone',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (deviceZone != null)
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile.adaptive(
                          key: const ValueKey('settings-follow-device'),
                          title: const Text('Use iPhone time zone'),
                          subtitle: Text(deviceZone!),
                          value: followDevice,
                          onChanged: savingTimezone ? null : _setFollowDevice,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        key: const ValueKey('settings-timezone'),
                        controller: _timezoneController,
                        readOnly: savingTimezone || followDevice,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: 'America/New_York',
                          errorText: timezoneError,
                          helperText: followDevice
                              ? 'Follows this iPhone. Turn it off to choose another zone.'
                              : 'Use an IANA time zone identifier.',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() {
                          _timezoneRevision++;
                          timezoneDraft = value;
                          timezoneDirty = true;
                          timezoneError = null;
                        }),
                      ),
                    ),
                    if (followDevice)
                      const SizedBox(height: 12)
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
                          child: FilledButton(
                            key: const ValueKey('save-timezone'),
                            onPressed: savingTimezone || !timezoneDirty
                                ? null
                                : _saveTimezone,
                            child: Text(
                              savingTimezone ? 'Saving…' : 'Save time zone',
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 22),
                  _sectionLabel('CONTEXTS · QUIET HOURS', secondary),
                  if (data!.contexts.isEmpty)
                    _group(surface, hairline, [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No contexts are available.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ),
                    ])
                  else
                    for (final item in data!.contexts) ...[
                      const SizedBox(height: 8),
                      _contextGroup(item, surface, hairline, text, secondary),
                    ],
                  if (widget.focusController != null)
                    AnimatedBuilder(
                      animation: widget.focusController!,
                      builder: (context, _) {
                        final focus = widget.focusController!;
                        if (!focus.planning) return const SizedBox.shrink();
                        final count = focus.focusTimes.length;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 22),
                            _sectionLabel('FOCUS', secondary),
                            _group(surface, hairline, [
                              Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  key: const ValueKey('settings-focus-times'),
                                  minTileHeight: 52,
                                  title: const Text('Focus times'),
                                  trailing: Text(
                                    '${count == 0 ? 'None yet' : '$count set up'} ›',
                                    style: TextStyle(color: secondary),
                                  ),
                                  onTap: () => openFocusTimes(
                                    context,
                                    focus,
                                    fromSettings: true,
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 22),
                  _sectionLabel('ACCOUNT', secondary),
                  _group(surface, hairline, [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.person_crop_circle,
                            color: secondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Signed in as',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: secondary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                SelectableText(
                                  data!.email,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: hairline,
                    ),
                    Material(
                      color: surface,
                      child: ListTile(
                        key: const ValueKey('settings-sign-out'),
                        leading: Icon(
                          CupertinoIcons.square_arrow_right,
                          color: secondary,
                        ),
                        title: Text(signingOut ? 'Signing out…' : 'Sign out'),
                        enabled: !signingOut && !deleting && !confirmingDelete,
                        onTap: _signOut,
                      ),
                    ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: hairline,
                    ),
                    Material(
                      color: surface,
                      child: ListTile(
                        key: const ValueKey('settings-delete-account'),
                        leading: Icon(
                          CupertinoIcons.delete,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          'Delete account',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        subtitle: const Text(
                          'Permanently delete your account and data',
                        ),
                        enabled: !signingOut && !deleting && !confirmingDelete,
                        onTap: _confirmDelete,
                      ),
                    ),
                    if (accountError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: _inlineError(theme, accountError!),
                      ),
                    if (deleting)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: LinearProgressIndicator(),
                      ),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _contextGroup(
    SettingsContext item,
    Color surface,
    Color hairline,
    Color text,
    Color secondary,
  ) {
    final theme = Theme.of(context);
    final draft = _draftFor(item);
    final accent = _contextColor(item.slug, theme.brightness);
    final saving = _savingQuiet.contains(item.id);
    return _group(surface, hairline, [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 24,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(item.name, style: theme.textTheme.titleMedium),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: ValueKey('quiet-start-${item.id}'),
                onPressed: saving ? null : () => _pickTime(item, start: true),
                icon: const Icon(CupertinoIcons.moon, size: 17),
                label: Text('Start · ${_displayTime(draft.start)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: ValueKey('quiet-end-${item.id}'),
                onPressed: saving ? null : () => _pickTime(item, start: false),
                icon: const Icon(CupertinoIcons.sun_max, size: 17),
                label: Text('End · ${_displayTime(draft.end)}'),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Row(
          children: [
            TextButton.icon(
              key: ValueKey('clear-quiet-${item.id}'),
              onPressed: saving ? null : () => _clearQuietHours(item),
              icon: const Icon(CupertinoIcons.clear, size: 17),
              label: const Text('Clear'),
            ),
            const Spacer(),
            if (saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              FilledButton.tonal(
                key: ValueKey('save-quiet-${item.id}'),
                onPressed: _dirtyQuiet.contains(item.id)
                    ? () => _saveQuietHours(item)
                    : null,
                child: const Text('Save'),
              ),
          ],
        ),
      ),
      if (_quietErrors[item.id] case final error?)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _inlineError(theme, error),
        ),
      if (item.quietHours.start?.isNotEmpty == true &&
          item.quietHours.end?.isNotEmpty == true &&
          item.quietHours.start == item.quietHours.end)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text(
            'Equal start and end times mean quiet hours are inactive.',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ),
    ]);
  }

  Color _contextColor(String slug, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (slug) {
      'work' => dark ? EzyDesignTokens.darkWork : EzyDesignTokens.lightWork,
      'side_gig' || 'side-gig' =>
        dark ? EzyDesignTokens.darkSidegig : EzyDesignTokens.lightSidegig,
      'social' =>
        dark ? EzyDesignTokens.darkSocial : EzyDesignTokens.lightSocial,
      'shopping' =>
        dark ? EzyDesignTokens.darkShopping : EzyDesignTokens.lightShopping,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Widget _sectionLabel(String label, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: .8,
      ),
    ),
  );

  Widget _group(Color surface, Color hairline, List<Widget> children) =>
      Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hairline),
          boxShadow: [
            Theme.of(context).brightness == Brightness.dark
                ? EzyDesignTokens.darkCardShadow
                : EzyDesignTokens.lightCardShadow,
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _inlineError(ThemeData theme, String message) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
      ),
    ),
  );

  Widget _loadFailure(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.wifi_exclamationmark,
            color: theme.colorScheme.error,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('retry-settings-load'),
            onPressed: _load,
            icon: const Icon(CupertinoIcons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
