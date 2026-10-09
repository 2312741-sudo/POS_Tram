// lib/core/constants/app_constants.dart

class AppConstants {
  // Firebase
  static const String firebaseDatabaseUrl = 'https://ungdungdidong-94edd-default-rtdb.firebaseio.com';
  static const String onlineOrderWebUrl = 'https://ungdungdidong-94edd.web.app';

  // SharedPreferences keys
  static const String prefUsername = 'USERNAME';
  static const String prefRole = 'USER_ROLE';
  static const String prefFullName = 'FULL_NAME';
  static const String prefKitchenPrinterIp = 'KITCHEN_PRINTER_IP';
  static const String prefBillPrinterIp = 'BILL_PRINTER_IP';
  static const String prefAutoPrintKitchen = 'AUTO_PRINT_KITCHEN';
  static const String prefBankId = 'BANK_ID';
  static const String prefBankAccount = 'BANK_ACCOUNT';
  static const String prefAccountName = 'ACCOUNT_NAME';

  // Default values
  static const String defaultPrinterIp = '192.168.1.100';
  static const String defaultBankId = 'MB';
  static const String defaultBankAccount = '123456789';
  static const String defaultAccountName = 'TRAM APP';

  // Anti-cheat
  static const int cancelOrderThreshold = 3; // Max cancel per day per staff before alert
  static const int sessionTimeoutMinutes = 30; // Auto lock after X minutes

  // Default zones
  static const List<String> defaultZones = ['Khu A', 'Khu B', 'Khu C', 'Khu D', 'Khu E'];

  // Roles
  static const String roleManager = 'MANAGER';
  static const String roleStaff = 'STAFF';
  static const String roleKitchen = 'KITCHEN';

  // Audit actions
  static const String actionLogin = 'LOGIN';
  static const String actionLogout = 'LOGOUT';
  static const String actionPayment = 'PAYMENT';
  static const String actionCancelOrder = 'CANCEL_ORDER';
  static const String actionDeleteHistory = 'DELETE_HISTORY';
  static const String actionAddProduct = 'ADD_PRODUCT';
  static const String actionEditProduct = 'EDIT_PRODUCT';
  static const String actionDeleteProduct = 'DELETE_PRODUCT';
  static const String actionAddUser = 'ADD_USER';
  static const String actionDeleteUser = 'DELETE_USER';
  static const String actionSendKitchen = 'SEND_KITCHEN';
  static const String actionConfirmOnlineOrder = 'CONFIRM_ONLINE_ORDER';
}
