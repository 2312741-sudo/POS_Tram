// lib/features/orders/order_list_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/utils/format_utils.dart';

class OrderListScreen extends StatefulWidget {
  final TableModel table;
  const OrderListScreen({super.key, required this.table});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final _fb = FirebaseService();
  String _categoryFilter = 'Tất cả';
  String _search = '';
  List<ProductModel> _products = [];
  List<ProductModel> _cart = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    // Carry over existing order from table
    _cart = List.from(widget.table.currentOrder);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadData() {
    _fb.productsStream().listen((products) {
      if (mounted) setState(() { _products = products; _loading = false; });
    });
    _fb.categoriesStream().listen((cats) {
      if (mounted) setState(() => _categories = cats);
    });
  }

  List<ProductModel> get _filteredProducts {
    return _products.where((p) {
      final matchCat = _categoryFilter == 'Tất cả' || p.category == _categoryFilter;
      final matchSearch = _search.isEmpty ||
        p.name.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
  }

  void _addToCart(ProductModel product) {
    setState(() {
      final idx = _cart.indexWhere((p) => p.name == product.name);
      if (idx >= 0) {
        _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity + 1);
      } else {
        _cart.add(product.copyWith(quantity: 1));
      }
    });
  }

  void _removeFromCart(ProductModel product) {
    setState(() {
      final idx = _cart.indexWhere((p) => p.name == product.name);
      if (idx >= 0) {
        if (_cart[idx].quantity > 1) {
          _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity - 1);
        } else {
          _cart.removeAt(idx);
        }
      }
    });
  }

  int _cartQty(ProductModel p) {
    final idx = _cart.indexWhere((c) => c.name == p.name);
    return idx >= 0 ? _cart[idx].quantity : 0;
  }

  int get _cartTotal => _cart.fold(0, (s, p) => s + p.total);
  int get _cartCount => _cart.fold(0, (s, p) => s + p.quantity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildCategoryChips(),
            Expanded(child: _loading ? _buildShimmer() : _buildProductGrid()),
          ],
        ),
      ),
      floatingActionButton: _cartCount > 0
        ? FloatingActionButton.extended(
            onPressed: () => context.push('/order-cart', extra: {
              'table': widget.table,
              'products': _cart,
            }),
            icon: Stack(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    child: Text('$_cartCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            label: Text(
              '${FormatUtils.currency(_cartTotal)} • Xem giỏ hàng',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.primary,
          ).animate().slideY(begin: 1, end: 0, duration: 300.ms)
        : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: AppColors.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.arrow_back_ios_new, size: 14, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chọn món', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700,
                )),
                Text('Bàn: ${widget.table.name} • ${widget.table.zone}',
                  style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm món...',
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
              )
            : null,
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cats = ['Tất cả', ..._categories.map((c) => c.name)];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final isSelected = _categoryFilter == cat;
          return GestureDetector(
            onTap: () => setState(() => _categoryFilter = cat),
            child: AnimatedContainer(
              duration: 200.ms,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
              ),
              child: Text(cat, style: GoogleFonts.beVietnamPro(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    final products = _filteredProducts;
    if (products.isEmpty) {
      return Center(
        child: Text('Không tìm thấy món', style: GoogleFonts.beVietnamPro(color: AppColors.textHint)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(
        product: products[i],
        quantity: _cartQty(products[i]),
        onAdd: () => _addToCart(products[i]),
        onRemove: () => _removeFromCart(products[i]),
      ).animate(delay: (i * 30).ms).fadeIn(duration: 250.ms),
    );
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.65,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: quantity > 0
          ? AppColors.primary.withOpacity(0.08)
          : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: quantity > 0 ? AppColors.primary.withOpacity(0.4) : AppColors.border,
          width: quantity > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
                ? _buildBase64Image(product.imageBase64!)
                : Container(
                    color: AppColors.cardElevated,
                    child: const Center(
                      child: Icon(Icons.restaurant, color: AppColors.textHint, size: 40),
                    ),
                  ),
            ),
          ),

          // Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(FormatUtils.currency(product.price),
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  // Cart controls
                  if (quantity == 0)
                    GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    )
                  else
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onRemove,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.cardElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(Icons.remove, color: AppColors.textPrimary, size: 14),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text('$quantity',
                              style: GoogleFonts.beVietnamPro(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBase64Image(String base64) {
    try {
      final String cleanBase64 = base64.contains(',') ? base64.split(',').last : base64;
      final bytes = base64Decode(cleanBase64);
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.cardElevated,
          child: const Center(child: Icon(Icons.restaurant, color: AppColors.textHint, size: 40)),
        ),
      );
    } catch (_) {
      return Container(
        color: AppColors.cardElevated,
        child: const Center(child: Icon(Icons.restaurant, color: AppColors.textHint, size: 40)),
      );
    }
  }
}
