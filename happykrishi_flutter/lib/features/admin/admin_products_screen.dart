import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';
import '../../core/services/pdf_service.dart';
import '../../core/utils/firebase_storage_web.dart' if (dart.library.io) '../../core/utils/firebase_storage_stub.dart';

final adminProductsProvider =
    FutureProvider.autoDispose.family<List<Product>, String>((ref, key) async {
  // key = "search|categoryId|stock|isActive"
  final parts    = key.split('|');
  final search   = parts[0].isNotEmpty ? parts[0] : null;
  final catId    = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final stock    = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final isActive = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminProducts, queryParameters: {
    if (search   != null) 'search':      search,
    if (catId    != null) 'category_id': catId,
    if (stock    != null) 'stock':       stock,
    if (isActive != null) 'is_active':   isActive,
  });
  return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
});

final categoriesAdminProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  final dio = ref.read(dioProvider);
  // Use admin endpoint that returns ALL categories (including inactive)
  final res = await dio.get(Endpoints.adminCategories);
  return (res.data['categories'] as List).map((e) => Category.fromJson(e)).toList();
});

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});
  @override
  ConsumerState<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  int? _categoryFilter;
  String? _stockFilter;
  String? _activeFilter; // '' = all, '1' = active, '0' = inactive

  String get _providerKey =>
      '$_search|${_categoryFilter ?? ''}|${_stockFilter ?? ''}|${_activeFilter ?? ''}';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(adminProductsProvider(_providerKey));
    final categories = ref.watch(categoriesAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          // PDF export — exports currently filtered list
          if (products.value != null && products.value!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: () {
                final filterLabel = [
                  if (_search.isNotEmpty) '"$_search"',
                  if (_categoryFilter != null)
                    categories.value?.firstWhere((c) => c.id == _categoryFilter,
                        orElse: () => Category(id: 0, name: 'Category')).name ?? '',
                  if (_stockFilter != null) _stockFilter!,
                ].join(', ');
                PdfService.shareAdminProductsReport(
                  context: context,
                  products: products.value!,
                  title: filterLabel.isNotEmpty
                      ? 'Products — $filterLabel'
                      : 'All Products',
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(adminProductsProvider);
              ref.invalidate(categoriesAdminProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage Categories',
            onPressed: () => _showCategoryDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Product',
            onPressed: () => _showProductForm(context, ref, categories.value ?? []),
          ),
        ],
      ),
      body: Column(children: [
        // ── Search + filters ─────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Search bar
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search products…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              ),
            ),
            const SizedBox(height: 10),
            // Stock filter chips — wrapping
            Wrap(spacing: 6, runSpacing: 6, children: [
              _FilterChip(
                label: 'All',
                selected: _stockFilter == null && _categoryFilter == null && _activeFilter == null,
                onTap: () => setState(() { _stockFilter = null; _categoryFilter = null; _activeFilter = null; }),
              ),
              _FilterChip(
                label: '✅ Active',
                selected: _activeFilter == '1',
                color: AppColors.primary,
                onTap: () => setState(() => _activeFilter = _activeFilter == '1' ? null : '1'),
              ),
              _FilterChip(
                label: '🚫 Inactive',
                selected: _activeFilter == '0',
                color: Colors.grey,
                onTap: () => setState(() => _activeFilter = _activeFilter == '0' ? null : '0'),
              ),
              _FilterChip(
                label: '⚠️ Low stock',
                selected: _stockFilter == 'low',
                color: Colors.orange,
                onTap: () => setState(() => _stockFilter = _stockFilter == 'low' ? null : 'low'),
              ),
              _FilterChip(
                label: '❌ Out of stock',
                selected: _stockFilter == 'out',
                color: Colors.red,
                onTap: () => setState(() => _stockFilter = _stockFilter == 'out' ? null : 'out'),
              ),
              _FilterChip(
                label: '✅ In stock',
                selected: _stockFilter == 'ok',
                color: Colors.green,
                onTap: () => setState(() => _stockFilter = _stockFilter == 'ok' ? null : 'ok'),
              ),
            ]),
            // Category chips — wrapping
            if (categories.value != null && categories.value!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: categories.value!.map((c) => _FilterChip(
                  label: c.name,
                  selected: _categoryFilter == c.id,
                  color: AppColors.primary,
                  onTap: () => setState(() =>
                      _categoryFilter = _categoryFilter == c.id ? null : c.id),
                )).toList(),
              ),
            ],
            // Result count
            products.when(
              data: (list) {
                final hasFilter = _search.isNotEmpty || _stockFilter != null || _categoryFilter != null;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    hasFilter ? '${list.length} filtered products' : '${list.length} products',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
            ),
          ]),
        ),
        const Divider(height: 1),

        // ── Product list ─────────────────────────────────────────────────────
        Expanded(
          child: products.when(
            data: (list) {
              final noCats = (categories.value ?? []).isEmpty;
              if (list.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                      noCats ? Icons.category_outlined : Icons.inventory_2_outlined,
                      size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      noCats ? 'No categories yet' : 'No products yet',
                      style: const TextStyle(color: Colors.grey, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      noCats
                          ? 'Create a category first before adding products.'
                          : 'Tap + to add your first product.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    if (noCats)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Create Category'),
                        onPressed: () => _showCategoryDialog(context, ref),
                      )
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Product'),
                        onPressed: () => _showProductForm(context, ref, categories.value ?? []),
                      ),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(adminProductsProvider);
                  ref.invalidate(categoriesAdminProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final isLow  = p.stockQty > 0 && p.stockQty <= p.lowStockThreshold;
                    final isOut  = p.stockQty <= 0;
                    final stockColor = isOut ? Colors.red : isLow ? Colors.orange : AppColors.primary;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: p.isActive ? Colors.transparent : Colors.grey.shade300,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Row 1: image + name + price + active toggle
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _ProductImageAvatar(product: p,
                                onUploaded: () => ref.invalidate(adminProductsProvider)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: p.isActive ? Colors.black87 : Colors.grey,
                                    )),
                                const SizedBox(height: 2),
                                Text('₹${p.pricePerUnit.toStringAsFixed(0)} / ${p.unit}',
                                    style: const TextStyle(fontSize: 13, color: AppColors.primary,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            // Active toggle
                            Column(children: [
                              Switch(
                                value: p.isActive,
                                activeTrackColor: AppColors.primary,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) async {
                                  await ref.read(dioProvider).put(Endpoints.product(p.id),
                                      data: {'is_active': v ? 1 : 0});
                                  ref.invalidate(adminProductsProvider);
                                },
                              ),
                              Text(p.isActive ? 'Active' : 'Off',
                                  style: TextStyle(fontSize: 9,
                                      color: p.isActive ? AppColors.primary : Colors.grey)),
                            ]),
                          ]),

                          const SizedBox(height: 8),

                          // Row 2: category + stock + weight badge
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (p.categoryName != null)
                              _InfoBadge(Icons.category_outlined, p.categoryName!,
                                  AppColors.primary),
                            _InfoBadge(Icons.inventory_2_outlined,
                                'Stock: ${p.stockQty.toStringAsFixed(1)} ${p.unit}',
                                stockColor),
                            if (isOut)
                              _InfoBadge(Icons.block_outlined, 'Out of stock', Colors.red),
                            if (isLow && !isOut)
                              _InfoBadge(Icons.warning_amber_outlined, 'Low stock', Colors.orange),
                            if (p.isWeightAdjusted)
                              _InfoBadge(Icons.scale_outlined, 'Weight adjusted', Colors.indigo),
                          ]),

                          const SizedBox(height: 8),

                          // Row 3: action buttons
                          Row(children: [
                            _ActionButton(
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              color: Colors.blue.shade700,
                              onTap: () => _showProductForm(context, ref,
                                  categories.value ?? [], product: p),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.copy_outlined,
                              label: 'Duplicate',
                              color: Colors.purple.shade700,
                              onTap: () => _duplicateProduct(context, ref, p,
                                  categories.value ?? []),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) { logError('admin-products', e); return Center(child: Text(friendlyError(e))); },
          ),
        ),
      ]),
    );
  }

  Future<void> _duplicateProduct(
      BuildContext context, WidgetRef ref, Product p, List<Category> cats) async {
    // Open the product form pre-filled with source product data, but cleared name
    _showProductForm(
      context, ref, cats,
      product: Product(
        id: 0, // 0 signals new product in the form
        name: '${p.name} (Copy)',
        nameOdia: p.nameOdia,
        description: p.description,
        unit: p.unit,
        pricePerUnit: p.pricePerUnit,
        stockQty: p.stockQty,
        lowStockThreshold: p.lowStockThreshold,
        minQty: p.minQty,
        qtyStep: p.qtyStep,
        isWeightAdjusted: p.isWeightAdjusted,
        categoryId: p.categoryId,
        categoryName: p.categoryName,
        isActive: true,
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CategoryManager(
        onChanged: () => ref.invalidate(categoriesAdminProvider),
      ),
    );
  }

  void _showProductForm(BuildContext context, WidgetRef ref, List<Category> categories,
      {Product? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProductForm(
        product: product,
        categories: categories,
        onSaved: () {
          ref.invalidate(adminProductsProvider);
          ref.invalidate(categoriesAdminProvider);
        },
      ),
    );
  }
}

