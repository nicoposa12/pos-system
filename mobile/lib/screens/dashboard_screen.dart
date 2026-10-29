import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/product_image_view.dart';
import '../widgets/skeleton.dart';
import 'add_edit_product_screen.dart';
import 'product_list_screen.dart';
import 'settings_screen.dart';
import 'transaction_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenPos;
  final void Function(TransactionFilter filter)? onOpenHistory;
  final void Function(StockFilter filter)? onOpenInventory;

  const DashboardScreen({
    super.key,
    this.onOpenPos,
    this.onOpenHistory,
    this.onOpenInventory,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final PageController _pageController;
  int _currentInsightPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    Future.microtask(() {
      if (!mounted) return;
      context.read<ProductProvider>().fetchProducts();
      context.read<TransactionProvider>().fetchTransactions();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _navigateToHistory(BuildContext context, TransactionFilter filter) {
    HapticFeedback.selectionClick();
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!(filter);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionHistoryScreen(initialFilter: filter),
        ),
      );
    }
  }

  void _navigateToInventory(BuildContext context, StockFilter filter) {
    HapticFeedback.selectionClick();
    if (widget.onOpenInventory != null) {
      widget.onOpenInventory!(filter);
    } else {
      final notifier = ValueNotifier<StockFilter?>(filter);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductListScreen(filterRequest: notifier),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final txProvider = context.watch<TransactionProvider>();
    final productProvider = context.watch<ProductProvider>();
    final user = auth.currentUser;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideHero = screenWidth >= 880;
    final isWideAnalytics = screenWidth >= 920;

    final firstName = (user?.fullName.trim().isNotEmpty == true)
        ? user!.fullName.trim().split(' ').first
        : 'Store Owner';

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.accentOrange,
        onRefresh: () async {
          final prodProv = context.read<ProductProvider>();
          final transProv = context.read<TransactionProvider>();
          await Future.wait([
            prodProv.fetchProducts(),
            transProv.fetchTransactions(),
          ]);
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Executive Top Bar ──
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 72,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  titleSpacing: 20,
                  title: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: settings.businessPhotoPath.isNotEmpty &&
                                    File(settings.businessPhotoPath).existsSync()
                                ? FileImage(File(settings.businessPhotoPath))
                                : const AssetImage('assets/images/app_icon.png')
                                    as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                          border: Border.all(
                            color: AppTheme.borderColor(context),
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
                              settings.storeName.trim().isNotEmpty
                                  ? settings.storeName
                                  : 'TindaKo POS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentOrange,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_greeting()}, $firstName',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    if (user?.pin != null)
                      IconButton(
                        icon: const Icon(Icons.lock_outline_rounded, size: 22),
                        tooltip: 'Lock Terminal',
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          context.read<AuthProvider>().lock();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, size: 22),
                      tooltip: 'Settings',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 22),
                      tooltip: 'Sign Out',
                      onPressed: () => _showLogoutDialog(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),

                // ── Main Content ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 1. Revenue Hero & Period Breakdown ──
                            if (txProvider.isLoading)
                              const Column(
                                children: [
                                  Skeleton(height: 176, borderRadius: 20),
                                  SizedBox(height: 12),
                                  Skeleton(height: 86, borderRadius: 16),
                                ],
                              )
                            else if (isWideHero)
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _HeroRevenueCard(
                                        dailyTotal: txProvider.dailyTotal,
                                        dailyOrders:
                                            txProvider.dailyTransactionCount,
                                        onNewSale: widget.onOpenPos,
                                        onTapCard: () => _navigateToHistory(
                                          context,
                                          TransactionFilter.daily,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: _PeriodMetricTile(
                                                    label: 'Last 7 Days',
                                                    amount:
                                                        txProvider.weeklyTotal,
                                                    icon: Icons
                                                        .date_range_rounded,
                                                    accent:
                                                        AppTheme.accentOrange,
                                                    onTap: () =>
                                                        _navigateToHistory(
                                                          context,
                                                          TransactionFilter
                                                              .weekly,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: _PeriodMetricTile(
                                                    label: 'This Month',
                                                    amount:
                                                        txProvider.monthlyTotal,
                                                    icon: Icons
                                                        .calendar_month_rounded,
                                                    accent:
                                                        AppTheme.accentIndigo,
                                                    onTap: () =>
                                                        _navigateToHistory(
                                                          context,
                                                          TransactionFilter
                                                              .monthly,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: _PeriodMetricTile(
                                              label:
                                                  'Year ${DateTime.now().year}',
                                              amount: txProvider.yearlyTotal,
                                              icon: Icons.insights_rounded,
                                              accent: AppTheme.accentTeal,
                                              isHorizontal: true,
                                              onTap: () => _navigateToHistory(
                                                context,
                                                TransactionFilter.yearly,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              _HeroRevenueCard(
                                dailyTotal: txProvider.dailyTotal,
                                dailyOrders: txProvider.dailyTransactionCount,
                                onNewSale: widget.onOpenPos,
                                onTapCard: () => _navigateToHistory(
                                  context,
                                  TransactionFilter.daily,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PeriodMetricTile(
                                      label: '7 Days',
                                      amount: txProvider.weeklyTotal,
                                      icon: Icons.date_range_rounded,
                                      accent: AppTheme.accentOrange,
                                      onTap: () => _navigateToHistory(
                                        context,
                                        TransactionFilter.weekly,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _PeriodMetricTile(
                                      label: 'Month',
                                      amount: txProvider.monthlyTotal,
                                      icon: Icons.calendar_month_rounded,
                                      accent: AppTheme.accentIndigo,
                                      onTap: () => _navigateToHistory(
                                        context,
                                        TransactionFilter.monthly,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _PeriodMetricTile(
                                      label: 'Year',
                                      amount: txProvider.yearlyTotal,
                                      icon: Icons.insights_rounded,
                                      accent: AppTheme.accentTeal,
                                      onTap: () => _navigateToHistory(
                                        context,
                                        TransactionFilter.yearly,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 24),

                            // ── 2. Store Operations Strip ──
                            _SectionHeader(
                              title: 'Store Operations',
                              trailingLabel: 'Sales History',
                              onTrailingTap: () => _navigateToHistory(
                                context,
                                TransactionFilter.all,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: productProvider.isLoading
                                      ? const Skeleton(
                                          height: 78,
                                          borderRadius: 16,
                                        )
                                      : _OperationalStatCard(
                                          label: 'Catalog SKUs',
                                          value:
                                              '${productProvider.allProducts.length}',
                                          icon: Icons.inventory_2_outlined,
                                          color: AppTheme.accentTeal,
                                          onTap: () => _navigateToInventory(
                                            context,
                                            StockFilter.all,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: productProvider.isLoading
                                      ? const Skeleton(
                                          height: 78,
                                          borderRadius: 16,
                                        )
                                      : _OperationalStatCard(
                                          label: 'Restock Alert',
                                          value:
                                              '${productProvider.lowStockProducts.length}',
                                          icon: Icons.warning_amber_rounded,
                                          color: productProvider
                                                  .lowStockProducts
                                                  .isEmpty
                                              ? AppTheme.accentTeal
                                              : AppTheme.accentRose,
                                          onTap: () => _navigateToInventory(
                                            context,
                                            StockFilter.lowStock,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: txProvider.isLoading
                                      ? const Skeleton(
                                          height: 78,
                                          borderRadius: 16,
                                        )
                                      : _OperationalStatCard(
                                          label: 'Orders Today',
                                          value:
                                              '${txProvider.dailyTransactionCount}',
                                          icon: Icons.receipt_long_outlined,
                                          color: AppTheme.accentIndigo,
                                          onTap: () => _navigateToHistory(
                                            context,
                                            TransactionFilter.daily,
                                          ),
                                        ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // ── 3. Analytics & Inventory Alerts ──
                            if (isWideAnalytics)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: _buildInsightsSection(
                                      context,
                                      txProvider,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 5,
                                    child: _buildLowStockSection(
                                      context,
                                      theme,
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              _buildInsightsSection(context, txProvider),
                              const SizedBox(height: 24),
                              _buildLowStockSection(context, theme),
                            ],
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsSection(
    BuildContext context,
    TransactionProvider txProvider,
  ) {
    final theme = Theme.of(context);
    const tabs = ['7-Day Trend', 'Best Sellers', 'Categories'];

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Business Insights',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(
                Icons.bar_chart_rounded,
                size: 20,
                color: AppTheme.mutedText(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Segmented Tab Switcher
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: List.generate(tabs.length, (index) {
                final isSelected = _currentInsightPage == index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.cardTheme.color
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: isSelected
                            ? AppTheme.cardShadow(context)
                            : const [],
                      ),
                      child: Text(
                        tabs[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.accentOrange
                              : AppTheme.mutedText(context),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 224,
            child: txProvider.isLoading
                ? const Skeleton(borderRadius: 12)
                : PageView(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentInsightPage = index),
                    children: const [
                      _WeeklySalesChart(),
                      _TopProductsChart(),
                      _CategorySalesChart(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockSection(BuildContext context, ThemeData theme) {
    final lowStock = context.watch<ProductProvider>().lowStockProducts;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Inventory Health',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (lowStock.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        _navigateToInventory(context, StockFilter.lowStock),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('View All'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (lowStock.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: AppTheme.accentTeal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All products well stocked',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No items are at or below the 5-unit alert threshold.',
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
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lowStock.length > 5 ? 5 : lowStock.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppTheme.borderColor(context)),
              itemBuilder: (context, index) {
                final product = lowStock[index];
                final isOut = product.stock <= 0;
                final badgeColor =
                    isOut ? AppTheme.accentRose : AppTheme.accentAmber;
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddEditProductScreen(product: product),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppTheme.subtleSurface(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ProductImageView(
                            imagePath: product.imagePath,
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
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Tap to restock',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.mutedText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isOut ? 'Out of stock' : '${product.stock} left',
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Sign Out?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Are you sure you want to sign out of TindaKo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
              minimumSize: const Size(100, 44),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  const _SectionHeader({
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailingLabel != null && onTrailingTap != null)
          TextButton.icon(
            onPressed: onTrailingTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(trailingLabel!),
          ),
      ],
    );
  }
}

class _HeroRevenueCard extends StatelessWidget {
  final double dailyTotal;
  final int dailyOrders;
  final VoidCallback? onNewSale;
  final VoidCallback onTapCard;

  const _HeroRevenueCard({
    required this.dailyTotal,
    required this.dailyOrders,
    this.onNewSale,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    final avgTicket = dailyOrders > 0 ? dailyTotal / dailyOrders : 0.0;
    final todayStr = DateFormat('EEE, MMM d').format(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.heroDarkGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentOrange.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTapCard,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentTeal,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "TODAY'S SALES",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            todayStr,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '₱${NumberFormat('#,##0.00').format(dailyTotal)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              _HeroStatPill(
                                label: 'Orders',
                                value: '$dailyOrders',
                              ),
                              _HeroStatPill(
                                label: 'Avg',
                                value: '₱${avgTicket.toStringAsFixed(0)}',
                              ),
                            ],
                          ),
                        ),
                        if (onNewSale != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              onNewSale!();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentOrange,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.point_of_sale_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Open POS',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  final String label;
  final String value;

  const _HeroStatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _PeriodMetricTile extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color accent;
  final bool isHorizontal;
  final VoidCallback onTap;

  const _PeriodMetricTile({
    required this.label,
    required this.amount,
    required this.icon,
    required this.accent,
    this.isHorizontal = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = amount >= 100000
        ? '₱${(amount / 1000).toStringAsFixed(1)}k'
        : '₱${NumberFormat('#,##0').format(amount)}';

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
            padding: const EdgeInsets.all(14),
            child: isHorizontal
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mutedText(context),
                          ),
                        ),
                      ),
                      Text(
                        formatted,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.mutedText(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(icon, size: 15, color: accent),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatted,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
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

class _OperationalStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OperationalStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.mutedText(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklySalesChart extends StatelessWidget {
  const _WeeklySalesChart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<TransactionProvider>();
    final weeklyData = provider.getWeeklySalesData();
    final sortedKeys = weeklyData.keys.toList();

    double maxVal = weeklyData.values.fold(0.0, (m, v) => v > m ? v : m);
    if (maxVal == 0) maxVal = 1000;
    final totalWeekly = weeklyData.values.fold(0.0, (sum, v) => sum + v);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.32,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppTheme.primaryDark,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final val = rod.toY;
                final percent = totalWeekly > 0 ? (val / totalWeekly * 100) : 0.0;
                return BarTooltipItem(
                  '₱${val.toStringAsFixed(2)}\n${percent.toStringAsFixed(1)}% of week',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < sortedKeys.length) {
                    final val = weeklyData[sortedKeys[idx]] ?? 0.0;
                    if (val <= 0) return const SizedBox.shrink();
                    final isToday = idx == sortedKeys.length - 1;
                    return Text(
                      val >= 1000
                          ? '₱${(val / 1000).toStringAsFixed(1)}k'
                          : '₱${val.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? AppTheme.accentOrange
                            : AppTheme.mutedText(context),
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < sortedKeys.length) {
                    DateTime date;
                    try {
                      date = DateTime.parse(sortedKeys[idx]);
                    } catch (_) {
                      date = DateTime.now();
                    }
                    final isToday = idx == sortedKeys.length - 1;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        isToday ? 'Today' : DateFormat('E').format(date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isToday ? FontWeight.w800 : FontWeight.w500,
                          color: isToday
                              ? AppTheme.accentOrange
                              : AppTheme.mutedText(context),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxVal / 3 > 0 ? maxVal / 3 : 250,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.1),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(sortedKeys.length, (i) {
            final val = weeklyData[sortedKeys[i]]!;
            final isToday = i == sortedKeys.length - 1;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  gradient: isToday
                      ? AppTheme.orangeGradient
                      : AppTheme.tealGradient,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxVal * 1.32,
                    color: AppTheme.subtleSurface(context),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _TopProductsChart extends StatelessWidget {
  const _TopProductsChart();

  @override
  Widget build(BuildContext context) {
    final topProducts = context.watch<TransactionProvider>().topProducts;

    if (topProducts.isEmpty) {
      return Center(
        child: Text(
          'Complete sales to see top-selling products',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.mutedText(context),
          ),
        ),
      );
    }

    double maxRevenue = topProducts.fold(0.0, (m, p) {
      final r = (p['total_revenue'] as num?)?.toDouble() ?? 0.0;
      return r > m ? r : m;
    });
    if (maxRevenue <= 0) maxRevenue = 1;

    final display = topProducts.take(4).toList();

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: display.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = display[index];
        final name = (item['name'] ?? 'Item').toString();
        final sold = (item['total_sold'] as num?)?.toInt() ?? 0;
        final revenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
        final ratio = (revenue / maxRevenue).clamp(0.05, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? AppTheme.accentOrange.withValues(alpha: 0.15)
                        : AppTheme.subtleSurface(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: index == 0
                          ? AppTheme.accentOrange
                          : AppTheme.mutedText(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$sold sold',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedText(context),
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '₱${revenue.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentOrange,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppTheme.subtleSurface(context),
                color: index == 0
                    ? AppTheme.accentOrange
                    : AppTheme.accentTeal,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategorySalesChart extends StatelessWidget {
  const _CategorySalesChart();

  @override
  Widget build(BuildContext context) {
    final categorySales = context.watch<TransactionProvider>().categorySales;

    if (categorySales.isEmpty) {
      return Center(
        child: Text(
          'Categorize products to view revenue mix',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.mutedText(context),
          ),
        ),
      );
    }

    final totalCategoryRevenue = categorySales.fold<double>(
      0.0,
      (sum, item) => sum + ((item['total_revenue'] as num?)?.toDouble() ?? 0.0),
    );

    const colors = [
      AppTheme.accentOrange,
      AppTheme.accentTeal,
      AppTheme.accentIndigo,
      AppTheme.accentAmber,
      AppTheme.accentRose,
    ];

    final displayItems = categorySales.length > 5 ? 5 : categorySales.length;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 34,
                  sections: List.generate(displayItems, (i) {
                    final data = categorySales[i];
                    final revenue =
                        (data['total_revenue'] as num?)?.toDouble() ?? 0.0;
                    return PieChartSectionData(
                      color: colors[i % colors.length],
                      value: revenue,
                      title: '',
                      radius: 26,
                    );
                  }),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.mutedText(context),
                    ),
                  ),
                  Text(
                    totalCategoryRevenue >= 1000
                        ? '₱${(totalCategoryRevenue / 1000).toStringAsFixed(1)}k'
                        : '₱${totalCategoryRevenue.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(displayItems, (i) {
              final data = categorySales[i];
              final revenue =
                  (data['total_revenue'] as num?)?.toDouble() ?? 0.0;
              final percent = totalCategoryRevenue > 0
                  ? (revenue / totalCategoryRevenue * 100)
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: colors[i % colors.length],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['category'] ?? 'Uncategorized',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mutedText(context),
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
