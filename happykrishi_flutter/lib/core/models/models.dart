// Plain Dart models — no code generation, handles snake_case from backend directly

class AppUser {
  final int id;
  final String name;
  final String? nameOdia;
  final String phone;
  final String? email;
  final String role;
  final double walletBalance;
  final bool isActive;
  final String? createdAt;
  final String? gender;
  final String? birthdate;
  final String? tierName;
  final String? tierColor;

  const AppUser({
    required this.id,
    required this.name,
    this.nameOdia,
    required this.phone,
    this.email,
    required this.role,
    required this.walletBalance,
    this.isActive = true,
    this.createdAt,
    this.gender,
    this.birthdate,
    this.tierName,
    this.tierColor,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        nameOdia: j['name_odia'] as String?,
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String?,
        role: j['role'] as String? ?? 'customer',
        walletBalance: _d(j['wallet_balance']),
        isActive: _b(j['is_active']),
        createdAt: j['created_at'] as String?,
        gender: j['gender'] as String?,
        birthdate: j['birthdate'] as String?,
        tierName: j['tier_name'] as String?,
        tierColor: j['tier_color'] as String?,
      );

  AppUser copyWith({String? name, String? email, double? walletBalance}) => AppUser(
        id: id, phone: phone, role: role, nameOdia: nameOdia,
        isActive: isActive, createdAt: createdAt,
        gender: gender, birthdate: birthdate, tierName: tierName, tierColor: tierColor,
        name: name ?? this.name,
        email: email ?? this.email,
        walletBalance: walletBalance ?? this.walletBalance,
      );
}

class Category {
  final int id;
  final String name;
  final String? nameOdia;
  final String? icon;
  final String? imageUrl;
  final int sortOrder;

  const Category({required this.id, required this.name, this.nameOdia, this.icon, this.imageUrl, this.sortOrder = 0});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as int,
        name: j['name'] as String,
        nameOdia: j['name_odia'] as String?,
        icon: j['icon'] as String?,
        imageUrl: j['image_url'] as String?,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

class Product {
  final int id;
  final int? categoryId;
  final String name;
  final String? nameOdia;
  final String? description;
  final String unit;
  final double pricePerUnit;
  final double stockQty;
  final double lowStockThreshold;
  final double minQty;
  final double qtyStep;
  final bool isWeightAdjusted;
  final String? imageUrl;
  final bool isActive;
  final String? categoryName;

  const Product({
    required this.id, this.categoryId, required this.name, this.nameOdia,
    this.description, required this.unit, required this.pricePerUnit,
    required this.stockQty, this.lowStockThreshold = 5,
    this.minQty = 0.5, this.qtyStep = 0.5,
    this.isWeightAdjusted = false, this.imageUrl, this.isActive = true,
    this.categoryName,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        categoryId: j['category_id'] as int?,
        name: j['name'] as String,
        nameOdia: j['name_odia'] as String?,
        description: j['description'] as String?,
        unit: j['unit'] as String? ?? 'kg',
        pricePerUnit: _d(j['price_per_unit']),
        stockQty: _d(j['stock_qty']),
        lowStockThreshold: _d(j['low_stock_threshold']),
        minQty: j['min_qty'] != null ? _d(j['min_qty']) : 0.5,
        qtyStep: j['qty_step'] != null ? _d(j['qty_step']) : 0.5,
        isWeightAdjusted: _b(j['is_weight_adjusted']),
        imageUrl: j['image_url'] as String?,
        isActive: _b(j['is_active']),
        categoryName: j['category_name'] as String?,
      );
}

class CartItem {
  final Product product;
  final double qty;
  const CartItem({required this.product, required this.qty});
  CartItem copyWith({double? qty}) => CartItem(product: product, qty: qty ?? this.qty);
}

class Address {
  final int id;
  final int userId;
  final String label;
  final String addressLine;
  final String city;
  final String? pincode;
  final double? lat;
  final double? lng;
  final bool isDefault;

  const Address({
    required this.id, required this.userId, required this.label,
    required this.addressLine, required this.city, this.pincode,
    this.lat, this.lng, this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        label: j['label'] as String? ?? 'Home',
        addressLine: j['address_line'] as String,
        city: j['city'] as String,
        pincode: j['pincode'] as String?,
        lat: j['lat'] == null ? null : _d(j['lat']),
        lng: j['lng'] == null ? null : _d(j['lng']),
        isDefault: _b(j['is_default']),
      );
}

class DeliverySlot {
  final int id;
  final String label;
  final String? labelOdia;
  final String startTime;
  final String endTime;

  const DeliverySlot({required this.id, required this.label, this.labelOdia, required this.startTime, required this.endTime});

  factory DeliverySlot.fromJson(Map<String, dynamic> j) => DeliverySlot(
        id: j['id'] as int,
        label: j['label'] as String,
        labelOdia: j['label_odia'] as String?,
        startTime: j['start_time'] as String,
        endTime: j['end_time'] as String,
      );
}

class OrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double estimatedQty;
  final double? actualQty;
  final double unitPrice;
  final double estimatedTotal;
  final double? actualTotal;
  final bool isWeightAdjusted;
  final String? productName;
  final String? productNameOdia;
  final String? unit;
  final String? imageUrl;

