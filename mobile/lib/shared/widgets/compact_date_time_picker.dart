import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.g.dart';

/// A compact date and time dialog with independent calendar and time controls.
///
/// It returns a local [DateTime] only when the user confirms; cancellation
/// returns `null` and leaves the caller's value untouched.
class CompactDateTimePicker extends StatefulWidget {
  const CompactDateTimePicker({super.key, required this.initial});

  final DateTime initial;

  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initial,
  }) => showDialog<DateTime>(
    context: context,
    builder: (_) => CompactDateTimePicker(initial: initial),
  );

  @override
  State<CompactDateTimePicker> createState() => _CompactDateTimePickerState();
}

class _CompactDateTimePickerState extends State<CompactDateTimePicker> {
  late DateTime _visibleMonth = DateTime(
    widget.initial.year,
    widget.initial.month,
  );
  late DateTime _selectedDate = DateTime(
    widget.initial.year,
    widget.initial.month,
    widget.initial.day,
  );
  late DateTime _selectedTime = DateTime(
    2000,
    1,
    1,
    widget.initial.hour,
    widget.initial.minute,
  );
  int _wheelRevision = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final textColor = dark
        ? EzyDesignTokens.darkText
        : EzyDesignTokens.lightText;
    final secondaryColor = dark
        ? EzyDesignTokens.darkText2
        : EzyDesignTokens.lightText2;
    final surface = dark
        ? EzyDesignTokens.darkSurface
        : EzyDesignTokens.lightSurface;
    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('date-previous-month'),
                    tooltip: 'Previous month',
                    onPressed: () => setState(
                      () => _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month - 1,
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _monthTitle(_visibleMonth),
                      key: const ValueKey('date-visible-month'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('date-next-month'),
                    tooltip: 'Next month',
                    onPressed: () => setState(
                      () => _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month + 1,
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final weekday in const [
                    'S',
                    'M',
                    'T',
                    'W',
                    'T',
                    'F',
                    'S',
                  ])
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            weekday,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _calendarGrid(theme),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Time',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: textColor,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(context, _selectedTime),
                    key: const ValueKey('selected-date-time-label'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  _timePreset('Morning', 9),
                  _timePreset('Noon', 12),
                  _timePreset('Evening', 18),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                key: const ValueKey('date-time-wheel'),
                height: 132,
                child: CupertinoDatePicker(
                  key: ValueKey('time-wheel-$_wheelRevision'),
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _selectedTime,
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  minuteInterval: 1,
                  onDateTimeChanged: (value) => setState(() {
                    _selectedTime = DateTime(
                      2000,
                      1,
                      1,
                      value.hour,
                      value.minute,
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('date-time-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('date-time-ok'),
                    onPressed: () => Navigator.of(context).pop(
                      DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        _selectedTime.hour,
                        _selectedTime.minute,
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timePreset(String label, int hour) => OutlinedButton(
    key: ValueKey('time-preset-${label.toLowerCase()}'),
    onPressed: () => setState(() {
      _selectedTime = DateTime(2000, 1, 1, hour);
      _wheelRevision++;
    }),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(label),
  );

  Widget _calendarGrid(ThemeData theme) {
    final firstWeekday =
        DateTime(_visibleMonth.year, _visibleMonth.month).weekday % 7;
    final dayCount = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final cellCount = ((firstWeekday + dayCount + 6) ~/ 7) * 7;
    final accent = theme.colorScheme.primary;
    return GridView.builder(
      key: const ValueKey('date-calendar-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 44,
      ),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        final day = index - firstWeekday + 1;
        if (day < 1 || day > dayCount) return const SizedBox.shrink();
        final selected =
            _selectedDate.year == _visibleMonth.year &&
            _selectedDate.month == _visibleMonth.month &&
            _selectedDate.day == day;
        return Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: TextButton(
              key: ValueKey('date-day-$day'),
              onPressed: () => setState(
                () => _selectedDate = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month,
                  day,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: selected ? theme.colorScheme.onPrimary : null,
                backgroundColor: selected ? accent : Colors.transparent,
                shape: const CircleBorder(),
              ),
              child: Text('$day'),
            ),
          ),
        );
      },
    );
  }

  String _monthTitle(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.year}';

  String _formatTime(BuildContext context, DateTime value) {
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    if (use24Hour) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}
