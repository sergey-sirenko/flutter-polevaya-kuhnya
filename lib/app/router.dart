import 'package:polevaya_kuhnya/shared/display_formats.dart';
import 'package:polevaya_kuhnya/shared/boot_loading.dart';
import 'package:polevaya_kuhnya/app/navigation.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_banner.dart';
import 'package:polevaya_kuhnya/features/cart/cart_summary_bar.dart';
import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/app/order_layout.dart';
import 'package:polevaya_kuhnya/features/menu/menu_categories_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/adaptive_app_shell.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/site/site_pages.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:polevaya_kuhnya/features/auth/reset_password_page.dart';
import 'package:polevaya_kuhnya/features/auth/sign_in_page.dart';
import 'package:polevaya_kuhnya/features/auth/sign_up_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/orders_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/features/profile/profile_page.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const about = '/about';
  static const delivery = '/delivery';
  static const howToOrder = '/how-to-order';
  static const contacts = '/contacts';
  static const offer = '/offer';
  static const install = '/install';
  static const privacy = '/privacy';
  static const personalDataConsent = '/personal-data-consent';
  static const aboutApp = '/about-app';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const resetPassword = '/reset-password';
  static const menu = '/menu';
  static const cart = '/cart';
  static const orders = '/orders';
  static const categories = '/orders/categories';
  static const profile = '/profile';
}

const _publicPages = {
  AppRoutes.about: AppStrings.about,
  AppRoutes.delivery: AppStrings.delivery,
  AppRoutes.howToOrder: AppStrings.howToOrder,
  AppRoutes.contacts: AppStrings.contacts,
  AppRoutes.offer: AppStrings.offer,
  AppRoutes.install: AppStrings.install,
  AppRoutes.privacy: AppStrings.privacy,
  AppRoutes.personalDataConsent: AppStrings.personalDataConsent,
  AppRoutes.aboutApp: AppStrings.aboutApp,
  AppRoutes.signIn: AppStrings.signIn,
  AppRoutes.signUp: AppStrings.signUp,
  AppRoutes.resetPassword: AppStrings.resetPassword,
  AppRoutes.menu: AppStrings.menu,
};

const _protectedPages = {
  AppRoutes.cart: AppStrings.cart,
  AppRoutes.orders: AppStrings.orders,
  AppRoutes.categories: AppStrings.menu,
  AppRoutes.profile: AppStrings.profile,
};

const _appDestinations = [
  AppRoutes.menu,
  AppRoutes.cart,
  AppRoutes.orders,
  AppRoutes.profile,
];

void _closePopups(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).popUntil((route) => route is! PopupRoute);
}

void _openOrderSheet(BuildContext context, WidgetRef ref, OrderSheet sheet) {
  _closePopups(context);
  ref.read(orderSheetProvider.notifier).toggle(sheet);
  final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
  if (path != AppRoutes.menu) _navigate(context, AppRoutes.menu);
}

Future<void> _openCartDay(
  BuildContext context,
  WidgetRef ref,
  String dateKey,
) async {
  _closePopups(context);
  ref.read(orderSheetProvider.notifier).close();
  ref.read(cartEditControllerProvider.notifier).selectRepeatDay(dateKey);
  final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
  await ref.read(menuSelectionProvider.notifier).openDate(dateKey, weeks);
  if (!context.mounted) return;
  _navigate(context, AppRoutes.menu);
}

Future<void> _openCartCategories(
  BuildContext context,
  WidgetRef ref,
  String dateKey,
) async {
  if (!ref.read(cartDayEditableProvider(dateKey))) return;
  ref.read(cartEditControllerProvider.notifier).selectRepeatDay(dateKey);
  final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
  final opened = await ref
      .read(menuSelectionProvider.notifier)
      .openDate(dateKey, weeks);
  if (!context.mounted ||
      !opened ||
      versionBlocksWork(ref.read(appVersionControllerProvider))) {
    return;
  }
  _closePopups(context);
  ref.read(orderSheetProvider.notifier).close();
  _navigate(
    context,
    MediaQuery.sizeOf(context).width < orderColumnsMinWidth
        ? AppRoutes.categories
        : AppRoutes.menu,
  );
}

void _openOrderMenu(BuildContext context, WidgetRef ref) {
  _closePopups(context);
  final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
  final narrow = MediaQuery.sizeOf(context).width < 600;
  if (path == AppRoutes.menu && narrow) {
    ref.read(orderSheetProvider.notifier).toggle(OrderSheet.categories);
    return;
  }
  ref.read(orderSheetProvider.notifier).close();
  _navigate(context, AppRoutes.menu);
}

