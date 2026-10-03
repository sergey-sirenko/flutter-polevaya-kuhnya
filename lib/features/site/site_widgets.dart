import 'package:polevaya_kuhnya/app/order_layout.dart';
import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';
import 'package:polevaya_kuhnya/shared/external_link.dart';

/// Переходы информационных страниц. Маршруты задаёт единственный router.
class SiteDestinations {
  const SiteDestinations({
    required this.onHome,
    required this.onMenu,
    this.onOrderLunch,
    this.onProfile,
    required this.onAbout,
    required this.onDelivery,
    required this.onHowToOrder,
    required this.onContacts,
    required this.onOffer,
    required this.onPrivacy,
    required this.onAboutApp,
  });

  final VoidCallback onHome;
  final VoidCallback onMenu;
  final VoidCallback? onOrderLunch;
  final VoidCallback? onProfile;
  final VoidCallback onAbout;
  final VoidCallback onDelivery;
  final VoidCallback onHowToOrder;
  final VoidCallback onContacts;
  final VoidCallback onOffer;
  final VoidCallback onPrivacy;
  final VoidCallback onAboutApp;

  List<(String, VoidCallback)> get sections => [
    (AppStrings.menu, onMenu),
    (AppStrings.about, onAbout),
    (AppStrings.delivery, onDelivery),
    (AppStrings.howToOrder, onHowToOrder),
    (AppStrings.contacts, onContacts),
    (AppStrings.offer, onOffer),
  ];

  List<(String, VoidCallback)> get compactSections => [
    ...sections,
    if (onProfile case final action?) (AppStrings.profile, action),
  ];
}

class _SiteBrand extends StatelessWidget {
  const _SiteBrand({required this.onPressed, this.flexible = false});

  final VoidCallback onPressed;
  final bool flexible;

  static const logoKey = ValueKey('site-brand-logo');
  static const logoSize = 56.0;
  static const title = 'Полевая\nкухня';

  @override
  Widget build(BuildContext context) {
    final label = Text(
      _SiteBrand.title,
      semanticsLabel: AppStrings.appTitle,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return TextButton(
      key: const ValueKey('site-brand'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Row(
        children: [
          const ClipOval(
            child: Image(
              image: AssetImage('assets/branding/app-logo-cb1bbbb6c0df.png'),
              key: logoKey,
              width: _SiteBrand.logoSize,
              height: _SiteBrand.logoSize,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 8),
          if (flexible) Expanded(child: label) else label,
        ],
      ),
    );
  }
}

const siteContentMaxWidth = 1200.0;
const siteNavMaxWidth = 1440.0;

/// Действие широкого верхнего меню. В компактном окне не показывается.
class SiteNavAction extends InheritedWidget {
  const SiteNavAction({required this.action, required super.child, super.key});

  final Widget action;

  static Widget? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SiteNavAction>()?.action;
  }

  @override
  bool updateShouldNotify(SiteNavAction oldWidget) =>
      action != oldWidget.action;
}

/// Router задаёт возврат, общая шапка отвечает за расположение и размер.
class SiteBackAction extends InheritedWidget {
  const SiteBackAction({
    required this.onBack,
    this.onMenuChanged,
    required super.child,
    super.key,
  });
  final VoidCallback? onBack;
  final void Function(VoidCallback?)? onMenuChanged;

  static Widget? buttonOf(
    BuildContext context, {
    VoidCallback? closeMenu,
    bool forceIcon = false,
  }) {
    final action = context.dependOnInheritedWidgetOfExactType<SiteBackAction>();
    if (action?.onBack == null) return null;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    if (size.width >= orderColumnsMinWidth) return null;
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final needed =
        56 +
        8 +
        16 +
        measure(_SiteBrand.title, theme.textTheme.titleMedium) +
        24 +
        8 +
        16 +
        measure('Назад', theme.textTheme.labelLarge) +
        48 +
        sitePagePadding(size.width) * 2;
    final onPressed = closeMenu ?? action!.onBack;
    if (forceIcon || size.width < needed) {
      return IconButton(
        key: const ValueKey('app-history-back'),
        tooltip: 'Назад',
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      );
    }
    return TextButton.icon(
      key: const ValueKey('app-history-back'),
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back),
      label: const Text('Назад'),
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    );
  }

  @override
  bool updateShouldNotify(SiteBackAction oldWidget) =>
      onBack != oldWidget.onBack;
}

/// Порог полной шапки «Городского обеда».
const siteNavSingleRowMinWidth = 1200.0;

/// Низкое альбомное окно тоже сворачивает меню, как media query рабочего сайта.
const siteNavLandscapeMaxHeight = 500.0;

/// Высота верхней строки: круглый логотип 56 px и небольшой зазор.
const siteNavBarHeight = 72.0;

double _siteNavHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: _SiteBrand.title,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout();
  final height = painter.height + 16;
  painter.dispose();
  return height > siteNavBarHeight ? height : siteNavBarHeight;
}

