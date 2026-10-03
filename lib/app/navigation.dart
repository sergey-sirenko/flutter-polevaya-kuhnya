import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/core/platform/semantic_url_strategy.dart';

/// Один ограниченный сценарий, а не журнал всех посещённых разделов.
final _navigations = Expando<AppNavigation>();

class AppNavigation {
  AppNavigation(
    this.router, {
    required this.allowed,
    required this.endOrder,
    required this.hasMenuLayer,
    this.browserHistory,
  }) {
    _navigations[router] = this;
    browserHistory?.consumeBack = () {
      if (!allowed()) return true;
      final closeHeader = headerBack.value;
      if (closeHeader != null) {
        closeHeader();
        return true;
      }
      if (path == '/menu' && hasMenuLayer()) {
        unawaited(router.routerDelegate.popRoute());
        return true;
      }
      return false;
    };
  }

  final GoRouter router;
  final bool Function() allowed;
  final VoidCallback endOrder;
  final bool Function() hasMenuLayer;
  final SemanticUrlStrategy? browserHistory;
  final headerBack = ValueNotifier<VoidCallback?>(null);
  List<String>? _orderSteps;

  void startOrder({required bool skipCart}) {
    _orderSteps = [
      '/orders',
      if (!skipCart) '/cart',
      '/orders/categories',
      '/menu',
    ];
  }

  void clearOrder() => _orderSteps = null;

  List<RouteMatch> get stack {
    final result = <RouteMatch>[];
    void collect(List<RouteMatchBase> matches) {
      for (final match in matches) {
        if (match is ShellRouteMatch) {
          collect(match.matches);
        } else if (match is RouteMatch) {
          result.add(match);
        }
      }
    }

    collect(router.routerDelegate.currentConfiguration.matches);
    return result;
  }

  String get path => router.routerDelegate.state.uri.path;

  String? get parent {
    if (path == '/') return null;
    if (path == '/sign-up' || path == '/reset-password') return '/sign-in';
    if ((path == '/privacy' || path == '/personal-data-consent') &&
        stack.any((match) => match.matchedLocation == '/sign-up')) {
      return '/sign-up';
    }
    final steps = _orderSteps;
    if (steps != null && steps.contains(path)) {
      final index = steps.indexOf(path);
      if (index > 0) return steps[index - 1];
    }
    if (path == '/orders/categories') return '/orders';
    return '/';
  }

  /// Используем существующие ключи страниц, в частности сохранённую форму.
  RouteMatchList _prefix(List<String> locations) {
    var result = router.configuration.findMatch(Uri.parse(locations.first));
    final existing = stack;
    final current = router.routerDelegate.currentConfiguration;
    if (current.uri.path == locations.first) {
      result = router.configuration.findMatch(current.uri);
    }
    for (final location in locations.skip(1)) {
      final previous = existing.where(
        (match) => match.matchedLocation == location,
      );
      final match = previous.isEmpty ? null : previous.last;
      result = result.push(
        match is ImperativeRouteMatch
            ? match
            : ImperativeRouteMatch(
                pageKey: match?.pageKey ?? ValueKey('semantic-$location'),
                matches: router.configuration.findMatch(Uri.parse(location)),
                completer: Completer<Object?>(),
              ),
      );
    }
    return result;
  }

  void navigate(BuildContext context, String location) {
    if (!allowed()) return;
    final target = Uri.parse(location).path;
    if (router.routeInformationProvider.value.uri.toString() == location) {
      return;
    }
    if (_orderSteps == null &&
        path == '/orders/categories' &&
        target == '/menu') {
      startOrder(skipCart: true);
    }
    List<String>? steps;
    if (_orderSteps != null &&
        ['/cart', '/orders/categories', '/menu'].contains(target)) {
      // Явное открытие корзины добавляет её даже для изначально пустого дня.
      if (target == '/cart' && !_orderSteps!.contains('/cart')) {
        _orderSteps = ['/orders', '/cart', '/orders/categories', '/menu'];
      }
      steps = _orderSteps!.take(_orderSteps!.indexOf(target) + 1).toList();
    } else if (target == '/sign-up' || target == '/reset-password') {
      steps = ['/sign-in', location];
    } else if ((target == '/privacy' || target == '/personal-data-consent') &&
        path == '/sign-up') {
      steps = ['/sign-in', '/sign-up', location];
    }
    if (steps == null) {
      if (_orderSteps != null) {
        clearOrder();
        endOrder();
      }
      // Меняем текущий раздел в браузерной истории; сохраняем вход с главной.
      if (path != '/' && target != '/') {
        Router.neglect(context, () => router.go(location));
      } else {
        router.go(location);
      }
      return;
    }
    final existing = stack.where((match) => match.matchedLocation == target);
    if (existing.isNotEmpty) {
      Router.neglect(context, () => router.restore(_prefix(steps!)));
    } else {
      router.routeInformationProvider.push<void>(
        location,
        base: _prefix(steps.take(steps.length - 1).toList()),
      );
    }
  }
}

AppNavigation? appNavigationOf(GoRouter router) => _navigations[router];

void appNavigate(BuildContext context, String location) {
  final router = GoRouter.of(context);
  final navigation = appNavigationOf(router);
  if (navigation == null) {
    router.go(location);
  } else {
    navigation.navigate(context, location);
  }
}

/// Для прямого URL вложенного шага, у которого ещё нет смыслового родителя.
class AppRouteBackScope extends StatelessWidget {
  const AppRouteBackScope({
    required this.navigation,
    required this.child,
    super.key,
  });
  final AppNavigation navigation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = navigation.parent;
    final stack = navigation.stack;
    final actualParent = stack.length > 1
        ? stack[stack.length - 2].matchedLocation
        : null;
    final fallback = parent != null && actualParent != parent;
    return ValueListenableBuilder<VoidCallback?>(
      valueListenable: navigation.headerBack,
      builder: (context, closeHeader, child) => PopScope(
        canPop: closeHeader == null && !fallback,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !navigation.allowed()) return;
          if (closeHeader != null) {
            closeHeader();
          } else if (fallback &&
              !(navigation.path == '/menu' && navigation.hasMenuLayer())) {
            appNavigate(context, parent);
          }
        },
        child: child!,
      ),
      child: child,
    );
  }
}
