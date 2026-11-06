import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/user.dart';
import '../providers/admin_store_controller.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import 'client_management_screen.dart';

/// Dedicated Executive Command Center workspace for Platform Administrators.
/// Replaces the cashier POS shell whenever an `admin` account is authenticated.
class AdminNavigationScreen extends StatefulWidget {
  final AdminStoreController? controller;

  const AdminNavigationScreen({super.key, this.controller});

  @override
  State<AdminNavigationScreen> createState() => _AdminNavigationScreenState();
}

class _AdminNavigationScreenState extends State<AdminNavigationScreen> {
  int _selectedIndex = 0;
  AdminStoreController? _ownedController;
  final ValueNotifier<String?> _storeFilterNotifier = ValueNotifier<String?>(null);

  AdminStoreController get _ctrl => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = AdminStoreController();
    }
  }

  @override
  void didUpdateWidget(covariant AdminNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller != null && _ownedController != null) {
        _ownedController!.dispose();
        _ownedController = null;
      } else if (widget.controller == null && _ownedController == null) {
        _ownedController = AdminStoreController();
      }
    }
  }

  @override
  void dispose() {
    _storeFilterNotifier.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  void _selectTab(int index, {String? storeFilter}) {
    HapticFeedback.selectionClick();
    if (storeFilter != null) {
      _storeFilterNotifier.value = storeFilter;
    }
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  Widget _storesBadgeIcon(Widget icon, int storesCount) {
    if (storesCount <= 0) return icon;
    return Badge(
      backgroundColor: AppTheme.accentViolet,
      textColor: Colors.white,
      label: Text(
        storesCount > 99 ? '99+' : '$storesCount',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
      child: icon,
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out of Admin Console?'),
        content: const Text(
          'You will be returned to the sign-in screen on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 700;
    final extendedRail = width >= 1120;
    final auth = context.watch<AuthProvider>();
    final adminUser = auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = <Widget>[
      _AdminCommandOverview(
        controller: _ctrl,
        onOpenStores: ({String? filter}) => _selectTab(1, storeFilter: filter),
      ),
      ClientManagementScreen(
        controller: _ctrl,
        embedded: true,
        filterRequest: _storeFilterNotifier,
      ),
      _AdminConsoleSettingsView(
        controller: _ctrl,
        onSignOut: () => _confirmSignOut(context),
      ),
    ];

    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final storesCount = _ctrl.totalStoresCount;

        if (useRail) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRailTheme(
                    data: NavigationRailTheme.of(context).copyWith(
                      indicatorColor: AppTheme.accentViolet.withValues(
                        alpha: isDark ? 0.22 : 0.14,
                      ),
                      selectedIconTheme: const IconThemeData(
                        color: AppTheme.accentViolet,
                        size: 24,
                      ),
                      selectedLabelTextStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentViolet,
                      ),
                    ),
                    child: NavigationRail(
                      extended: extendedRail,
                      minWidth: 82,
                      minExtendedWidth: 240,
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectTab,
                      labelType: extendedRail
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      leading: Padding(
                        padding: EdgeInsets.fromLTRB(
                          extendedRail ? 16 : 0,
                          14,
                          extendedRail ? 16 : 0,
                          18,
                        ),
                        child: extendedRail
                            ? SizedBox(
                                width: 208,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentViolet.withValues(
                                              alpha: isDark ? 0.22 : 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: AppTheme.accentViolet.withValues(
                                                alpha: isDark ? 0.35 : 0.20,
                                              ),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.hub_rounded,
                                            color: AppTheme.accentViolet,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'TindaKo HQ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15.5,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                              Text(
                                                'Platform Admin Console',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.mutedText(context),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppTheme.cardDark : AppTheme.subtleLight,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppTheme.borderColor(context),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: _ctrl.isCloudSynced
                                                  ? const Color(0xFF059669)
                                                  : AppTheme.accentAmber,
                                              shape: BoxShape.circle,
                                              boxShadow: _ctrl.isCloudSynced
                                                  ? [
                                                      BoxShadow(
                                                        color: const Color(0xFF059669).withValues(alpha: 0.5),
                                                        blurRadius: 4,
                                                        spreadRadius: 1,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _ctrl.isCloudSynced
                                                  ? 'Neon Cloud Connected'
                                                  : 'Offline SQLite Cache',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: _ctrl.isCloudSynced
                                                    ? (isDark ? AppTheme.accentTeal : const Color(0xFF047857))
                                                    : AppTheme.accentAmber,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.violetGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.hub_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                      ),
                      trailing: Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: extendedRail
                                ? Container(
                                    width: 208,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.subtleSurface(context),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.borderColor(context),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 17,
                                          backgroundColor: AppTheme.accentViolet,
                                          child: Text(
                                            (adminUser?.fullName.isNotEmpty == true)
                                                ? adminUser!.fullName[0]
                                                    .toUpperCase()
                                                : 'A',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                adminUser?.fullName ??
                                                    'Administrator',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '@${adminUser?.username ?? 'admin'}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.mutedText(context),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Sign Out',
                                          icon: const Icon(
                                            Icons.logout_rounded,
                                            size: 18,
                                            color: AppTheme.accentRose,
                                          ),
                                          onPressed: () => _confirmSignOut(context),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (adminUser?.pin != null)
                                        IconButton(
                                          tooltip: 'Lock Console',
                                          icon: const Icon(
                                            Icons.lock_outline_rounded,
                                          ),
                                          onPressed: () => auth.lock(),
                                        ),
                                      IconButton(
                                        tooltip: 'Sign Out',
                                        icon: const Icon(
                                          Icons.logout_rounded,
                                          color: AppTheme.accentRose,
                                        ),
                                        onPressed: () => _confirmSignOut(context),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      destinations: [
                        const NavigationRailDestination(
                          icon: Icon(Icons.space_dashboard_outlined),
                          selectedIcon: Icon(Icons.space_dashboard_rounded),
                          label: Text('Command'),
                        ),
                        NavigationRailDestination(
                          icon: _storesBadgeIcon(
                            const Icon(Icons.storefront_outlined),
                            storesCount,
                          ),
                          selectedIcon: _storesBadgeIcon(
                            const Icon(Icons.storefront_rounded),
                            storesCount,
                          ),
                          label: const Text('Stores'),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.admin_panel_settings_outlined),
                          selectedIcon: Icon(Icons.admin_panel_settings_rounded),
                          label: Text('Admin'),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppTheme.borderColor(context),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: screens,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _selectedIndex,
              children: screens,
            ),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.borderColor(context), width: 1),
              ),
            ),
            child: NavigationBarTheme(
              data: NavigationBarTheme.of(context).copyWith(
                indicatorColor: AppTheme.accentViolet.withValues(
                  alpha: isDark ? 0.22 : 0.14,
                ),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentViolet,
                    );
                  }
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText(context),
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const IconThemeData(
                      color: AppTheme.accentViolet,
                      size: 24,
                    );
                  }
                  return IconThemeData(
                    color: AppTheme.mutedText(context),
                    size: 24,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    selectedIcon: Icon(Icons.space_dashboard_rounded),
                    label: 'Command',
                  ),
                  NavigationDestination(
                    icon: _storesBadgeIcon(
                      const Icon(Icons.storefront_outlined),
                      storesCount,
                    ),
                    selectedIcon: _storesBadgeIcon(
                      const Icon(Icons.storefront_rounded),
                      storesCount,
                    ),
                    label: 'Stores',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings_rounded),
                    label: 'Admin',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// TAB 0: EXECUTIVE COMMAND OVERVIEW (Multi-Store Network Telemetry)
// ============================================================================

class _AdminCommandOverview extends StatelessWidget {
  final AdminStoreController controller;
  final void Function({String? filter}) onOpenStores;

  const _AdminCommandOverview({
    required this.controller,
    required this.onOpenStores,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final firstName = (user?.fullName.trim().isNotEmpty == true)
        ? user!.fullName.trim().split(' ').first
        : 'Admin';

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideHero = screenWidth >= 780;
    final isWideKpi = screenWidth >= 860;
    final isWideColumns = screenWidth >= 920;

    return RefreshIndicator(
      color: AppTheme.accentViolet,
      onRefresh: () => controller.refresh(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top Command Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth >= 700 ? 24 : 16,
                    16,
                    screenWidth >= 700 ? 24 : 16,
                    8,
                  ),
                  child: Row(
                    children: [
                      if (screenWidth < 700) ...[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: AppTheme.violetGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.hub_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${_greeting()}, $firstName',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentViolet
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'HQ ADMIN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accentViolet,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Managing ${controller.totalStoresCount} client ${controller.totalStoresCount == 1 ? 'business' : 'businesses'} across TindaKo Network',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.mutedText(context),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sync Network Telemetry',
                        onPressed: controller.isLoading
                            ? null
                            : () => controller.refresh(),
                        icon: const Icon(Icons.sync_rounded),
                      ),
                      if (screenWidth < 700 && user?.pin != null)
                        IconButton(
                          tooltip: 'Lock Console',
                          onPressed: () => auth.lock(),
                          icon: const Icon(Icons.lock_outline_rounded),
                        ),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  screenWidth >= 700 ? 24 : 16,
                  10,
                  screenWidth >= 700 ? 24 : 16,
                  40,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Executive Command Hero Card
                    _buildExecutiveHero(
                      context,
                      currency: currency,
                      isWideHero: isWideHero,
                    ),

                    const SizedBox(height: 18),

                    // 2. 4-Card Bento Network KPIs
                    if (isWideKpi)
                      Row(
                        children: [
                          Expanded(
                            child: _NetworkBentoCard(
                              label: 'Active Stores',
                              value: '${controller.activeStoresCount}',
                              subtitle: 'Live POS access',
                              icon: Icons.storefront_rounded,
                              accent: AppTheme.accentTeal,
                              onTap: () => onOpenStores(filter: 'active'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NetworkBentoCard(
                              label: 'Suspended',
                              value: '${controller.suspendedStoresCount}',
                              subtitle: 'Restricted stores',
                              icon: Icons.pause_circle_outline_rounded,
                              accent: AppTheme.accentRose,
                              onTap: () => onOpenStores(filter: 'suspended'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NetworkBentoCard(
                              label: 'Catalog Items',
                              value: '${controller.totalNetworkProducts}',
                              subtitle: 'Across all stores',
                              icon: Icons.inventory_2_rounded,
                              accent: AppTheme.accentViolet,
                              onTap: () => onOpenStores(filter: 'stores'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NetworkBentoCard(
                              label: 'Platform Admins',
                              value: '${controller.adminsCount}',
                              subtitle: 'Console operators',
                              icon: Icons.shield_outlined,
                              accent: AppTheme.accentIndigo,
                              onTap: () => onOpenStores(filter: 'admins'),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _NetworkBentoCard(
                                  label: 'Active Stores',
                                  value: '${controller.activeStoresCount}',
                                  subtitle: 'Live POS access',
                                  icon: Icons.storefront_rounded,
                                  accent: AppTheme.accentTeal,
                                  onTap: () => onOpenStores(filter: 'active'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _NetworkBentoCard(
                                  label: 'Suspended',
                                  value: '${controller.suspendedStoresCount}',
                                  subtitle: 'Restricted stores',
                                  icon: Icons.pause_circle_outline_rounded,
                                  accent: AppTheme.accentRose,
                                  onTap: () => onOpenStores(filter: 'suspended'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _NetworkBentoCard(
                                  label: 'Catalog Items',
                                  value: '${controller.totalNetworkProducts}',
                                  subtitle: 'Across all stores',
                                  icon: Icons.inventory_2_rounded,
                                  accent: AppTheme.accentViolet,
                                  onTap: () => onOpenStores(filter: 'stores'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _NetworkBentoCard(
                                  label: 'Platform Admins',
                                  value: '${controller.adminsCount}',
                                  subtitle: 'Console operators',
                                  icon: Icons.shield_outlined,
                                  accent: AppTheme.accentIndigo,
                                  onTap: () => onOpenStores(filter: 'admins'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                    const SizedBox(height: 24),

                    // 3. Leaderboard & Governance Split
                    if (isWideColumns)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildStoreLeaderboard(context, currency),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: _buildGovernancePanel(context),
                          ),
                        ],
                      )
                    else ...[
                      _buildStoreLeaderboard(context, currency),
                      const SizedBox(height: 20),
                      _buildGovernancePanel(context),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveHero(
    BuildContext context, {
    required NumberFormat currency,
    required bool isWideHero,
  }) {
    final totalStores = controller.totalStoresCount;
    final activeRatio = totalStores > 0
        ? (controller.activeStoresCount / totalStores).clamp(0.0, 1.0)
        : 1.0;

    final leftTelemetry = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: controller.isCloudSynced
                          ? AppTheme.accentTeal
                          : AppTheme.accentAmber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    controller.isCloudSynced
                        ? 'NEON POSTGRESQL LIVE'
                        : 'OFFLINE CACHE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'NETWORK GROSS SALES (ALL CLIENT STORES)',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          currency.format(controller.totalNetworkSales),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            fontFeatures: AppTheme.tabularFigures,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _HeroStatChip(
              icon: Icons.receipt_long_rounded,
              text: '${controller.totalNetworkOrders} network orders',
            ),
            _HeroStatChip(
              icon: Icons.assignment_late_outlined,
              text: '${controller.totalUnpaidDebts} open store debts',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Fleet Active Health Bar
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: activeRatio,
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.accentTeal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${controller.activeStoresCount}/$totalStores Active',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ],
        ),
      ],
    );

    final actionButtons = Column(
      crossAxisAlignment:
          isWideHero ? CrossAxisAlignment.end : CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accentViolet,
            foregroundColor: Colors.white,
            minimumSize: const Size(190, 50),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => ClientManagementScreen.showProvisionModal(
            context,
            controller: controller,
          ),
          icon: const Icon(Icons.add_business_rounded, size: 20),
          label: const Text(
            'Provision Store',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(190, 48),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => onOpenStores(filter: 'stores'),
          icon: const Icon(Icons.storefront_outlined, size: 19),
          label: const Text(
            'Manage All Stores',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.adminHeroGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentViolet.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isWideHero
          ? Row(
              children: [
                Expanded(child: leftTelemetry),
                const SizedBox(width: 24),
                actionButtons,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftTelemetry,
                const SizedBox(height: 20),
                actionButtons,
              ],
            ),
    );
  }

  Widget _buildStoreLeaderboard(BuildContext context, NumberFormat currency) {
    final topStores = controller.topPerformingStores.take(5).toList();
    final maxSales = topStores.isNotEmpty
        ? controller.metricsFor(topStores.first).totalSales
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.leaderboard_rounded,
                size: 20,
                color: AppTheme.accentViolet,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Client Store Leaderboard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => onOpenStores(filter: 'stores'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (topStores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.store_mall_directory_outlined,
                    size: 42,
                    color: AppTheme.mutedText(context),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No client stores registered yet',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Provision your first client business to track store sales and catalog activity here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.mutedText(context),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < topStores.length; i++) ...[
              if (i > 0)
                Divider(height: 18, color: AppTheme.borderColor(context)),
              _LeaderboardRow(
                rank: i + 1,
                user: topStores[i],
                metrics: controller.metricsFor(topStores[i]),
                maxSales: maxSales,
                currency: currency,
                onTap: () => ClientManagementScreen.showInspectorModal(
                  context,
                  user: topStores[i],
                  controller: controller,
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildGovernancePanel(BuildContext context) {
    final attentionStores = controller.storesNeedingAttention.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppTheme.accentIndigo,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Store Governance & Health',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ClientManagementScreen.showProvisionModal(
                  context,
                  controller: controller,
                  initialRole: 'admin',
                ),
                child: const Text('+ Admin'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (attentionStores.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentTeal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accentTeal.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.accentTeal,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.totalStoresCount == 0
                          ? 'Platform ready. Provision client stores to monitor PIN security and active status.'
                          : 'All client businesses are active, PIN-configured, and clear of unpaid debt alerts.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < attentionStores.length; i++) ...[
              if (i > 0)
                Divider(height: 14, color: AppTheme.borderColor(context)),
              _GovernanceAlertRow(
                user: attentionStores[i],
                metrics: controller.metricsFor(attentionStores[i]),
                onTap: () => ClientManagementScreen.showInspectorModal(
                  context,
                  user: attentionStores[i],
                  controller: controller,
                ),
              ),
            ],
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: ADMINISTRATOR & PLATFORM SETTINGS VIEW
// ============================================================================

class _AdminConsoleSettingsView extends StatefulWidget {
  final AdminStoreController controller;
  final VoidCallback onSignOut;

  const _AdminConsoleSettingsView({
    required this.controller,
    required this.onSignOut,
  });

  @override
  State<_AdminConsoleSettingsView> createState() =>
      _AdminConsoleSettingsViewState();
}

class _AdminConsoleSettingsViewState extends State<_AdminConsoleSettingsView> {
  bool _testingConnection = false;

  Future<void> _testCloudConnection() async {
    setState(() => _testingConnection = true);
    final reachable = await ApiService.instance.checkConnection();
    if (reachable) {
      await widget.controller.refresh(silent: true);
    }
    if (!mounted) return;
    setState(() => _testingConnection = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? 'Connected to Render & Neon Cloud (${ApiService.instance.baseUrl})'
              : 'Could not reach ${ApiService.instance.baseUrl}',
        ),
        backgroundColor: reachable ? AppTheme.accentTeal : AppTheme.accentRose,
      ),
    );
  }

  void _showConfigureApiDialog(BuildContext context) {
    final urlCtrl = TextEditingController(text: ApiService.instance.baseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud Backend API URL'),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(
            labelText: 'Laravel / Render Endpoint',
            hintText: 'https://pos-system-wdlx.onrender.com/api',
            prefixIcon: Icon(Icons.cloud_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
            ),
            onPressed: () async {
              final next = urlCtrl.text.trim();
              if (next.isNotEmpty) {
                await ApiService.instance.setBaseUrl(next);
                await widget.controller.refresh();
                if (mounted) setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save & Sync'),
          ),
        ],
      ),
    );
  }

  void _showUpdateAdminPinDialog(BuildContext context, AuthProvider auth) {
    final pinCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Admin Master PIN'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: 'New 4–6 Digit Admin PIN',
              hintText: 'e.g. 9999',
              prefixIcon: Icon(Icons.dialpad_rounded),
            ),
            validator: (v) {
              if (v == null || v.length < 4) return 'Enter 4–6 digits';
              if (v == '0000') return '0000 is reserved';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final ok = await auth.updatePin(pinCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Admin PIN updated.' : 'Failed to update PIN.',
                    ),
                    backgroundColor:
                        ok ? AppTheme.accentTeal : AppTheme.accentRose,
                  ),
                );
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  void _showChangeAdminPasswordDialog(BuildContext context, AuthProvider auth) {
    final currentCtrl = TextEditingController();
    final nextCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Admin Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nextCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password (min 4 chars)',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
                validator: (v) => (v == null || v.length < 4)
                    ? 'Minimum 4 characters'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final ok = await auth.changePassword(
                currentCtrl.text,
                nextCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Administrator password updated.'
                          : (auth.errorMessage ?? 'Password update failed.'),
                    ),
                    backgroundColor:
                        ok ? AppTheme.accentTeal : AppTheme.accentRose,
                  ),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final user = auth.currentUser;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: [
            const Text(
              'Platform & Admin Settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your administrator credentials, Neon Cloud connection, and console theme.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.mutedText(context),
              ),
            ),
            const SizedBox(height: 20),

            // Admin Identity Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.adminHeroGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppTheme.violetGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? 'System Administrator',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${user?.username ?? 'admin'}${user?.email != null ? ' • ${user!.email}' : ''}',
                          style: const TextStyle(
                            color: AppTheme.textSecondaryDark,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      color: AppTheme.accentViolet.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'SUPER ADMIN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _AdminSettingsLabel('SECURITY & CONSOLE LOCK'),
            const SizedBox(height: 8),
            _AdminSettingsGroup(
              children: [
                _AdminSettingsTile(
                  icon: Icons.dialpad_rounded,
                  iconColor: AppTheme.accentViolet,
                  title: 'Master Quick PIN',
                  subtitle: user?.pin != null
                      ? 'Active • Auto-locks console after 2 min idle'
                      : 'Configure 4–6 digit PIN for fast unlock',
                  onTap: () => _showUpdateAdminPinDialog(context, auth),
                ),
                Divider(height: 1, color: AppTheme.borderColor(context)),
                _AdminSettingsTile(
                  icon: Icons.key_rounded,
                  iconColor: AppTheme.accentAmber,
                  title: 'Change Admin Password',
                  subtitle: 'Update your administrator login password',
                  onTap: () => _showChangeAdminPasswordDialog(context, auth),
                ),
                if (user?.pin != null) ...[
                  Divider(height: 1, color: AppTheme.borderColor(context)),
                  _AdminSettingsTile(
                    icon: Icons.lock_outline_rounded,
                    iconColor: AppTheme.accentIndigo,
                    title: 'Lock Console Now',
                    subtitle: 'Require PIN before viewing store telemetry',
                    onTap: () => auth.lock(),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),
            _AdminSettingsLabel('CLOUD BACKEND & NEON DATABASE'),
            const SizedBox(height: 8),
            _AdminSettingsGroup(
              children: [
                _AdminSettingsTile(
                  icon: widget.controller.isCloudSynced
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  iconColor: widget.controller.isCloudSynced
                      ? AppTheme.accentTeal
                      : AppTheme.accentAmber,
                  title: 'Cloud API Endpoint',
                  subtitle: ApiService.instance.baseUrl,
                  onTap: () => _showConfigureApiDialog(context),
                ),
                Divider(height: 1, color: AppTheme.borderColor(context)),
                _AdminSettingsTile(
                  icon: Icons.network_check_rounded,
                  iconColor: AppTheme.accentIndigo,
                  title: _testingConnection
                      ? 'Pinging Cloud Server...'
                      : 'Test Render & Neon Connection',
                  subtitle: 'Verifies live backend health and refreshes stores',
                  onTap: _testingConnection ? null : _testCloudConnection,
                ),
              ],
            ),

            const SizedBox(height: 24),
            _AdminSettingsLabel('CONSOLE APPEARANCE'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                children: [
                  _ThemeSegment(
                    label: 'System',
                    icon: Icons.brightness_auto_rounded,
                    selected: settings.themeMode == ThemeMode.system,
                    onTap: () => settings.setThemeMode(ThemeMode.system),
                  ),
                  _ThemeSegment(
                    label: 'Light',
                    icon: Icons.light_mode_rounded,
                    selected: settings.themeMode == ThemeMode.light,
                    onTap: () => settings.setThemeMode(ThemeMode.light),
                  ),
                  _ThemeSegment(
                    label: 'Dark',
                    icon: Icons.dark_mode_rounded,
                    selected: settings.themeMode == ThemeMode.dark,
                    onTap: () => settings.setThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentRose,
                side: BorderSide(
                  color: AppTheme.accentRose.withValues(alpha: 0.45),
                ),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text(
                'Sign Out of Admin Console',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SUPPORTING ADMIN WIDGETS
// ============================================================================

class _HeroStatChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroStatChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white70),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NetworkBentoCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _NetworkBentoCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBackground(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  Icon(
                    Icons.north_east_rounded,
                    size: 16,
                    color: AppTheme.mutedText(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  fontFeatures: AppTheme.tabularFigures,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.mutedText(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final User user;
  final StoreMetrics metrics;
  final double maxSales;
  final NumberFormat currency;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.rank,
    required this.user,
    required this.metrics,
    required this.maxSales,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxSales > 0
        ? (metrics.totalSales / maxSales).clamp(0.04, 1.0)
        : 0.04;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? AppTheme.accentViolet
                        : AppTheme.subtleSurface(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: rank == 1 ? Colors.white : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${user.username} • ${metrics.transactionsCount} orders • ${metrics.productsCount} items',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.mutedText(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currency.format(metrics.totalSales),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentTeal,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: AppTheme.subtleSurface(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  rank == 1 ? AppTheme.accentViolet : AppTheme.accentIndigo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GovernanceAlertRow extends StatelessWidget {
  final User user;
  final StoreMetrics metrics;
  final VoidCallback onTap;

  const _GovernanceAlertRow({
    required this.user,
    required this.metrics,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> reasons = [];
    Color badgeColor = AppTheme.accentAmber;
    if (!user.isActive) {
      reasons.add('Store Suspended');
      badgeColor = AppTheme.accentRose;
    }
    if (!metrics.hasPin) {
      reasons.add('No Quick PIN');
    }
    if (metrics.debtsCount > 0) {
      reasons.add('${metrics.debtsCount} Unpaid Debts');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                !user.isActive
                    ? Icons.block_rounded
                    : Icons.warning_amber_rounded,
                size: 18,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    reasons.join(' • '),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AdminSettingsLabel extends StatelessWidget {
  final String text;
  const _AdminSettingsLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        color: AppTheme.mutedText(context),
      ),
    );
  }
}

class _AdminSettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _AdminSettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(children: children),
    );
  }
}

class _AdminSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _AdminSettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppTheme.mutedText(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onTap != null
          ? Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppTheme.mutedText(context),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentViolet : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppTheme.mutedText(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

