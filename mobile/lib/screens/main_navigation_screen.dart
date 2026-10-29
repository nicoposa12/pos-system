import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'product_list_screen.dart';
import 'settings_screen.dart';
import 'transaction_history_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final ValueNotifier<TransactionFilter?> _historyFilterNotifier =
      ValueNotifier<TransactionFilter?>(null);
  final ValueNotifier<StockFilter?> _inventoryFilterNotifier =
      ValueNotifier<StockFilter?>(null);

  late final List<Widget> _screens = [
    DashboardScreen(
      onOpenPos: () => _selectTab(1),
      onOpenHistory: (filter) {
        _historyFilterNotifier.value = filter;
        _selectTab(3);
      },
      onOpenInventory: (filter) {
        _inventoryFilterNotifier.value = filter;
        _selectTab(2);
      },
    ),
    const PosScreen(),
    ProductListScreen(filterRequest: _inventoryFilterNotifier),
    TransactionHistoryScreen(filterRequest: _historyFilterNotifier),
  ];

  @override
  void dispose() {
    _historyFilterNotifier.dispose();
    _inventoryFilterNotifier.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
  }

  Widget _posBadgeIcon(Widget icon, int cartCount) {
    if (cartCount <= 0) return icon;
    return Badge(
      backgroundColor: AppTheme.accentOrange,
      textColor: Colors.white,
      label: Text(
        cartCount > 99 ? '99+' : '$cartCount',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
      child: icon,
    );
  }

  Widget _inventoryBadgeIcon(Widget icon, int lowStockCount) {
    if (lowStockCount <= 0) return icon;
    return Badge(
      backgroundColor: AppTheme.accentAmber,
      smallSize: 8,
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 700;
    final extendedRail = width >= 1120;
    final cartCount = context.watch<CartProvider>().itemCount;
    final lowStockCount =
        context.watch<ProductProvider>().lowStockProducts.length;
    final settings = context.watch<SettingsProvider>();
    final storeName = settings.storeName;
    final hasBusinessPhoto = settings.businessPhotoPath.isNotEmpty &&
        File(settings.businessPhotoPath).existsSync();

    if (useRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: extendedRail,
                minWidth: 80,
                minExtendedWidth: 224,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                labelType: extendedRail
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: Padding(
                  padding: EdgeInsets.fromLTRB(
                    extendedRail ? 16 : 0,
                    12,
                    extendedRail ? 16 : 0,
                    20,
                  ),
                  child: extendedRail
                      ? SizedBox(
                          width: 192,
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  image: DecorationImage(
                                    image: hasBusinessPhoto
                                        ? FileImage(File(settings.businessPhotoPath))
                                        : const AssetImage(
                                            'assets/images/app_icon.png',
                                          ) as ImageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'TindaKo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      storeName,
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
                            ],
                          ),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: hasBusinessPhoto
                                  ? FileImage(File(settings.businessPhotoPath))
                                  : const AssetImage('assets/images/app_icon.png')
                                      as ImageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: Text('Overview'),
                  ),
                  NavigationRailDestination(
                    icon: _posBadgeIcon(
                      const Icon(Icons.point_of_sale_outlined),
                      cartCount,
                    ),
                    selectedIcon: _posBadgeIcon(
                      const Icon(Icons.point_of_sale_rounded),
                      cartCount,
                    ),
                    label: const Text('POS'),
                  ),
                  NavigationRailDestination(
                    icon: _inventoryBadgeIcon(
                      const Icon(Icons.inventory_2_outlined),
                      lowStockCount,
                    ),
                    selectedIcon: _inventoryBadgeIcon(
                      const Icon(Icons.inventory_2_rounded),
                      lowStockCount,
                    ),
                    label: const Text('Inventory'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: Text('History'),
                  ),
                ],
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppTheme.borderColor(context),
              ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.borderColor(context), width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectTab,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: _posBadgeIcon(
                const Icon(Icons.point_of_sale_outlined),
                cartCount,
              ),
              selectedIcon: _posBadgeIcon(
                const Icon(Icons.point_of_sale_rounded),
                cartCount,
              ),
              label: 'POS',
            ),
            NavigationDestination(
              icon: _inventoryBadgeIcon(
                const Icon(Icons.inventory_2_outlined),
                lowStockCount,
              ),
              selectedIcon: _inventoryBadgeIcon(
                const Icon(Icons.inventory_2_rounded),
                lowStockCount,
              ),
              label: 'Inventory',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
