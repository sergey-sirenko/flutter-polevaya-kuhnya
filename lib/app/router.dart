import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/adaptive_app_shell.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/session_gate_page.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/site/site_home_page.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const about = '/about';
  static const delivery = '/delivery';
  static const howToOrder = '/how-to-order';
  static const contacts = '/contacts';
  static const install = '/install';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const resetPassword = '/reset-password';
  static const menu = '/menu';
  static const cart = '/cart';
  static const orders = '/orders';
  static const profile = '/profile';
}

const _publicPages = {
  AppRoutes.about: AppStrings.about,
  AppRoutes.delivery: AppStrings.delivery,
  AppRoutes.howToOrder: AppStrings.howToOrder,
  AppRoutes.contacts: AppStrings.contacts,
  AppRoutes.install: AppStrings.install,
  AppRoutes.signIn: AppStrings.signIn,
  AppRoutes.signUp: AppStrings.signUp,
  AppRoutes.resetPassword: AppStrings.resetPassword,
  AppRoutes.menu: AppStrings.menu,
};

const _protectedPages = {
  AppRoutes.cart: AppStrings.cart,
  AppRoutes.orders: AppStrings.orders,
  AppRoutes.profile: AppStrings.profile,
};

const _appDestinations = [
  AppRoutes.menu,
  AppRoutes.cart,
  AppRoutes.orders,
  AppRoutes.profile,
];

final routerProvider = Provider<GoRouter>((ref) {
  final isTest = ref.read(appConfigProvider).isTest;
  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
    // Явный адрес платформы имеет приоритет над обычным стартом ADR-8.
    overridePlatformDefaultLocation: false,
    redirect: (context, state) {
      final status = ref.read(sessionStatusProvider);
      // Проверяем совпавший маршрут, а не сырой URL (например, /orders/).
      final path = state.topRoute?.path;
      if (_protectedPages.containsKey(path) &&
          status == SessionStatus.signedOut) {
        return Uri(
          path: AppRoutes.signIn,
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (path == AppRoutes.signIn && status == SessionStatus.signedIn) {
        return _returnLocation(state.uri);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        caseSensitive: true,
        builder: (context, state) => SiteHomePage(
          isTest: isTest,
          onOrder: () => context.go(AppRoutes.menu),
        ),
      ),
      for (final entry in _publicPages.entries)
        if (entry.key != AppRoutes.menu)
          GoRoute(
            path: entry.key,
            caseSensitive: true,
            builder: (context, state) => RoutePage(
              title: entry.value,
              isTest: isTest,
              onHome: () => context.go(AppRoutes.home),
            ),
          ),
      ShellRoute(
        builder: (context, state, child) {
          final selectedIndex = _appDestinations.indexOf(
            state.topRoute?.path ?? state.uri.path,
          );
          return AdaptiveAppShell(
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            menuPanel: RoutePage(
              title: AppStrings.menu,
              isTest: isTest,
              onHome: () => context.go(AppRoutes.home),
            ),
            cartPanel: SessionGatePage(title: AppStrings.cart, isTest: isTest),
            onDestinationSelected: (index) =>
                context.go(_appDestinations[index]),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: AppRoutes.menu,
            caseSensitive: true,
            builder: (context, state) => RoutePage(
              title: AppStrings.menu,
              isTest: isTest,
              onHome: () => context.go(AppRoutes.home),
            ),
          ),
          for (final entry in _protectedPages.entries)
            GoRoute(
              path: entry.key,
              caseSensitive: true,
              builder: (context, state) =>
                  SessionGatePage(title: entry.value, isTest: isTest),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => RoutePage(
      title: AppStrings.pageNotFound,
      message: AppStrings.pageNotFoundMessage,
      isTest: isTest,
      onHome: () => context.go(AppRoutes.home),
    ),
  );
  // Смена сессии пересчитывает доступ, сохраняя экземпляр router и его историю.
  ref.listen(sessionStatusProvider, (previous, next) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

String _returnLocation(Uri signInUri) {
  final values = signInUri.queryParametersAll['from'];
  if (values == null || values.length != 1) return AppRoutes.menu;
  final target = Uri.tryParse(values.single);
  if (target == null || target.hasScheme || target.hasAuthority) {
    return AppRoutes.menu;
  }
  final path = target.path.replaceFirst(RegExp(r'/+$'), '');
  final known =
      target.path == AppRoutes.home ||
      _publicPages.containsKey(path) ||
      _protectedPages.containsKey(path);
  if (!known ||
      path == AppRoutes.signIn ||
      path == AppRoutes.signUp ||
      path == AppRoutes.resetPassword) {
    return AppRoutes.menu;
  }
  return target.toString();
}
