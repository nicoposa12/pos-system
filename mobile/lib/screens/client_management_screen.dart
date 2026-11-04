import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/user.dart';
import '../providers/admin_store_controller.dart';
import '../providers/auth_provider.dart';

enum StoreSortOption { revenueDesc, newest, nameAsc, catalogDesc }

class ClientManagementScreen extends StatefulWidget {
  final AdminStoreController? controller;
  final bool embedded;
  final ValueNotifier<String?>? filterRequest;

  const ClientManagementScreen({
    super.key,
    this.controller,
    this.embedded = false,
    this.filterRequest,
  });

  /// Opens the Provision Store / Administrator modal from any admin screen.
  static Future<void> showProvisionModal(
    BuildContext context, {
    required AdminStoreController controller,
    String initialRole = 'client',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProvisionAccountSheet(
        controller: controller,
        initialRole: initialRole,
      ),
    );
  }

  /// Opens the Store Command Inspector sheet on mobile/tablet viewports.
  static Future<void> showInspectorModal(
    BuildContext context, {
    required User user,
    required AdminStoreController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        expand: false,
        builder: (sheetCtx, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetCtx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppTheme.borderColor(sheetCtx)),
          ),
          child: StoreInspectorPanel(
            key: ValueKey('modal_inspector_${user.id}_${user.username}'),
            user: user,
            controller: controller,
            scrollController: scrollController,
            onClose: () => Navigator.pop(sheetCtx),
          ),
        ),
      ),
    );
  }

  @override
  State<ClientManagementScreen> createState() => _ClientManagementScreenState();
}

class _ClientManagementScreenState extends State<ClientManagementScreen> {
  AdminStoreController? _ownedController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  // Default to 'stores' so the Admin focuses immediately on client businesses
  String _filter = 'stores'; // 'stores', 'active', 'suspended', 'admins', 'all'
  StoreSortOption _sort = StoreSortOption.revenueDesc;
  String _searchQuery = '';
  int? _selectedUserId;

