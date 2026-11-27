import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../services/pdf_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/product_image_view.dart';
import '../widgets/order_details_modal.dart';
import '../widgets/skeleton.dart';
import 'add_edit_product_screen.dart';
import 'scanner_screen.dart';

enum StockFilter { all, inStock, lowStock, outOfStock }

enum InventorySort { nameAsc, stockLowFirst, priceHighFirst, profitHighFirst }

class ProductListScreen extends StatefulWidget {
  final ValueNotifier<StockFilter?>? filterRequest;

  const ProductListScreen({super.key, this.filterRequest});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  StockFilter _stockFilter = StockFilter.all;
  InventorySort _sortBy = InventorySort.nameAsc;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    widget.filterRequest?.addListener(_handleExternalFilter);
    if (widget.filterRequest?.value != null) {
      _stockFilter = widget.filterRequest!.value!;
      widget.filterRequest!.value = null;
    }
    Future.microtask(() {
      if (!mounted) return;
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void didUpdateWidget(covariant ProductListScreen oldWidget) {
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
        _stockFilter = requested;
        _selectedCategory = 'All';
        _searchQuery = '';
        _searchController.clear();
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
        builder: (_) => const ScannerScreen(title: 'Scan Product'),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final handled = await handleOrderBarcodeScan(context, code);
    if (handled || !mounted) return;
    setState(() {
      _searchController.text = code;
      _searchQuery = code;
    });
  }

  List<Product> _filterAndSort(List<Product> all) => _filterAndSortWith(
    all,
    stockFilter: _stockFilter,
    category: _selectedCategory,
    searchQuery: _searchQuery,
  );

  List<Product> _filterAndSortWith(
    List<Product> all, {
    required StockFilter stockFilter,
    required String category,
    String searchQuery = '',
  }) {
    Iterable<Product> result = all;

    if (category != 'All') {
      result = result.where((p) => p.category == category);
    }

    switch (stockFilter) {
      case StockFilter.inStock:
        result = result.where((p) => p.stock > 5);
        break;
      case StockFilter.lowStock:
        result = result.where((p) => p.stock > 0 && p.stock <= 5);
        break;
      case StockFilter.outOfStock:
        result = result.where((p) => p.stock <= 0);
        break;
      case StockFilter.all:
        break;
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result.where(
        (p) =>
            p.name.toLowerCase().contains(q) ||
            (p.category?.toLowerCase().contains(q) ?? false) ||
            (p.barcode?.toLowerCase().contains(q) ?? false),
      );
    }

    final list = result.toList();
    switch (_sortBy) {
      case InventorySort.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case InventorySort.stockLowFirst:
        list.sort((a, b) => a.stock.compareTo(b.stock));
        break;
      case InventorySort.priceHighFirst:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case InventorySort.profitHighFirst:
        list.sort((a, b) {
          final pa = a.unitProfit;
          final pb = b.unitProfit;
          if (pa == null && pb == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pb.compareTo(pa);
        });
        break;
    }
    return list;
  }

  String _stockFilterLabel(StockFilter filter) {
    switch (filter) {
      case StockFilter.all:
        return 'All Items';
      case StockFilter.inStock:
        return 'Healthy';
      case StockFilter.lowStock:
        return 'Low Stock';
      case StockFilter.outOfStock:
        return 'Out of Stock';
    }
  }

  Color _stockFilterColor(StockFilter filter) {
    switch (filter) {
      case StockFilter.all:
        return AppTheme.accentOrange;
      case StockFilter.inStock:
        return AppTheme.accentTeal;
      case StockFilter.lowStock:
        return AppTheme.accentAmber;
      case StockFilter.outOfStock:
        return AppTheme.accentRose;
    }
  }

  String _sortLabel(InventorySort sort) {
    switch (sort) {
      case InventorySort.nameAsc:
        return 'Name (A-Z)';
      case InventorySort.stockLowFirst:
        return 'Stock (Lowest first)';
      case InventorySort.priceHighFirst:
        return 'Price (Highest first)';
      case InventorySort.profitHighFirst:
        return 'Profit (Highest first)';
    }
  }

  String _inventoryExportFileName(StockFilter filter) {
    final slug = switch (filter) {
      StockFilter.all => 'All_Items',
      StockFilter.inStock => 'Healthy',
      StockFilter.lowStock => 'Low_Stock',
      StockFilter.outOfStock => 'Out_of_Stock',
    };
    final dateTag = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'TindaKo_Inventory_${slug}_$dateTag.pdf';
  }

  Future<void> _showExportInventoryPdfSheet({
    required BuildContext context,
    required List<Product> allProducts,
    required List<String> categories,
  }) async {
    StockFilter exportFilter = _stockFilter;
    String exportCategory = _selectedCategory;
    bool isExporting = false;
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final theme = Theme.of(modalCtx);
            final categoryFilteredBase = exportCategory == 'All'
                ? allProducts
                : allProducts
                      .where((p) => p.category == exportCategory)
                      .toList();
            final exportProducts = _filterAndSortWith(
              allProducts,
              stockFilter: exportFilter,
              category: exportCategory,
              searchQuery: _searchQuery,
            );

            int countFor(StockFilter f) {
              return _filterAndSortWith(
                categoryFilteredBase,
                stockFilter: f,
                category: 'All',
                searchQuery: _searchQuery,
              ).length;
            }

            final totalUnits = exportProducts.fold<double>(
              0.0,
              (sum, p) => sum + p.stock,
            );
            final retailValue = exportProducts.fold<double>(
              0.0,
              (sum, p) => sum + p.stockRetailValue,
            );
            final hasCostData = exportProducts.any((p) => p.costPrice != null);
            final potentialProfit = exportProducts.fold<double>(
              0.0,
              (sum, p) => sum + (p.potentialStockProfit ?? 0.0),
            );

            Future<void> runExport({required bool saveToFile}) async {
              if (isExporting || exportProducts.isEmpty) return;
              setModalState(() => isExporting = true);
              try {
                final settings = context.read<SettingsProvider>();
                final filterLabel = _stockFilterLabel(exportFilter);
                final fileName = _inventoryExportFileName(exportFilter);

                if (saveToFile) {
                  final saved = await PdfService.saveOrShareInventoryReport(
                    products: exportProducts,
                    filterLabel: filterLabel,
                    sortLabel: _sortLabel(_sortBy),
                    categoryLabel: exportCategory,
                    storeName: settings.storeName,
                    storeAddress: settings.storeAddress,
                    storePhone: settings.storePhone,
                    fileName: fileName,
                  );
                  if (saved != null && modalCtx.mounted) {
                    Navigator.of(sheetCtx).pop();
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        message: saved == 'shared'
                            ? 'Inventory ($filterLabel) PDF ready to share'
                            : 'Saved PDF: $fileName',
                      );
                    }
                  }
                } else {
                  Navigator.of(sheetCtx).pop();
                  await PdfService.generateInventoryReport(
                    products: exportProducts,
                    filterLabel: filterLabel,
                    sortLabel: _sortLabel(_sortBy),
                    categoryLabel: exportCategory,
                    storeName: settings.storeName,
                    storeAddress: settings.storeAddress,
                    storePhone: settings.storePhone,
                    fileName: fileName,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  AppToast.show(
                    context,
                    message: 'Failed to export PDF: $e',
                    isError: true,
                  );
                }
              } finally {
                if (modalCtx.mounted) {
                  setModalState(() => isExporting = false);
                }
              }
            }

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.88,
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppTheme.borderColor(sheetCtx),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentOrange.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: AppTheme.accentOrange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Export Inventory PDF',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Export All Items, Healthy, Low Stock, or Out of Stock',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
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
                          const SizedBox(height: 16),

                          Text(
                            'STOCK FILTER',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppTheme.mutedText(sheetCtx),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: StockFilter.values.map((filter) {
                              final selected = exportFilter == filter;
                              final accent = _stockFilterColor(filter);
                              final count = countFor(filter);
                              return ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                selected: selected,
                                showCheckmark: false,
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => exportFilter = filter);
                                },
                                selectedColor: accent,
                                backgroundColor:
                                    AppTheme.subtleSurface(sheetCtx),
                                side: BorderSide(
                                  color: selected
                                      ? accent
                                      : AppTheme.borderColor(sheetCtx),
                                ),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: selected ? Colors.white : accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text('${_stockFilterLabel(filter)} ($count)'),
                                  ],
                                ),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              );
                            }).toList(),
                          ),

                          if (categories.length > 1) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Text(
                                  'Category:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.mutedText(sheetCtx),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.subtleSurface(sheetCtx),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.borderColor(sheetCtx),
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: categories.contains(exportCategory)
                                            ? exportCategory
                                            : 'All',
                                        isExpanded: true,
                                        isDense: true,
                                        items: categories
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(
                                                  c == 'All'
                                                      ? 'All Categories'
                                                      : c,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(
                                              () => exportCategory = val,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),

                          // Live Preview Summary
                          if (exportProducts.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
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
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: AppTheme.accentAmber,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No products match this stock filter. Pick another filter or category.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(sheetCtx),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderColor(sheetCtx),
                                ),
                              ),
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 8,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Products / Units',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.mutedText(sheetCtx),
                                        ),
                                      ),
                                      Text(
                                        '${exportProducts.length} items · ${formatQuantity(totalUnits)} units',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Retail Value',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.mutedText(sheetCtx),
                                        ),
                                      ),
                                      Text(
                                        '₱${NumberFormat('#,##0.00').format(retailValue)}',
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.accentOrange,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (hasCostData)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Potential Profit',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.mutedText(sheetCtx),
                                          ),
                                        ),
                                        Text(
                                          '${potentialProfit < 0 ? '-' : '+'}₱${NumberFormat('#,##0.00').format(potentialProfit.abs())}',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: potentialProfit < 0
                                                ? AppTheme.accentRose
                                                : AppTheme.accentTeal,
                                            fontFeatures:
                                                AppTheme.tabularFigures,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 18),

                          // Export Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      (isExporting || exportProducts.isEmpty)
                                      ? null
                                      : () => runExport(saveToFile: true),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    foregroundColor: AppTheme.accentOrange,
                                    side: BorderSide(
                                      color: AppTheme.accentOrange.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    isDesktop
                                        ? Icons.download_rounded
                                        : Icons.share_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    isDesktop ? 'Save PDF' : 'Share PDF',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (isExporting || exportProducts.isEmpty)
                                      ? null
                                      : () => runExport(saveToFile: false),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                  ),
                                  icon: isExporting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.print_rounded,
                                          size: 18,
                                        ),
                                  label: const Text('Print / Preview'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedCategory = 'All';
      _stockFilter = StockFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ProductProvider>();
    final allProducts = provider.allProducts;
    final categories = provider.categories;

    // Reset category if deleted
    if (_selectedCategory != 'All' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final filtered = _filterAndSort(allProducts);
    final lowCount = allProducts.where((p) => p.stock > 0 && p.stock <= 5).length;
    final outCount = allProducts.where((p) => p.stock <= 0).length;
    final inStockCount = allProducts.where((p) => p.stock > 5).length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final horizontalPadding = isCompact ? 12.0 : 20.0;
    final isWide = screenWidth >= 760;

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.accentOrange,
        onRefresh: () => context.read<ProductProvider>().refreshProducts(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Clean App Bar ──
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 68,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  titleSpacing: isCompact ? 14 : 20,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Flexible(
                        child: Text(
                          'Inventory',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Text(
                          '${allProducts.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mutedText(context),
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    PopupMenuButton<InventorySort>(
                      tooltip: 'Sort products',
                      initialValue: _sortBy,
                      onSelected: (val) {
                        HapticFeedback.selectionClick();
                        setState(() => _sortBy = val);
                      },
                      icon: const Icon(Icons.swap_vert_rounded),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: InventorySort.nameAsc,
                          child: Text('Name (A–Z)'),
                        ),
                        PopupMenuItem(
                          value: InventorySort.stockLowFirst,
                          child: Text('Stock (Lowest first)'),
                        ),
                        PopupMenuItem(
                          value: InventorySort.priceHighFirst,
                          child: Text('Price (Highest first)'),
                        ),
                        PopupMenuItem(
                          value: InventorySort.profitHighFirst,
                          child: Text('Profit (Highest first)'),
                        ),
                      ],
                    ),
                    if (isCompact)
                      IconButton(
                        tooltip: 'Export PDF',
                        onPressed: allProducts.isEmpty
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                _showExportInventoryPdfSheet(
                                  context: context,
                                  allProducts: allProducts,
                                  categories: categories,
                                );
                              },
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: AppTheme.accentOrange,
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.only(
                          right: isWide ? 6 : 16,
                          left: 4,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: allProducts.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  _showExportInventoryPdfSheet(
                                    context: context,
                                    allProducts: allProducts,
                                    categories: categories,
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(0, isWide ? 42 : 38),
                            padding: EdgeInsets.symmetric(
                              horizontal: isWide ? 14 : 12,
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
                          label: Text(isWide ? 'Export PDF' : 'PDF'),
                        ),
                      ),
                    if (isWide)
                      Padding(
                        padding: const EdgeInsets.only(right: 20, left: 4),
                        child: ElevatedButton.icon(
                          onPressed: () => _navigateToAdd(context),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add Product'),
                        ),
                      )
                    else if (isCompact)
                      const SizedBox(width: 4),
                  ],
                ),

                // ── Stock Health Filter Strip ──
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        _StatusFilterChip(
                          label: 'All Items',
                          count: allProducts.length,
                          color: AppTheme.accentOrange,
                          isSelected: _stockFilter == StockFilter.all,
                          onTap: () => setState(() => _stockFilter = StockFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Healthy',
                          count: inStockCount,
                          color: AppTheme.accentTeal,
                          isSelected: _stockFilter == StockFilter.inStock,
                          onTap: () =>
                              setState(() => _stockFilter = StockFilter.inStock),
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Low Stock',
                          count: lowCount,
                          color: AppTheme.accentAmber,
                          isSelected: _stockFilter == StockFilter.lowStock,
                          onTap: () =>
                              setState(() => _stockFilter = StockFilter.lowStock),
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Out of Stock',
                          count: outCount,
                          color: AppTheme.accentRose,
                          isSelected: _stockFilter == StockFilter.outOfStock,
                          onTap: () =>
                              setState(() => _stockFilter = StockFilter.outOfStock),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Search & Barcode Bar ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                            },
                            onSubmitted: (value) async {
                              if (parseOrderBarcode(value) != null) {
                                final handled = await handleOrderBarcodeScan(context, value);
                                if (handled && mounted) {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                }
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Search product, category, or barcode...',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: AppTheme.mutedText(context),
                                size: 20,
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
                        Material(
                          color: theme.cardTheme.color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            side: BorderSide(color: AppTheme.borderColor(context)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                      ],
                    ),
                  ),
                ),

                // ── Category Filter Chips ──
                if (categories.length > 1)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 4),
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
                  ),

                // ── Product List / Grid ──
                if (provider.isLoading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 96),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, _) => const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Skeleton(height: 88, borderRadius: 16),
                        ),
                        childCount: 6,
                      ),
                    ),
                  )
                else if (allProducts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyInventoryState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Your inventory is empty',
                      subtitle:
                          'Add your store products, prices, and barcodes to start selling.',
                      actionLabel: 'Add First Product',
                      onAction: () => _navigateToAdd(context),
                    ),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyInventoryState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'No matching products',
                      subtitle:
                          'Try adjusting your search query, category, or stock filter.',
                      actionLabel: 'Reset Filters',
                      onAction: _resetFilters,
                    ),
                  )
                else if (isWide)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 96),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent:
                            MediaQuery.sizeOf(context).width >= 1140 ? 420 : 480,
                        mainAxisExtent: 112,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = filtered[index];
                          return _InventoryProductCard(
                            product: product,
                            onEdit: () => _navigateToEdit(context, product),
                            onDelete: () => _confirmDelete(context, product),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 96),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = filtered[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InventoryProductCard(
                              product: product,
                              onEdit: () => _navigateToEdit(context, product),
                              onDelete: () => _confirmDelete(context, product),
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
              heroTag: 'product_list_fab',
              onPressed: () => _navigateToAdd(context),
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Product',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  void _navigateToAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddEditProductScreen()),
    );
  }

  void _navigateToEdit(BuildContext context, Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEditProductScreen(product: product),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Product product) {
    final auth = context.read<AuthProvider>();
    final TextEditingController pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Delete Product?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remove "${product.name}" from your inventory? Past sales records will be preserved.',
              ),
              if (auth.currentUser?.hasPin == true) ...[
                const SizedBox(height: 16),
                const Text(
                  'Enter account PIN to authorize deletion:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: '••••',
                    errorText: pinError,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final authProvider = context.read<AuthProvider>();
                final prodProvider = context.read<ProductProvider>();
                final messenger = ScaffoldMessenger.of(context);

                if (auth.currentUser?.hasPin == true) {
                  final entered = pinController.text.trim();
                  if (entered.isEmpty) {
                    setDialogState(() => pinError = 'PIN required');
                    return;
                  }
                  final ok = await authProvider.verifyPin(entered);
                  if (!ok) {
                    setDialogState(() => pinError = 'Incorrect PIN');
                    return;
                  }
                }
                try {
                  await prodProvider.deleteProduct(product.id!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Removed "${product.name}"')),
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    setDialogState(() => pinError = e.toString().replaceFirst('Exception: ', ''));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentRose,
                minimumSize: const Size(96, 44),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusFilterChip({
    required this.label,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? color.withValues(alpha: 0.12)
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: isSelected ? color : AppTheme.borderColor(context),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? color : AppTheme.mutedText(context),
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InventoryProductCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = product.stock <= 0;
    final isLow = product.stock > 0 && product.stock <= 5;
    final statusColor = isOut
        ? AppTheme.accentRose
        : (isLow ? AppTheme.accentAmber : AppTheme.accentTeal);
    final statusLabel = isOut
        ? 'Out of stock'
        : (isLow ? '${formatQuantity(product.stock)} low' : '${formatQuantity(product.stock)} in stock');

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactCard = screenWidth < 400;
    final thumbSize = isCompactCard ? 48.0 : 62.0;

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
          onTap: onEdit,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: EdgeInsets.fromLTRB(isCompactCard ? 8 : 12, 10, isCompactCard ? 2 : 6, 10),
            child: Row(
              children: [
                // Product Thumbnail
                Container(
                  width: thumbSize,
                  height: thumbSize,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.subtleSurface(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: AppTheme.borderColor(context).withValues(alpha: 0.6),
                    ),
                  ),
                  child: ProductImageView(
                    imagePath: product.imagePath,
                    fit: BoxFit.cover,
                    placeholder: Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.mutedText(context),
                      size: 26,
                    ),
                  ),
                ),
                SizedBox(width: isCompactCard ? 8 : 14),

                // Product Identity & Metadata
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
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
                            product.category?.isNotEmpty == true
                                ? product.category!
                                : 'Uncategorized',
                            style: TextStyle(
                              fontSize: isCompactCard ? 11 : 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.mutedText(context),
                            ),
                          ),
                          if (product.variants.isNotEmpty) ...[
                            Text(
                              '•',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            Text(
                              '${product.variants.length} variants',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentIndigo,
                              ),
                            ),
                          ],
                          if (product.barcode != null &&
                              product.barcode!.isNotEmpty) ...[
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
                SizedBox(width: isCompactCard ? 6 : 8),

                // Price, Cost/Profit & Stock Status
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: isCompactCard ? 13.5 : 15,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    if (product.costPrice != null && product.unitProfit != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        isCompactCard
                            ? '${product.unitProfit! < 0 ? '-' : '+'}₱${product.unitProfit!.abs().toStringAsFixed(2)}'
                            : 'Cost ₱${product.costPrice!.toStringAsFixed(2)} · ${product.unitProfit! < 0 ? '-' : '+'}₱${product.unitProfit!.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          color: product.unitProfit! < 0
                              ? AppTheme.accentRose
                              : AppTheme.accentTeal,
                          fontWeight: FontWeight.w700,
                          fontSize: isCompactCard ? 10 : 11,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
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
                            ? (isOut
                                ? 'Out'
                                : (isLow ? '${formatQuantity(product.stock)} low' : '${formatQuantity(product.stock)} left'))
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

                // Accessible Action Menu (48dp touch target)
                PopupMenuButton<String>(
                  tooltip: 'Product options',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: AppTheme.mutedText(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit Product'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.accentRose,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.accentRose),
                          ),
                        ],
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
}

class _EmptyInventoryState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyInventoryState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppTheme.accentOrange),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppTheme.mutedText(context),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
