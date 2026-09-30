// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../data/models/app_models.dart';
import '../../features/auth/login_screen.dart';
import '../../features/tables/table_list_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/orders/order_cart_screen.dart';
import '../../features/kitchen/kitchen_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/promotions/promotions_screen.dart';
import '../../features/audit_logs/audit_logs_screen.dart';
import '../../features/permissions/permissions_matrix_screen.dart';
import '../../features/menu_management/menu_management_screen.dart';
import '../../features/category_management/category_management_screen.dart';
import '../../features/zone_management/zone_management_screen.dart';
import '../../features/user_management/user_management_screen.dart';
import '../../features/online_orders/online_order_screen.dart';
import '../../features/online_orders/online_order_detail_screen.dart';
import '../../features/qr_code/qr_code_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/manager/manager_hub_screen.dart';
import '../../features/cash_shift/cash_shifts_screen.dart';
import '../../features/reports/end_of_day_report_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = AuthService();
      final isLoggingIn = state.uri.path == '/login';
      if (!auth.isLoggedIn && !isLoggingIn) return '/login';
      if (auth.isLoggedIn && isLoggingIn) {
        if (auth.isKitchen) return '/kitchen';
        if (auth.canAccessManagerHub) return '/manager-hub';
        return '/tables';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/manager-hub',
        builder: (_, state) {
          final tabStr = state.uri.queryParameters['tab'];
          final initialTab = int.tryParse(tabStr ?? '0') ?? 0;
          return ManagerHubScreen(initialTab: initialTab);
        },
      ),
      GoRoute(path: '/tables', builder: (_, __) => const TableListScreen()),
      GoRoute(
        path: '/order-list',
        builder: (_, state) {
          if (state.extra is Map) {
            final map = state.extra as Map;
            return OrderListScreen(
              table: map['table'] as TableModel,
              isAddingMore: map['isAddingMore'] == true,
            );
          }
          final table = state.extra as TableModel;
          return OrderListScreen(table: table);
        },
      ),
      GoRoute(
        path: '/order-cart',
        builder: (_, state) {
          final extra = state.extra as Map;
          return OrderCartScreen(
            table: extra['table'] as TableModel,
            initialProducts: (extra['products'] as List?)?.cast<OrderItemModel>() ?? const [],
          );
        },
      ),
      GoRoute(path: '/kitchen', builder: (_, __) => const KitchenScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(path: '/promotions', builder: (_, __) => const PromotionsScreen()),
      GoRoute(path: '/audit-logs', builder: (_, __) => const AuditLogsScreen()),
      GoRoute(path: '/permissions-matrix', builder: (_, __) => const PermissionsMatrixScreen()),
      GoRoute(path: '/menu-management', builder: (_, __) => const MenuManagementScreen()),
      GoRoute(path: '/category-management', builder: (_, state) => CategoryManagementScreen(initialStoreCode: state.extra as String?)),
      GoRoute(path: '/zone-management', builder: (_, __) => const ZoneManagementScreen()),
      GoRoute(path: '/user-management', builder: (_, __) => const UserManagementScreen()),
      GoRoute(path: '/online-orders', builder: (_, __) => const OnlineOrderScreen()),
      GoRoute(
        path: '/online-order-detail',
        builder: (_, state) => OnlineOrderDetailScreen(order: state.extra as OnlineOrderModel),
      ),
      GoRoute(
        path: '/qr-code',
        builder: (_, state) {
          final extra = state.extra as Map;
          return QRCodeScreen(tableName: extra['tableName'], tableZone: extra['tableZone']);
        },
      ),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
      GoRoute(path: '/cash-shifts', builder: (_, __) => const CashShiftsScreen()),
      GoRoute(path: '/end-of-day-report', builder: (_, __) => const EndOfDayReportScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Không tìm thấy trang: ${state.error}')),
    ),
  );
}