  AdminStoreController get _ctrl => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = AdminStoreController();
    }
    widget.filterRequest?.addListener(_handleExternalFilterRequest);
    _applyPendingFilterRequest();
  }

  @override
  void didUpdateWidget(covariant ClientManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRequest != widget.filterRequest) {
      oldWidget.filterRequest?.removeListener(_handleExternalFilterRequest);
      widget.filterRequest?.addListener(_handleExternalFilterRequest);
      _applyPendingFilterRequest();
    }
    if (oldWidget.controller != widget.controller) {
      if (widget.controller != null && _ownedController != null) {
        _ownedController!.dispose();
        _ownedController = null;
      } else if (widget.controller == null && _ownedController == null) {
        _ownedController = AdminStoreController();
      }
    }
  }

  void _handleExternalFilterRequest() {
    if (!mounted) return;
    _applyPendingFilterRequest();
  }

  void _applyPendingFilterRequest() {
    final requested = widget.filterRequest?.value;
    if (requested != null && requested.isNotEmpty) {
      setState(() => _filter = requested);
      widget.filterRequest?.value = null;
    }
  }

  @override
  void dispose() {
    widget.filterRequest?.removeListener(_handleExternalFilterRequest);
    _searchController.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  List<User> _computeFiltered(AdminStoreController ctrl) {
    final list = ctrl.users.where((user) {
      switch (_filter) {
        case 'stores':
          if (user.isAdmin) return false;
          break;
        case 'active':
          if (user.isAdmin || !user.isActive) return false;
          break;
        case 'suspended':
          if (user.isAdmin || user.isActive) return false;
          break;
        case 'admins':
          if (!user.isAdmin) return false;
          break;
        case 'all':
        default:
          break;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = user.fullName.toLowerCase().contains(q);
        final matchUser = user.username.toLowerCase().contains(q);
        final matchEmail = user.email?.toLowerCase().contains(q) ?? false;
        return matchName || matchUser || matchEmail;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case StoreSortOption.revenueDesc:
          final diff = ctrl.metricsFor(b).totalSales.compareTo(
                ctrl.metricsFor(a).totalSales,
              );
          return diff != 0 ? diff : b.createdAt.compareTo(a.createdAt);
        case StoreSortOption.newest:
          return b.createdAt.compareTo(a.createdAt);
        case StoreSortOption.nameAsc:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case StoreSortOption.catalogDesc:
          final diff = ctrl.metricsFor(b).productsCount.compareTo(
                ctrl.metricsFor(a).productsCount,
              );
          return diff != 0 ? diff : a.fullName.compareTo(b.fullName);
      }
    });

    return list;
  }

  String _sortLabel(StoreSortOption option) {
    switch (option) {
      case StoreSortOption.revenueDesc:
        return 'Top Revenue';
      case StoreSortOption.newest:
        return 'Newest';
      case StoreSortOption.nameAsc:
        return 'Name (A–Z)';
      case StoreSortOption.catalogDesc:
        return 'Largest Catalog';
    }
  }

  Future<void> _confirmAndToggleStatus(User user) async {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final currentUsername = context.read<AuthProvider>().currentUser?.username;
    if ((user.id != null && user.id == currentUserId) ||
        user.username == currentUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot suspend your own administrator account.'),
          backgroundColor: AppTheme.accentAmber,
        ),
      );
      return;
    }

    final willActivate = !user.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willActivate ? 'Reactivate Store Access?' : 'Suspend Store Access?'),
        content: Text(
          willActivate
              ? 'Restore POS login and cloud sync access for "${user.fullName}" (@${user.username})?'
              : 'Suspending "${user.fullName}" (@${user.username}) immediately blocks new POS logins for this business until reactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: willActivate ? AppTheme.accentTeal : AppTheme.accentRose,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willActivate ? 'Reactivate Store' : 'Suspend Store'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();
    final err = await _ctrl.toggleStatus(user);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (willActivate
                  ? '${user.fullName} is now Active.'
                  : '${user.fullName} has been Suspended.'),
        ),
        backgroundColor: err != null
            ? AppTheme.accentRose
            : (willActivate ? AppTheme.accentTeal : AppTheme.accentAmber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isSplitDesktop = screenWidth >= 1040;
    final isCompactMobile = screenWidth < 700;

    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final filtered = _computeFiltered(_ctrl);

        // Keep desktop detail selection valid
        User? selectedStore;
        if (filtered.isNotEmpty) {
          selectedStore = filtered.firstWhere(
            (u) => u.id != null && u.id == _selectedUserId,
            orElse: () => filtered.first,
          );
        }

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.embedded) _buildEmbeddedHeader(context, isCompactMobile),
            if (_ctrl.syncBannerMessage != null) _buildOfflineNotice(context),
            Expanded(
              child: isSplitDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              _buildControlsHeader(context),
                              Expanded(
                                child: _buildDirectoryList(
                                  context,
                                  filtered: filtered,
                                  isSplitDesktop: true,
                                  selectedStore: selectedStore,
                                ),
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
                          flex: 6,
                          child: selectedStore != null
                              ? StoreInspectorPanel(
                                  key: ValueKey(
                                    'split_inspector_${selectedStore.id}_${selectedStore.username}',
                                  ),
                                  user: selectedStore,
                                  controller: _ctrl,
                                )
                              : _buildEmptyInspectorPlaceholder(context),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildControlsHeader(context),
                        Expanded(
                          child: _buildDirectoryList(
                            context,
                            filtered: filtered,
                            isSplitDesktop: false,
                            selectedStore: null,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );

        if (widget.embedded) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: isCompactMobile
                ? FloatingActionButton.extended(
                    heroTag: 'provision_store_fab_embedded',
                    backgroundColor: AppTheme.accentViolet,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add_business_rounded),
                    label: const Text(
                      'Provision Store',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => ClientManagementScreen.showProvisionModal(
                      context,
                      controller: _ctrl,
                      initialRole: _filter == 'admins' ? 'admin' : 'client',
                    ),
                  )
                : null,
            body: content,
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Stores & Businesses'),
            actions: [
              IconButton(
                tooltip: 'Sync Cloud Directory',
                icon: const Icon(Icons.sync_rounded),
                onPressed: () => _ctrl.refresh(),
              ),
              if (!isCompactMobile)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentViolet,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => ClientManagementScreen.showProvisionModal(
                      context,
                      controller: _ctrl,
                      initialRole: _filter == 'admins' ? 'admin' : 'client',
                    ),
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: const Text('Provision Store'),
                  ),
                ),
            ],
          ),
          floatingActionButton: isCompactMobile
              ? FloatingActionButton.extended(
                  heroTag: 'provision_store_fab_standalone',
                  backgroundColor: AppTheme.accentViolet,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_business_rounded),
                  label: const Text(
                    'Provision Store',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => ClientManagementScreen.showProvisionModal(
                    context,
                    controller: _ctrl,
                    initialRole: _filter == 'admins' ? 'admin' : 'client',
                  ),
                )
              : null,
          body: content,
        );
      },
    );
  }

  Widget _buildEmbeddedHeader(BuildContext context, bool isCompactMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompactMobile ? 16 : 24,
        isCompactMobile ? 14 : 20,
        isCompactMobile ? 16 : 24,
        12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppTheme.violetGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Stores & Businesses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_ctrl.activeStoresCount} active stores • ${_ctrl.totalStoresCount} registered businesses',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _CloudSyncBadge(isCloudSynced: _ctrl.isCloudSynced),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh Directory',
            onPressed: _ctrl.isLoading ? null : () => _ctrl.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (!isCompactMobile) ...[
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentViolet,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => ClientManagementScreen.showProvisionModal(
                context,
                controller: _ctrl,
                initialRole: _filter == 'admins' ? 'admin' : 'client',
              ),
              icon: const Icon(Icons.add_business_rounded, size: 18),
              label: const Text(
                'Provision Store',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfflineNotice(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accentAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.accentAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ctrl.syncBannerMessage!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => _ctrl.refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search store name, @username, or email...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      borderSide: const BorderSide(
                        color: AppTheme.accentViolet,
                        width: 1.8,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<StoreSortOption>(
                tooltip: 'Sort stores',
                initialValue: _sort,
                onSelected: (opt) => setState(() => _sort = opt),
                itemBuilder: (_) => StoreSortOption.values
                    .map(
                      (opt) => PopupMenuItem<StoreSortOption>(
                        value: opt,
                        child: Row(
                          children: [
                            Icon(
                              _sort == opt
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 18,
                              color: _sort == opt
                                  ? AppTheme.accentViolet
                                  : AppTheme.mutedText(context),
                            ),
                            const SizedBox(width: 10),
                            Text(_sortLabel(opt)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sort_rounded,
                        size: 18,
                        color: AppTheme.accentViolet,
                      ),
                      if (MediaQuery.sizeOf(context).width >= 520) ...[
                        const SizedBox(width: 6),
                        Text(
                          _sortLabel(_sort),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSegmentChip(
                  'stores',
                  'Client Stores (${_ctrl.totalStoresCount})',
                  Icons.storefront_rounded,
                ),
                const SizedBox(width: 8),
                _buildSegmentChip(
                  'active',
                  'Active (${_ctrl.activeStoresCount})',
                  Icons.check_circle_outline_rounded,
                ),
                const SizedBox(width: 8),
                _buildSegmentChip(
                  'suspended',
                  'Suspended (${_ctrl.suspendedStoresCount})',
                  Icons.pause_circle_outline_rounded,
                ),
                const SizedBox(width: 8),
                _buildSegmentChip(
                  'admins',
                  'Admins (${_ctrl.adminsCount})',
                  Icons.shield_outlined,
                ),
                const SizedBox(width: 8),
                _buildSegmentChip(
                  'all',
                  'All (${_ctrl.users.length})',
                  Icons.layers_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentChip(String key, String label, IconData icon) {
    final selected = _filter == key;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AppTheme.mutedText(context),
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.accentViolet,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _filter = key);
      },
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? Colors.white : AppTheme.mutedText(context),
      ),
    );
  }

  Widget _buildDirectoryList(
    BuildContext context, {
    required List<User> filtered,
    required bool isSplitDesktop,
    required User? selectedStore,
  }) {
    if (_ctrl.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentViolet),
      );
    }

    if (filtered.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.accentViolet,
        onRefresh: () => _ctrl.refresh(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppTheme.accentViolet.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 34,
                        color: AppTheme.accentViolet,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No matching businesses'
                          : (_filter == 'stores'
                              ? 'No client stores provisioned yet'
                              : 'No accounts in this view'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'Try searching a different store name, @username, or owner email.'
                          : 'Provision a client business account so the store owner can sign in on their POS device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.mutedText(context),
                        height: 1.4,
                      ),
                    ),
                    if (_searchQuery.isEmpty) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentViolet,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () => ClientManagementScreen.showProvisionModal(
                          context,
                          controller: _ctrl,
                          initialRole: _filter == 'admins' ? 'admin' : 'client',
                        ),
                        icon: const Icon(Icons.add_business_rounded, size: 18),
                        label: const Text(
                          'Provision First Store',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentViolet,
      onRefresh: () => _ctrl.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final user = filtered[index];
          final isSelected = isSplitDesktop &&
              selectedStore != null &&
              user.id == selectedStore.id &&
              user.username == selectedStore.username;
          return _buildStoreBusinessCard(
            context,
            user: user,
            isSelected: isSelected,
            onTap: () {
              HapticFeedback.selectionClick();
              if (isSplitDesktop) {
                setState(() => _selectedUserId = user.id);
              } else {
                ClientManagementScreen.showInspectorModal(
                  context,
                  user: user,
                  controller: _ctrl,
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildStoreBusinessCard(
    BuildContext context, {
    required User user,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final metrics = _ctrl.metricsFor(user);
    final authUser = context.read<AuthProvider>().currentUser;
    final isSelf = (user.id != null && user.id == authUser?.id) ||
        user.username == authUser?.username;

    final Color borderColor = isSelected
        ? AppTheme.accentViolet
        : (!user.isActive
            ? AppTheme.accentRose.withValues(alpha: 0.38)
            : AppTheme.borderColor(context));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.accentViolet.withValues(alpha: 0.06)
            : AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identity Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: user.isAdmin
                            ? AppTheme.violetGradient
                            : (user.isActive
                                ? AppTheme.tealGradient
                                : AppTheme.roseGradient),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        user.isAdmin
                            ? Icons.admin_panel_settings_rounded
                            : (user.isActive
                                ? Icons.storefront_rounded
                                : Icons.store_mall_directory_outlined),
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.fullName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusBadge(user: user),
                              if (isSelf) ...[
                                const SizedBox(width: 6),
                                _MicroPill(
                                  label: 'YOU',
                                  color: AppTheme.accentViolet,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '@${user.username}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.mutedText(context),
                                ),
                              ),
                              if (user.email != null && user.email!.isNotEmpty)
                                Text(
                                  '• ${user.email}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.mutedText(context),
                                  ),
                                ),
                              _MicroPill(
                                label: metrics.hasPin ? 'PIN READY' : 'NO PIN',
                                color: metrics.hasPin
                                    ? AppTheme.accentIndigo
                                    : AppTheme.accentAmber,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Store KPI Strip (shown for client businesses or any account with activity)
                if (!user.isAdmin || metrics.totalSales > 0 || metrics.productsCount > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleSurface(context).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _InlineKpi(
                            label: 'GROSS SALES',
                            value: _currency.format(metrics.totalSales),
                            valueColor: AppTheme.accentTeal,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: AppTheme.borderColor(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: _InlineKpi(
                            label: 'CATALOG',
                            value: '${metrics.productsCount} items',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: AppTheme.borderColor(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: _InlineKpi(
                            label: metrics.debtsCount > 0 ? 'UNPAID DEBTS' : 'ORDERS',
                            value: metrics.debtsCount > 0
                                ? '${metrics.debtsCount} open'
                                : '${metrics.transactionsCount} sales',
                            valueColor: metrics.debtsCount > 0
                                ? AppTheme.accentRose
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Quick Touch Governance Bar (responsive, zero overflow at any width)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accentViolet,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onPressed: onTap,
                          icon: const Icon(Icons.analytics_outlined, size: 17),
                          label: Text(
                            user.isAdmin ? 'Inspect' : 'Inspect Store',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reset Password / Quick PIN',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.key_rounded, size: 18),
                          color: AppTheme.accentAmber,
                          onPressed: () => _showResetCredentialsSheet(
                            context,
                            user: user,
                            controller: _ctrl,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit Store Profile',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppTheme.mutedText(context),
                          onPressed: () => _showEditAccountSheet(
                            context,
                            user: user,
                            controller: _ctrl,
                          ),
                        ),
                      ],
                    ),
                    if (!isSelf)
                      SizedBox(
                        height: 36,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: user.isActive,
                            activeThumbColor: AppTheme.accentTeal,
                            onChanged: (_) => _confirmAndToggleStatus(user),
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
    );
  }

  Widget _buildEmptyInspectorPlaceholder(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: AppTheme.mutedText(context),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a store business on the left to inspect live sales, catalog metrics, and credentials.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LIVE STORE COMMAND INSPECTOR PANEL (Used in Desktop Split & Mobile Sheet)
// ============================================================================

class StoreInspectorPanel extends StatefulWidget {
  final User user;
  final AdminStoreController controller;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  const StoreInspectorPanel({
    super.key,
    required this.user,
    required this.controller,
    this.scrollController,
    this.onClose,
  });

  @override
  State<StoreInspectorPanel> createState() => _StoreInspectorPanelState();
}

class _StoreInspectorPanelState extends State<StoreInspectorPanel> {
  final NumberFormat _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  bool _loadingLive = false;
  double? _todaySales;
  List<Map<String, dynamic>> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadLiveDetails();
  }

  @override
  void didUpdateWidget(covariant StoreInspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.username != widget.user.username) {
      _todaySales = null;
      _recentTransactions = [];
      _loadLiveDetails();
    }
  }

  Future<void> _loadLiveDetails() async {
    if (widget.user.id == null) return;
    setState(() => _loadingLive = true);
    final details = await widget.controller.fetchStoreLiveDetails(widget.user.id!);
    if (!mounted) return;
    if (details != null) {
      final stats = details['stats'] is Map
          ? Map<String, dynamic>.from(details['stats'] as Map)
          : const <String, dynamic>{};
      final rawTx = details['recent_transactions'];
      setState(() {
        _todaySales = (stats['today_sales'] as num?)?.toDouble() ?? 0.0;
        if (rawTx is List) {
          _recentTransactions = rawTx
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        _loadingLive = false;
      });
    } else {
      setState(() => _loadingLive = false);
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Store Permanently?'),
        content: Text(
          'This will permanently remove "${widget.user.fullName}" (@${widget.user.username}) '
          'from Neon Cloud and erase all of its products, sales history, debts, and active login tokens.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    HapticFeedback.heavyImpact();
    final err = await widget.controller.deleteAccount(widget.user);
    if (!context.mounted) return;

    if (err == null) {
      widget.onClose?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Store @${widget.user.username} permanently deleted.'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  Future<void> _handleToggleStatus(BuildContext context) async {
    final willActivate = !widget.user.isActive;
    HapticFeedback.mediumImpact();
    final err = await widget.controller.toggleStatus(widget.user);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (willActivate
                  ? '${widget.user.fullName} is now Active.'
                  : '${widget.user.fullName} is now Suspended.'),
        ),
        backgroundColor: err != null
            ? AppTheme.accentRose
            : (willActivate ? AppTheme.accentTeal : AppTheme.accentAmber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pull freshest user snapshot from controller if updated
    final liveUser = widget.controller.users.firstWhere(
      (u) =>
          (widget.user.id != null && u.id == widget.user.id) ||
          u.username == widget.user.username,
      orElse: () => widget.user,
    );
    final metrics = widget.controller.metricsFor(liveUser);
    final authUser = context.watch<AuthProvider>().currentUser;
    final isSelf = (liveUser.id != null && liveUser.id == authUser?.id) ||
        liveUser.username == authUser?.username;
    final joinedStr = DateFormat('MMM d, yyyy').format(liveUser.createdAt);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [
        if (widget.onClose != null)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.borderColor(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

        // Store Identity Hero Header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppTheme.adminHeroGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: liveUser.isAdmin
                          ? AppTheme.violetGradient
                          : (liveUser.isActive
                              ? AppTheme.tealGradient
                              : AppTheme.roseGradient),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      liveUser.isAdmin
                          ? Icons.admin_panel_settings_rounded
                          : Icons.storefront_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                liveUser.fullName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(user: liveUser),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${liveUser.username}${liveUser.email != null && liveUser.email!.isNotEmpty ? ' • ${liveUser.email}' : ''}',
                          style: const TextStyle(
                            color: AppTheme.textSecondaryDark,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MicroPill(
                              label: 'Provisioned $joinedStr',
                              color: Colors.white70,
                              darkSurface: true,
                            ),
                            _MicroPill(
                              label: metrics.hasPin ? 'Quick PIN Active' : 'No Quick PIN',
                              color: metrics.hasPin
                                  ? AppTheme.accentTeal
                                  : AppTheme.accentAmber,
                              darkSurface: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: 'Close Inspector',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    )
                  else
                    IconButton(
                      tooltip: 'Refresh Live Telemetry',
                      onPressed: _loadingLive ? null : _loadLiveDetails,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Governance Action Toolbar
        const _SectionTitle('STORE GOVERNANCE & ACCESS'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _GovernanceActionChip(
              icon: Icons.edit_note_rounded,
              label: 'Edit Profile',
              color: AppTheme.accentViolet,
              onTap: () => _showEditAccountSheet(
                context,
                user: liveUser,
                controller: widget.controller,
              ),
            ),
            _GovernanceActionChip(
              icon: Icons.key_rounded,
              label: 'Reset Password / PIN',
              color: AppTheme.accentAmber,
              onTap: () => _showResetCredentialsSheet(
                context,
                user: liveUser,
                controller: widget.controller,
              ),
            ),
            if (!isSelf)
              _GovernanceActionChip(
                icon: liveUser.isActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                label: liveUser.isActive ? 'Suspend Access' : 'Reactivate Store',
                color: liveUser.isActive ? AppTheme.accentRose : AppTheme.accentTeal,
                onTap: () => _handleToggleStatus(context),
              ),
            if (!isSelf)
              _GovernanceActionChip(
                icon: Icons.delete_forever_rounded,
                label: 'Delete Store',
                color: AppTheme.accentRose,
                outlined: true,
                onTap: () => _handleDelete(context),
              ),
          ],
        ),

        const SizedBox(height: 22),

        // Store Performance Telemetry
        Row(
          children: [
            const Expanded(
              child: _SectionTitle('CLOUD STORE TELEMETRY'),
            ),
            if (_loadingLive)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentViolet,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InspectorKpiCard(
                label: 'Today\'s Sales',
                value: _todaySales != null
                    ? _currency.format(_todaySales)
                    : (_loadingLive ? '...' : '₱0.00'),
                icon: Icons.today_rounded,
                accent: AppTheme.accentViolet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InspectorKpiCard(
                label: 'Lifetime Sales',
                value: _currency.format(metrics.totalSales),
                icon: Icons.payments_rounded,
                accent: AppTheme.accentTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _InspectorKpiCard(
                label: 'Products Cataloged',
                value: '${metrics.productsCount}',
                icon: Icons.inventory_2_rounded,
                accent: AppTheme.accentIndigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InspectorKpiCard(
                label: 'Transactions',
                value: '${metrics.transactionsCount}',
                icon: Icons.receipt_long_rounded,
                accent: AppTheme.accentOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InspectorKpiCard(
                label: 'Unpaid Debts',
                value: '${metrics.debtsCount}',
                icon: Icons.assignment_late_rounded,
                accent: metrics.debtsCount > 0
                    ? AppTheme.accentRose
                    : AppTheme.mutedText(context),
              ),
            ),
          ],
        ),

        if (!liveUser.isAdmin) ...[
          const SizedBox(height: 24),
          const _SectionTitle('RECENT STORE TRANSACTIONS'),
          const SizedBox(height: 10),
          if (_loadingLive && _recentTransactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppTheme.accentViolet,
              ),
            )
          else if (_recentTransactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: AppTheme.mutedText(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No cloud sales synced for this store yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.mutedText(context),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _recentTransactions.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: AppTheme.borderColor(context)),
                    _buildTransactionRow(context, _recentTransactions[i]),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTransactionRow(BuildContext context, Map<String, dynamic> tx) {
    final id = tx['id'] ?? '';
    final total = (tx['total_amount'] as num?)?.toDouble() ?? 0.0;
    final method = (tx['payment_method'] ?? 'cash').toString().toUpperCase();
    final items = tx['items'] is List ? (tx['items'] as List).length : 0;
    final rawDate = tx['date'] ?? tx['created_at'];
    final parsedDate = rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;
    final dateStr = parsedDate != null
        ? DateFormat('MMM d • h:mm a').format(parsedDate.toLocal())
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentViolet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              size: 18,
              color: AppTheme.accentViolet,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Order #$id',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MicroPill(
                      label: method,
                      color: method == 'DEBT'
                          ? AppTheme.accentAmber
                          : AppTheme.accentTeal,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${items > 0 ? '$items items • ' : ''}$dateStr',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _currency.format(total),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PROVISION ACCOUNT / EDIT STORE / RESET CREDENTIALS SHEETS
// ============================================================================

class _ProvisionAccountSheet extends StatefulWidget {
  final AdminStoreController controller;
  final String initialRole;

  const _ProvisionAccountSheet({
    required this.controller,
    this.initialRole = 'client',
  });

  @override
  State<_ProvisionAccountSheet> createState() => _ProvisionAccountSheetState();
}

class _ProvisionAccountSheetState extends State<_ProvisionAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  late String _role = widget.initialRole;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorBanner;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _generateRandomPin() {
    final rng = math.Random.secure();
    String candidate;
    do {
      candidate = (1000 + rng.nextInt(9000)).toString();
    } while (candidate == '0000' || candidate == '9999');
    setState(() => _pinCtrl.text = candidate);
    HapticFeedback.selectionClick();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorBanner = null;
    });

    final username = _usernameCtrl.text.trim();
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null;
    final password = _passwordCtrl.text;
    final pin = _pinCtrl.text.trim().isNotEmpty ? _pinCtrl.text.trim() : null;

    final err = await widget.controller.createAccount(
      username: username,
      fullName: fullName,
      password: password,
      email: email,
      pin: pin,
      role: _role,
    );

    if (!mounted) return;
    if (err != null) {
      setState(() {
        _submitting = false;
        _errorBanner = err;
      });
      return;
    }

    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _role == 'admin'
              ? 'Administrator @$username created in Neon Cloud.'
              : 'Store "$fullName" (@$username) provisioned successfully.',
        ),
        backgroundColor: AppTheme.accentTeal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isClient = _role == 'client';
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        top: 22,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.violetGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isClient
                            ? Icons.add_business_rounded
                            : Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClient ? 'Provision Client Store' : 'Add Platform Admin',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            isClient
                                ? 'Create store credentials synced directly to Neon Cloud'
                                : 'Grant full multi-store console privileges',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Account Type Selector
                _RoleToggleBar(
                  selectedRole: _role,
                  onChanged: (r) => setState(() => _role = r),
                ),
                const SizedBox(height: 16),

                if (_errorBanner != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRose.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.accentRose.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: AppTheme.accentRose,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorBanner!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentRose,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                TextFormField(
                  controller: _fullNameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: isClient ? 'Store / Business Name *' : 'Administrator Full Name *',
                    hintText: isClient ? 'e.g. Santos Mini Mart' : 'e.g. Juan Dela Cruz',
                    prefixIcon: Icon(
                      isClient ? Icons.storefront_rounded : Icons.badge_outlined,
                      size: 20,
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? (isClient ? 'Store name is required' : 'Full name is required')
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Login Username *',
                    hintText: isClient ? 'e.g. santos_mart' : 'e.g. hq_admin',
                    prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Username is required';
                    if (v.trim().length < 3) return 'Minimum 3 characters';
                    if (v.trim().toLowerCase() == 'developer') {
                      return 'Reserved username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Owner / Contact Email (Optional)',
                    hintText: 'owner@business.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Login Password *',
                    hintText: 'Minimum 4 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 4)
                      ? 'Password must be at least 4 characters'
                      : null,
                ),
                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _pinCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Quick POS PIN (Optional)',
                          hintText: '4–6 digits',
                          prefixIcon: Icon(Icons.dialpad_rounded, size: 20),
                        ),
                        validator: (v) {
                          if (v != null && v.isNotEmpty) {
                            if (v.length < 4) return 'Use 4–6 digits';
                            if (v == '0000') return '0000 is not allowed';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _generateRandomPin,
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                        label: const Text('Generate'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentViolet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isClient ? 'Provision Store Account' : 'Create Admin Account',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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

Future<void> _showEditAccountSheet(
  BuildContext context, {
  required User user,
  required AdminStoreController controller,
}) {
  final formKey = GlobalKey<FormState>();
  final fullNameCtrl = TextEditingController(text: user.fullName);
  final emailCtrl = TextEditingController(text: user.email ?? '');
  String selectedRole = user.role;
  bool saving = false;
  String? errorText;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (modalCtx, setModalState) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(modalCtx).bottom + 24,
            top: 22,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(modalCtx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppTheme.borderColor(modalCtx)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentViolet.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: AppTheme.accentViolet,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Edit Business Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '@${user.username}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedText(modalCtx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(modalCtx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _RoleToggleBar(
                    selectedRole: selectedRole,
                    onChanged: (r) => setModalState(() => selectedRole = r),
                  ),
                  const SizedBox(height: 16),
                  if (errorText != null) ...[
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: AppTheme.accentRose,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: fullNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Store / Full Name *',
                      prefixIcon: Icon(Icons.storefront_rounded, size: 20),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              saving = true;
                              errorText = null;
                            });
                            final err = await controller.updateAccount(
                              user,
                              fullName: fullNameCtrl.text.trim(),
                              email: emailCtrl.text.trim().isNotEmpty
                                  ? emailCtrl.text.trim()
                                  : null,
                              role: selectedRole,
                            );
                            if (!modalCtx.mounted) return;
                            if (err != null) {
                              setModalState(() {
                                saving = false;
                                errorText = err;
                              });
                              return;
                            }
                            Navigator.pop(modalCtx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Store profile updated.'),
                                  backgroundColor: AppTheme.accentTeal,
                                ),
                              );
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(fontWeight: FontWeight.w700),
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

Future<void> _showResetCredentialsSheet(
  BuildContext context, {
  required User user,
  required AdminStoreController controller,
}) {
  final formKey = GlobalKey<FormState>();
  final passwordCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  bool obscure = true;
  bool saving = false;
  String? errorText;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (modalCtx, setModalState) {
        void generatePin() {
          final rng = math.Random.secure();
          String candidate;
          do {
            candidate = (1000 + rng.nextInt(9000)).toString();
          } while (candidate == '0000' || candidate == '9999');
          setModalState(() => pinCtrl.text = candidate);
        }

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(modalCtx).bottom + 24,
            top: 22,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(modalCtx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppTheme.borderColor(modalCtx)),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentAmber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.key_rounded,
                          color: AppTheme.accentAmber,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reset Store Credentials',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${user.fullName} (@${user.username})',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedText(modalCtx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(modalCtx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (errorText != null) ...[
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: AppTheme.accentRose,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password (Optional)',
                      hintText: 'Leave blank to keep current password',
                      prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setModalState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 4) {
                        return 'Minimum 4 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: pinCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'New Quick PIN (Optional)',
                            hintText: '4–6 digits',
                            prefixIcon: Icon(Icons.dialpad_rounded, size: 20),
                          ),
                          validator: (v) {
                            if (v != null && v.isNotEmpty) {
                              if (v.length < 4) return 'Use 4–6 digits';
                              if (v == '0000') return '0000 is reserved';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : generatePin,
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                          label: const Text('Generate'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentAmber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            final pw = passwordCtrl.text;
                            final pin = pinCtrl.text.trim();
                            if (pw.isEmpty && pin.isEmpty) {
                              setModalState(() {
                                errorText = 'Enter a new password or PIN to update.';
                              });
                              return;
                            }
                            setModalState(() {
                              saving = true;
                              errorText = null;
                            });
                            final err = await controller.resetCredentials(
                              user,
                              password: pw.isNotEmpty ? pw : null,
                              pin: pin.isNotEmpty ? pin : null,
                            );
                            if (!modalCtx.mounted) return;
                            if (err != null) {
                              setModalState(() {
                                saving = false;
                                errorText = err;
                              });
                              return;
                            }
                            Navigator.pop(modalCtx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Credentials updated for @${user.username}.',
                                  ),
                                  backgroundColor: AppTheme.accentTeal,
                                ),
                              );
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Update Credentials',
                            style: TextStyle(fontWeight: FontWeight.w700),
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

// ============================================================================
// SHARED ATOMIC ADMIN COMPONENTS
// ============================================================================

class _RoleToggleBar extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onChanged;

  const _RoleToggleBar({
    required this.selectedRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged('client'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectedRole == 'client'
                      ? AppTheme.accentViolet
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 16,
                      color: selectedRole == 'client'
                          ? Colors.white
                          : AppTheme.mutedText(context),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Client Business',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selectedRole == 'client'
                              ? Colors.white
                              : AppTheme.mutedText(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged('admin'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectedRole == 'admin'
                      ? AppTheme.accentIndigo
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: selectedRole == 'admin'
                          ? Colors.white
                          : AppTheme.mutedText(context),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Platform Admin',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selectedRole == 'admin'
                              ? Colors.white
                              : AppTheme.mutedText(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
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

class _CloudSyncBadge extends StatelessWidget {
  final bool isCloudSynced;

  const _CloudSyncBadge({required this.isCloudSynced});

  @override
  Widget build(BuildContext context) {
    final color = isCloudSynced ? AppTheme.accentTeal : AppTheme.accentAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isCloudSynced ? 'NEON LIVE' : 'CACHED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final User user;

  const _StatusBadge({required this.user});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    if (user.isAdmin) {
      color = AppTheme.accentViolet;
      text = 'ADMIN';
    } else if (user.isActive) {
      color = AppTheme.accentTeal;
      text = 'ACTIVE';
    } else {
      color = AppTheme.accentRose;
      text = 'SUSPENDED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MicroPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool darkSurface;

  const _MicroPill({
    required this.label,
    required this.color,
    this.darkSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: darkSurface
            ? Colors.white.withValues(alpha: 0.10)
            : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _InlineKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InlineKpi({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppTheme.mutedText(context),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: AppTheme.tabularFigures,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

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

class _GovernanceActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _GovernanceActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: outlined ? Colors.transparent : color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: outlined ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _InspectorKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedText(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFeatures: AppTheme.tabularFigures,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
