import '../config/app_config.dart';

class Endpoints {
  static const String baseUrl = AppConfig.baseUrl;
  static const String wsBaseUrl = AppConfig.wsBaseUrl;

  // Resolve an image URL — Firebase Storage URLs are full HTTPS, local ones are relative
  static String imageUrl(String? url) {
    if (url == null) return '';
    if (url.startsWith('http')) return url;
    return '$baseUrl$url';
  }

  // Auth
  static const sendOtp = '/api/auth/send-otp';
  static const verifyOtp = '/api/auth/verify-otp';
  static const phoneLogin = '/api/auth/phone-login';
  static const register = '/api/auth/register';
  static const adminLogin = '/api/auth/admin-login';
  static const sendEmailVerification = '/api/auth/send-email-verification';
  static const verifyEmail           = '/api/auth/verify-email';
  static const changePhoneRequestOtp    = '/api/auth/change-phone/request-otp';
  static const changePhoneConfirm       = '/api/auth/change-phone/confirm';
  static const changePhoneFirebaseConfirm = '/api/auth/change-phone/firebase-confirm';
  static const verifyFirebasePhone   = '/api/auth/verify-firebase-phone';
  static const me = '/api/auth/me';
  static const updateProfile = '/api/auth/profile';
  static const emailSignup = '/api/auth/email-signup';
  static const emailLogin = '/api/auth/email-login';
  static const setPassword = '/api/auth/set-password';
  static const changePasswordRequestOtp = '/api/auth/change-password/request-otp';
  static const changePassword = '/api/auth/change-password';

  // Products
  static const categories = '/api/categories';
  static String deleteCategory(int id) => '/api/categories/$id';
  static const products = '/api/products';
  static String product(int id) => '/api/products/$id';

  // Orders
  static const orders = '/api/orders';
  static String order(int id) => '/api/orders/$id';
  static String cancelOrder(int id) => '/api/orders/$id/cancel';
  static String staffCancelOrder(int id, String role) =>
      role == 'salesman' ? '/api/salesman/orders/$id/cancel' : '/api/admin/orders/$id/cancel';
  static String reorder(int id) => '/api/orders/$id/reorder';
  static String customerLocation(int id) => '/api/orders/$id/customer-location';
  static const deliveryCharge = '/api/orders/delivery-charge';
  static const checkPincode = '/api/delivery/check-pincode';
  static const customDeliveryRequests = '/api/custom-delivery';
  static const myCustomDeliveryRequests = '/api/custom-delivery/my';
  static String approveCustomDelivery(int id) => '/api/custom-delivery/$id/approve';
  static String rejectCustomDelivery(int id) => '/api/custom-delivery/$id/reject';
  static const whitelistedPincodes = '/api/custom-delivery/pincodes';
  static String whitelistedPincode(String pincode) => '/api/custom-delivery/pincodes/$pincode';
  static String pincodeRules(String pincode) => '/api/custom-delivery/pincodes/$pincode/rules';
  static String pincodeRule(String pincode, int id) => '/api/custom-delivery/pincodes/$pincode/rules/$id';
  static String pincodeAddresses(String pincode) => '/api/custom-delivery/pincodes/$pincode/addresses';

  // Wallet
  static const wallet = '/api/wallet';
  static const walletTransactions = '/api/wallet/transactions';
  static const topupRequest = '/api/wallet/topup-request';
  static const myTopupRequests = '/api/wallet/topup-requests';

  // Delivery (agent)
  static const myDeliveryOrder = '/api/delivery/my-order';
  static const deliveryLocation = '/api/delivery/location';
  static String markPicked(int id) => '/api/delivery/$id/picked';
  static String markDelivered(int id) => '/api/delivery/$id/delivered';

  // Notifications
  static const fcmToken = '/api/notifications/fcm-token';
  static const notifications = '/api/notifications';

  // Addresses
  static const addresses = '/api/addresses';
  static String address(int id) => '/api/addresses/$id';

  // Admin
  static const adminDashboard = '/api/admin/dashboard';
  static const adminOrders = '/api/admin/orders';
  static const adminPlaceOrderForCustomer = '/api/admin/orders/place-for-customer';
  static const salesmanPlaceOrderForCustomer = '/api/salesman/orders/place-for-customer';
  static String adminOrderStatus(int id) => '/api/admin/orders/$id/status';
  static String adminWaiveDelivery(int id) => '/api/admin/orders/$id/waive-delivery';
  static String salesmanWaiveDelivery(int id) => '/api/salesman/orders/$id/waive-delivery';
  static String adminAssignAgent(int id) => '/api/admin/orders/$id/assign';
  static String adminUpdateOrderItems(int id) => '/api/admin/orders/$id/items';
  static String adminMarkCollected(int id) => '/api/admin/orders/$id/mark-collected';
  static String salesmanUpdateOrderItems(int id) => '/api/salesman/orders/$id/items';
  static const adminAgents = '/api/admin/agents';
  static const adminAgentLocations = '/api/admin/agents/locations';
  static String adminAgentForceLogout(int id) => '/api/admin/agents/$id/force-logout';
  static String adminSalesmanForceLogout(int id) => '/api/admin/salesmen/$id/force-logout';
  static String adminRaiseSalesmanSettlement(int id) => '/api/admin/salesmen/$id/raise-settlement';
  static String adminAgentToggle(int id) => '/api/admin/agents/$id/toggle';
  static const adminProducts = '/api/admin/products';
  static String adminProductImage(int id) => '/api/admin/products/$id/image';
  static String adminProductImageUrl(int id) => '/api/admin/products/$id/image-url';
  static String adminCategoryImage(int id) => '/api/admin/categories/$id/image';
  static const adminUsers = '/api/admin/users';
  static String adminToggleCustomer(int id) => '/api/admin/users/$id/toggle';
  static String adminResetCustomerPassword(int id) => '/api/admin/users/$id/reset-password';
  static String adminCustomerForceLogout(int id) => '/api/admin/users/$id/force-logout';
  static const adminCreditWallet = '/api/admin/wallet/credit';
  static const adminDebitWallet = '/api/admin/wallet/debit';

