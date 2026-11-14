import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/transaction.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/pdf_service.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/order_details_modal.dart';
import '../widgets/skeleton.dart';
import '../widgets/app_toast.dart';
import '../widgets/period_picker_dialogs.dart';
import 'scanner_screen.dart';

enum TransactionFilter { all, daily, weekly, monthly, yearly }

class TransactionHistoryScreen extends StatefulWidget {
  final ValueNotifier<TransactionFilter?>? filterRequest;
  final TransactionFilter initialFilter;

  const TransactionHistoryScreen({
    super.key,
    this.filterRequest,
    this.initialFilter = TransactionFilter.all,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  late TransactionFilter _currentFilter;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedYear = DateTime.now().year;
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String _paymentFilter = 'all'; // 'all', 'cash', 'gcash'

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.initialFilter;
    _searchController = TextEditingController();
    widget.filterRequest?.addListener(_handleExternalFilter);
    if (widget.filterRequest?.value != null) {
      _currentFilter = widget.filterRequest!.value!;
      _selectedDate = DateTime.now();
      _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
      _selectedYear = DateTime.now().year;
      widget.filterRequest!.value = null;
    }
    Future.microtask(() {
      if (!mounted) return;
      context.read<TransactionProvider>().fetchTransactions();
    });
  }

  @override
  void didUpdateWidget(covariant TransactionHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRequest != widget.filterRequest) {
      oldWidget.filterRequest?.removeListener(_handleExternalFilter);
      widget.filterRequest?.addListener(_handleExternalFilter);
    }
  }

  void _handleExternalFilter() {
    final requested = widget.filterRequest?.value;
    if (requested != null && mounted) {
      setState(() {
        _currentFilter = requested;
        _selectedDate = DateTime.now();
        _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
        _selectedYear = DateTime.now().year;
      });
      widget.filterRequest?.value = null;
    }
  }

