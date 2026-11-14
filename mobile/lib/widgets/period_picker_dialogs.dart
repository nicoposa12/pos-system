import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_theme.dart';

/// Returns the Sunday (`00:00:00`) of the calendar week containing [date].
DateTime startOfCalendarWeek(DateTime date) {
  final offset = date.weekday % 7; // Sun=0, Mon=1, ..., Sat=6
  return DateTime(date.year, date.month, date.day - offset);
}

/// Returns the Saturday (`00:00:00`) of the calendar week starting at [weekStart].
DateTime endOfCalendarWeek(DateTime weekStart) {
  return DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
}

/// Formats a 7-day week range cleanly (e.g. `Nov 8 – 14, 2026` or `Oct 26 – Nov 1, 2026`).
String formatWeekRangeLabel(DateTime weekStart) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end = endOfCalendarWeek(start);
  if (start.year == end.year) {
    if (start.month == end.month) {
      return '${DateFormat('MMM d').format(start)} – ${end.day}, ${end.year}';
    }
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }
  return '${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
}

/// Opens a custom Week picker dialog (Sun–Sat rows) and returns the selected
/// week's Sunday (`DateTime(year, month, day)`), or `null` if dismissed.
Future<DateTime?> showWeekPickerDialog(
  BuildContext context, {
  required DateTime initialWeekStart,
}) {
  DateTime pickerWeekStart = startOfCalendarWeek(initialWeekStart);
  int viewYear = initialWeekStart.year;
  int viewMonth = initialWeekStart.month;

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final currentWeekStart = startOfCalendarWeek(today);

          final firstOfMonth = DateTime(viewYear, viewMonth, 1);
          final gridStartOffset = firstOfMonth.weekday % 7;
          final firstGridSunday = DateTime(
            viewYear,
            viewMonth,
            1 - gridStartOffset,
          );
          final daysInMonth = DateTime(viewYear, viewMonth + 1, 0).day;
          final weekCount = ((gridStartOffset + daysInMonth) / 7).ceil();
          const weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

          final canPrevMonth =
              viewYear > 2020 || (viewYear == 2020 && viewMonth > 1);
          final canNextMonth =
              viewYear < now.year + 1 ||
              (viewYear == now.year + 1 && viewMonth < 12);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            backgroundColor: isDark
                ? AppTheme.surfaceDark
                : AppTheme.surfaceLight,
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: const Icon(
                    Icons.view_week_rounded,
                    color: AppTheme.accentOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Week',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 330,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Month & Year selector banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.cardDark
                            : AppTheme.subtleSurface(dialogCtx),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: AppTheme.borderColor(dialogCtx),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            tooltip: 'Previous Month',
                            onPressed: canPrevMonth
                                ? () {
                                    setDialogState(() {
                                      final prev = DateTime(
                                        viewYear,
                                        viewMonth - 1,
                                      );
                                      viewYear = prev.year;
                                      viewMonth = prev.month;
                                    });
                                  }
                                : null,
                          ),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  DateFormat('MMMM yyyy').format(
                                    DateTime(viewYear, viewMonth),
                                  ),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            tooltip: 'Next Month',
                            onPressed: canNextMonth
                                ? () {
                                    setDialogState(() {
                                      final next = DateTime(
                                        viewYear,
                                        viewMonth + 1,
                                      );
                                      viewYear = next.year;
                                      viewMonth = next.month;
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Weekday headers
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: weekdayLabels
                            .map(
                              (label) => Expanded(
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.mutedText(dialogCtx),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Selectable Week Rows
                    ...List.generate(weekCount, (rowIdx) {
                      final weekSunday = DateTime(
                        firstGridSunday.year,
                        firstGridSunday.month,
                        firstGridSunday.day + rowIdx * 7,
                      );
                      final isSelected = isSameDay(weekSunday, pickerWeekStart);
                      final isCurrentWeek =
                          isSameDay(weekSunday, currentWeekStart);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: isSelected
                              ? AppTheme.accentOrange
                              : (isDark ? AppTheme.cardDark : Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? AppTheme.accentOrange
                                  : (isCurrentWeek
                                      ? AppTheme.accentOrange.withValues(
                                          alpha: 0.6,
                                        )
                                      : AppTheme.borderColor(dialogCtx)),
                              width: isCurrentWeek && !isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            onTap: () {
                              setDialogState(() {
                                pickerWeekStart = weekSunday;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 9,
                              ),
                              child: Row(
                                children: List.generate(7, (dayIdx) {
                                  final day = DateTime(
                                    weekSunday.year,
                                    weekSunday.month,
                                    weekSunday.day + dayIdx,
                                  );
                                  final inViewedMonth = day.month == viewMonth;
                                  final isTodayCell = isSameDay(day, today);

                                  Color textColor;
                                  if (isSelected) {
                                    textColor = inViewedMonth
                                        ? Colors.white
                                        : Colors.white70;
                                  } else if (isTodayCell) {
                                    textColor = AppTheme.accentOrange;
                                  } else if (inViewedMonth) {
                                    textColor = Theme.of(
                                      dialogCtx,
                                    ).colorScheme.onSurface;
                                  } else {
                                    textColor = AppTheme.mutedText(
                                      dialogCtx,
                                    ).withValues(alpha: 0.55);
                                  }

                                  return Expanded(
                                    child: Center(
                                      child: Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected || isTodayCell
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: textColor,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Text(
                        formatWeekRangeLabel(pickerWeekStart),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop(currentWeekStart);
                      },
                      child: const Text('This Week'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop(pickerWeekStart);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Opens the custom Month & Year picker dialog and returns the chosen month
/// (as `DateTime(year, month)`), or `null` if dismissed.
Future<DateTime?> showMonthYearPickerDialog(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  int pickerYear = initialMonth.year;
  int pickerMonth = initialMonth.month;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          final now = DateTime.now();
          const monthNames = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          ];

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            backgroundColor: isDark
                ? AppTheme.surfaceDark
                : AppTheme.surfaceLight,
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: AppTheme.accentOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Month & Year',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 330,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Year selector banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.cardDark
                          : AppTheme.subtleSurface(dialogCtx),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: AppTheme.borderColor(dialogCtx),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          tooltip: 'Previous Year',
                          onPressed: pickerYear > 2020
                              ? () => setDialogState(() => pickerYear--)
                              : null,
                        ),
                        Text(
                          '$pickerYear',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          tooltip: 'Next Year',
                          onPressed: pickerYear < now.year + 2
                              ? () => setDialogState(() => pickerYear++)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Months 3x4 Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 2.1,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, idx) {
                      final monthNum = idx + 1;
                      final isSelected = monthNum == pickerMonth;
                      final isCurrentRealMonth =
                          pickerYear == now.year && monthNum == now.month;

                      return Material(
                        color: isSelected
                            ? AppTheme.accentOrange
                            : (isDark ? AppTheme.cardDark : Colors.white),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.accentOrange
                                : (isCurrentRealMonth
                                    ? AppTheme.accentOrange.withValues(
                                        alpha: 0.6,
                                      )
                                    : AppTheme.borderColor(dialogCtx)),
                            width:
                                isCurrentRealMonth && !isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          onTap: () {
                            setDialogState(() {
                              pickerMonth = monthNum;
                            });
                          },
                          child: Center(
                            child: Text(
                              monthNames[idx],
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isCurrentRealMonth
                                        ? AppTheme.accentOrange
                                        : Theme.of(
                                            dialogCtx,
                                          ).colorScheme.onSurface),
                                fontWeight: isSelected || isCurrentRealMonth
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop(DateTime(now.year, now.month));
                },
                child: const Text('This Month'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(
                        dialogCtx,
                      ).pop(DateTime(pickerYear, pickerMonth));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

/// Opens the custom Year picker dialog and returns the selected year,
/// or `null` if dismissed.
Future<int?> showYearPickerDialog(
  BuildContext context, {
  required int initialYear,
}) {
  int pickerYear = initialYear;
  final now = DateTime.now();
  const startYear = 2020;
  final endYear = now.year + 1;
  final years = List<int>.generate(
    endYear - startYear + 1,
    (i) => endYear - i,
  );

  return showDialog<int>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            backgroundColor: isDark
                ? AppTheme.surfaceDark
                : AppTheme.surfaceLight,
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: const Icon(
                    Icons.date_range_rounded,
                    color: AppTheme.accentOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Year',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: years.map((y) {
                  final isSelected = y == pickerYear;
                  final isCurrentYear = y == now.year;

                  return Material(
                    color: isSelected
                        ? AppTheme.accentOrange
                        : (isDark ? AppTheme.cardDark : Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.accentOrange
                            : (isCurrentYear
                                ? AppTheme.accentOrange.withValues(alpha: 0.6)
                                : AppTheme.borderColor(dialogCtx)),
                        width: isCurrentYear && !isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      onTap: () {
                        setDialogState(() {
                          pickerYear = y;
                        });
                      },
                      child: Container(
                        width: 88,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$y',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isCurrentYear
                                        ? AppTheme.accentOrange
                                        : Theme.of(
                                            dialogCtx,
                                          ).colorScheme.onSurface),
                                fontWeight: isSelected || isCurrentYear
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 15,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                            if (isCurrentYear) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Current',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isSelected
                                      ? Colors.white70
                                      : AppTheme.accentOrange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(now.year),
                child: const Text('This Year'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(pickerYear),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}