  // Rewards
  static const adminRewardsRules = '/api/admin/rewards/rules';
  static String adminRewardsRule(int id) => '/api/admin/rewards/rules/$id';
  static const adminRewardsCalculate = '/api/admin/rewards/calculate';
  static const adminRewardsApprove = '/api/admin/rewards/approve';
  static const adminRewardsReject = '/api/admin/rewards/reject';
  static const adminRewardsPayouts = '/api/admin/rewards/payouts';
  static const adminRewardsProductsCategories = '/api/admin/rewards/products-and-categories';
  static const adminConfig = '/api/admin/config';
  static const adminUploadQr = '/api/admin/upload-qr';
  static const appInfo = '/api/app-info';

  static const adminTopupRequests = '/api/admin/topup-requests';
  static const adminCreditAdvances = '/api/admin/credit-advances';
  static String adminApproveTopup(int id) => '/api/admin/topup-requests/$id/approve';
  static String adminRejectTopup(int id) => '/api/admin/topup-requests/$id/reject';
  static const adminCreditAdvance = '/api/admin/topup-requests/credit-advance';
  static String adminMarkCreditPaid(int id) => '/api/admin/topup-requests/$id/mark-paid';
  static const salesmanCreditAdvance = '/api/salesman/credit-advance';
  static String salesmanMarkCreditPaid(int id) => '/api/salesman/credit-advances/$id/mark-paid';
  static const salesmanCreditAdvances = '/api/salesman/credit-advances';
  static const adminSalesmanSummary  = '/api/admin/salesman-summary';
  static const adminSalesmanSettle   = '/api/admin/salesman-settle';
  static String adminAcknowledgeSettlement(int id) => '/api/admin/salesman-settlements/$id/acknowledge';
  static const adminSalesmen = '/api/admin/salesmen';
  static String adminSalesmanToggle(int id) => '/api/admin/salesmen/$id/toggle';
  static String adminSalesmanResetPassword(int id) => '/api/admin/salesmen/$id/reset-password';
  static String adminSalesmanUpdate(int id) => '/api/admin/salesmen/$id';
  static const salesmanLogin = '/api/salesman/login';
  static const salesmanProducts = '/api/salesman/products';
  static String salesmanProductStock(int id) => '/api/salesman/products/$id/stock';
  static const salesmanList = '/api/salesman/list';
  static const salesmanPendingOrders = '/api/salesman/pending-orders';
  static String salesmanConfirmOrder(int id) => '/api/salesman/pending-orders/$id/confirm';
  static const salesmanDashboard = '/api/salesman/dashboard';
  static const salesmanHistory = '/api/salesman/history';
  static const salesmanCustomers = '/api/salesman/customers';
  static const salesmanPendingCollections = '/api/salesman/pending-collections';
  static const salesmanApprovedCollections = '/api/salesman/approved-collections';
  static const salesmanRaiseSettlement    = '/api/salesman/settlements/raise';
  static String salesmanApproveCollection(int id) => '/api/salesman/collections/$id/approve';
  static String salesmanResetCustomerPassword(int id) => '/api/salesman/customers/$id/reset-password';
  static String salesmanMarkPicked(int deliveryId) => '/api/salesman/delivery/$deliveryId/pick';
  static String salesmanMarkDelivered(int deliveryId) => '/api/salesman/delivery/$deliveryId/deliver';

  // Analytics & messaging
  static const adminAnalytics = '/api/admin/analytics';
  static String adminCustomerBehaviour(int id) => '/api/admin/analytics/customer/$id';
  static const adminCustomerActivity = '/api/admin/customer-activity';
  static const adminSalesReport = '/api/admin/sales-report';
  static const adminBroadcast = '/api/admin/broadcast';
  static const adminDueReminders = '/api/admin/due-reminders';

  // Customer tiers
  static const adminTiers = '/api/admin/tiers';
  static String adminTier(int id) => '/api/admin/tiers/$id';
  static String adminAssignCustomerTier(int id) => '/api/admin/customers/$id/tier';
  static String adminUpdateCustomer(int id) => '/api/admin/users/$id';
  static String adminCustomerWalletHistory(int id) => '/api/admin/users/$id/wallet-history';
  static const adminWalletAudit = '/api/admin/wallet-audit';
  static const adminWalletAuditSummary = '/api/admin/wallet-audit/summary';
  static const registerFcmToken = '/api/auth/fcm-token';
  static const publicTiers = '/api/tiers';

  // Referral
  static const referralMyCodes  = '/api/referral/my-codes';
  static const referralGenerate = '/api/referral/generate';
  static const referralApply    = '/api/referral/apply';
  static const adminReferrals            = '/api/admin/referrals';
  static const adminReferralsGenerate    = '/api/admin/referrals/generate';
  static const adminReferralsGeneric     = '/api/admin/referrals/generic';
  static String adminReferralGeneric(int id) => '/api/admin/referrals/generic/$id';

  // Promo codes
  static const promoCodes         = '/api/promo';
  static const promoValidate      = '/api/promo/validate';
  static const promoAvailable     = '/api/promo/available';
  static String promoCode(int id) => '/api/promo/$id';

  // Delivery confirmation
  static String orderConfirmDelivery(int id) => '/api/orders/$id/confirm-delivery';
}
