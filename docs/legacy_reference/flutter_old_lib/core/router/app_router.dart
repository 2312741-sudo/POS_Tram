// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../features/auth/login_screen.dart';
import '../../features/tables/table_list_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/orders/order_cart_screen.dart';
import '../../features/kitchen/kitchen_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/menu_management/menu_management_screen.dart';
import '../../features/category_management/category_management_screen.dart';
import '../../features/zone_management/zone_management_screen.dart';
import '../../features/user_management/user_management_screen.dart';
import '../../features/online_orders/online_order_screen.dart';
import '../../features/online_orders/online_order_detail_screen.dart';
import '../../features/qr_code/qr_code_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../data/models/app_models.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = AuthService();
      final isLoggingIn = state.uri.path == '/login';
      if (!auth.isLoggedIn && !isLoggingIn) return '/login';
      if (auth.isLoggedIn && isLoggingIn) {
        if (auth.isKitchen) return '/kitchen';
        return '/tables';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/tables', builder: (_, __) => const TableListScreen()),
      GoRoute(
        path: '/order-list',
        builder: (_, state) {
          final table = state.extra as TableModel;
          return OrderListScreen(table: table);
        },
      ),
      GoRoute(
        path: '/order-cart',
        builder: (_, state) {
          final extra = state.extra as Map;
          return OrderCartScreen(table: extra['table'], initialProducts: extra['products'] ?? []);
        },
      ),
      GoRoute(path: '/kitchen', builder: (_, __) => const KitchenScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(path: '/menu-management', builder: (_, __) => const MenuManagementScreen()),
      GoRoute(path: '/category-management', builder: (_, __) => const CategoryManagementScreen()),
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
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Không tìm thấy trang: ${state.error}')),
    ),
  );
}
