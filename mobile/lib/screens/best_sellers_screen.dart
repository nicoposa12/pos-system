import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/order_details_modal.dart';
import '../widgets/period_picker_dialogs.dart';
import '../widgets/product_image_view.dart';
import '../widgets/skeleton.dart';

enum BestSellersPeriod { all, daily, weekly, monthly, yearly }

/// Full product sales leaderboard with Daily, Weekly, Monthly, Yearly, and All-Time filters.
class BestSellersScreen extends StatefulWidget {
  final BestSellersPeriod initialPeriod;

  const BestSellersScreen({
    super.key,
    this.initialPeriod = BestSellersPeriod.all,
  });

  @override
  State<BestSellersScreen> createState() => _BestSellersScreenState();
}

class _BestSellersScreenState extends State<BestSellersScreen> {
  late BestSellersPeriod _period;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedWeekStart = startOfCalendarWeek(DateTime.now());
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;
  bool _sortByRevenue = false;
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _searchController = TextEditingController();
    Future.microtask(() {
      if (!mounted) return;
      context.read<TransactionProvider>().fetchTransactions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesPeriod(SaleTransaction tx, DateTime now) {
    switch (_period) {
      case BestSellersPeriod.all:
        return true;
      case BestSellersPeriod.daily:
        return tx.date.year == _selectedDate.year &&
            tx.date.month == _selectedDate.month &&
            tx.date.day == _selectedDate.day;
      case BestSellersPeriod.weekly:
        final txDay = DateTime(tx.date.year, tx.date.month, tx.date.day);
        final start = DateTime(
          _selectedWeekStart.year,
          _selectedWeekStart.month,
          _selectedWeekStart.day,
        );
        final end = endOfCalendarWeek(start);
        return !txDay.isBefore(start) && !txDay.isAfter(end);
      case BestSellersPeriod.monthly:
        return tx.date.year == _selectedMonth.year &&
            tx.date.month == _selectedMonth.month;
      case BestSellersPeriod.yearly:
        return tx.date.year == _selectedYear;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _hasCustomPicker => _period != BestSellersPeriod.all;

  bool _canStepForward(DateTime now) {
    switch (_period) {
      case BestSellersPeriod.daily:
        final today = DateTime(now.year, now.month, now.day);
        final current = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        return current.isBefore(today);
      case BestSellersPeriod.weekly:
        return _selectedWeekStart.isBefore(startOfCalendarWeek(now));
      case BestSellersPeriod.monthly:
        return _selectedMonth.year < now.year ||
            (_selectedMonth.year == now.year &&
                _selectedMonth.month < now.month);
      case BestSellersPeriod.yearly:
        return _selectedYear < now.year;
      case BestSellersPeriod.all:
        return false;
    }
  }

  bool _canStepBackward() {
    switch (_period) {
      case BestSellersPeriod.daily:
        return _selectedDate.isAfter(DateTime(2020, 1, 1));
      case BestSellersPeriod.weekly:
        return _selectedWeekStart.isAfter(DateTime(2020, 1, 1));
      case BestSellersPeriod.monthly:
        return _selectedMonth.year > 2020 ||
            (_selectedMonth.year == 2020 && _selectedMonth.month > 1);
      case BestSellersPeriod.yearly:
        return _selectedYear > 2020;
      case BestSellersPeriod.all:
        return false;
    }
  }

  void _stepPeriod(int delta) {
    final now = DateTime.now();
    HapticFeedback.selectionClick();
    setState(() {
      switch (_period) {
        case BestSellersPeriod.daily:
          final next = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day + delta,
          );
          final today = DateTime(now.year, now.month, now.day);
          if (next.isAfter(today)) {
            _selectedDate = today;
          } else if (!next.isBefore(DateTime(2020, 1, 1))) {
            _selectedDate = next;
          }
          break;
        case BestSellersPeriod.weekly:
          final next = DateTime(
            _selectedWeekStart.year,
            _selectedWeekStart.month,
            _selectedWeekStart.day + (delta * 7),
          );
          final currentWeekStart = startOfCalendarWeek(now);
          if (next.isAfter(currentWeekStart)) {
            _selectedWeekStart = currentWeekStart;
          } else if (!next.isBefore(DateTime(2020, 1, 1))) {
            _selectedWeekStart = next;
          }
          break;
        case BestSellersPeriod.monthly:
          final next = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
          final currentMonth = DateTime(now.year, now.month);
          if (next.isAfter(currentMonth)) {
            _selectedMonth = currentMonth;
          } else if (next.year >= 2020) {
            _selectedMonth = next;
          }
          break;
        case BestSellersPeriod.yearly:
          final next = (_selectedYear + delta).clamp(2020, now.year);
          _selectedYear = next;
          break;
        case BestSellersPeriod.all:
          break;
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _period = BestSellersPeriod.daily;
      });
    }
  }

  Future<void> _pickWeek() async {
    final picked = await showWeekPickerDialog(
      context,
      initialWeekStart: _selectedWeekStart,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedWeekStart = picked;
        _period = BestSellersPeriod.weekly;
      });
    }
  }

  Future<void> _pickMonthYear() async {
    final picked = await showMonthYearPickerDialog(
      context,
      initialMonth: _selectedMonth,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedMonth = picked;
        _period = BestSellersPeriod.monthly;
      });
    }
  }

  Future<void> _pickYear() async {
    final picked = await showYearPickerDialog(
      context,
      initialYear: _selectedYear,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedYear = picked;
        _period = BestSellersPeriod.yearly;
      });
    }
  }

  void _openActivePicker() {
    switch (_period) {
      case BestSellersPeriod.weekly:
        _pickWeek();
        break;
      case BestSellersPeriod.monthly:
        _pickMonthYear();
        break;
      case BestSellersPeriod.yearly:
        _pickYear();
        break;
      case BestSellersPeriod.daily:
      case BestSellersPeriod.all:
        _pickCustomDate();
        break;
    }
  }

  String _chipLabel(BestSellersPeriod period, DateTime now) {
    switch (period) {
      case BestSellersPeriod.all:
        return 'All';
      case BestSellersPeriod.daily:
        return _isSameDay(_selectedDate, now)
            ? 'Daily'
            : DateFormat('MMM d').format(_selectedDate);
      case BestSellersPeriod.weekly:
        final isCurrentWeek = _isSameDay(
          _selectedWeekStart,
          startOfCalendarWeek(now),
        );
        if (isCurrentWeek) return 'Weekly';
        final end = endOfCalendarWeek(_selectedWeekStart);
        if (_selectedWeekStart.month == end.month) {
          return '${DateFormat('MMM d').format(_selectedWeekStart)}–${end.day}';
        }
        return '${DateFormat('MMM d').format(_selectedWeekStart)}–${DateFormat('MMM d').format(end)}';
      case BestSellersPeriod.monthly:
        final isThisMonth =
            _selectedMonth.year == now.year &&
            _selectedMonth.month == now.month;
        return isThisMonth
            ? 'Monthly'
            : DateFormat('MMM yyyy').format(_selectedMonth);
      case BestSellersPeriod.yearly:
        return _selectedYear == now.year ? 'Yearly' : '$_selectedYear';
    }
  }

  String _periodSummaryLabel(DateTime now) {
    switch (_period) {
      case BestSellersPeriod.all:
        return 'All Time';
      case BestSellersPeriod.daily:
        return _isSameDay(_selectedDate, now)
            ? 'Today (${DateFormat('MMM d').format(_selectedDate)})'
            : DateFormat('MMM d, yyyy').format(_selectedDate);
      case BestSellersPeriod.weekly:
        final isCurrentWeek = _isSameDay(
          _selectedWeekStart,
          startOfCalendarWeek(now),
        );
        final rangeLabel = formatWeekRangeLabel(_selectedWeekStart);
        return isCurrentWeek ? 'This Week ($rangeLabel)' : 'Week of $rangeLabel';
      case BestSellersPeriod.monthly:
        return DateFormat('MMMM yyyy').format(_selectedMonth);
      case BestSellersPeriod.yearly:
        return 'Year $_selectedYear';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txProvider = context.watch<TransactionProvider>();
    final productProvider = context.watch<ProductProvider>();
    final now = DateTime.now();

    final productsById = <int, Product>{
      for (final p in productProvider.allProducts)
        if (p.id != null) p.id!: p,
    };

    final periodSales = txProvider.getProductSales(
      filter: (tx) => _matchesPeriod(tx, now),
      sortByRevenue: _sortByRevenue,
    );

    final query = _searchQuery.trim().toLowerCase();
    final displayed = query.isEmpty
        ? periodSales
        : periodSales.where((item) {
            final name = (item['name'] ?? '').toString().toLowerCase();
            final category = (item['category'] ?? '').toString().toLowerCase();
            return name.contains(query) || category.contains(query);
          }).toList();

    final totalUnits = displayed.fold<double>(
      0.0,
      (sum, item) => sum + ((item['total_sold'] as num?)?.toDouble() ?? 0.0),
    );
    final totalRevenue = displayed.fold<double>(
      0.0,
      (sum, item) =>
          sum + ((item['total_revenue'] as num?)?.toDouble() ?? 0.0),
    );

    double maxMetric = 0.0;
    for (final item in displayed) {
      final metric = _sortByRevenue
          ? ((item['total_revenue'] as num?)?.toDouble() ?? 0.0)
          : ((item['total_sold'] as num?)?.toDouble() ?? 0.0);
      if (metric > maxMetric) maxMetric = metric;
    }
    if (maxMetric <= 0) maxMetric = 1.0;

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.accentOrange,
        onRefresh: () async {
          await Future.wait([
            txProvider.fetchTransactions(),
            productProvider.fetchProducts(),
          ]);
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 68,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  titleSpacing: 8,
                  title: const Text(
                    'Best Sellers',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search & Calendar Picker Row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                decoration: InputDecoration(
                                  hintText: 'Search product or category...',
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: AppTheme.mutedText(context),
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Clear',
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: theme.cardTheme.color,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                side: BorderSide(
                                  color: _hasCustomPicker
                                      ? AppTheme.accentOrange
                                      : AppTheme.borderColor(context),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                onTap: _openActivePicker,
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Tooltip(
                                    message: _period == BestSellersPeriod.weekly
                                        ? 'Select Week'
                                        : (_period == BestSellersPeriod.monthly
                                            ? 'Select Month & Year'
                                            : (_period == BestSellersPeriod.yearly
                                                ? 'Select Year'
                                                : 'Select Date')),
                                    child: const Icon(
                                      Icons.calendar_month_rounded,
                                      color: AppTheme.accentOrange,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Period Filter Chips
                        Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          children: BestSellersPeriod.values.map((period) {
                            final isSelected = _period == period;
                            final hasPicker = period != BestSellersPeriod.all;

                            return ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_chipLabel(period, now)),
                                  if (isSelected && hasPicker) ...[
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ],
                                ],
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                if (isSelected && hasPicker) {
                                  _openActivePicker();
                                } else {
                                  setState(() => _period = period);
                                }
                              },
                              selectedColor: AppTheme.accentOrange,
                              backgroundColor: theme.cardTheme.color,
                              side: BorderSide(
                                color: isSelected
                                    ? AppTheme.accentOrange
                                    : AppTheme.borderColor(context),
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : theme.colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 12.5,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Period Summary Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusLg,
                            ),
                            border: Border.all(
                              color: AppTheme.borderColor(context),
                            ),
                            boxShadow: AppTheme.cardShadow(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: _hasCustomPicker
                                          ? _openActivePicker
                                          : null,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                _periodSummaryLabel(now),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.mutedText(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_hasCustomPicker) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.arrow_drop_down_rounded,
                                                size: 18,
                                                color: AppTheme.accentOrange,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_hasCustomPicker) ...[
                                    IconButton(
                                      tooltip: 'Previous',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                        size: 20,
                                      ),
                                      onPressed: _canStepBackward()
                                          ? () => _stepPeriod(-1)
                                          : null,
                                    ),
                                    const SizedBox(width: 2),
                                    IconButton(
                                      tooltip: 'Next',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                      ),
                                      onPressed: _canStepForward(now)
                                          ? () => _stepPeriod(1)
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Product Sales',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.mutedText(context),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '₱${NumberFormat('#,##0.00').format(totalRevenue)}',
                                            style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.accentOrange,
                                              letterSpacing: -0.5,
                                              fontFeatures:
                                                  AppTheme.tabularFigures,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 36,
                                    color: AppTheme.borderColor(context),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Products',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppTheme.mutedText(
                                                context,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '${displayed.length}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                fontFeatures:
                                                    AppTheme.tabularFigures,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Units Sold',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.mutedText(context),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            formatQuantity(totalUnits),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              fontFeatures:
                                                  AppTheme.tabularFigures,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Text(
                                'Ranked Products (${displayed.length})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    label: const Text('Most Sold'),
                                    selected: !_sortByRevenue,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      HapticFeedback.selectionClick();
                                      setState(() => _sortByRevenue = false);
                                    },
                                    selectedColor: AppTheme.accentTeal,
                                    backgroundColor: theme.cardTheme.color,
                                    side: BorderSide(
                                      color: !_sortByRevenue
                                          ? AppTheme.accentTeal
                                          : AppTheme.borderColor(context),
                                    ),
                                    labelStyle: TextStyle(
                                      color: !_sortByRevenue
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                      fontWeight: !_sortByRevenue
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    label: const Text('Top Revenue'),
                                    selected: _sortByRevenue,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      HapticFeedback.selectionClick();
                                      setState(() => _sortByRevenue = true);
                                    },
                                    selectedColor: AppTheme.accentIndigo,
                                    backgroundColor: theme.cardTheme.color,
                                    side: BorderSide(
                                      color: _sortByRevenue
                                          ? AppTheme.accentIndigo
                                          : AppTheme.borderColor(context),
                                    ),
                                    labelStyle: TextStyle(
                                      color: _sortByRevenue
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                      fontWeight: _sortByRevenue
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                // Content List
                if (txProvider.isLoading && txProvider.transactions.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, _) => const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Skeleton(height: 84, borderRadius: 16),
                        ),
                        childCount: 6,
                      ),
                    ),
                  )
                else if (txProvider.errorMessage != null &&
                    txProvider.transactions.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 40,
                              color: AppTheme.mutedText(context),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              txProvider.errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () => txProvider.fetchTransactions(),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (displayed.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(context),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                query.isNotEmpty
                                    ? Icons.search_off_rounded
                                    : Icons.inventory_2_outlined,
                                size: 32,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              query.isNotEmpty
                                  ? 'No matching products'
                                  : 'No products sold in this period',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              query.isNotEmpty
                                  ? 'Try a different product name or category.'
                                  : 'No product sales recorded for ${_periodSummaryLabel(now)}.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedText(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            if (query.isNotEmpty)
                              OutlinedButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Text('Clear Search'),
                              )
                            else if (_period != BestSellersPeriod.all)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (_period != BestSellersPeriod.weekly)
                                    OutlinedButton(
                                      onPressed: () => setState(
                                        () => _period = BestSellersPeriod.weekly,
                                      ),
                                      child: const Text('View Weekly'),
                                    ),
                                  OutlinedButton(
                                    onPressed: () => setState(
                                      () => _period = BestSellersPeriod.all,
                                    ),
                                    child: const Text('Show All Time'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList.separated(
                      itemCount: displayed.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = displayed[index];
                        final productId =
                            (item['product_id'] as num?)?.toInt() ?? 0;
                        final product = productId > 0
                            ? productsById[productId]
                            : null;
                        final sold =
                            (item['total_sold'] as num?)?.toDouble() ?? 0.0;
                        final revenue =
                            (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
                        final metric = _sortByRevenue ? revenue : sold;
                        final ratio = (metric / maxMetric).clamp(0.04, 1.0);
                        final sharePercent = totalRevenue > 0
                            ? (revenue / totalRevenue * 100)
                            : 0.0;

                        return _BestSellerRowCard(
                          rank: index + 1,
                          name: (item['name'] ?? 'Item').toString(),
                          category:
                              (item['category'] ?? product?.category)
                                  ?.toString(),
                          unit: product?.unit,
                          imagePath: product?.imagePath,
                          sold: sold,
                          revenue: revenue,
                          orderCount:
                              (item['order_count'] as num?)?.toInt() ?? 0,
                          ratio: ratio,
                          sharePercent: sharePercent,
                          sortByRevenue: _sortByRevenue,
                          onTap: () => _showProductBreakdown(
                            context: context,
                            item: item,
                            product: product,
                            transactions: txProvider.transactions,
                            now: now,
                            periodLabel: _periodSummaryLabel(now),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProductBreakdown({
    required BuildContext context,
    required Map<String, dynamic> item,
    required Product? product,
    required List<SaleTransaction> transactions,
    required DateTime now,
    required String periodLabel,
  }) {
    final targetId = (item['product_id'] as num?)?.toInt() ?? 0;
    final targetName = (item['name'] ?? 'Item').toString();

    final matchingOrders = <({SaleTransaction tx, num qty, double subtotal})>[];
    for (final tx in transactions) {
      if (!_matchesPeriod(tx, now)) continue;
      num orderQty = 0;
      double orderSubtotal = 0.0;
      for (final line in tx.items) {
        final lineId = (line['product_id'] as num?)?.toInt() ?? 0;
        final lineName = (line['product_name'] ?? '').toString();
        final matches = targetId > 0
            ? lineId == targetId
            : lineName.toLowerCase() == targetName.toLowerCase();
        if (!matches) continue;
        final q = (line['quantity'] as num?) ?? 0;
        final sub = (line['subtotal'] as num?)?.toDouble() ?? 0.0;
        if (q <= 0 && sub <= 0) continue;
        orderQty += q;
        orderSubtotal += sub;
      }
      if (orderQty > 0 || orderSubtotal > 0) {
        matchingOrders.add((tx: tx, qty: orderQty, subtotal: orderSubtotal));
      }
    }

    final sold = (item['total_sold'] as num?)?.toDouble() ?? 0.0;
    final revenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final unit = product?.unit.trim();
    final unitSuffix = (unit != null && unit.isNotEmpty) ? ' $unit' : '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.82,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.borderColor(sheetCtx)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.borderColor(sheetCtx),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: AppTheme.subtleSurface(sheetCtx),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ProductImageView(
                              imagePath: product?.imagePath,
                              fit: BoxFit.cover,
                              placeholder: Icon(
                                Icons.inventory_2_outlined,
                                size: 20,
                                color: AppTheme.mutedText(sheetCtx),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  targetName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$periodLabel · ${matchingOrders.length} ${matchingOrders.length == 1 ? 'order' : 'orders'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.mutedText(sheetCtx),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface(sheetCtx),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sold',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.mutedText(sheetCtx),
                                    ),
                                  ),
                                  Text(
                                    '${formatQuantity(sold)}$unitSuffix',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: AppTheme.tabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Revenue',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.mutedText(sheetCtx),
                                    ),
                                  ),
                                  Text(
                                    '₱${NumberFormat('#,##0.00').format(revenue)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accentOrange,
                                      fontFeatures: AppTheme.tabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (product != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'In Stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.mutedText(sheetCtx),
                                      ),
                                    ),
                                    Text(
                                      product.formattedStock,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        itemCount: matchingOrders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final entry = matchingOrders[idx];
                          final tx = entry.tx;
                          return Material(
                            color: AppTheme.subtleSurface(ctx),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.of(sheetCtx).pop();
                                showOrderDetailsModal(context, tx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Order #${tx.id ?? '-'}',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat(
                                              'MMM d, yyyy · h:mm a',
                                            ).format(tx.date),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppTheme.mutedText(ctx),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₱${NumberFormat('#,##0.00').format(entry.subtotal)}',
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.accentOrange,
                                            fontFeatures:
                                                AppTheme.tabularFigures,
                                          ),
                                        ),
                                        Text(
                                          '${formatQuantity(entry.qty)}$unitSuffix',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.mutedText(ctx),
                                            fontFeatures:
                                                AppTheme.tabularFigures,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BestSellerRowCard extends StatelessWidget {
  final int rank;
  final String name;
  final String? category;
  final String? unit;
  final String? imagePath;
  final double sold;
  final double revenue;
  final int orderCount;
  final double ratio;
  final double sharePercent;
  final bool sortByRevenue;
  final VoidCallback onTap;

  const _BestSellerRowCard({
    required this.rank,
    required this.name,
    required this.category,
    required this.unit,
    required this.imagePath,
    required this.sold,
    required this.revenue,
    required this.orderCount,
    required this.ratio,
    required this.sharePercent,
    required this.sortByRevenue,
    required this.onTap,
  });

  Color _rankColor(BuildContext context) {
    switch (rank) {
      case 1:
        return AppTheme.accentOrange;
      case 2:
        return AppTheme.accentTeal;
      case 3:
        return AppTheme.accentIndigo;
      default:
        return AppTheme.mutedText(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rankColor = _rankColor(context);
    final isTop3 = rank <= 3;
    final trimmedUnit = unit?.trim();
    final soldLabel = (trimmedUnit != null && trimmedUnit.isNotEmpty)
        ? '${formatQuantity(sold)} $trimmedUnit sold'
        : '${formatQuantity(sold)} sold';
    final catLabel =
        (category != null && category!.trim().isNotEmpty)
            ? '${category!.trim()} · '
            : '';
    final ordersLabel =
        '$orderCount ${orderCount == 1 ? 'order' : 'orders'}';

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop3
                            ? rankColor.withValues(alpha: 0.14)
                            : AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: rankColor,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ProductImageView(
                        imagePath: imagePath,
                        fit: BoxFit.cover,
                        placeholder: Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: AppTheme.mutedText(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$catLabel$ordersLabel · ${sharePercent.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.mutedText(context),
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₱${NumberFormat('#,##0.00').format(revenue)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentOrange,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          soldLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mutedText(context),
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: AppTheme.subtleSurface(context),
                    color: rank == 1
                        ? AppTheme.accentOrange
                        : (sortByRevenue
                            ? AppTheme.accentIndigo
                            : AppTheme.accentTeal),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