// ── Info badge ────────────────────────────────────────────────────────────────

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoBadge(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

// ── Tappable product avatar — tap to upload image directly from the list ──────

class _ProductImageAvatar extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback onUploaded;
  const _ProductImageAvatar({required this.product, required this.onUploaded});
  @override
  ConsumerState<_ProductImageAvatar> createState() => _ProductImageAvatarState();
}

class _ProductImageAvatarState extends ConsumerState<_ProductImageAvatar> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final filename = 'products/product_${widget.product.id}.$ext';
      final dio = ref.read(dioProvider);

      if (kIsWeb) {
        // Web: use JS bridge → Firebase REST API directly (Flutter SDK hangs on web)
        final resultJson = await uploadImageToFirebaseViaJs(bytes, filename, 'image/$ext');
        if (resultJson['success'] == true) {
          final firebaseUrl = resultJson['url'] as String;
          await dio.post(Endpoints.adminProductImageUrl(widget.product.id),
              data: {'url': firebaseUrl});
        } else {
          // Firebase JS failed — fall back to server upload
          final formData = FormData.fromMap({
            'image': MultipartFile.fromBytes(bytes, filename: picked.name),
          });
          await dio.post(Endpoints.adminProductImage(widget.product.id), data: formData);
        }
      } else {
        // Mobile: upload to Firebase Storage for permanent storage
        String downloadUrl;
        try {
          final storageRef = FirebaseStorage.instance.ref().child(filename);
          await storageRef.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
          downloadUrl = await storageRef.getDownloadURL();
          await dio.post(Endpoints.adminProductImageUrl(widget.product.id),
              data: {'url': downloadUrl});
        } catch (fbError) {
          // Firebase failed — fall back to server upload
          final formData = FormData.fromMap({
            'image': MultipartFile.fromBytes(bytes, filename: picked.name),
          });
          await dio.post(Endpoints.adminProductImage(widget.product.id), data: formData);
        }
      }

      widget.onUploaded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Image updated ✅'), backgroundColor: AppColors.primary));
      }
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.product.imageUrl;
    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      child: Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFEAF2EA),
          backgroundImage: imageUrl != null
              ? NetworkImage(imageUrl.startsWith('http') ? imageUrl : Endpoints.imageUrl(imageUrl))
              : null,
          child: _uploading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : imageUrl == null
                  ? Text(widget.product.name.substring(0, 1),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
                  : null,
        ),
        if (!_uploading)
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              width: 14, height: 14,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, size: 9, color: Colors.white),
            ),
          ),
      ]),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  final Product? product;
  final List<Category> categories;
  final VoidCallback onSaved;
  const _ProductForm({this.product, required this.categories, required this.onSaved});
  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final _nameCtrl = TextEditingController(text: widget.product?.name);
  late final _descCtrl = TextEditingController(text: widget.product?.description ?? '');
  late final _priceCtrl =
      TextEditingController(text: widget.product?.pricePerUnit.toString() ?? '');
  late final _stockCtrl =
      TextEditingController(text: widget.product?.stockQty.toString() ?? '0');
  late final _unitCtrl = TextEditingController(text: widget.product?.unit ?? 'kg');
  late final _thresholdCtrl = TextEditingController(
      text: (widget.product?.lowStockThreshold ?? 5).toString());
  late final _minQtyCtrl = TextEditingController(
      text: (widget.product?.minQty ?? 0.5).toString());
  late final _qtyStepCtrl = TextEditingController(
      text: (widget.product?.qtyStep ?? 0.5).toString());
  late bool _isWeightAdjusted = widget.product?.isWeightAdjusted ?? false;
  late int? _categoryId = widget.product?.categoryId;
  bool _saving = false;
  bool _uploadingImage = false;
  String? _imagePreviewUrl;

  @override
  void initState() {
    super.initState();
    if (widget.product?.imageUrl != null) {
      _imagePreviewUrl = Endpoints.imageUrl(widget.product!.imageUrl);
    }
  }

  Future<void> _pickAndUploadImage(int productId) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final res = await dio.post(Endpoints.adminProductImage(productId), data: formData);
      final url = '${Endpoints.baseUrl}${res.data['url']}';
      setState(() => _imagePreviewUrl = url);
      ref.invalidate(adminProductsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image uploaded ✅'), backgroundColor: AppColors.primary));
      }
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _priceCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name and price are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final data = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'price_per_unit': double.parse(_priceCtrl.text),
        'stock_qty': double.parse(_stockCtrl.text.isEmpty ? '0' : _stockCtrl.text),
        'unit': _unitCtrl.text.trim(),
        'is_weight_adjusted': _isWeightAdjusted ? 1 : 0,
        'low_stock_threshold': double.parse(_thresholdCtrl.text.isEmpty ? '5' : _thresholdCtrl.text),
        'min_qty': double.parse(_minQtyCtrl.text.isEmpty ? '0.5' : _minQtyCtrl.text),
        'qty_step': double.parse(_qtyStepCtrl.text.isEmpty ? '0.5' : _qtyStepCtrl.text),
        if (_categoryId != null) 'category_id': _categoryId,
      };
      if (widget.product != null && widget.product!.id > 0) {
        await dio.put(Endpoints.product(widget.product!.id), data: data);
      } else {
        await dio.post(Endpoints.products, data: data);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                widget.product == null ? 'Product added ✅' : 'Product updated ✅')));
      }
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              widget.product == null
                  ? 'Add Product'
                  : widget.product!.id == 0
                      ? 'Duplicate Product'
                      : 'Edit Product',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 12),

          // Category dropdown
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('No Category')),
              ...widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),

          TextField(controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Product Name *', border: OutlineInputBorder())),
          const SizedBox(height: 12),

          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (shown to customers)',
              hintText: 'e.g. Fresh farm-grown paneer, made daily from cow milk.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Price *', prefixText: '₹ ', border: OutlineInputBorder())),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Stock', border: OutlineInputBorder())),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Unit', border: OutlineInputBorder())),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _thresholdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Low stock alert at',
              suffixText: 'units',
              border: OutlineInputBorder(),
              helperText: 'Dashboard shows warning when stock ≤ this value',
              helperStyle: TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minQtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Min Qty',
                  helperText: 'First ADD amount',
                  helperStyle: TextStyle(fontSize: 11),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _qtyStepCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Step',
                  helperText: '+/− increment',
                  helperStyle: TextStyle(fontSize: 11),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Weight adjusted at delivery'),
            subtitle: const Text('e.g. paneer, fish — actual weight billed'),
            value: _isWeightAdjusted,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _isWeightAdjusted = v),
          ),
          const SizedBox(height: 12),

          // Image section — upload only available after product is created
          if (widget.product != null) ...[
            const Text('Product Image', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Thumbnail
              GestureDetector(
                onTap: () => _pickAndUploadImage(widget.product!.id),
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey.shade100,
                  ),
                  child: _uploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _imagePreviewUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(_imagePreviewUrl!, fit: BoxFit.cover,
                                  errorBuilder: (ctx2, url2, err2) => const Icon(Icons.image, color: Colors.grey, size: 32)))
                          : const Center(child: Icon(Icons.add_photo_alternate, color: Colors.grey, size: 32)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Tap image to change', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: _uploadingImage
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.upload, size: 16),
                  label: Text(_imagePreviewUrl != null ? 'Change Image' : 'Upload Image'),
                  onPressed: _uploadingImage ? null : () => _pickAndUploadImage(widget.product!.id),
                  style: ElevatedButton.styleFrom(minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                ),
                if (_imagePreviewUrl != null) ...[
                  const SizedBox(height: 6),
                  const Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 14),
                    SizedBox(width: 4),
                    Text('Image set', style: TextStyle(color: Colors.green, fontSize: 12)),
                  ]),
                ],
              ])),
            ]),
            const SizedBox(height: 12),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Save the product first, then you can upload an image.',
                    style: TextStyle(color: Colors.blue, fontSize: 12))),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(widget.product == null ? 'Add Product' : 'Save Changes'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Category Manager ──────────────────────────────────────────────────────────

class _CategoryManager extends ConsumerStatefulWidget {
  final VoidCallback onChanged;
  const _CategoryManager({required this.onChanged});
  @override
  ConsumerState<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends ConsumerState<_CategoryManager> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _addCategory() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.categories, data: {'name': name});
      setState(() => _nameCtrl.clear());
      ref.invalidate(categoriesAdminProvider);
      widget.onChanged();
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCategory(Category cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Delete "${cat.name}"? Products in this category will have no category.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete(Endpoints.deleteCategory(cat.id));
      ref.invalidate(categoriesAdminProvider);
      widget.onChanged();
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesAdminProvider);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + 20;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'New Category Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addCategory(),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _saving ? null : _addCategory,
              style: ElevatedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Add'),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1),

          categoriesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) { logError('admin-products', e); return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(e), style: const TextStyle(color: Colors.red)),
            ); },
            data: (cats) => cats.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No categories yet', style: TextStyle(color: Colors.grey)),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: cats.length,
                      itemBuilder: (_, i) {
                        final cat = cats[i];
                        return _CategoryImageTile(
                          category: cat,
                          onDelete: () => _deleteCategory(cat),
                          onImageUploaded: () => ref.invalidate(categoriesAdminProvider),
                        );
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Category image tile ───────────────────────────────────────────────────────

class _CategoryImageTile extends ConsumerStatefulWidget {
  final Category category;
  final VoidCallback onDelete;
  final VoidCallback onImageUploaded;
  const _CategoryImageTile({
    required this.category,
    required this.onDelete,
    required this.onImageUploaded,
  });
  @override
  ConsumerState<_CategoryImageTile> createState() => _CategoryImageTileState();
}

class _CategoryImageTileState extends ConsumerState<_CategoryImageTile> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      await dio.post(Endpoints.adminCategoryImage(widget.category.id), data: formData);
      widget.onImageUploaded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Image updated ✅'), backgroundColor: AppColors.primary));
      }
    } catch (e, st) {
      logError('admin-products', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.category.imageUrl;
    return ListTile(
      dense: true,
      leading: GestureDetector(
        onTap: _uploading ? null : _pickAndUpload,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFEAF2EA),
              backgroundImage: imageUrl != null
                  ? NetworkImage(Endpoints.imageUrl(imageUrl))
                  : null,
              child: imageUrl == null
                  ? Text(widget.category.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14))
                  : null,
            ),
            if (_uploading)
              const Positioned.fill(
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.black38,
                  child: SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                ),
              )
            else
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 14, height: 14,
                  decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, size: 9, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
      title: Text(widget.category.name,
          style: TextStyle(
            color: widget.category.isActive ? null : Colors.grey,
            decoration: widget.category.isActive ? null : TextDecoration.lineThrough,
          )),
      subtitle: imageUrl != null
          ? const Text('Tap image to change', style: TextStyle(fontSize: 11, color: Colors.grey))
          : const Text('Tap to add image', style: TextStyle(fontSize: 11, color: Colors.orange)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Switch(
          value: widget.category.isActive,
          activeThumbColor: AppColors.primary,
          onChanged: (v) async {
            try {
              final dio = ref.read(dioProvider);
              await dio.patch(Endpoints.toggleCategory(widget.category.id));
              widget.onImageUploaded(); // reuse refresh callback
            } catch (e, st) {
              logError('admin-products', e, st);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyError(e))));
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
          onPressed: widget.onDelete,
        ),
      ]),
    );
  }
}