  const OrderItem({
    required this.id, required this.orderId, required this.productId,
    required this.estimatedQty, this.actualQty, required this.unitPrice,
    required this.estimatedTotal, this.actualTotal,
    this.isWeightAdjusted = false, this.productName, this.productNameOdia,
    this.unit, this.imageUrl,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] as int,
        orderId: j['order_id'] as int,
        productId: j['product_id'] as int,
        estimatedQty: _d(j['estimated_qty']),
        actualQty: j['actual_qty'] == null ? null : _d(j['actual_qty']),
        unitPrice: _d(j['unit_price']),
        estimatedTotal: _d(j['estimated_total']),
        actualTotal: j['actual_total'] == null ? null : _d(j['actual_total']),
        isWeightAdjusted: _b(j['is_weight_adjusted']),
        productName: j['product_name'] as String?,
        productNameOdia: j['product_name_odia'] as String?,
        unit: j['unit'] as String?,
        imageUrl: j['image_url'] as String?,
      );
}

class Order {
  final int id;
  final String orderNumber;
  final int userId;
  final int? addressId;   // null for pickup orders
  final int? slotId;
  final String status;
  final String deliveryDate;
  final double subtotal;
  final double deliveryCharge;
  final double discountAmount;
  final double walletUsed;
  final double finalAmount;
  final String paymentStatus;
  final String? notes;
  final String? cancelledReason;
  final String createdAt;
  final String? slotLabel;
  final String? addressLine;
  final String? city;
  final String? salesmanName;
  final String? salesmanPhone;
  final String? orderType;
  final double? customerWalletBalance;

  const Order({
    required this.id, required this.orderNumber, required this.userId,
    this.addressId, this.slotId, required this.status,
    required this.deliveryDate, required this.subtotal,
    required this.deliveryCharge, this.discountAmount = 0,
    this.walletUsed = 0, required this.finalAmount,
    required this.paymentStatus, this.notes, this.cancelledReason,
    required this.createdAt, this.slotLabel, this.addressLine, this.city,
    this.salesmanName, this.salesmanPhone, this.orderType,
    this.customerWalletBalance,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as int,
        orderNumber: j['order_number'] as String,
        userId: j['user_id'] as int,
        addressId: j['address_id'] as int?,
        slotId: j['slot_id'] as int?,
        status: j['status'] as String,
        deliveryDate: j['delivery_date'] as String,
        subtotal: _d(j['subtotal']),
        deliveryCharge: _d(j['delivery_charge']),
        discountAmount: _d(j['discount_amount']),
        walletUsed: _d(j['wallet_used']),
        finalAmount: _d(j['final_amount']),
        paymentStatus: j['payment_status'] as String,
        notes: j['notes'] as String?,
        cancelledReason: j['cancelled_reason'] as String?,
        createdAt: j['created_at'] as String,
        slotLabel: j['slot_label'] as String?,
        addressLine: j['address_line'] as String?,
        city: j['city'] as String?,
        salesmanName: j['salesman_name'] as String?,
        salesmanPhone: j['salesman_phone'] as String?,
        orderType: j['order_type'] as String?,
        customerWalletBalance: j['customer_wallet_balance'] == null
            ? null
            : _d(j['customer_wallet_balance']),
      );
}

class WalletTransaction {
  final int id;
  final int userId;
  final String type;
  final double amount;
  final double balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final String? description;
  final String createdAt;

  const WalletTransaction({
    required this.id, required this.userId, required this.type,
    required this.amount, required this.balanceAfter, this.referenceType,
    this.referenceId, this.description, required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        type: j['type'] as String,
        amount: _d(j['amount']),
        balanceAfter: _d(j['balance_after']),
        referenceType: j['reference_type'] as String?,
        referenceId: j['reference_id'] as int?,
        description: j['description'] as String?,
        createdAt: j['created_at'] as String,
      );
}

class AppNotification {
  final int id;
  final String title;
  final String body;
  final String? type;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id, required this.title, required this.body,
    this.type, this.isRead = false, required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        type: j['type'] as String?,
        isRead: _b(j['is_read']),
        createdAt: j['created_at'] as String,
      );
}

class DeliveryInfo {
  final int id;
  final int orderId;
  final int? agentId;
  final String status;
  final String? assignedAt;
  final String? pickedAt;
  final String? deliveredAt;
  final String? agentName;
  final String? agentPhone;

  const DeliveryInfo({
    required this.id, required this.orderId, this.agentId,
    required this.status, this.assignedAt, this.pickedAt,
    this.deliveredAt, this.agentName, this.agentPhone,
  });

  factory DeliveryInfo.fromJson(Map<String, dynamic> j) => DeliveryInfo(
        id: j['id'] as int,
        orderId: j['order_id'] as int,
        agentId: j['agent_id'] as int?,
        status: j['status'] as String,
        assignedAt: j['assigned_at'] as String?,
        pickedAt: j['picked_at'] as String?,
        deliveredAt: j['delivered_at'] as String?,
        agentName: j['agent_name'] as String?,
        agentPhone: j['agent_phone'] as String?,
      );
}

// ── helpers ──────────────────────────────────────────────────────────────────
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
bool _b(dynamic v) => v == true || v == 1;
