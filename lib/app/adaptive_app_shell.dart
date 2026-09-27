import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

class AdaptiveAppShell extends StatelessWidget {
  const AdaptiveAppShell({
    required this.selectedIndex,
    required this.child,
    required this.menuPanel,
    required this.cartPanel,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final Widget child;
  final Widget menuPanel;
  final Widget cartPanel;
  final ValueChanged<int> onDestinationSelected;

  static const _labels = [
    AppStrings.menu,
    AppStrings.cart,
    AppStrings.ordersTab,
    AppStrings.profile,
  ];
  static const _icons = [
    Icons.restaurant_menu_outlined,
    Icons.shopping_cart_outlined,
    Icons.receipt_long_outlined,
    Icons.person_outline,
  ];
  static const _selectedIcons = [
    Icons.restaurant_menu,
    Icons.shopping_cart,
    Icons.receipt_long,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Scaffold(
            body: child,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (var index = 0; index < _labels.length; index++)
                  NavigationDestination(
                    icon: Icon(_icons[index]),
                    selectedIcon: Icon(_selectedIcons[index]),
                    label: _labels[index],
                  ),
              ],
            ),
          );
        }

        final wide = constraints.maxWidth >= 1024;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (var index = 0; index < _labels.length; index++)
                      NavigationRailDestination(
                        icon: Icon(_icons[index]),
                        selectedIcon: Icon(_selectedIcons[index]),
                        label: Text(_labels[index]),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: wide && selectedIndex <= 1
                      ? Row(
                          key: const ValueKey('menu-cart-columns'),
                          children: [
                            Expanded(
                              child: KeyedSubtree(
                                key: const ValueKey('menu-panel'),
                                child: selectedIndex == 0 ? child : menuPanel,
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: KeyedSubtree(
                                key: const ValueKey('cart-panel'),
                                child: selectedIndex == 1 ? child : cartPanel,
                              ),
                            ),
                          ],
                        )
                      : child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