final routerProvider = Provider<GoRouter>((ref) {
  // onEnter закрывает переходы; onExit также защищает imperative/system pop.
  bool canLeave(BuildContext context, GoRouterState state) =>
      !versionBlocksWork(ref.read(appVersionControllerProvider));
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final shellNavigatorKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
    // Явный адрес платформы имеет приоритет над обычным стартом ADR-8.
    overridePlatformDefaultLocation: false,
    onEnter: (context, current, next, router) =>
        versionBlocksWork(ref.read(appVersionControllerProvider))
        ? const Block.stop()
        : const Allow(),
    redirect: (context, state) {
      final status = ref.read(sessionStatusProvider);
      // Проверяем совпавший маршрут, а не сырой URL (например, /orders/).
      final path = _routePath(state.uri);
      if (_protectedPages.containsKey(path) &&
          status == SessionStatus.signedOut) {
        return Uri(
          path: AppRoutes.signIn,
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (status == SessionStatus.signedIn) {
        if (path == AppRoutes.signIn) {
          return _returnLocation(state.uri);
        }
        if (path == AppRoutes.signUp) {
          return _returnLocation(state.uri, fallback: AppRoutes.orders);
        }
      }
      return null;
    },
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          final path = _routePath(state.uri);
          final navigation = appNavigationOf(GoRouter.of(context))!;
          Widget content() {
            // Публичные страницы используют тот же Navigator без оболочки заказа.
            if (!_appDestinations.contains(path) &&
                path != AppRoutes.categories) {
              if ([
                AppRoutes.signIn,
                AppRoutes.signUp,
                AppRoutes.resetPassword,
              ].contains(path)) {
                return SiteSectionChrome(
                  destinations: _siteDestinations(context),
                  child: child,
                );
              }
              return child;
            }
            final selectedIndex = path == AppRoutes.categories
                ? 2
                : _appDestinations.indexOf(_routePath(state.uri));
            return Consumer(
              builder: (context, ref, _) {
                void leave(String location) {
                  _closePopups(context);
                  ref.read(orderSheetProvider.notifier).close();
                  _navigate(context, location);
                }

                final chrome = SiteSectionChrome(
                  currentLabel: path == AppRoutes.menu ? AppStrings.menu : null,
                  destinations: SiteDestinations(
                    onHome: () => leave(AppRoutes.home),
                    onMenu: () => leave(AppRoutes.menu),
                    onAbout: () => leave(AppRoutes.about),
                    onDelivery: () => leave(AppRoutes.delivery),
                    onHowToOrder: () => leave(AppRoutes.howToOrder),
                    onContacts: () => leave(AppRoutes.contacts),
                    onOffer: () => leave(AppRoutes.offer),
                    onPrivacy: () => leave(AppRoutes.privacy),
                    onAboutApp: () => leave(AppRoutes.aboutApp),
                  ),
                  child: AdaptiveAppShell(
                    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                    menuPanel: _menuPage(context),
                    cartPanel: CartPage(
                      onOpenDay: (dateKey) =>
                          _openCartDay(context, ref, dateKey),
                      onAddDishes: (dateKey) =>
                          _openCartCategories(context, ref, dateKey),
                    ),
                    bottomSummary: CartSummaryBar(
                      onOpenCart: () => leave(AppRoutes.cart),
                    ),
                    onDaySelected: () =>
                        _openOrderSheet(context, ref, OrderSheet.day),
                    onMenuSelected: () => _openOrderMenu(context, ref),
                    onDestinationSelected: (index) {
                      leave(_appDestinations[index]);
                    },
                    child: child,
                  ),
                );
                return chrome;
              },
            );
          }

          return SiteBackAction(
            onBack: path == AppRoutes.home
                ? null
                : () async {
                    if (navigation.allowed()) {
                      await GoRouter.of(context).routerDelegate.popRoute();
                    }
                  },
            onMenuChanged: (close) => navigation.headerBack.value = close,
            child: content(),
          );
        },
        routes: [
          _semanticRoute(
            onExit: canLeave,
            path: AppRoutes.home,
            caseSensitive: true,
            builder: (context, state) => Consumer(
              builder: (context, ref, _) {
                if (state.uri.path != AppRoutes.home) {
                  return const SizedBox.shrink();
                }
                final config = ref.watch(appConfigProvider);
                final menu = ref.watch(menuControllerProvider);
                if (menu.isLoading) return const BootLoading();
                final weeks = menu.asData?.value;
                final days = (weeks ?? const <MenuWeek>[])
                    .expand((week) => week.deliveryDays)
                    .toList();
                final today = DateUtils.dateOnly(DateTime.now());
                final heroDay =
                    selectedMenuDay(
                      weeks ?? const [],
                      ref.watch(menuSelectionProvider),
                    ) ??
                    days
                        .where((day) => !day.date.isBefore(today))
                        .firstOrNull ??
                    days.firstOrNull;
                final heroCategories =
                    heroDay?.categoriesSorted ?? const <MenuCategory>[];
                final heroDishes =
                    (heroCategories.length > 1
                            ? heroCategories
                                  .skip(1)
                                  .followedBy(heroCategories.take(1))
                            : heroCategories)
                        .expand((category) => category.dishesSorted)
                        .where((dish) => dish.imagePath?.isNotEmpty ?? false)
                        .toList();
                return SiteHomePage(
                  destinations: _siteDestinations(context),
                  onRetryMenu: menu.hasError
                      ? () => ref.read(menuControllerProvider.notifier).reload()
                      : null,
                  heroDayKey: heroDay?.dateKey,
                  heroDishes: [
                    for (final dish in heroDishes)
                      SiteHomeDish(
                        id: dish.dishId,
                        name: dish.dishName,
                        price: dish.price,
                        image: MenuNetworkImage(
                          config: config,
                          imagePath: dish.imagePath,
                          version: dish.imageVersion,
                          fit: BoxFit.contain,
                        ),
                      ),
                  ],
                  categories: [
                    for (final category in uniqueMenuCategories(
                      weeks ?? const [],
                    ))
                      SiteHomeCategory(
                        id: category.categoryId,
                        name: category.categoryName,
                        imagePath: category.categoryImagePath,
                        imageVersion: category.imageVersion,
                      ),
                  ],
                  categoryImage: (category) => MenuNetworkImage(
                    config: config,
                    imagePath: category.imagePath,
                    version: category.imageVersion,
                    width: 120,
                    height: 120,
                  ),
                  onCategory: (category) {
                    final weeks =
                        ref.read(menuControllerProvider).asData?.value ??
                        const <MenuWeek>[];
                    ref
                        .read(menuSelectionProvider.notifier)
                        .showCategory(category.id, weeks);
                    ref
                        .read(menuActiveCategoryProvider.notifier)
                        .select(category.id);
                    _navigate(context, AppRoutes.menu);
                  },
                );
              },
            ),
            routes: [
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.about.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    AboutPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.delivery.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    DeliveryPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.howToOrder.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    HowToOrderPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.contacts.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    ContactsPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.offer.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    OfferPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.install.substring(1),
                caseSensitive: true,
                builder: (context, state) => InstallPage(
                  destinations: _siteDestinations(context),
                  channel: ref.watch(installChannelProvider),
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.privacy.substring(1),
                caseSensitive: true,
                builder: (context, state) => PrivacyPage(
                  destinations: _siteDestinations(context),
                  onBack:
                      appNavigationOf(GoRouter.of(context))!.parent ==
                          AppRoutes.signUp
                      ? () => context.pop()
                      : null,
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.personalDataConsent.substring(1),
                caseSensitive: true,
                builder: (context, state) => PersonalDataConsentPage(
                  destinations: _siteDestinations(context),
                  onBack:
                      appNavigationOf(GoRouter.of(context))!.parent ==
                          AppRoutes.signUp
                      ? () => context.pop()
                      : null,
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.aboutApp.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    AboutAppPage(destinations: _siteDestinations(context)),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.signIn.substring(1),
                caseSensitive: true,
                builder: (context, state) => SignInPage(
                  onSignUp: () => _navigate(
                    context,
                    _authLocation(
                      AppRoutes.signUp,
                      state.uri,
                      fallback: AppRoutes.orders,
                    ),
                  ),
                  onResetPassword: () => _navigate(
                    context,
                    _authLocation(AppRoutes.resetPassword, state.uri),
                  ),
                  onHome: () => _navigate(context, AppRoutes.home),
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.signUp.substring(1),
                caseSensitive: true,
                builder: (context, state) => SignUpPage(
                  onSignIn: () => _navigate(
                    context,
                    _authLocation(
                      AppRoutes.signIn,
                      state.uri,
                      fallback: AppRoutes.orders,
                    ),
                  ),
                  onPrivacy: () => _navigate(context, AppRoutes.privacy),
                  onConsent: () =>
                      _navigate(context, AppRoutes.personalDataConsent),
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.resetPassword.substring(1),
                caseSensitive: true,
                builder: (context, state) => ResetPasswordPage(
                  onSignIn: () => _navigate(
                    context,
                    _authLocation(AppRoutes.signIn, state.uri),
                  ),
                  onHome: () => _navigate(context, AppRoutes.home),
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.menu.substring(1),
                caseSensitive: true,
                builder: (context, state) => _menuPage(context),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.cart.substring(1),
                caseSensitive: true,
                builder: (context, state) =>
                    state.uri.queryParameters['prepare'] != null
                    ? _OrderPreparationPage(
                        key: ValueKey(state.uri.queryParameters['prepare']),
                        dateKey: state.uri.queryParameters['prepare']!,
                      )
                    : Consumer(
                        builder: (context, ref, _) => CartPage(
                          onOpenDay: (dateKey) =>
                              _openCartDay(context, ref, dateKey),
                          onAddDishes: (dateKey) =>
                              _openCartCategories(context, ref, dateKey),
                        ),
                      ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.orders.substring(1),
                caseSensitive: true,
                builder: (context, state) => _ordersPage(context),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.categories.substring(1),
                caseSensitive: true,
                builder: (context, state) => LayoutBuilder(
                  builder: (context, constraints) {
                    if (MediaQuery.sizeOf(context).width >=
                        orderColumnsMinWidth) {
                      return _ordersPage(context);
                    }
                    return Consumer(
                      builder: (context, ref, _) => MenuCategoriesPage(
                        onCategory: (id) {
                          ref
                              .read(menuActiveCategoryProvider.notifier)
                              .select(id);
                          _navigate(context, AppRoutes.menu);
                        },
                      ),
                    );
                  },
                ),
              ),
              _semanticRoute(
                onExit: canLeave,
                path: AppRoutes.profile.substring(1),
                caseSensitive: true,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      return RoutePage(
        title: AppStrings.pageNotFound,
        message: AppStrings.pageNotFoundMessage,
        onHome: () => context.go(AppRoutes.home),
      );
    },
  );
  final navigation = AppNavigation(
    router,
    browserHistory: ref.read(semanticUrlStrategyProvider),
    allowed: () => !versionBlocksWork(ref.read(appVersionControllerProvider)),
    endOrder: () => ref.read(cartEditControllerProvider.notifier).end(),
    hasMenuLayer: () =>
        ref.read(menuHasPhotoOverlayProvider) ||
        ref.read(orderSheetProvider) != null,
  );
  // refresh пересчитывает базовый URI; вход поверх него открыт через push.
  // Заменяем только активную форму входа, сохраняя предыдущие страницы.
  void refreshSessionRoute() {
    final configuration = router.routerDelegate.currentConfiguration;
    if (configuration.matches.isNotEmpty &&
        !versionBlocksWork(ref.read(appVersionControllerProvider))) {
      final active = router.routerDelegate.state;
      final status = ref.read(sessionStatusProvider);
      if (status == SessionStatus.signedIn &&
          configuration.last is ImperativeRouteMatch) {
        if (_routePath(active.uri) == AppRoutes.signIn) {
          router.go(_returnLocation(active.uri));
          return;
        }
        if (_routePath(active.uri) == AppRoutes.signUp) {
          router.go(_returnLocation(active.uri, fallback: AppRoutes.orders));
          return;
        }
      }
      if (status == SessionStatus.signedOut &&
          _protectedPages.containsKey(_routePath(active.uri))) {
        // Выход закрывает личную историю; Back не открывает прежний стек.
        router.go(
          Uri(
            path: AppRoutes.signIn,
            queryParameters: {'from': active.uri.toString()},
          ).toString(),
        );
        return;
      }
    }
    router.refresh();
  }

  ref.listen(sessionStatusProvider, (previous, next) => refreshSessionRoute());
  ref.listen(appVersionControllerProvider, (previous, next) {
    if (!versionBlocksWork(next)) refreshSessionRoute();
  });
  String? previousPath;
  void observeEditRoute() {
    if (router.routerDelegate.currentConfiguration.matches.isEmpty) return;
    final path = router.routerDelegate.state.uri.path;
    if (path != previousPath) {
      if (previousPath != null &&
          (path == AppRoutes.orders ||
              (!{
                    AppRoutes.cart,
                    AppRoutes.categories,
                    AppRoutes.menu,
                  }.contains(path) &&
                  ref.read(cartEditControllerProvider).active) ||
              ref.read(cartEditControllerProvider).loading)) {
        navigation.clearOrder();
        ref.read(cartEditControllerProvider.notifier).end();
      }
      previousPath = path;
    }
  }

  router.routerDelegate.addListener(observeEditRoute);
  ref.onDispose(() => router.routerDelegate.removeListener(observeEditRoute));
  ref.onDispose(navigation.headerBack.dispose);
  ref.onDispose(() => navigation.browserHistory?.consumeBack = null);
  ref.onDispose(router.dispose);
  return router;
});

SiteDestinations _siteDestinations(BuildContext context) {
  return SiteDestinations(
    onHome: () => _navigate(context, AppRoutes.home),
    onMenu: () => _navigate(
      context,
      MediaQuery.sizeOf(context).width >= orderColumnsMinWidth
          ? AppRoutes.orders
          : AppRoutes.menu,
    ),
    onOrderLunch: () => _navigate(context, AppRoutes.orders),
    onProfile: () => _navigate(context, AppRoutes.profile),
    onAbout: () => _navigate(context, AppRoutes.about),
    onDelivery: () => _navigate(context, AppRoutes.delivery),
    onHowToOrder: () => _navigate(context, AppRoutes.howToOrder),
    onContacts: () => _navigate(context, AppRoutes.contacts),
    onOffer: () => _navigate(context, AppRoutes.offer),
    onPrivacy: () => _navigate(context, AppRoutes.privacy),
    onAboutApp: () => _navigate(context, AppRoutes.aboutApp),
  );
}

String _routePath(Uri uri) =>
    uri.path == '/' ? '/' : uri.path.replaceFirst(RegExp(r'/+$'), '');

void _navigate(BuildContext context, String location) =>
    appNavigate(context, location);

Widget _ordersPage(BuildContext context) => Consumer(
  builder: (context, ref, _) => OrdersPage(
    onRepeatReady: () async {
      final router = GoRouter.of(context);
      final source = router.routerDelegate.state.uri;
      final scope = ref.read(cartEditControllerProvider).repeatScope;
      final date = ref.read(cartEditControllerProvider).dateKey;
      if (date == null) return;
      final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
      await ref.read(menuSelectionProvider.notifier).openDate(date, weeks);
      if (!context.mounted ||
          router.routerDelegate.state.uri != source ||
          ref.read(cartEditControllerProvider).repeatScope != scope) {
        return;
      }
      ref.read(orderSheetProvider.notifier).close();
      appNavigationOf(GoRouter.of(context))!.startOrder(skipCart: false);
      _navigate(context, AppRoutes.cart);
    },
    selectedDateKey: ref.watch(menuSelectionProvider)?.dateKey,
    onSelectDay: (dateKey) {
      ref.read(orderSheetProvider.notifier).close();
      final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
      ref.read(menuSelectionProvider.notifier).openDate(dateKey, weeks);
    },
    onStartOrder: (dateKey) {
      ref.read(orderSheetProvider.notifier).close();
      final router = GoRouter.of(context);
      appNavigationOf(router)!.startOrder(skipCart: false);
      _navigate(
        context,
        Uri(
          path: AppRoutes.cart,
          queryParameters: {'prepare': dateKey},
        ).toString(),
      );
    },
  ),
);

MenuPage _menuPage(BuildContext context) {
  return MenuPage(
    onHome: () => _navigate(context, AppRoutes.home),
    onSignIn: () => _navigate(
      context,
      Uri(
        path: AppRoutes.signIn,
        queryParameters: {'from': AppRoutes.menu},
      ).toString(),
    ),
  );
}

String _authLocation(
  String path,
  Uri source, {
  String fallback = AppRoutes.menu,
}) => Uri(
  path: path,
  queryParameters: {'from': _returnLocation(source, fallback: fallback)},
).toString();

String _returnLocation(Uri signInUri, {String fallback = AppRoutes.menu}) {
  final values = signInUri.queryParametersAll['from'];
  if (values == null || values.length != 1) return fallback;
  final target = Uri.tryParse(values.single);
  if (target == null || target.hasScheme || target.hasAuthority) {
    return fallback;
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
    return fallback;
  }
  return target.toString();
}

GoRoute _semanticRoute({
  required String path,
  required GoRouterWidgetBuilder builder,
  ExitCallback? onExit,
  bool caseSensitive = true,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  onExit: onExit,
  caseSensitive: caseSensitive,
  routes: routes,
  builder: (context, state) => AppRouteBackScope(
    navigation: appNavigationOf(GoRouter.of(context))!,
    child: builder(context, state),
  ),
);

/// Показываем следующий экран до обновления профиля и доступности дней.
class _OrderPreparationPage extends ConsumerStatefulWidget {
  const _OrderPreparationPage({required this.dateKey, super.key});
  final String dateKey;

  @override
  ConsumerState<_OrderPreparationPage> createState() =>
      _OrderPreparationPageState();
}

class _OrderPreparationPageState extends ConsumerState<_OrderPreparationPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    // Следующий кадр гарантирует отображение экрана до сетевой подготовки.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final router = GoRouter.of(context);
    final source = router.routerDelegate.state.uri;
    if (source.path != AppRoutes.cart ||
        source.queryParameters['prepare'] != widget.dateKey) {
      return;
    }
    bool current() => mounted && router.routerDelegate.state.uri == source;
    final ready = await ref
        .read(cartEditControllerProvider.notifier)
        .begin(widget.dateKey);
    if (!mounted || !current()) return;
    if (!ready) {
      setState(() {
        _loading = false;
        _error = ref.read(cartEditControllerProvider).message ?? 'Не удалось подготовить заказ. Вернитесь в заказы или повторите загрузку.';
      });
      return;
    }
    await _openPrepared(widget.dateKey, source);
  }

  Future<void> _openPrepared(String dateKey, Uri source) async {
    if (!mounted) return;
    final router = GoRouter.of(context);
    bool current() => mounted && router.routerDelegate.state.uri == source;
    if (!current() ||
        source.path != AppRoutes.cart ||
        source.queryParameters['prepare'] != widget.dateKey) {
      return;
    }
    final weeks = ref.read(menuControllerProvider).asData?.value ?? const [];
    final opened = await ref
        .read(menuSelectionProvider.notifier)
        .openDate(dateKey, weeks);
    if (!mounted || !current()) return;
    if (!opened ||
        ref.read(cartEditControllerProvider).dateKey != dateKey ||
        versionBlocksWork(ref.read(appVersionControllerProvider))) {
      setState(() {
        _loading = false;
        _error = 'День недоступен для изменения. Вернитесь в заказы.';
      });
      return;
    }
    final skipCart =
        MediaQuery.sizeOf(context).width < orderColumnsMinWidth &&
        ref.read(cartEditControllerProvider).originals[dateKey]?.isEmpty ==
            true &&
        ref.read(editingCartProvider).dayFor(dateKey) == null;
    appNavigationOf(router)!.startOrder(skipCart: skipCart);
    if (skipCart) {
      _navigate(context, AppRoutes.categories);
    } else {
      // Заменяем экран подготовки, сохраняя путь Назад в календарь.
      router.replace(AppRoutes.cart);
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _prepare();
  }

  @override
  Widget build(BuildContext context) {
    final edit = ref.watch(cartEditControllerProvider);
    final savedWork = !edit.isRepeat && (edit.hasSavedWork || edit.blocked);
    final source = GoRouter.of(context).routerDelegate.state.uri;
    return Scaffold(
      key: const ValueKey('order-preparation-page'),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: MediaQuery.sizeOf(context).width < orderColumnsMinWidth
            ? const Text(AppStrings.cart, key: ValueKey('route-page-title'))
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatMenuDayLabel(widget.dateKey)),
              const SizedBox(height: 16),
              if (_loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Подготовка заказа…'),
              ] else if (savedWork) ...[
                CartWorkBanner(
                  onReady: () {
                    final date = ref.read(cartEditControllerProvider).dateKey;
                    if (date != null) _openPrepared(date, source);
                  },
                  onDiscarded: () {
                    if (mounted &&
                        GoRouter.of(context).routerDelegate.state.uri ==
                            source) {
                      _retry();
                    }
                  },
                ),
              ] else ...[
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('order-preparation-retry'),
                  onPressed: _retry,
                  child: const Text('Повторить загрузку'),
                ),
              ],
              TextButton(
                key: const ValueKey('order-preparation-back'),
                onPressed: () => _navigate(context, AppRoutes.orders),
                child: const Text('Вернуться в заказы'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
