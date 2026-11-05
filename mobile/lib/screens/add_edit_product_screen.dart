import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/product_image_view.dart';
import 'scanner_screen.dart';

class AddEditProductScreen extends StatefulWidget {
  final Product? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _barcodeController;
  String? _selectedImagePath;
  final List<_VariantField> _variantFields = [];
  bool _isSaving = false;

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _categoryController = TextEditingController(
      text: widget.product?.category ?? '',
    );
    _priceController = TextEditingController(
      text: widget.product != null
          ? (widget.product!.price % 1 == 0
                ? widget.product!.price.toStringAsFixed(0)
                : widget.product!.price.toString())
          : '',
    );
    _stockController = TextEditingController(
      text: widget.product?.stock.toString() ?? '',
    );
    _barcodeController = TextEditingController(
      text: widget.product?.barcode ?? '',
    );
    _selectedImagePath = widget.product?.imagePath;

    if (widget.product?.variants != null) {
      for (final variant in widget.product!.variants) {
        _variantFields.add(
          _VariantField(
            nameController: TextEditingController(text: variant.name),
            priceController: TextEditingController(
              text: variant.price.toString(),
            ),
            stockController: TextEditingController(
              text: variant.stock != null ? variant.stock.toString() : '',
            ),
            imagePath: variant.imagePath,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    for (final field in _variantFields) {
      field.dispose();
    }
    super.dispose();
  }

  void _addVariant() {
    HapticFeedback.selectionClick();
    setState(() {
      _variantFields.add(
        _VariantField(
          nameController: TextEditingController(),
          priceController: TextEditingController(),
          stockController: TextEditingController(),
        ),
      );
    });
  }

  void _removeVariant(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _variantFields[index].dispose();
      _variantFields.removeAt(index);
    });
  }

  void _incrementStock(int delta) {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_stockController.text.trim()) ?? 0;
    final updated = (current + delta).clamp(0, 999999);
    setState(() {
      _stockController.text = '$updated';
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (pickedFile != null && mounted) {
      setState(() {
        _selectedImagePath = pickedFile.path;
      });
    }
  }

  Future<void> _pickVariantImage(int index, ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (pickedFile != null && mounted) {
      setState(() {
        _variantFields[index].imagePath = pickedFile.path;
      });
    }
  }

  void _showImagePickerSheet({
    required String title,
    required bool hasImage,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required VoidCallback onRemove,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.borderColor(ctx),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Text(
                title,
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(ctx);
                      onCamera();
                    },
                  ),
                  _ImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(ctx);
                      onGallery();
                    },
                  ),
                  if (hasImage)
                    _ImageSourceOption(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                      color: AppTheme.accentRose,
                      onTap: () {
                        Navigator.pop(ctx);
                        onRemove();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteProduct() {
    if (!isEditing || widget.product?.id == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete Product?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text('Remove "${widget.product!.name}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = context.read<ProductProvider>();
              final navigator = Navigator.of(context);
              Navigator.pop(ctx);
              await provider.deleteProduct(widget.product!.id!);
              if (mounted) navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
              minimumSize: const Size(96, 44),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValidMainImage = _selectedImagePath != null &&
        _selectedImagePath!.isNotEmpty &&
        (_selectedImagePath!.startsWith('http://') ||
            _selectedImagePath!.startsWith('https://') ||
            File(_selectedImagePath!).existsSync());

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'New Product'),
        actions: [
          if (isEditing)
            IconButton(
              onPressed: _confirmDeleteProduct,
              tooltip: 'Delete Product',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.accentRose,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. Photo & Identity Card ──
                  _FormSectionCard(
                    title: 'Product Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showImagePickerSheet(
                                title: 'Product Photo',
                                hasImage: hasValidMainImage,
                                onCamera: () => _pickImage(ImageSource.camera),
                                onGallery: () =>
                                    _pickImage(ImageSource.gallery),
                                onRemove: () =>
                                    setState(() => _selectedImagePath = null),
                              ),
                              child: Container(
                                width: 92,
                                height: 92,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: AppTheme.subtleSurface(context),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: AppTheme.borderColor(context),
                                  ),
                                ),
                                child: hasValidMainImage
                                    ? ProductImageView(
                                        imagePath: _selectedImagePath,
                                        fit: BoxFit.cover,
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.add_a_photo_outlined,
                                            color: AppTheme.accentOrange,
                                            size: 26,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Add Photo',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.mutedText(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Product Image',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Clear photos make items faster to spot at the POS register.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _showImagePickerSheet(
                                      title: 'Product Photo',
                                      hasImage: hasValidMainImage,
                                      onCamera: () =>
                                          _pickImage(ImageSource.camera),
                                      onGallery: () =>
                                          _pickImage(ImageSource.gallery),
                                      onRemove: () => setState(
                                        () => _selectedImagePath = null,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.upload_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      hasValidMainImage ? 'Change' : 'Upload',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Product Name
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Product Name',
                            hintText: 'e.g. Lucky Me Pancit Canton',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a product name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Category Autocomplete
                        Consumer<ProductProvider>(
                          builder: (context, provider, _) {
                            final existing = provider.categories
                                .where((c) => c != 'All')
                                .toList();
                            final presets = <String>{
                              ...existing,
                              'Snacks',
                              'Drinks',
                              'Canned Goods',
                              'Essentials',
                              'Personal Care',
                            }.toList();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Autocomplete<String>(
                                  initialValue: TextEditingValue(
                                    text: _categoryController.text,
                                  ),
                                  optionsBuilder: (textEditingValue) {
                                    if (textEditingValue.text.isEmpty) {
                                      return presets;
                                    }
                                    return presets.where(
                                      (option) => option.toLowerCase().contains(
                                        textEditingValue.text.toLowerCase(),
                                      ),
                                    );
                                  },
                                  onSelected: (selection) {
                                    setState(() {
                                      _categoryController.text = selection;
                                    });
                                  },
                                  fieldViewBuilder:
                                      (
                                        context,
                                        controller,
                                        focusNode,
                                        onFieldSubmitted,
                                      ) {
                                        if (controller.text !=
                                                _categoryController.text &&
                                            !focusNode.hasFocus) {
                                          controller.text =
                                              _categoryController.text;
                                        }
                                        return TextFormField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: const InputDecoration(
                                            labelText: 'Category',
                                            hintText: 'e.g. Drinks, Snacks',
                                            prefixIcon: Icon(
                                              Icons.category_outlined,
                                            ),
                                          ),
                                          textCapitalization:
                                              TextCapitalization.words,
                                          onChanged: (val) {
                                            _categoryController.text = val;
                                          },
                                          onFieldSubmitted: (_) =>
                                              onFieldSubmitted(),
                                        );
                                      },
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: presets.take(6).map((cat) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: ActionChip(
                                          label: Text(cat),
                                          visualDensity: VisualDensity.compact,
                                          labelStyle: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.mutedText(context),
                                          ),
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _categoryController.text = cat;
                                            });
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 2. Pricing, Stock & Barcode Card ──
                  _FormSectionCard(
                    title: 'Pricing & Inventory',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _priceController,
                                decoration: const InputDecoration(
                                  labelText: 'Selling Price (₱)',
                                  prefixIcon: Icon(Icons.payments_outlined),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  final parsed = double.tryParse(value);
                                  if (parsed == null || parsed < 0) {
                                    return 'Invalid price';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _stockController,
                                decoration: const InputDecoration(
                                  labelText: 'Stock Quantity',
                                  prefixIcon: Icon(Icons.layers_outlined),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  final parsed = int.tryParse(value);
                                  if (parsed == null || parsed < 0) {
                                    return 'Invalid qty';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Quick Restock Chips
                        Row(
                          children: [
                            Text(
                              'Quick add stock:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.mutedText(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [1, 5, 12, 24].map((step) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ActionChip(
                                        label: Text('+$step'),
                                        visualDensity: VisualDensity.compact,
                                        labelStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.accentTeal,
                                          fontFeatures: AppTheme.tabularFigures,
                                        ),
                                        side: BorderSide(
                                          color: AppTheme.accentTeal.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        backgroundColor: AppTheme.accentTeal
                                            .withValues(alpha: 0.08),
                                        onPressed: () => _incrementStock(step),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Barcode Field
                        TextFormField(
                          controller: _barcodeController,
                          decoration: InputDecoration(
                            labelText: 'Barcode / SKU (Optional)',
                            prefixIcon: const Icon(Icons.qr_code_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'Scan barcode',
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: AppTheme.accentOrange,
                              ),
                              onPressed: () async {
                                final code = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ScannerScreen(),
                                  ),
                                );
                                if (code != null && mounted) {
                                  setState(() {
                                    _barcodeController.text = code;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 3. Variants / Sub-prices Card ──
                  _FormSectionCard(
                    title: 'Variants & Sub-prices',
                    trailing: _variantFields.isNotEmpty
                        ? TextButton.icon(
                            onPressed: _addVariant,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Option'),
                          )
                        : null,
                    child: _variantFields.isEmpty
                        ? InkWell(
                            onTap: _addVariant,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurface(context),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: AppTheme.borderColor(context),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentOrange.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.tune_rounded,
                                      size: 22,
                                      color: AppTheme.accentOrange,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No variants added',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Optional: Add sizes, portions, or packaging options with separate prices & quantities.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 16,
                                          color: AppTheme.accentOrange,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Add First Option',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.accentOrange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...List.generate(_variantFields.length, (i) {
                                final field = _variantFields[i];
                                final hasVarImage = field.imagePath != null &&
                                    field.imagePath!.isNotEmpty &&
                                    (field.imagePath!.startsWith('http://') ||
                                        field.imagePath!.startsWith('https://') ||
                                        File(field.imagePath!).existsSync());

                                return Container(
                                  margin: EdgeInsets.only(
                                    bottom: i == _variantFields.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.subtleSurface(context),
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusMd,
                                    ),
                                    border: Border.all(
                                      color: AppTheme.borderColor(context),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // ── Option Header: Badge & Remove Action ──
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.accentOrange
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Option ${i + 1}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.accentOrange,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          InkWell(
                                            onTap: () => _removeVariant(i),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 16,
                                                    color: AppTheme.accentRose,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Remove',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          AppTheme.accentRose,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // ── Row 1: Variant Photo + Option Name ──
                                      Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showImagePickerSheet(
                                              title: 'Variant Photo',
                                              hasImage: hasVarImage,
                                              onCamera: () => _pickVariantImage(
                                                i,
                                                ImageSource.camera,
                                              ),
                                              onGallery: () =>
                                                  _pickVariantImage(
                                                    i,
                                                    ImageSource.gallery,
                                                  ),
                                              onRemove: () => setState(
                                                () => field.imagePath = null,
                                              ),
                                            ),
                                            child: Container(
                                              width: 46,
                                              height: 46,
                                              clipBehavior: Clip.antiAlias,
                                              decoration: BoxDecoration(
                                                color: theme.cardTheme.color,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: AppTheme.borderColor(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                              child: hasVarImage
                                                  ? ProductImageView(
                                                      imagePath:
                                                          field.imagePath,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons
                                                          .add_a_photo_outlined,
                                                      size: 18,
                                                      color:
                                                          AppTheme.accentOrange,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextFormField(
                                              controller: field.nameController,
                                              decoration: InputDecoration(
                                                labelText: 'Option Name',
                                                hintText:
                                                    'e.g. Small, 500ml, Per Kilo',
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    theme.cardTheme.color,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              textCapitalization:
                                                  TextCapitalization.words,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // ── Row 2: Price & Quantity Inputs ──
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: field.priceController,
                                              decoration: InputDecoration(
                                                labelText: 'Price',
                                                prefixText: '₱ ',
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    theme.cardTheme.color,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextFormField(
                                              controller: field.stockController,
                                              decoration: InputDecoration(
                                                labelText: 'Stock Qty',
                                                hintText: '0',
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    theme.cardTheme.color,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _addVariant,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentOrange,
                                  side: BorderSide(
                                    color: AppTheme.accentOrange.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusMd,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text(
                                  'Add Another Option',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
        ),
        child: SafeArea(
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProduct,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isEditing ? Icons.check_rounded : Icons.add_rounded,
                          ),
                    label: Text(
                      _isSaving
                          ? (isEditing ? 'Saving...' : 'Creating...')
                          : (isEditing ? 'Save Changes' : 'Create Product'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _saveProduct() async {
    if (_isSaving) return;

    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);

      try {
        final name = _nameController.text.trim();
        final category = _categoryController.text.trim();
        final price = double.parse(_priceController.text.trim());
        final stock = int.parse(_stockController.text.trim());
        final barcode = _barcodeController.text.trim();

        final auth = context.read<AuthProvider>();
        final userId = auth.currentUser?.id ?? 0;
        final provider = context.read<ProductProvider>();

        final variants = _variantFields
            .map(
              (f) => ProductVariant(
                name: f.nameController.text.trim(),
                price: double.tryParse(f.priceController.text.trim()) ?? 0.0,
                stock: int.tryParse(f.stockController.text.trim()),
                imagePath: f.imagePath,
              ),
            )
            .where((v) => v.name.isNotEmpty)
            .toList();

        final product = Product(
          id: widget.product?.id,
          userId: userId,
          name: name,
          category: category.isEmpty ? null : category,
          price: price,
          stock: stock,
          barcode: barcode.isEmpty ? null : barcode,
          imagePath: _selectedImagePath,
          variants: variants,
          createdAt: widget.product?.createdAt ?? DateTime.now(),
        );

        if (isEditing) {
          await provider.updateProduct(product);
        } else {
          await provider.addProduct(product);
        }

        if (mounted) {
          HapticFeedback.mediumImpact();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    isEditing
                        ? 'Product updated successfully'
                        : 'Product added to inventory',
                  ),
                ],
              ),
              backgroundColor: AppTheme.accentTeal,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save product: $e'),
              backgroundColor: AppTheme.accentRose,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }
}

class _FormSectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _FormSectionCard({
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppTheme.accentOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Icon(icon, color: themeColor, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantField {
  TextEditingController? _nameController;
  TextEditingController? _priceController;
  TextEditingController? _stockController;
  String? imagePath;

  TextEditingController get nameController =>
      _nameController ??= TextEditingController();
  TextEditingController get priceController =>
      _priceController ??= TextEditingController();
  TextEditingController get stockController =>
      _stockController ??= TextEditingController();

  _VariantField({
    TextEditingController? nameController,
    TextEditingController? priceController,
    TextEditingController? stockController,
    this.imagePath,
  }) : _nameController = nameController,
       _priceController = priceController,
       _stockController = stockController;

  void dispose() {
    _nameController?.dispose();
    _priceController?.dispose();
    _stockController?.dispose();
  }
}