  @override
  void dispose() {
    widget.filterRequest?.removeListener(_handleExternalFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(title: 'Scan Receipt Barcode'),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final handled = await handleOrderBarcodeScan(context, code);
    if (!handled && mounted) {
      setState(() {
        _searchController.text = code;
        _searchQuery = code;
      });
    }
  }

  List<SaleTransaction> _getFilteredTransactions(List<SaleTransaction> all) {
    final now = DateTime.now();
    Iterable<SaleTransaction> list;

    switch (_currentFilter) {
      case TransactionFilter.daily:
        list = all.where(
          (t) =>
              t.date.year == _selectedDate.year &&
              t.date.month == _selectedDate.month &&
              t.date.day == _selectedDate.day,
        );
        break;
      case TransactionFilter.weekly:
        final weekAgo = now.subtract(const Duration(days: 7));
        list = all.where((t) => t.date.isAfter(weekAgo));
        break;
      case TransactionFilter.monthly:
        list = all.where(
          (t) =>
              t.date.year == _selectedMonth.year &&
              t.date.month == _selectedMonth.month,
        );
        break;
      case TransactionFilter.yearly:
        list = all.where((t) => t.date.year == _selectedYear);
        break;
      case TransactionFilter.all:
        list = all;
        break;
    }

    if (_paymentFilter != 'all') {
      list = list.where((t) {
        final m = t.paymentMethod.toLowerCase();
        if (_paymentFilter == 'pending') {
          return m == 'pending' || m == 'debt';
        }
        return m == _paymentFilter;
      });
    }

    if (_searchQuery.trim().isNotEmpty) {
      var q = _searchQuery.trim().toLowerCase();
      q = q
          .replaceAll(
            RegExp(r'^(?:order|tx|receipt|rec)[-\s#:]*', caseSensitive: false),
            '',
          )
          .replaceAll('#', '')
          .trim();
      list = list.where(
        (t) =>
            '${t.id ?? ''}'.contains(q) ||
            t.paymentMethod.toLowerCase().contains(q) ||
            t.totalAmount.toStringAsFixed(2).contains(q),
      );
    }

    return list.toList();
  }

  String _getFilterLabel() {
    switch (_currentFilter) {
      case TransactionFilter.daily:
        final now = DateTime.now();
        final isToday =
            _selectedDate.year == now.year &&
            _selectedDate.month == now.month &&
            _selectedDate.day == now.day;
        return isToday
            ? 'Today (${DateFormat('MMM d').format(_selectedDate)})'
            : DateFormat('MMM d, yyyy').format(_selectedDate);
      case TransactionFilter.weekly:
        return 'Last 7 Days';
      case TransactionFilter.monthly:
        return DateFormat('MMMM yyyy').format(_selectedMonth);
      case TransactionFilter.yearly:
        return 'Year $_selectedYear';
      case TransactionFilter.all:
        return 'All Sales Records';
    }
  }

  String _chipLabel(TransactionFilter filter) {
    switch (filter) {
      case TransactionFilter.all:
        return 'All';
      case TransactionFilter.daily:
        final now = DateTime.now();
        final isToday =
            _selectedDate.year == now.year &&
            _selectedDate.month == now.month &&
            _selectedDate.day == now.day;
        return isToday ? 'Daily' : DateFormat('MMM d').format(_selectedDate);
      case TransactionFilter.weekly:
        return '7 Days';
      case TransactionFilter.monthly:
        final now = DateTime.now();
        final isThisMonth =
            _selectedMonth.year == now.year &&
            _selectedMonth.month == now.month;
        return isThisMonth
            ? 'Monthly'
            : DateFormat('MMM yyyy').format(_selectedMonth);
      case TransactionFilter.yearly:
        final now = DateTime.now();
        final isThisYear = _selectedYear == now.year;
        return isThisYear ? 'Yearly' : '$_selectedYear';
    }
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _currentFilter = TransactionFilter.daily;
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
        _currentFilter = TransactionFilter.monthly;
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
        _currentFilter = TransactionFilter.yearly;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<TransactionProvider>();
    final filteredTransactions = _getFilteredTransactions(
      provider.transactions,
    );
    final totalAmount = filteredTransactions.fold<double>(
      0.0,
      (sum, t) => sum + t.totalAmount,
    );
    final avgAmount = filteredTransactions.isEmpty
        ? 0.0
        : totalAmount / filteredTransactions.length;
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.accentOrange,
        onRefresh: () =>
            context.read<TransactionProvider>().fetchTransactions(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── App Bar ──
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 68,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  titleSpacing: 20,
                  title: const Text(
                    'Sales History',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  actions: [
                    IconButton(
                      onPressed: () => _showReturnsLog(context),
                      tooltip: 'Return Log',
                      icon: const Icon(Icons.assignment_return_outlined),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16, left: 4),
                      child: OutlinedButton.icon(
                        onPressed: filteredTransactions.isEmpty
                            ? null
                            : () {
                                final settings = context
                                    .read<SettingsProvider>();
                                PdfService.generateSalesReport(
                                  transactions: filteredTransactions,
                                  periodLabel: _getFilterLabel(),
                                  storeName: settings.storeName,
                                  storeAddress: settings.storeAddress,
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          foregroundColor: AppTheme.accentOrange,
                          side: BorderSide(
                            color: AppTheme.accentOrange.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 18,
                        ),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),

                // ── Period & Payment Controls ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search & Date Picker Row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                onSubmitted: (val) async {
                                  if (parseOrderBarcode(val) != null) {
                                    await handleOrderBarcodeScan(context, val);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search receipt # or amount...',
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
                                  color: AppTheme.borderColor(context),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                onTap: _scanBarcode,
                                child: const SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: AppTheme.accentOrange,
                                    size: 22,
                                  ),
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
                                  color:
                                      (_currentFilter == TransactionFilter.daily ||
                                       _currentFilter == TransactionFilter.monthly ||
                                       _currentFilter == TransactionFilter.yearly)
                                      ? AppTheme.accentOrange
                                      : AppTheme.borderColor(context),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                onTap: () {
                                  if (_currentFilter == TransactionFilter.monthly) {
                                    _pickMonthYear();
                                  } else if (_currentFilter == TransactionFilter.yearly) {
                                    _pickYear();
                                  } else {
                                    _pickCustomDate();
                                  }
                                },
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Tooltip(
                                    message: _currentFilter == TransactionFilter.monthly
                                        ? 'Select Month & Year'
                                        : (_currentFilter == TransactionFilter.yearly
                                            ? 'Select Year'
                                            : 'Select Date'),
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

                        // Period Filter Chips + Payment Mode Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...TransactionFilter.values.map((filter) {
                                final isSelected = _currentFilter == filter;
                                final hasPicker = filter == TransactionFilter.daily ||
                                    filter == TransactionFilter.monthly ||
                                    filter == TransactionFilter.yearly;

                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_chipLabel(filter)),
                                        if (isSelected && hasPicker) ...[
                                          const SizedBox(width: 3),
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
                                      if (filter == TransactionFilter.daily) {
                                        if (_currentFilter == TransactionFilter.daily) {
                                          _pickCustomDate();
                                        } else {
                                          setState(() => _currentFilter = filter);
                                        }
                                      } else if (filter == TransactionFilter.monthly) {
                                        if (_currentFilter == TransactionFilter.monthly) {
                                          _pickMonthYear();
                                        } else {
                                          setState(() => _currentFilter = filter);
                                          _pickMonthYear();
                                        }
                                      } else if (filter == TransactionFilter.yearly) {
                                        if (_currentFilter == TransactionFilter.yearly) {
                                          _pickYear();
                                        } else {
                                          setState(() => _currentFilter = filter);
                                          _pickYear();
                                        }
                                      } else {
                                        setState(() => _currentFilter = filter);
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
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }),
                              Container(
                                height: 22,
                                width: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                color: AppTheme.borderColor(context),
                              ),
                              const SizedBox(width: 4),
                              _PaymentFilterChip(
                                label: 'Cash',
                                isSelected: _paymentFilter == 'cash',
                                color: AppTheme.accentTeal,
                                onTap: () => setState(
                                  () => _paymentFilter =
                                      _paymentFilter == 'cash' ? 'all' : 'cash',
                                ),
                              ),
                              const SizedBox(width: 8),
                              _PaymentFilterChip(
                                label: 'GCash',
                                isSelected: _paymentFilter == 'gcash',
                                color: AppTheme.accentIndigo,
                                onTap: () => setState(
                                  () =>
                                      _paymentFilter = _paymentFilter == 'gcash'
                                      ? 'all'
                                      : 'gcash',
                                ),
                              ),
                              const SizedBox(width: 8),
                              _PaymentFilterChip(
                                label: 'Pending',
                                isSelected: _paymentFilter == 'pending',
                                color: AppTheme.accentAmber,
                                onTap: () => setState(
                                  () => _paymentFilter =
                                      _paymentFilter == 'pending'
                                      ? 'all'
                                      : 'pending',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

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
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (_currentFilter == TransactionFilter.monthly) {
                                          _pickMonthYear();
                                        } else if (_currentFilter == TransactionFilter.yearly) {
                                          _pickYear();
                                        } else if (_currentFilter == TransactionFilter.daily) {
                                          _pickCustomDate();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                _getFilterLabel(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.mutedText(context),
                                                ),
                                              ),
                                            ),
                                            if (_currentFilter == TransactionFilter.daily ||
                                                _currentFilter == TransactionFilter.monthly ||
                                                _currentFilter == TransactionFilter.yearly) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.arrow_drop_down_rounded,
                                                size: 16,
                                                color: AppTheme.accentOrange,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₱${NumberFormat('#,##0.00').format(totalAmount)}',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.accentOrange,
                                        letterSpacing: -0.5,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 38,
                                color: AppTheme.borderColor(context),
                              ),
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Orders',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.mutedText(context),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${filteredTransactions.length}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Avg. Ticket',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.mutedText(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₱${avgAmount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // ── Transaction List / Grid ──
                if (provider.isLoading)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, _) => const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Skeleton(height: 78, borderRadius: 16),
                        ),
                        childCount: 5,
                      ),
                    ),
                  )
                else if (filteredTransactions.isEmpty)
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
                                Icons.receipt_long_outlined,
                                size: 32,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sales records found',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Completed transactions for this period will appear here.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedText(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (isWide)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 520,
                            mainAxisExtent: 82,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final tx = filteredTransactions[index];
                        return _TransactionCard(
                          transaction: tx,
                          onTap: () => _showTransactionDetails(context, tx),
                        );
                      }, childCount: filteredTransactions.length),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final tx = filteredTransactions[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TransactionCard(
                            transaction: tx,
                            onTap: () => _showTransactionDetails(context, tx),
                          ),
                        );
                      }, childCount: filteredTransactions.length),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, SaleTransaction tx) async {
    final txProvider = context.read<TransactionProvider>();
    final initialItems = tx.items.isNotEmpty
        ? tx.items
        : await txProvider.getTransactionItems(tx.id!);
    if (!context.mounted) return;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Consumer<TransactionProvider>(
        builder: (consumerCtx, provider, _) {
          // Reactively fetch the latest transaction from provider
          final currentTx = provider.transactions.firstWhere(
            (t) => t.id == tx.id,
            orElse: () => tx,
          );
          final items = currentTx.items.isNotEmpty
              ? currentTx.items
              : initialItems;
          final customerName = currentTx.customerName;
          final isPending =
              currentTx.paymentMethod.toLowerCase() == 'pending' ||
              currentTx.paymentMethod.toLowerCase() == 'debt';
          final remainingBalance = (currentTx.totalAmount - currentTx.cashReceived).clamp(
            0.0,
            currentTx.totalAmount,
          );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Order #${currentTx.id}',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _PaymentBadge(method: currentTx.paymentMethod),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat(
                                    'EEE, MMM d, yyyy • h:mm a',
                                  ).format(currentTx.date),
                                  style: TextStyle(
                                    color: AppTheme.mutedText(sheetCtx),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (customerName != null &&
                                    customerName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline_rounded,
                                        size: 14,
                                        color: AppTheme.accentOrange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Customer: $customerName',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ITEMS PURCHASED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: AppTheme.mutedText(sheetCtx),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(sheetCtx),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: AppTheme.borderColor(sheetCtx),
                                ),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: AppTheme.borderColor(sheetCtx),
                                ),
                                itemBuilder: (ctx, index) {
                                  final item = items[index];
                                  final netQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                                  final originalQty = (item['original_quantity'] as num?)?.toDouble() ?? netQty;
                                  final returnedQty = (item['returned_quantity'] as num?)?.toDouble() ?? 0.0;
                                  final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
                                  final isFullyReturned = netQty <= 0 && returnedQty > 0;
                                  final isPartiallyReturned = returnedQty > 0 && netQty > 0;

                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      10,
                                      6,
                                      10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isFullyReturned
                                                ? AppTheme.accentRose.withValues(alpha: 0.12)
                                                : AppTheme.accentOrange.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isFullyReturned ? '0×' : '${formatQuantity(netQty)}×',
                                            style: TextStyle(
                                              color: isFullyReturned
                                                  ? AppTheme.accentRose
                                                  : AppTheme.accentOrange,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                              fontFeatures: AppTheme.tabularFigures,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                item['product_name'] ?? 'Unknown Item',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  decoration: isFullyReturned ? TextDecoration.lineThrough : null,
                                                  color: isFullyReturned ? AppTheme.mutedText(sheetCtx) : null,
                                                ),
                                              ),
                                              if (isFullyReturned)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    'RETURNED (${formatQuantity(returnedQty)})',
                                                    style: const TextStyle(
                                                      color: AppTheme.accentRose,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                )
                                              else if (isPartiallyReturned)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    '${formatQuantity(returnedQty)} of ${formatQuantity(originalQty)} returned',
                                                    style: TextStyle(
                                                      color: AppTheme.mutedText(sheetCtx),
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₱${subtotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: isFullyReturned ? AppTheme.mutedText(sheetCtx) : null,
                                            fontFeatures: AppTheme.tabularFigures,
                                          ),
                                        ),
                                        if (!isFullyReturned)
                                          IconButton(
                                            onPressed: () =>
                                                _showReturnDialog(context, currentTx, item),
                                            icon: const Icon(
                                              Icons.assignment_return_outlined,
                                              size: 19,
                                              color: AppTheme.accentRose,
                                            ),
                                            tooltip: 'Return Item',
                                          )
                                        else
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 12),
                                            child: Icon(
                                              Icons.check_circle_outline_rounded,
                                              size: 18,
                                              color: AppTheme.accentRose,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Financial Breakdown
                            if (currentTx.discount > 0) ...[
                              _ReceiptRow(
                                label: 'Subtotal',
                                value:
                                    '₱${(currentTx.totalAmount + currentTx.discount).toStringAsFixed(2)}',
                              ),
                              const SizedBox(height: 8),
                              _ReceiptRow(
                                label: 'Discount',
                                value: '-₱${currentTx.discount.toStringAsFixed(2)}',
                                valueColor: AppTheme.accentTeal,
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (currentTx.paymentMethod == 'cash') ...[
                              _ReceiptRow(
                                label: 'Cash Received',
                                value: '₱${currentTx.cashReceived.toStringAsFixed(2)}',
                              ),
                              const SizedBox(height: 8),
                              _ReceiptRow(
                                label: 'Change Given',
                                value: '₱${currentTx.change.toStringAsFixed(2)}',
                                valueColor: AppTheme.accentTeal,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (isPending) ...[
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentAmber.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.accentAmber.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.pending_actions_rounded,
                                      color: AppTheme.accentAmber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Pending Balance Due',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: AppTheme.accentAmber,
                                            ),
                                          ),
                                          if (currentTx.cashReceived > 0)
                                            Text(
                                              'Deposit Paid: ₱${currentTx.cashReceived.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.mutedText(sheetCtx),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '₱${remainingBalance.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppTheme.accentAmber,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            const Divider(height: 16),
                            _ReceiptRow(
                              label: 'Total Amount',
                              value: '₱${currentTx.totalAmount.toStringAsFixed(2)}',
                              isTotal: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPending) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _showCollectPaymentDialog(
                                    context,
                                    tx: currentTx,
                                    remainingBalance: remainingBalance,
                                    customerName: customerName,
                                    parentSheetContext: sheetCtx,
                                  );
                                },
                                icon: const Icon(Icons.payments_rounded, size: 20),
                                label: Text(
                                  'Collect Payment (₱${remainingBalance.toStringAsFixed(2)})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusMd,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final auth = context.read<AuthProvider>();
                                    showReceiptDialog(
                                      context,
                                      transaction: currentTx,
                                      items: items,
                                      user: auth.currentUser,
                                      customerName: customerName,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.receipt_long_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Thermal Receipt'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(sheetCtx),
                                  child: const Text('Done'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCollectPaymentDialog(
    BuildContext context, {
    required SaleTransaction tx,
    required double remainingBalance,
    required String? customerName,
    required BuildContext parentSheetContext,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => _CollectPaymentSheet(
        tx: tx,
        remainingBalance: remainingBalance,
        customerName: customerName,
        onPaymentSuccess: () {
          Navigator.pop(modalCtx);
          Navigator.pop(parentSheetContext);
        },
      ),
    );
  }

  void _showReturnDialog(
    BuildContext context,
    SaleTransaction tx,
    Map<String, dynamic> item,
  ) async {
    final netQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    if (netQty <= 0) {
      AppToast.show(
        context,
        message: 'Item has already been fully returned.',
        isError: true,
      );
      return;
    }

    final reasonController = TextEditingController();
    final quantityController = TextEditingController(text: formatQuantity(netQty));
    final maxQty = netQty;
    final unitPrice = (item['unit_price'] as num?)?.toDouble() ??
        (maxQty > 0 ? ((item['subtotal'] as num).toDouble() / maxQty) : 0.0);
    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final inputQty = double.tryParse(quantityController.text) ?? 0.0;
          final validQty = inputQty.clamp(0.0, maxQty);
          final refundAmount = validQty * unitPrice;
          final newTotal = (tx.totalAmount - refundAmount).clamp(0.0, double.infinity);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRose.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assignment_return_outlined,
                    color: AppTheme.accentRose,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Return ${item['product_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Unit Price: ₱${unitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.mutedText(dialogCtx),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: 'Quantity to Return (Max: ${formatQuantity(maxQty)})',
                      hintText: 'Enter quantity',
                      suffixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Text(
                          'max: ${formatQuantity(maxQty)}',
                          style: TextStyle(
                            color: AppTheme.mutedText(dialogCtx),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) => setDialogState(() {
                      dialogError = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Real-time price & deduction breakdown
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleSurface(dialogCtx),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor(dialogCtx)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Refund / Deduction:',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedText(dialogCtx),
                              ),
                            ),
                            Text(
                              '-₱${refundAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentRose,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'New Order Total:',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedText(dialogCtx),
                              ),
                            ),
                            Text(
                              '₱${newTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentOrange,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Return',
                      hintText: 'e.g. Damaged, Expired, Wrong item',
                    ),
                    maxLines: 2,
                    onChanged: (val) {
                      if (dialogError != null) {
                        setDialogState(() {
                          dialogError = null;
                        });
                      }
                    },
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentRose.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.accentRose, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dialogError!,
                              style: const TextStyle(
                                color: AppTheme.accentRose,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final qty = double.tryParse(quantityController.text) ?? 0.0;
                  if (qty <= 0 || qty > (maxQty + 0.0001)) {
                    setDialogState(() {
                      dialogError = 'Invalid quantity (0.01 - ${formatQuantity(maxQty)} allowed)';
                    });
                    return;
                  }
                  if (reasonController.text.trim().isEmpty) {
                    setDialogState(() {
                      dialogError = 'Please provide a reason for return';
                    });
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentRose,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 44),
                ),
                child: const Text('Process Return'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      final qtyToReturn = double.parse(quantityController.text);
      final newStock = await context.read<TransactionProvider>().processReturn(
        transactionId: tx.id!,
        productId: item['product_id'],
        quantity: qtyToReturn,
        reason: reasonController.text.trim(),
      );

      if (newStock != null && context.mounted) {
        if (newStock >= 0) {
          context.read<ProductProvider>().applyStockLevels({item['product_id']: newStock});
        } else {
          context.read<ProductProvider>().fetchProducts(silent: true);
        }
        // Do NOT pop the order details modal! It updates in real-time.
        final refundAmount = qtyToReturn * unitPrice;
        final newTotal = (tx.totalAmount - refundAmount).clamp(0.0, double.infinity);
        AppToast.show(
          context,
          message: 'Returned ${formatQuantity(qtyToReturn)}× ${item['product_name']}. Total updated to ₱${newTotal.toStringAsFixed(2)}.',
        );
      } else if (context.mounted) {
        final err = context.read<TransactionProvider>().lastActionError ??
            'Failed to process return';
        AppToast.show(
          context,
          message: err,
          isError: true,
        );
      }
    }
  }

  void _showReturnsLog(BuildContext context) async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    final returns = await context.read<TransactionProvider>().fetchReturns();
    if (!context.mounted) return;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.borderColor(ctx)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(ctx),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentRose.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.assignment_return_rounded,
                          color: AppTheme.accentRose,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Return Log',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: returns.isEmpty
                      ? Center(
                          child: Text(
                            'No returns recorded yet.',
                            style: TextStyle(color: AppTheme.mutedText(ctx)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: returns.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final ret = returns[i];
                            final date = (DateTime.tryParse(ret['date']?.toString() ?? '') ?? DateTime.now()).toLocal();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(ctx),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: AppTheme.borderColor(ctx),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ret['product_name'] ?? 'Item',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Reason: ${ret['reason']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.mutedText(ctx),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat(
                                            'MMM d, yyyy • h:mm a',
                                          ).format(date),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.mutedText(ctx),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentRose.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Qty ${ret['quantity']}',
                                      style: const TextStyle(
                                        color: AppTheme.accentRose,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                    ),
                                  ),
                                ],
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
}

class _PaymentFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _PaymentFilterChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
      backgroundColor: theme.cardTheme.color,
      selectedColor: color.withValues(alpha: 0.15),
      side: BorderSide(
        color: isSelected ? color : AppTheme.borderColor(context),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isSelected ? color : AppTheme.mutedText(context),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String method;

  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final m = method.toLowerCase();
    final isGcash = m == 'gcash';
    final isPending = m == 'pending' || m == 'debt';
    final color = isPending
        ? AppTheme.accentAmber
        : (isGcash ? AppTheme.accentIndigo : AppTheme.accentTeal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: isPending
            ? Border.all(
                color: AppTheme.accentAmber.withValues(alpha: 0.35),
                width: 1,
              )
            : null,
      ),
      child: Text(
        isPending ? 'PENDING' : method.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? onSurface : AppTheme.mutedText(context),
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            fontSize: isTotal ? 16 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? (isTotal ? AppTheme.accentOrange : onSurface),
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            fontSize: isTotal ? 20 : 14,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final SaleTransaction transaction;
  final VoidCallback onTap;

  const _TransactionCard({required this.transaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = transaction.paymentMethod.toLowerCase();
    final isGcash = m == 'gcash';
    final isPending = m == 'pending' || m == 'debt';
    final methodColor = isPending
        ? AppTheme.accentAmber
        : (isGcash ? AppTheme.accentIndigo : AppTheme.accentTeal);

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
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPending
                        ? Icons.pending_actions_rounded
                        : (isGcash
                              ? Icons.account_balance_wallet_rounded
                              : Icons.payments_rounded),
                    color: methodColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Order #${transaction.id}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (transaction.discount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accentAmber.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'DISC',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accentAmber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat(
                          'MMM d, yyyy • h:mm a',
                        ).format(transaction.date),
                        style: TextStyle(
                          color: AppTheme.mutedText(context),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${transaction.totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _PaymentBadge(method: transaction.paymentMethod),
                  ],
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.mutedText(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectPaymentSheet extends StatefulWidget {
  final SaleTransaction tx;
  final double remainingBalance;
  final String? customerName;
  final VoidCallback onPaymentSuccess;

  const _CollectPaymentSheet({
    required this.tx,
    required this.remainingBalance,
    required this.customerName,
    required this.onPaymentSuccess,
  });

  @override
  State<_CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends State<_CollectPaymentSheet> {
  String _selectedMethod = 'cash'; // 'cash' or 'gcash'
  late final TextEditingController _cashController;
  double _cashTendered = 0.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController();
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  void _setExact() {
    setState(() {
      _cashTendered = widget.remainingBalance;
      _cashController.text = widget.remainingBalance.toStringAsFixed(2);
    });
  }

  void _setDenomination(double amount) {
    setState(() {
      _cashTendered = amount;
      _cashController.text = amount.toStringAsFixed(0);
    });
  }

  List<double> get _quickDenominations {
    final baseList = [50.0, 100.0, 200.0, 500.0, 1000.0];
    final valid = baseList.where((d) => d > widget.remainingBalance).toList();
    if (valid.isEmpty) {
      final nextRound = ((widget.remainingBalance / 500).ceil() * 500)
          .toDouble();
      if (nextRound > widget.remainingBalance) {
        valid.add(nextRound);
      }
      valid.add(nextRound + 500);
    }
    return valid;
  }

  Future<void> _submitPayment() async {
    if (_isSubmitting) return;

    if (_selectedMethod == 'cash' && _cashTendered <= 0) {
      AppToast.show(
        context,
        message: 'Please enter an amount to pay or deposit.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final paymentAmount = _selectedMethod == 'cash'
        ? _cashTendered
        : widget.remainingBalance;

    final isFullyPaid = paymentAmount >= widget.remainingBalance;
    final change =
        (_selectedMethod == 'cash' && paymentAmount > widget.remainingBalance)
        ? (paymentAmount - widget.remainingBalance)
        : 0.0;

    final totalCashReceived = isFullyPaid
        ? widget.tx.totalAmount
        : (widget.tx.cashReceived + paymentAmount);

    final newPaymentMethod = isFullyPaid ? _selectedMethod : 'pending';

    final success = await context
        .read<TransactionProvider>()
        .markTransactionPaid(
          transactionId: widget.tx.id!,
          newPaymentMethod: newPaymentMethod,
          cashReceived: totalCashReceived,
          changeAmount: change,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      widget.onPaymentSuccess();
      AppToast.show(
        context,
        message: isFullyPaid
            ? 'Order #${widget.tx.id} marked as Paid (${_selectedMethod.toUpperCase()})'
            : 'Downpayment of ₱${paymentAmount.toStringAsFixed(2)} recorded for Order #${widget.tx.id}',
      );
    } else {
      AppToast.show(
        context,
        message: 'Failed to update transaction. Please try again.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCash = _selectedMethod == 'cash';
    final changeDue = (_cashTendered - widget.remainingBalance).clamp(
      0.0,
      double.infinity,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.borderColor(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collect Payment',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Order #${widget.tx.id}${widget.customerName != null && widget.customerName!.isNotEmpty ? ' • ${widget.customerName}' : ''}',
                              style: TextStyle(
                                color: AppTheme.mutedText(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Unpaid Balance Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UNPAID BALANCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: AppTheme.mutedText(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₱${widget.remainingBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.accentOrange,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentAmber.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'PENDING',
                              style: TextStyle(
                                color: AppTheme.accentAmber,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Payment Method Choice
                    Text(
                      'RECEIVE PAYMENT VIA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTheme.mutedText(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MethodChoiceCard(
                            label: 'Cash',
                            icon: Icons.payments_rounded,
                            isSelected: isCash,
                            onTap: () =>
                                setState(() => _selectedMethod = 'cash'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MethodChoiceCard(
                            label: 'GCash',
                            icon: Icons.account_balance_wallet_rounded,
                            isSelected: !isCash,
                            onTap: () =>
                                setState(() => _selectedMethod = 'gcash'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Cash Controls
                    if (isCash) ...[
                      Text(
                        'CASH TENDERED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppTheme.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cashController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              '₱',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                          hintText: '0.00 (Enter full or partial amount)',
                        ),
                        onChanged: (val) {
                          setState(() {
                            _cashTendered = double.tryParse(val) ?? 0.0;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Quick Cash Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              label: Text(
                                'Exact ₱${widget.remainingBalance.toStringAsFixed(2)}',
                              ),
                              onPressed: _setExact,
                              backgroundColor: AppTheme.subtleSurface(context),
                            ),
                            const SizedBox(width: 8),
                            ..._quickDenominations.map(
                              (denom) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text('₱${denom.toStringAsFixed(0)}'),
                                  onPressed: () => _setDenomination(denom),
                                  backgroundColor: AppTheme.subtleSurface(
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Partial Downpayment Balance or Change Due Banner
                      if (_cashTendered > 0 &&
                          _cashTendered < widget.remainingBalance) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentAmber.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Remaining Balance After Deposit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accentAmber,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Order stays pending until fully paid',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '₱${(widget.remainingBalance - _cashTendered).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: AppTheme.accentAmber,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Change Due',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentTeal,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '₱${changeDue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: AppTheme.accentTeal,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      // GCash Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accentIndigo.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.accentIndigo.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.qr_code_2_rounded,
                                color: AppTheme.accentIndigo,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GCash Mobile Payment',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Collect exact ₱${widget.remainingBalance.toStringAsFixed(2)} from customer via QR or Express Send.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Confirm Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitPayment,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                (_selectedMethod == 'cash' &&
                                        _cashTendered > 0 &&
                                        _cashTendered < widget.remainingBalance)
                                    ? Icons.payments_outlined
                                    : Icons.check_circle_rounded,
                                size: 20,
                              ),
                        label: Text(
                          _isSubmitting
                              ? 'Saving Payment...'
                              : ((_selectedMethod == 'cash' &&
                                        _cashTendered > 0 &&
                                        _cashTendered < widget.remainingBalance)
                                    ? 'Save Downpayment (₱${_cashTendered.toStringAsFixed(2)})'
                                    : 'Confirm & Mark as Paid'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (_selectedMethod == 'cash' &&
                                  _cashTendered > 0 &&
                                  _cashTendered < widget.remainingBalance)
                              ? AppTheme.accentAmber
                              : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
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

class _MethodChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MethodChoiceCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.accentOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.1)
              : AppTheme.subtleSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.borderColor(context),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : AppTheme.mutedText(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
                color: isSelected
                    ? activeColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
