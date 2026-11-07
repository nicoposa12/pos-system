import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/product_image_view.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/skeleton.dart';
import 'scanner_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    Future.microtask(() {
      if (!mounted) return;
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filterProducts(List<Product> all) {
    Iterable<Product> filtered = all;
    if (_selectedCategory != 'All') {
      filtered = filtered.where((p) => p.category == _selectedCategory);
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where(
        (p) =>
            p.name.toLowerCase().contains(q) ||
            (p.category?.toLowerCase().contains(q) ?? false) ||
            (p.barcode?.toLowerCase().contains(q) ?? false),
      );
    }
    return filtered.toList();
  }

  Future<void> _scanBarcodeToCart(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cartProvider = context.read<CartProvider>();
    final productProvider = context.read<ProductProvider>();

    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(title: 'Scan Item to Add'),
      ),
    );

    if (code == null || !mounted) return;

    final product = productProvider.allProducts.cast<Product?>().firstWhere(
          (p) => p?.barcode == code,
          orElse: () => null,
        );

    if (product != null) {
      if (product.stock > 0) {
        HapticFeedback.mediumImpact();
        cartProvider.addItem(product);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Added "${product.name}" to order'),
            duration: const Duration(milliseconds: 1200),
            backgroundColor: AppTheme.accentTeal,
          ),
        );
      } else {
        HapticFeedback.vibrate();
        messenger.showSnackBar(
          SnackBar(
            content: Text('"${product.name}" is out of stock'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    } else {
      HapticFeedback.vibrate();
      messenger.showSnackBar(
        SnackBar(
          content: Text('No product found for barcode $code'),
          backgroundColor: AppTheme.accentAmber,
        ),
      );
    }
  }

  void _confirmClearCart(BuildContext context) {
    if (context.read<CartProvider>().itemCount == 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Clear Current Order?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Remove all items from the current basket?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CartProvider>().clear();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
              minimumSize: const Size(96, 44),
            ),
            child: const Text('Clear Order'),
          ),
        ],
      ),
    );
  }

  void _openCartBottomSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.borderColor(sheetCtx)),
              ),
              child: SafeArea(
                top: false,
                child: Consumer<CartProvider>(
                  builder: (ctx, cart, _) {
                    if (cart.itemCount == 0) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
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
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 48,
                                    color: AppTheme.mutedText(ctx),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Order basket is empty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap products or scan a barcode to add items.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.mutedText(ctx),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    final entries = cart.items.entries.toList();

                    return Column(
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
                          padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                          child: Row(
                            children: [
                              const Text(
                                'Current Order',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentOrange.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${cart.itemCount} items',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentOrange,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  _confirmClearCart(context);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.accentRose,
                                ),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 16,
                              color: AppTheme.borderColor(ctx),
                            ),
                            itemBuilder: (_, index) {
                              final entry = entries[index];
                              return _CartLineTile(
                                key: ValueKey('cart_tile_${entry.key}'),
                                variantKey: entry.key,
                                item: entry.value,
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            border: Border(
                              top: BorderSide(color: AppTheme.borderColor(ctx)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Subtotal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedText(ctx),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '₱${NumberFormat('#,##0.00').format(cart.totalAmount)}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accentOrange,
                                      fontFeatures: AppTheme.tabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(sheetCtx);
                                    _showPaymentSummary(context);
                                  },
                                  icon: const Icon(
                                    Icons.payments_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('Proceed to Pay'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSplitPos = AppTheme.isWidePos(context);
    final productProvider = context.watch<ProductProvider>();
    final categories = productProvider.categories;

    if (_selectedCategory != 'All' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final filteredProducts = _filterProducts(productProvider.allProducts);

    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final horizontalPadding = isCompact ? 12.0 : 20.0;

    final catalogColumn = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            // ── Search + Barcode Scanner Bar ──
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search product or barcode...',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppTheme.mutedText(context),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                icon:
                                    const Icon(Icons.close_rounded, size: 18),
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
                  Material(
                    color: AppTheme.accentOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      onTap: () => _scanBarcodeToCart(context),
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMd),
                          border: Border.all(
                            color: AppTheme.accentOrange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              color: AppTheme.accentOrange,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Category Filter Chips ──
            if (categories.length > 1)
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategory == cat;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      showCheckmark: false,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategory = cat);
                      },
                      backgroundColor: theme.cardTheme.color,
                      selectedColor: AppTheme.accentOrange,
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.accentOrange
                            : AppTheme.borderColor(context),
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),

            // ── Product Catalog List (Row-by-Row) ──
            Expanded(
              child: Builder(
                builder: (context) {
                  if (productProvider.isLoading) {
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, _) => const Skeleton(
                        height: 88,
                        borderRadius: AppTheme.radiusLg,
                      ),
                    );
                  }

                  if (filteredProducts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(context),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.storefront_outlined,
                                size: 32,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              productProvider.allProducts.isEmpty
                                  ? 'No products in catalog'
                                  : 'No matching products',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              productProvider.allProducts.isEmpty
                                  ? 'Add products in the Inventory tab to begin selling.'
                                  : 'Try clearing your search or selecting another category.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.mutedText(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final hasFloatingBar = !isSplitPos &&
                      context.select<CartProvider, bool>((cart) => cart.itemCount > 0);

                  return RefreshIndicator(
                    color: AppTheme.accentOrange,
                    onRefresh: () =>
                        context.read<ProductProvider>().fetchProducts(),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        6,
                        horizontalPadding,
                        hasFloatingBar ? 104 : 24,
                      ),
                      itemCount: filteredProducts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        return _PosProductCard(
                          product: product,
                          onAddBase: () => _tryAddProduct(context, product),
                          onSelectVariant: (variant) => _tryAddProduct(
                            context,
                            product,
                            variant: variant,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        title: const Text(
          'Point of Sale',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          if (!isSplitPos)
            Consumer<CartProvider>(
              builder: (context, cart, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'View Current Order',
                      onPressed: () => _openCartBottomSheet(context),
                      icon: Badge(
                        isLabelVisible: cart.itemCount > 0,
                        backgroundColor: AppTheme.accentOrange,
                        textColor: Colors.white,
                        label: Text(
                          '${cart.itemCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, size: 22),
                      ),
                    ),
                    if (cart.itemCount > 0)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          size: 22,
                          color: AppTheme.accentRose,
                        ),
                        tooltip: 'Clear Order',
                        onPressed: () => _confirmClearCart(context),
                      ),
                    const SizedBox(width: 8),
                  ],
                );
              },
            ),
        ],
      ),
      body: isSplitPos
          ? Row(
              children: [
                Expanded(child: catalogColumn),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.borderColor(context),
                ),
                SizedBox(
                  width: 372,
                  child: _CartSidePanel(
                    onClear: () => _confirmClearCart(context),
                    onCheckout: () => _showPaymentSummary(context),
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                catalogColumn,
                // ── Compact Floating Checkout Bar (Mobile) ──
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: Consumer<CartProvider>(
                    builder: (context, cart, _) {
                      if (cart.itemCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return _FloatingCheckoutBar(
                        itemCount: cart.itemCount,
                        totalAmount: cart.totalAmount,
                        onOpenCart: () => _openCartBottomSheet(context),
                        onCheckout: () => _showPaymentSummary(context),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _tryAddProduct(
    BuildContext context,
    Product product, {
    ProductVariant? variant,
  }) {
    final cart = context.read<CartProvider>();
    final inCart = cart.items.values
        .where((item) => item.product.id == product.id)
        .fold<int>(0, (sum, item) => sum + item.quantity);

    if (inCart >= product.stock) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Maximum available stock (${product.stock}) reached for "${product.name}"',
            ),
            duration: const Duration(milliseconds: 1400),
            backgroundColor: AppTheme.accentAmber,
          ),
        );
      return;
    }

    HapticFeedback.lightImpact();
    cart.addItem(product, variant: variant);
  }

  void _showPaymentSummary(BuildContext context) {
    final cart = context.read<CartProvider>();
    if (cart.itemCount == 0) return;

    showDialog(
      context: context,
      builder: (ctx) => _PaymentSummaryDialog(
        cart: cart,
        onComplete: (discount, cash, paymentMethod, {customerName}) {
          _handleCheckout(
            context,
            discount: discount,
            cashReceived: cash,
            paymentMethod: paymentMethod,
            customerName: customerName,
          );
        },
      ),
    );
  }

  void _handleCheckout(
    BuildContext ctx, {
    double discount = 0.0,
    double cashReceived = 0.0,
    String paymentMethod = 'cash',
    String? customerName,
  }) async {
    final cart = ctx.read<CartProvider>();
    final productProvider = ctx.read<ProductProvider>();
    final transactionProvider = ctx.read<TransactionProvider>();
    final auth = ctx.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(ctx);

    final result = await cart.checkout(
      discount: discount,
      cashReceived: cashReceived,
      paymentMethod: paymentMethod,
      customerName: customerName,
    );

    if (!mounted || !ctx.mounted) return;
    if (result != null) {
      HapticFeedback.heavyImpact();
      transactionProvider.fetchTransactions();
      productProvider.fetchProducts();

      showReceiptDialog(
        context,
        transaction: result['transaction'],
        items: result['items'],
        user: auth.currentUser,
        customerName: customerName,
      );

      messenger.showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Sale completed successfully'),
            ],
          ),
          action: SnackBarAction(
            label: 'RECEIPT',
            textColor: Colors.white,
            onPressed: () {
              showReceiptDialog(
                ctx,
                transaction: result['transaction'],
                items: result['items'],
                user: auth.currentUser,
                customerName: customerName,
              );
            },
          ),
          backgroundColor: AppTheme.accentTeal,
        ),
      );
    } else {
      HapticFeedback.vibrate();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Transaction failed. Please try again.'),
            ],
          ),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }
}

class _FloatingCheckoutBar extends StatelessWidget {
  final int itemCount;
  final double totalAmount;
  final VoidCallback onOpenCart;
  final VoidCallback onCheckout;

  const _FloatingCheckoutBar({
    required this.itemCount,
    required this.totalAmount,
    required this.onOpenCart,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.heroDarkGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpenCart,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '$itemCount',
                      style: const TextStyle(
                        color: AppTheme.accentOrange,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'View Basket',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ],
                        ),
                        Text(
                          '₱${NumberFormat('#,##0.00').format(totalAmount)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
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
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onCheckout,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text(
              'Checkout',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSidePanel extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback onCheckout;

  const _CartSidePanel({
    required this.onClear,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = context.watch<CartProvider>();
    final entries = cart.items.entries.toList();

    return Container(
      color: theme.cardTheme.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 20,
                  color: AppTheme.accentOrange,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Current Order',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (cart.itemCount > 0)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentRose,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppTheme.subtleSurface(context),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.point_of_sale_rounded,
                              size: 28,
                              color: AppTheme.mutedText(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No items added yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select products on the left or scan a barcode.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.mutedText(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 16,
                      color: AppTheme.borderColor(context),
                    ),
                    itemBuilder: (_, index) {
                      final entry = entries[index];
                      return _CartLineTile(
                        key: ValueKey('cart_tile_${entry.key}'),
                        variantKey: entry.key,
                        item: entry.value,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border(
                top: BorderSide(color: AppTheme.borderColor(context)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Items (${cart.itemCount})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mutedText(context),
                      ),
                    ),
                    Text(
                      '₱${NumberFormat('#,##0.00').format(cart.totalAmount)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentOrange,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: cart.itemCount > 0 ? onCheckout : null,
                  icon: const Icon(Icons.payments_rounded, size: 20),
                  label: Text(
                    cart.itemCount > 0
                        ? 'Charge ₱${NumberFormat('#,##0.00').format(cart.totalAmount)}'
                        : 'Select Items to Charge',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatefulWidget {
  final String variantKey;
  final CartItem item;

  const _CartLineTile({
    super.key,
    required this.variantKey,
    required this.item,
  });

  @override
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.item.quantity}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.item.quantity != oldWidget.item.quantity) {
      _controller.text = '${widget.item.quantity}';
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _commitQuantity();
    }
  }

  void _commitQuantity() {
    final text = _controller.text.trim();
    final parsed = int.tryParse(text);
    final cart = context.read<CartProvider>();

    if (parsed == null || text.isEmpty) {
      _controller.text = '${widget.item.quantity}';
      return;
    }

    if (parsed <= 0) {
      cart.removeItem(widget.variantKey);
      return;
    }

    if (parsed == widget.item.quantity) return;

    ProductVariant? matchedVariant;
    if (widget.item.variantName != null) {
      final matches = widget.item.product.variants
          .where((v) => v.name == widget.item.variantName)
          .toList();
      if (matches.isNotEmpty) matchedVariant = matches.first;
    }

    final variantStock = matchedVariant?.stock;
    final int maxAvailable;
    if (variantStock != null) {
      maxAvailable = variantStock;
    } else {
      final otherLinesCount = cart.items.entries
          .where((e) =>
              e.key != widget.variantKey && e.value.product.id == widget.item.product.id)
          .fold(0, (sum, e) => sum + e.value.quantity);
      maxAvailable =
          (widget.item.product.stock - otherLinesCount).clamp(0, widget.item.product.stock);
    }

    final exact = cart.updateQuantity(widget.variantKey, parsed);
    if (!exact) {
      _controller.text = '$maxAvailable';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Quantity adjusted to available stock ($maxAvailable)',
            ),
            backgroundColor: AppTheme.accentAmber,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    String? imgPath;
    if (widget.item.variantName != null) {
      final match = widget.item.product.variants
          .where((v) => v.name == widget.item.variantName && v.hasValidImage)
          .toList();
      if (match.isNotEmpty) {
        imgPath = match.first.imagePath;
      }
    }
    imgPath ??= widget.item.product.hasValidImage
        ? widget.item.product.imagePath
        : null;
    final hasFile = imgPath != null && File(imgPath).existsSync();

    return Dismissible(
      key: ValueKey('cart_${widget.variantKey}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        cart.removeItem(widget.variantKey);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppTheme.accentRose.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppTheme.accentRose,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.subtleSurface(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: hasFile
                ? Image.file(
                    File(imgPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: AppTheme.mutedText(context),
                    ),
                  )
                : Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: AppTheme.mutedText(context),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '₱${widget.item.price.toStringAsFixed(2)}  •  ₱${widget.item.subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedText(context),
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.subtleSurface(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip:
                      widget.item.quantity == 1 ? 'Remove item' : 'Decrease',
                  icon: Icon(
                    widget.item.quantity == 1
                        ? Icons.delete_outline_rounded
                        : Icons.remove_rounded,
                    size: 18,
                    color: widget.item.quantity == 1
                        ? AppTheme.accentRose
                        : null,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _focusNode.unfocus();
                    cart.removeSingleItem(widget.variantKey);
                  },
                ),
                Container(
                  width: 44,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? AppTheme.accentOrange
                          : AppTheme.borderColor(context),
                      width: _focusNode.hasFocus ? 1.5 : 1,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onSubmitted: (_) {
                      _focusNode.unfocus();
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Increase',
                  icon: const Icon(Icons.add_rounded, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _focusNode.unfocus();
                    ProductVariant? matchedVariant;
                    if (widget.item.variantName != null) {
                      final matches = widget.item.product.variants
                          .where((v) => v.name == widget.item.variantName)
                          .toList();
                      if (matches.isNotEmpty) {
                        matchedVariant = matches.first;
                      }
                    }
                    cart.addItem(widget.item.product, variant: matchedVariant);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSummaryDialog extends StatefulWidget {
  final CartProvider cart;
  final void Function(
    double discount,
    double cash,
    String paymentMethod, {
    String? customerName,
  }) onComplete;

  const _PaymentSummaryDialog({
    required this.cart,
    required this.onComplete,
  });

  @override
  State<_PaymentSummaryDialog> createState() => _PaymentSummaryDialogState();
}

class _PaymentSummaryDialogState extends State<_PaymentSummaryDialog> {
  late final TextEditingController _cashController;
  late final TextEditingController _discountController;
  late final TextEditingController _customerNameController;
  double _currentDiscount = 0.0;
  double _currentCash = 0.0;
  String _paymentMethod = 'cash'; // 'cash', 'gcash', 'pending'

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController();
    _discountController = TextEditingController();
    _customerNameController = TextEditingController();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _discountController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  void _applyQuickCash(double amount) {
    HapticFeedback.selectionClick();
    final formatted = amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    setState(() {
      _cashController.text = formatted;
      _currentCash = amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = widget.cart.totalAmount;
    final clampedDiscount = _currentDiscount.clamp(0.0, subtotal);
    final total = subtotal - clampedDiscount;
    final diff = _currentCash - total;
    final change = diff > 0 ? diff : 0.0;

    final bool isReady = _paymentMethod == 'gcash'
        ? total > 0
        : (_paymentMethod == 'pending'
            ? total > 0
            : (_currentCash >= total && total > 0));

    final quickBills = <double>{
      total,
      if (total <= 50) 50,
      if (total <= 100) 100,
      if (total <= 200) 200,
      if (total <= 500) 500,
      if (total <= 1000) 1000,
    }.toList()
      ..sort();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog Header
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Checkout',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Total Due Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.subtleSurface(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtotal (${widget.cart.itemCount} items)',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.mutedText(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '₱${subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Due',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '₱${NumberFormat('#,##0.00').format(total)}',
                          style: const TextStyle(
                            fontSize: 26,
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
              const SizedBox(height: 16),

              // Payment Mode Toggle (Radio Buttons)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.subtleSurface(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        label: 'Cash',
                        icon: Icons.payments_rounded,
                        isActive: _paymentMethod == 'cash',
                        activeColor: AppTheme.accentOrange,
                        onTap: () => setState(() => _paymentMethod = 'cash'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ModeButton(
                        label: 'GCash',
                        icon: Icons.account_balance_wallet_rounded,
                        isActive: _paymentMethod == 'gcash',
                        activeColor: const Color(0xFF007DFE),
                        onTap: () => setState(() => _paymentMethod = 'gcash'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ModeButton(
                        label: 'Pending',
                        icon: Icons.schedule_rounded,
                        isActive: _paymentMethod == 'pending',
                        activeColor: AppTheme.accentAmber,
                        onTap: () => setState(() {
                          _paymentMethod = 'pending';
                          _cashController.clear();
                          _currentCash = 0.0;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Optional Discount Input
              TextField(
                controller: _discountController,
                decoration: const InputDecoration(
                  labelText: 'Discount (₱ Optional)',
                  prefixIcon: Icon(Icons.local_offer_outlined, size: 19),
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  setState(() {
                    _currentDiscount = double.tryParse(val) ?? 0.0;
                  });
                },
              ),
              const SizedBox(height: 16),

              if (_paymentMethod == 'cash') ...[
                TextField(
                  controller: _cashController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Cash Tendered (₱)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (val) {
                    setState(() {
                      _currentCash = double.tryParse(val) ?? 0.0;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Quick Denomination Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickBills.map((bill) {
                    final isExact = (bill - total).abs() < 0.005;
                    final label = isExact
                        ? 'Exact'
                        : '₱${bill.toStringAsFixed(0)}';
                    final isSelected = (_currentCash - bill).abs() < 0.005 &&
                        _cashController.text.isNotEmpty;
                    return ActionChip(
                      label: Text(label),
                      onPressed: () => _applyQuickCash(bill),
                      backgroundColor: isSelected
                          ? AppTheme.accentOrange.withValues(alpha: 0.14)
                          : theme.cardTheme.color,
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.accentOrange
                            : AppTheme.borderColor(context),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppTheme.accentOrange
                            : theme.colorScheme.onSurface,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Live Change / Balance Callout
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: (_currentCash >= total || _currentCash == 0)
                        ? AppTheme.accentTeal.withValues(alpha: 0.1)
                        : AppTheme.accentRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: (_currentCash >= total || _currentCash == 0)
                          ? AppTheme.accentTeal.withValues(alpha: 0.3)
                          : AppTheme.accentRose.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        (_currentCash > 0 && _currentCash < total)
                            ? 'Amount Short'
                            : 'Change Due',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (_currentCash > 0 && _currentCash < total)
                              ? AppTheme.accentRose
                              : AppTheme.accentTeal,
                        ),
                      ),
                      Text(
                        (_currentCash > 0 && _currentCash < total)
                            ? '₱${(total - _currentCash).toStringAsFixed(2)}'
                            : '₱${change.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: (_currentCash > 0 && _currentCash < total)
                              ? AppTheme.accentRose
                              : AppTheme.accentTeal,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    final hasQr = settings.gcashQrPath.isNotEmpty &&
                        File(settings.gcashQrPath).existsSync();
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (settings.gcashNumber.trim().isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  settings.gcashNumber,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.accentIndigo,
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy GCash number',
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: settings.gcashNumber),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('GCash number copied'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          if (hasQr)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                File(settings.gcashQrPath),
                                height: 190,
                                width: 190,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              height: 130,
                              width: 130,
                              decoration: BoxDecoration(
                                color: theme.cardTheme.color,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.borderColor(context),
                                ),
                              ),
                              child: Icon(
                                Icons.qr_code_2_rounded,
                                size: 56,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            'Confirm GCash reference before completing sale.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedText(context),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              if (_paymentMethod == 'pending') ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentAmber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: AppTheme.accentAmber.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.accentAmber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: AppTheme.accentAmber,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Payment (Utang)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentAmber,
                                  ),
                                ),
                                Text(
                                  'Order will be saved with an unpaid balance.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _customerNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Customer Name (Optional)',
                          hintText: 'e.g. Juan dela Cruz',
                          prefixIcon:
                              Icon(Icons.person_outline_rounded, size: 20),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cashController,
                        decoration: const InputDecoration(
                          labelText: 'Initial Downpayment (₱ Optional)',
                          hintText: '0.00 (Leave blank for full utang)',
                          prefixIcon: Icon(Icons.payments_outlined, size: 20),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (val) {
                          setState(() {
                            _currentCash = double.tryParse(val) ?? 0.0;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.borderColor(context)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Unpaid Balance (Utang):',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₱${NumberFormat('#,##0.00').format((total - _currentCash).clamp(0.0, total))}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentAmber,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: isReady
                    ? () {
                        final cash = (_paymentMethod == 'cash' ||
                                _paymentMethod == 'pending')
                            ? (double.tryParse(_cashController.text) ?? 0.0)
                            : 0.0;
                        final customer = _customerNameController.text.trim();
                        Navigator.pop(context);
                        widget.onComplete(
                          clampedDiscount,
                          cash,
                          _paymentMethod,
                          customerName: customer.isNotEmpty ? customer : null,
                        );
                      }
                    : null,
                icon: Icon(
                  _paymentMethod == 'pending'
                      ? Icons.schedule_send_rounded
                      : Icons.check_circle_rounded,
                  size: 20,
                ),
                label: Text(
                  _paymentMethod == 'gcash'
                      ? 'Complete GCash Sale'
                      : (_paymentMethod == 'pending'
                          ? (_currentCash > 0
                              ? 'Complete with ₱${_currentCash.toStringAsFixed(2)} Downpayment'
                              : 'Complete Pending Sale')
                          : 'Complete Cash Sale'),
                ),
                style: _paymentMethod == 'pending'
                    ? ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentAmber,
                        foregroundColor: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = activeColor ?? AppTheme.accentOrange;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? effectiveColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: effectiveColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Subtle modern radio dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive
                        ? Colors.white
                        : AppTheme.mutedText(context).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: isActive
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 5),
              Icon(
                icon,
                color: isActive ? Colors.white : AppTheme.mutedText(context),
                size: 15,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onAddBase;
  final void Function(ProductVariant variant) onSelectVariant;

  const _PosProductCard({
    required this.product,
    required this.onAddBase,
    required this.onSelectVariant,
  });

  @override
  State<_PosProductCard> createState() => _PosProductCardState();
}

class _PosProductCardState extends State<_PosProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOutOfStock = widget.product.stock <= 0;
    final isLowStock = widget.product.stock > 0 && widget.product.stock <= 5;
    final statusColor = isOutOfStock
        ? AppTheme.accentRose
        : (isLowStock ? AppTheme.accentAmber : AppTheme.accentTeal);
    final statusLabel = isOutOfStock
        ? 'Out of stock'
        : (isLowStock
            ? '${widget.product.stock} low'
            : '${widget.product.stock} in stock');

    final inCartQty = context.select<CartProvider, int>(
      (cart) => cart.items.values
          .where((item) => item.product.id == widget.product.id)
          .fold<int>(0, (sum, item) => sum + item.quantity),
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactCard = screenWidth < 360;
    final thumbSize = isCompactCard ? 48.0 : 62.0;

    return Semantics(
      button: !isOutOfStock,
      enabled: !isOutOfStock,
      label:
          '${widget.product.name}, ₱${widget.product.price.toStringAsFixed(2)}, $statusLabel${inCartQty > 0 ? ', $inCartQty in order' : ''}',
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: inCartQty > 0
                  ? AppTheme.accentOrange
                  : AppTheme.borderColor(context),
              width: inCartQty > 0 ? 1.6 : 1.0,
            ),
            boxShadow: AppTheme.cardShadow(context),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              onTapDown: isOutOfStock ? null : (_) => _controller.forward(),
              onTapUp: isOutOfStock ? null : (_) => _controller.reverse(),
              onTapCancel: isOutOfStock ? null : () => _controller.reverse(),
              onTap: isOutOfStock ? null : () => _handleProductTap(context),
              child: Padding(
                padding: EdgeInsets.all(isCompactCard ? 8 : 12),
                child: Row(
                  children: [
                    // Product Thumbnail (matches Inventory card)
                    Opacity(
                      opacity: isOutOfStock ? 0.5 : 1.0,
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface(context),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMd),
                          border: Border.all(
                            color: AppTheme.borderColor(context)
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: ProductImageView(
                          imagePath: widget.product.imagePath,
                          fit: BoxFit.cover,
                          placeholder: Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.mutedText(context),
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isCompactCard ? 8 : 14),

                    // Product Identity & Metadata
                    Expanded(
                      child: Opacity(
                        opacity: isOutOfStock ? 0.6 : 1.0,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.product.name,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: isCompactCard ? 13.5 : 15,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  widget.product.category?.isNotEmpty == true
                                      ? widget.product.category!
                                      : 'Uncategorized',
                                  style: TextStyle(
                                    fontSize: isCompactCard ? 11 : 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.mutedText(context),
                                  ),
                                ),
                                if (widget.product.variants.isNotEmpty) ...[
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                  Text(
                                    '${widget.product.variants.length + 1} options',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.accentIndigo,
                                    ),
                                  ),
                                ],
                                if (widget.product.barcode != null &&
                                    widget.product.barcode!.isNotEmpty) ...[
                                  Icon(
                                    Icons.qr_code_rounded,
                                    size: 13,
                                    color: AppTheme.mutedText(context),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isCompactCard ? 6 : 8),

                    // Price & Stock Status (matches Inventory card)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₱${widget.product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isOutOfStock
                                ? AppTheme.mutedText(context)
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: isCompactCard ? 13.5 : 15,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompactCard ? 6 : 8,
                            vertical: isCompactCard ? 2 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isCompactCard
                                ? (isOutOfStock
                                    ? 'Out'
                                    : (isLowStock
                                        ? '${widget.product.stock} low'
                                        : '${widget.product.stock} left'))
                                : statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: isCompactCard ? 10 : 11,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: isCompactCard ? 6 : 10),

                    // Add / In-Cart Quantity Badge
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      constraints: BoxConstraints(
                        minWidth: isCompactCard ? 30 : 34,
                        minHeight: isCompactCard ? 30 : 34,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: inCartQty > 0 ? (isCompactCard ? 7 : 9) : (isCompactCard ? 5 : 7),
                        vertical: isCompactCard ? 5 : 7,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isOutOfStock
                            ? AppTheme.subtleSurface(context)
                            : inCartQty > 0
                                ? AppTheme.accentOrange
                                : AppTheme.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOutOfStock
                              ? AppTheme.borderColor(context)
                              : inCartQty > 0
                                  ? AppTheme.accentOrange
                                  : AppTheme.accentOrange
                                      .withValues(alpha: 0.28),
                        ),
                      ),
                      child: inCartQty > 0
                          ? Text(
                              '$inCartQty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            )
                          : Icon(
                              isOutOfStock
                                  ? Icons.block_rounded
                                  : Icons.add_rounded,
                              color: isOutOfStock
                                  ? AppTheme.mutedText(context)
                                  : AppTheme.accentOrange,
                              size: 18,
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

  void _handleProductTap(BuildContext context) {
    if (widget.product.variants.isEmpty) {
      widget.onAddBase();
      return;
    }

    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.borderColor(ctx)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.borderColor(ctx),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.product.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Choose an option to add to order',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedText(ctx),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _VariantOptionTile(
                    label: 'Standard / Base',
                    price: widget.product.price,
                    stock: widget.product.stock,
                    imagePath: widget.product.imagePath,
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onAddBase();
                    },
                  ),
                  ...widget.product.variants.map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _VariantOptionTile(
                        label: v.name,
                        price: v.price,
                        stock: v.stock,
                        imagePath: v.hasValidImage
                            ? v.imagePath
                            : widget.product.imagePath,
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onSelectVariant(v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantOptionTile extends StatelessWidget {
  final String label;
  final double price;
  final int? stock;
  final String? imagePath;
  final VoidCallback onTap;

  const _VariantOptionTile({
    required this.label,
    required this.price,
    this.stock,
    this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.subtleSurface(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(8),
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
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (stock != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        stock! > 0 ? 'Stock: $stock' : 'Out of stock',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: stock! <= 5
                              ? AppTheme.accentRose
                              : AppTheme.mutedText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '₱${price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.accentOrange,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.add_circle_rounded,
                color: AppTheme.accentOrange,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
