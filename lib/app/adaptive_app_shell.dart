import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';
import 'package:polevaya_kuhnya/app/order_layout.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

class AdaptiveAppShell extends StatefulWidget {
  const AdaptiveAppShell({
    required this.selectedIndex,
    required this.child,
    required this.menuPanel,
    required this.cartPanel,
    required this.onDestinationSelected,
    required this.onDaySelected,
    required this.onMenuSelected,
    this.bottomSummary,
    super.key,
  });

  final int selectedIndex;
  final Widget child;
  final Widget menuPanel;
  final Widget cartPanel;
  final Widget? bottomSummary;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onDaySelected;
  final VoidCallback onMenuSelected;

  @override
  State<AdaptiveAppShell> createState() => _AdaptiveAppShellState();
}

class _AdaptiveAppShellState extends State<AdaptiveAppShell> {
  // Перенос активного экрана между body, rail и колонками без потери State.
  final _activePageKey = GlobalKey();

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
    final selectedIndex = widget.selectedIndex;
    final menuPanel = widget.menuPanel;
    final cartPanel = widget.cartPanel;
    final onDestinationSelected = widget.onDestinationSelected;
    final onDaySelected = widget.onDaySelected;
    final onMenuSelected = widget.onMenuSelected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = KeyedSubtree(key: _activePageKey, child: widget.child);
        if (constraints.maxWidth < 600) {
          return Scaffold(
            body: child,
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedIndex == 0 && widget.bottomSummary != null)
                  widget.bottomSummary!,
                _OrderBottomBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  onDaySelected: onDaySelected,
                  onMenuSelected: onMenuSelected,
                ),
              ],
            ),
          );
        }

        final columns = constraints.maxWidth >= orderColumnsMinWidth;
        if (columns) {
          return _OrderColumns(
            selectedIndex: selectedIndex,
            menuPanel: menuPanel,
            cartPanel: cartPanel,
            onDestinationSelected: onDestinationSelected,
            width: constraints.maxWidth,
            child: child,
          );
        }
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) {
                    final destinations = [0, 1, if (selectedIndex != 1) 2, 3];
                    onDestinationSelected(destinations[index]);
                  },
                  destinations: [
                    for (var index = 0; index < _labels.length; index++)
                      if (selectedIndex != 1 || index != 2)
                        NavigationRailDestination(
                          icon: Icon(_icons[index]),
                          selectedIcon: Icon(_selectedIcons[index]),
                          label: Text(_labels[index]),
                        ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OrderColumns extends StatelessWidget {
  const _OrderColumns({
    required this.selectedIndex,
    required this.menuPanel,
    required this.cartPanel,
    required this.child,
    required this.onDestinationSelected,
    required this.width,
  });

  final int selectedIndex;
  final Widget menuPanel;
  final Widget cartPanel;
  final Widget child;
  final ValueChanged<int> onDestinationSelected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final sideIndex = selectedIndex == 0 ? 1 : selectedIndex;
    final sideChild = selectedIndex == 0 ? cartPanel : child;
    final sideKey = switch (sideIndex) {
      2 => 'orders-panel',
      3 => 'profile-panel',
      _ => 'cart-panel',
    };
    return Scaffold(
      body: SafeArea(
        child: Row(
          key: const ValueKey('menu-cart-columns'),
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('menu-panel'),
                child: selectedIndex == 0 ? child : menuPanel,
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: orderSideWidth(width),
              child: Column(
                children: [
                  _OrderSideNav(
                    selectedIndex: sideIndex,
                    onDestinationSelected: onDestinationSelected,
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(sideKey),
                      child: sideChild,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSideNav extends StatelessWidget {
  const _OrderSideNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <(int, String, ValueKey<String>)>[
      if (selectedIndex == 1)
        (1, AppStrings.cart, const ValueKey('order-side-cart'))
      else
        (2, AppStrings.ordersTab, const ValueKey('order-side-orders')),
      (3, AppStrings.profile, const ValueKey('order-side-profile')),
    ];
    return Material(
      key: const ValueKey('order-side-nav'),
      color: scheme.surface,
      child: Row(
        children: [
          for (final (index, label, key) in items)
            Expanded(
              child: TextButton(
                key: key,
                style: TextButton.styleFrom(
                  foregroundColor: index == selectedIndex
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  backgroundColor: index == selectedIndex
                      ? scheme.secondaryContainer
                      : null,
                  minimumSize: const Size(0, 44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: () => onDestinationSelected(index),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderBottomBar extends ConsumerWidget {
  const _OrderBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onDaySelected,
    required this.onMenuSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onDaySelected;
  final VoidCallback onMenuSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(menuSelectionProvider);
    final scheme = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 18.2;
    final items = <Widget>[
      _OrderBottomItem(
        itemKey: const ValueKey('order-bottom-day'),
        label: selection == null
            ? AppStrings.orderDay
            : formatMenuDayLabel(selection.dateKey),
        icon: Icons.calendar_today_outlined,
        selected: false,
        onTap: onDaySelected,
      ),
      _OrderBottomItem(
        itemKey: const ValueKey('order-bottom-menu'),
        label: AppStrings.menu,
        icon: selectedIndex == 0
            ? Icons.restaurant_menu
            : Icons.restaurant_menu_outlined,
        selected: selectedIndex == 0,
        onTap: onMenuSelected,
      ),
      _OrderBottomItem(
        itemKey: const ValueKey('order-bottom-order'),
        label: selectedIndex == 1 ? AppStrings.cart : AppStrings.orderAction,
        icon: selectedIndex == 1 || selectedIndex == 2
            ? Icons.shopping_cart
            : Icons.shopping_cart_outlined,
        selected: selectedIndex == 1 || selectedIndex == 2,
        onTap: () => onDestinationSelected(selectedIndex == 1 ? 1 : 2),
      ),
      _OrderBottomItem(
        itemKey: const ValueKey('order-bottom-profile'),
        label: AppStrings.profile,
        icon: selectedIndex == 3 ? Icons.person : Icons.person_outline,
        selected: selectedIndex == 3,
        onTap: () => onDestinationSelected(3),
      ),
    ];
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const ValueKey('order-bottom-bar'),
          height:
              (56 +
                  (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                    0,
                    100,
                  )) *
              (largeText ? 2 : 1),
          child: largeText
              ? Column(
                  children: [
                    Expanded(child: Row(children: items.take(2).toList())),
                    Expanded(child: Row(children: items.skip(2).toList())),
                  ],
                )
              : Row(children: items),
        ),
      ),
    );
  }
}

class _OrderBottomItem extends StatelessWidget {
  const _OrderBottomItem({
    required this.itemKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Key itemKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: selected ? scheme.secondaryContainer : scheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            key: itemKey,
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: color, height: 1.1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