/// Строка разделов видна, пока окно не стало узким или низким альбомным.
bool siteNavIsCompact(Size size, {double requiredWidth = 0}) {
  if (size.width < siteNavSingleRowMinWidth || size.width < requiredWidth) {
    return true;
  }
  return size.width > size.height && size.height <= siteNavLandscapeMaxHeight;
}

// Измеряем ту же типографику, что использует строка. Учитываем действие
// скачивания: оно задаётся интеграционным слоем через SiteNavAction.
double _siteNavRequiredWidth(
  BuildContext context,
  Size size,
  SiteDestinations destinations, {
  bool iconBack = false,
}) {
  final theme = Theme.of(context);
  double measure(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  const padding = 16.0;
  var required =
      56 + 8 + 16 + measure(_SiteBrand.title, theme.textTheme.titleMedium);
  for (final (label, _) in destinations.sections) {
    required += measure(label, theme.textTheme.labelMedium) + 16;
  }
  if (SiteNavAction.maybeOf(context) != null) {
    required +=
        measure(AppStrings.menuDownload, theme.textTheme.labelLarge) + 32;
  }
  if (size.width < orderColumnsMinWidth &&
      context.dependOnInheritedWidgetOfExactType<SiteBackAction>()?.onBack !=
          null) {
    required += iconBack
        ? 48
        : 24 + 8 + 16 + measure('Назад', theme.textTheme.labelLarge);
  }
  required += padding * 2;
  return required;
}

bool _compactSiteNav(
  BuildContext context,
  Size size,
  SiteDestinations destinations,
) {
  final required = _siteNavRequiredWidth(
    context,
    size,
    destinations,
    iconBack: true,
  );
  return required > siteNavMaxWidth ||
      siteNavIsCompact(size, requiredWidth: required);
}

bool _wideBackNeedsIcon(BuildContext context, SiteDestinations destinations) {
  final size = MediaQuery.sizeOf(context);
  final required = _siteNavRequiredWidth(context, size, destinations);
  return required > siteNavMaxWidth || required > size.width;
}

const siteGridTwoColumnMaxWidth = 768.0;

/// Небольшая витрина: высота каждой строки задаётся её содержимым.
class SiteCardGrid extends StatelessWidget {
  const SiteCardGrid({
    required this.columns,
    required this.children,
    super.key,
  });

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: start + column < children.length
                        ? children[start + column]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

double sitePagePadding(double width) {
  if (width < 600) return 16;
  if (width < 1024) return 24;
  return 32;
}

class SiteFrame extends StatefulWidget {
  const SiteFrame({
    required this.destinations,
    required this.child,
    this.title,
    super.key,
  });

  static const contentKey = ValueKey('site-content');
  static const pageScrollKey = ValueKey('site-page-scroll');
  static const navToggleKey = ValueKey('site-nav-toggle');
  static const navBarKey = ValueKey('site-nav-bar');
  static const navRowKey = ValueKey('site-nav-row');
  static const navPanelKey = ValueKey('site-nav-panel');
  static const navBarrierKey = ValueKey('site-nav-barrier');

  final SiteDestinations destinations;
  final Widget child;
  final String? title;

  static ValueKey<String> navItemKey(String label) =>
      ValueKey('site-nav-$label');

  @override
  State<SiteFrame> createState() => _SiteFrameState();
}

class _SiteFrameState extends State<SiteFrame> {
  bool _navOpen = false;

  void _closeNav() {
    if (_navOpen) {
      setState(() => _navOpen = false);
      context
          .dependOnInheritedWidgetOfExactType<SiteBackAction>()
          ?.onMenuChanged
          ?.call(null);
    }
  }

  void _toggleNav() {
    setState(() => _navOpen = !_navOpen);
    context
        .dependOnInheritedWidgetOfExactType<SiteBackAction>()
        ?.onMenuChanged
        ?.call(_navOpen ? _closeNav : null);
  }

  List<Widget> _sectionButtons(ThemeData theme, {required bool compact}) {
    return [
      for (final (label, onTap)
          in (compact
              ? widget.destinations.compactSections
              : widget.destinations.sections))
        TextButton(
          key: SiteFrame.navItemKey(label),
          style: TextButton.styleFrom(
            foregroundColor: label == widget.title
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            backgroundColor: label == widget.title
                ? theme.colorScheme.secondaryContainer
                : null,
            textStyle: compact
                ? theme.textTheme.titleMedium?.copyWith(fontSize: 18)
                : theme.textTheme.labelMedium,
            alignment: compact ? Alignment.centerLeft : Alignment.center,
            minimumSize: Size(44, compact ? 48 : 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onPressed: () {
            _closeNav();
            onTap();
          },
          child: Text(label),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.title ?? AppStrings.appTitle;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth;
        final compact = _compactSiteNav(context, size, widget.destinations);
        if (!compact && _navOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _navOpen) _closeNav();
          });
        }
        final open = compact && _navOpen;
        final padding = sitePagePadding(width.isFinite ? width : 1200);
        final sections = _sectionButtons(theme, compact: compact);
        final navigation = compact
            ? SizedBox(
                height: _siteNavHeight(context),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SiteBrand(
                          onPressed: widget.destinations.onHome,
                          flexible: true,
                        ),
                      ),
                      ?SiteBackAction.buttonOf(
                        context,
                        closeMenu: open ? _closeNav : null,
                      ),
                      IconButton(
                        key: SiteFrame.navToggleKey,
                        tooltip: open
                            ? AppStrings.close
                            : AppStrings.siteSections,
                        onPressed: () => _toggleNav(),
                        icon: Icon(open ? Icons.close : Icons.menu),
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: siteNavMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SingleChildScrollView(
                      key: SiteFrame.navBarKey,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        key: SiteFrame.navRowKey,
                        children: [
                          _SiteBrand(onPressed: widget.destinations.onHome),
                          ?SiteBackAction.buttonOf(
                            context,
                            forceIcon: _wideBackNeedsIcon(
                              context,
                              widget.destinations,
                            ),
                          ),
                          ...sections,
                          ?SiteNavAction.maybeOf(context),
                        ],
                      ),
                    ),
                  ),
                ),
              );
        final titleBar = widget.title == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kToolbarHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    heading,
                    key: const ValueKey('route-page-title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              );
        final panelMaxHeight =
            ((constraints.maxHeight.isFinite ? constraints.maxHeight : 900) -
                    60 -
                    kToolbarHeight)
                .clamp(120.0, double.infinity) *
            0.75;
        return PopScope(
          canPop: !open,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && open) _closeNav();
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Material(color: theme.colorScheme.surface, child: navigation),
                  if (open)
                    Material(
                      key: SiteFrame.navPanelKey,
                      color: theme.colorScheme.surface,
                      elevation: 8,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: panelMaxHeight),
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(horizontal: padding),
                          children: sections,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            ?titleBar,
                            Expanded(
                              child: SingleChildScrollView(
                                key: SiteFrame.pageScrollKey,
                                physics: open
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                padding: EdgeInsets.symmetric(
                                  vertical: padding,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Center(
                                      child: ConstrainedBox(
                                        key: SiteFrame.contentKey,
                                        constraints: const BoxConstraints(
                                          maxWidth: siteContentMaxWidth,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: padding,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [widget.child],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    _SiteFooter(
                                      destinations: widget.destinations,
                                      padding: padding,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (open)
                          Positioned.fill(
                            child: GestureDetector(
                              key: SiteFrame.navBarrierKey,
                              onTap: _closeNav,
                              behavior: HitTestBehavior.opaque,
                              child: ColoredBox(
                                color: theme.colorScheme.scrim.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Верхняя полоса разделов на экранах заказа. До адаптивного окна разделы
/// видны строкой, как на рабочем сайте; в узком или низком альбомном окне
/// остаётся кнопка.
class SiteSectionChrome extends StatefulWidget {
  const SiteSectionChrome({
    required this.destinations,
    required this.child,
    this.currentLabel,
    super.key,
  });

  final SiteDestinations destinations;
  final Widget child;
  final String? currentLabel;

  @override
  State<SiteSectionChrome> createState() => _SiteSectionChromeState();
}

class _SiteSectionChromeState extends State<SiteSectionChrome> {
  bool _navOpen = false;

  void _closeNav() {
    if (_navOpen) {
      setState(() => _navOpen = false);
      context
          .dependOnInheritedWidgetOfExactType<SiteBackAction>()
          ?.onMenuChanged
          ?.call(null);
    }
  }

  void _toggleNav() {
    setState(() => _navOpen = !_navOpen);
    context
        .dependOnInheritedWidgetOfExactType<SiteBackAction>()
        ?.onMenuChanged
        ?.call(_navOpen ? _closeNav : null);
  }

  List<Widget> _sectionButtons(ThemeData theme, {required bool compact}) {
    return [
      for (final (label, onTap)
          in (compact
              ? widget.destinations.compactSections
              : widget.destinations.sections))
        TextButton(
          key: SiteFrame.navItemKey(label),
          style: TextButton.styleFrom(
            foregroundColor: label == widget.currentLabel
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            backgroundColor: label == widget.currentLabel
                ? theme.colorScheme.secondaryContainer
                : null,
            textStyle: compact
                ? theme.textTheme.titleMedium?.copyWith(fontSize: 18)
                : theme.textTheme.labelMedium,
            alignment: compact ? Alignment.centerLeft : Alignment.center,
            minimumSize: Size(44, compact ? 48 : 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onPressed: () {
            _closeNav();
            onTap();
          },
          child: Text(label),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = _compactSiteNav(context, size, widget.destinations);
    if (!compact && _navOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navOpen) _closeNav();
      });
    }
    final open = compact && _navOpen;
    final padding = sitePagePadding(size.width.isFinite ? size.width : 1200);
    final sections = _sectionButtons(theme, compact: open);
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && open) _closeNav();
      },
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            elevation: 1,
            child: SafeArea(
              bottom: false,
              // Широкая строка как у информационных страниц: без фиксированной
              // высоты 72 px, иначе логотип и кнопки центрируются и вся полоса
              // оказывается ниже, чем на «О компании» и остальных разделах.
              child: compact
                  ? SizedBox(
                      height: _siteNavHeight(context),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: Row(
                          children: [
                            Expanded(
                              child: _SiteBrand(
                                flexible: true,
                                onPressed: () {
                                  _closeNav();
                                  widget.destinations.onHome();
                                },
                              ),
                            ),
                            ?SiteBackAction.buttonOf(
                              context,
                              closeMenu: open ? _closeNav : null,
                            ),
                            IconButton(
                              key: SiteFrame.navToggleKey,
                              tooltip: open
                                  ? AppStrings.close
                                  : AppStrings.siteSections,
                              onPressed: () => _toggleNav(),
                              icon: Icon(open ? Icons.close : Icons.menu),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: siteNavMaxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              key: SiteFrame.navRowKey,
                              children: [
                                _SiteBrand(
                                  onPressed: widget.destinations.onHome,
                                ),
                                ?SiteBackAction.buttonOf(
                                  context,
                                  forceIcon: _wideBackNeedsIcon(
                                    context,
                                    widget.destinations,
                                  ),
                                ),
                                ...sections,
                                ?SiteNavAction.maybeOf(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Stack(
                children: [
                  widget.child,
                  if (open) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        key: SiteFrame.navBarrierKey,
                        onTap: _closeNav,
                        behavior: HitTestBehavior.opaque,
                        child: ColoredBox(
                          color: theme.colorScheme.scrim.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Material(
                        key: SiteFrame.navPanelKey,
                        color: theme.colorScheme.surface,
                        elevation: 8,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: size.height * 0.75,
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            children: sections,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SiteScaffold extends StatelessWidget {
  const SiteScaffold({
    required this.title,
    required this.destinations,
    required this.child,
    this.panel = true,
    super.key,
  });

  final String title;
  final SiteDestinations destinations;
  final Widget child;

  /// Общая белая карточка. Информационные разделы сайта выводят собственные блоки.
  final bool panel;

  @override
  Widget build(BuildContext context) {
    return SiteFrame(
      title: title,
      destinations: destinations,
      child: Align(
        alignment: Alignment.topCenter,
        child: panel
            ? ContentPanel(maxWidth: 840, child: child)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: child,
              ),
      ),
    );
  }
}

class _SiteFooter extends StatelessWidget {
  const _SiteFooter({required this.destinations, required this.padding});

  final SiteDestinations destinations;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow =
        MediaQuery.sizeOf(context).width <= siteGridTwoColumnMaxWidth ||
        MediaQuery.textScalerOf(context).scale(16) >= 20.8;
    final identity = Column(
      key: const ValueKey('site-footer-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          SiteContent.legalName,
          style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 12),
        const Text(
          SiteContent.phoneDisplay,
          style: TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(SiteContent.email, style: TextStyle(color: Colors.white)),
      ],
    );
    final links = Column(
      key: const ValueKey('site-footer-links'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, action) in [
          (AppStrings.offer, destinations.onOffer),
          (AppStrings.privacy, destinations.onPrivacy),
          (AppStrings.aboutApp, destinations.onAboutApp),
        ])
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(0, 44),
              alignment: Alignment.centerLeft,
            ),
            onPressed: action,
            child: Text(label),
          ),
      ],
    );
    return ColoredBox(
      color: AppTheme.footer,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: siteContentMaxWidth),
          child: Padding(
            key: const ValueKey('site-footer'),
            padding: EdgeInsets.fromLTRB(padding, 24, padding, 24),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 16), links],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 24),
                      Expanded(child: links),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class SiteSection extends StatelessWidget {
  const SiteSection({
    required this.title,
    required this.children,
    this.lead,
    super.key,
  });

  final String title;
  final String? lead;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: AppTheme.radius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (lead != null) ...[
                const SizedBox(height: 12),
                Text(
                  lead!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (children.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...children,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openExternal(
  BuildContext context,
  String url, {
  ExternalUrlLauncher? launcher,
}) async {
  final uri = Uri.tryParse(url);
  final opened = uri != null && await tryOpenExternal(uri, launcher: launcher);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(AppStrings.externalLinkUnavailable)),
  );
}

Widget bulletList(List<String> items) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 4),
        Text('• ${items[i]}'),
      ],
    ],
  );
}

class ContactLines extends StatelessWidget {
  const ContactLines({this.showHours = true, this.centered = false, super.key});

  final bool showHours;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.profilePhone,
          style: heading,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: 4),
        _ContactLink(
          label: SiteContent.phoneDisplay,
          url: 'tel:${SiteContent.phoneTel}',
          centered: centered,
        ),
        const SizedBox(height: 12),
        Text(
          AppStrings.siteEmail,
          style: heading,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: 4),
        _ContactLink(
          label: SiteContent.email,
          url: 'mailto:${SiteContent.email}',
          centered: centered,
        ),
        if (showHours) ...[
          const SizedBox(height: 12),
          Text(
            AppStrings.siteHours,
            style: heading,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          ),
          const SizedBox(height: 4),
          Text(SiteContent.hoursWeekday),
          Text(SiteContent.hoursFriday),
          Text(SiteContent.hoursWeekend),
        ],
      ],
    );
  }
}

class _ContactLink extends StatelessWidget {
  const _ContactLink({
    required this.label,
    required this.url,
    this.centered = false,
  });

  final String label;
  final String url;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: () => openExternal(context, url),
        child: Text(
          label,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
      ),
    );
  }
}
