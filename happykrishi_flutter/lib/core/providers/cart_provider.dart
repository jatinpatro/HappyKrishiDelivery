import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(Product product, double qty) {
    final idx = state.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) state[i].copyWith(qty: state[i].qty + qty) else state[i]
      ];
    } else {
      state = [...state, CartItem(product: product, qty: qty)];
    }
  }

  void updateQty(int productId, double qty) {
    if (qty <= 0) {
      removeItem(productId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId) item.copyWith(qty: qty) else item
    ];
  }

  void removeItem(int productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void clear() => state = [];

  double get subtotal => state.fold(0, (s, i) => s + i.product.pricePerUnit * i.qty);
  int get itemCount => state.length;
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (_) => CartNotifier(),
);

final cartSubtotalProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0, (s, i) => s + i.product.pricePerUnit * i.qty);
});

final cartItemCountProvider = Provider<int>((ref) => ref.watch(cartProvider).length);
