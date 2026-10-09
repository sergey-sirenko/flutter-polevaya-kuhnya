import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/app_version.dart';
import 'package:polevaya_kuhnya/features/site/contact_form.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:polevaya_kuhnya/shared/external_link.dart';

class SiteHomeCategory {
  const SiteHomeCategory({
    required this.id,
    required this.name,
    this.imagePath,
    this.imageVersion,
  });

  final String id;
  final String name;
  final String? imagePath;
  final String? imageVersion;
}

class SiteHomeDish {
  const SiteHomeDish({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
  });

  final String id;
  final String name;
  final num price;
  final Widget image;
}

class SiteHomePage extends StatelessWidget {
  const SiteHomePage({
    required this.destinations,
    this.categories = const [],
    this.categoryImage,
    this.onCategory,
    this.storeLauncher,
    this.heroDishes = const [],
    this.heroDayKey,
    this.onRetryMenu,
    super.key,
  });

  final SiteDestinations destinations;
  final List<SiteHomeCategory> categories;
  final Widget Function(SiteHomeCategory category)? categoryImage;
  final ValueChanged<SiteHomeCategory>? onCategory;
  final ExternalUrlLauncher? storeLauncher;
  final List<SiteHomeDish> heroDishes;
  final String? heroDayKey;
  final VoidCallback? onRetryMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SiteFrame(
      destinations: destinations,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(16) >= 20.8;
          final width = constraints.maxWidth;
          final categoryColumns = largeText
              ? (width >= 700 ? 2 : 1)
              : MediaQuery.sizeOf(context).width >= 1200
              ? 4
              : width >= 600
              ? 3
              : width >= 292
              ? 2
              : 1;
          final categoryWidth =
              (width - 24 - 12 * (categoryColumns - 1)) / categoryColumns;
          final horizontalCategories = !largeText && categoryWidth >= 224;
          final categoryHeight = _CategoryCard.heightFor(
            context,
            categories,
            categoryWidth,
            horizontal: horizontalCategories,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onRetryMenu != null) ...[
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    const Text('Не удалось загрузить меню.'),
                    TextButton(
                      onPressed: onRetryMenu,
                      child: const Text('Повторить загрузку'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              _HomeHero(
                key: ValueKey(heroDayKey),
                destinations: destinations,
                dishes: heroDishes,
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 32),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: AppTheme.radius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          AppStrings.siteDishCategories,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        SiteCardGrid(
                          key: const ValueKey('site-categories'),
                          columns: categoryColumns,
                          children: [
                            for (final category in categories)
                              SizedBox(
                                height: categoryHeight,
                                child: _CategoryCard(
                                  category: category,
                                  onTap: () {
                                    final select = onCategory;
                                    if (select != null) {
                                      select(category);
                                    } else {
                                      destinations.onMenu();
                                    }
                                  },
                                  image: categoryImage?.call(category),
                                  horizontal: horizontalCategories,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SiteCardGrid(
                key: const ValueKey('site-features'),
                columns: largeText
                    ? 1
                    : width >= 900
                    ? 3
                    : width >= 600
                    ? 2
                    : 1,
                children: [
                  for (var i = 0; i < SiteContent.features.length; i++)
                    _FeatureCard(
                      title: SiteContent.features[i].$1,
                      text: SiteContent.features[i].$2,
                      icon: const [
                        Icons.eco_outlined,
                        Icons.local_shipping_outlined,
                        Icons.restaurant_menu,
                      ][i],
                    ),
                ],
              ),
              _AppDownloadSection(launcher: storeLauncher),
            ],
          );
        },
      ),
    );
  }
}

class _HomeHero extends StatefulWidget {
  const _HomeHero({
    required this.destinations,
    required this.dishes,
    super.key,
  });

  final SiteDestinations destinations;
  final List<SiteHomeDish> dishes;

  @override
  State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> {
  String? _dishId;

  int get _index {
    final found = widget.dishes.indexWhere((dish) => dish.id == _dishId);
    return found < 0 ? 0 : found;
  }

  void _move(int step) {
    if (widget.dishes.length < 2) return;
    setState(() {
      _dishId = widget.dishes[(_index + step) % widget.dishes.length].id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destinations = widget.destinations;
    final dish = widget.dishes.isEmpty ? null : widget.dishes[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(16) < 20.8;
        final copy = Column(
          key: const ValueKey('site-hero-copy'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              SiteContent.heroCity,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              SiteContent.heroTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: horizontal ? 40 : 32,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              SiteContent.heroSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: destinations.onOrderLunch ?? destinations.onMenu,
                  child: const Text(AppStrings.orderLunch),
                ),
                OutlinedButton(
                  onPressed: destinations.onDelivery,
                  child: const Text(AppStrings.delivery),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _HomeDetails(),
          ],
        );
        final photo = Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            key: const ValueKey('site-hero-photo'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ColoredBox(
                  color: Colors.white,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      dish?.image ?? const ColoredBox(color: Colors.white),
                      if (widget.dishes.length > 1)
                        Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton.filledTonal(
                                  key: const ValueKey('site-hero-previous'),
                                  tooltip: AppStrings.sitePreviousDish,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: () => _move(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                IconButton.filledTonal(
                                  key: const ValueKey('site-hero-next'),
                                  tooltip: AppStrings.siteNextDish,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: () => _move(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (dish != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dish.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        formatRubles(dish.price),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
        return SizedBox(
          key: const ValueKey('site-home-hero'),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Center(child: copy)),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: photo,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 24), photo],
                ),
        );
      },
    );
  }
}

class _HomeDetails extends StatelessWidget {
  const _HomeDetails();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        double widthFor(double width) =>
            (width * scale).clamp(0, constraints.maxWidth).toDouble();
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 24,
          children: [
            SizedBox(
              width: widthFor(180),
              child: Column(
                key: const ValueKey('site-home-hours'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.siteHours,
                    style: heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text('Пн–Чт: 08:00–12:00', textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text('Пт: 08:00–15:00', textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text('Сб, Вс — выходной', textAlign: TextAlign.center),
                ],
              ),
            ),
            SizedBox(
              width: widthFor(250),
              child: Column(
                key: const ValueKey('site-home-contacts'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.contacts,
                    style: heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const ContactLines(showHours: false, centered: true),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppDownloadSection extends StatelessWidget {
  const _AppDownloadSection({this.launcher});

  final ExternalUrlLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        key: const ValueKey('site-app-download'),
        children: [
          Text(
            AppStrings.siteAppDownload.toUpperCase(),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: narrow ? 26 : 36,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.siteAppDownloadSubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: narrow ? 22 : 32,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final badge in SiteContent.appBadges)
                _StoreBadge(badge: badge, launcher: launcher),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  const _StoreBadge({required this.badge, this.launcher});

  final SiteAppBadge badge;
  final ExternalUrlLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Semantics(
      button: true,
      label: badge.label,
      child: InkWell(
        key: ValueKey('site-badge-${badge.id}'),
        onTap: () => openExternal(context, badge.url, launcher: launcher),
        child: SvgPicture.asset(
          badge.asset,
          height: narrow ? 50 : 54,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.text,
    required this.icon,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: AppTheme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onTap,
    required this.image,
    required this.horizontal,
  });

  final SiteHomeCategory category;
  final VoidCallback onTap;
  final Widget? image;
  final bool horizontal;

  // Все строки используют высоту самого длинного названия при текущих
  // ширине, шрифте и масштабе текста, включая неполную последнюю строку.
  static double heightFor(
    BuildContext context,
    List<SiteHomeCategory> categories,
    double width, {
    required bool horizontal,
  }) {
    final textWidth = width - 24 - (horizontal ? 84 : 0);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final style = DefaultTextStyle.of(context).style
        .merge(Theme.of(context).textTheme.titleSmall);
    var textHeight = 0.0;
    for (final category in categories) {
      painter.text = TextSpan(text: category.name, style: style);
      painter.layout(maxWidth: textWidth);
      if (painter.height > textHeight) textHeight = painter.height;
    }
    painter.dispose();
    return 24 +
        (horizontal ? (textHeight > 72 ? textHeight : 72) : 84 + textHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('site-category-${category.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Builder(
            builder: (context) {
              final photo = SizedBox(
                width: 72,
                height: 72,
                child: ClipOval(child: image ?? const _CategoryImageFallback()),
              );
              final name = Text(
                category.name,
                textAlign: horizontal ? TextAlign.start : TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              );
              return horizontal
                  ? Row(
                      children: [
                        photo,
                        const SizedBox(width: 12),
                        Expanded(child: name),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [photo, const SizedBox(height: 12), name],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryImageFallback extends StatelessWidget {
  const _CategoryImageFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.restaurant_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: AppStrings.about,
      destinations: destinations,
      panel: false,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SiteSection(
            title: SiteContent.companyName,
            lead: SiteContent.aboutLead,
            children: [],
          ),
          SiteSection(
            title: AppStrings.siteAddress,
            children: [Text(SiteContent.address)],
          ),
          SiteSection(
            title: AppStrings.siteLegalAddress,
            children: [Text(SiteContent.legalAddress)],
          ),
          SiteSection(
            title: AppStrings.siteRequisites,
            children: [
              Text(SiteContent.legalName),
              Text('ИНН ${SiteContent.inn} / ОГРН ${SiteContent.ogrn}'),
            ],
          ),
        ],
      ),
    );
  }
}

class DeliveryPage extends StatelessWidget {
  const DeliveryPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: AppStrings.delivery,
      destinations: destinations,
      panel: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SiteSection(
            title: AppStrings.siteDeliveryTerms,
            lead: SiteContent.deliveryLead,
            children: [bulletList(SiteContent.deliveryPoints)],
          ),
          SiteSection(
            title: AppStrings.sitePayment,
            children: [bulletList(SiteContent.paymentPoints)],
          ),
          const SiteSection(
            title: AppStrings.siteDeliveryZone,
            children: [Text(SiteContent.deliveryZone)],
          ),
          SiteSection(
            title: AppStrings.siteOrderTime,
            children: [bulletList(SiteContent.orderDeadlines)],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: destinations.onContacts,
              child: const Text(AppStrings.contacts),
            ),
          ),
        ],
      ),
    );
  }
}

class HowToOrderPage extends StatelessWidget {
  const HowToOrderPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: AppStrings.howToOrder,
      destinations: destinations,
      panel: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < SiteContent.orderSteps.length; i++)
            SiteSection(
              title: '${i + 1}. ${SiteContent.orderSteps[i].$1}',
              children: [Text(SiteContent.orderSteps[i].$2)],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: destinations.onMenu,
              child: const Text(AppStrings.orderLunch),
            ),
          ),
        ],
      ),
    );
  }
}

class ContactsPage extends StatelessWidget {
  const ContactsPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: AppStrings.contacts,
      destinations: destinations,
      panel: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 640 ||
              MediaQuery.textScalerOf(context).scale(16) >= 20.8;
          final details = const SiteSection(
            key: ValueKey('contact-details'),
            title: SiteContent.companyName,
            children: [ContactLines()],
          );
          const form = SiteSection(
            key: ValueKey('contact-form'),
            title: AppStrings.siteContactTitle,
            children: [ContactForm()],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, form],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              const Expanded(child: form),
            ],
          );
        },
      ),
    );
  }
}

class OfferPage extends StatelessWidget {
  const OfferPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: AppStrings.offer,
      destinations: destinations,
      panel: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SiteSection(
            title: AppStrings.offerHeading,
            children: [
              const Text(SiteContent.offerNotice),
              const SizedBox(height: 8),
              _OfferContactLine(onForm: destinations.onContacts),
            ],
          ),
          SiteSection(
            title: AppStrings.offerLaw,
            children: [
              Text('1. ${SiteContent.offerLawPoints[0]}'),
              const SizedBox(height: 8),
              Text('2. ${SiteContent.offerLawPoints[1]}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfferContactLine extends StatefulWidget {
  const _OfferContactLine({required this.onForm});

  final VoidCallback onForm;

  @override
  State<_OfferContactLine> createState() => _OfferContactLineState();
}

class _OfferContactLineState extends State<_OfferContactLine> {
  late final TapGestureRecognizer _form;
  late final TapGestureRecognizer _phone;

  @override
  void initState() {
    super.initState();
    _form = TapGestureRecognizer()..onTap = widget.onForm;
    _phone = TapGestureRecognizer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phone.onTap = () => openExternal(context, 'tel:${SiteContent.phoneTel}');
  }

  @override
  void didUpdateWidget(_OfferContactLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _form.onTap = widget.onForm;
  }

  @override
  void dispose() {
    _form.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(color: Theme.of(context).colorScheme.primary);
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: SiteContent.offerContactBefore),
          TextSpan(
            text: SiteContent.offerContactForm,
            style: link,
            recognizer: _form,
          ),
          const TextSpan(text: SiteContent.offerContactMiddle),
          TextSpan(
            text: SiteContent.phoneDisplay,
            style: link,
            recognizer: _phone,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({required this.destinations, this.onBack, super.key});

  final SiteDestinations destinations;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => _DataDocumentPage(
    title: AppStrings.privacy,
    paragraphs: SiteContent.privacyParagraphs,
    destinations: destinations,
    onBack: onBack,
  );
}

class PersonalDataConsentPage extends StatelessWidget {
  const PersonalDataConsentPage({
    required this.destinations,
    this.onBack,
    super.key,
  });

  final SiteDestinations destinations;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => _DataDocumentPage(
    title: AppStrings.personalDataConsent,
    paragraphs: SiteContent.personalDataConsentParagraphs,
    destinations: destinations,
    onBack: onBack,
  );
}

class _DataDocumentPage extends StatelessWidget {
  const _DataDocumentPage({
    required this.title,
    required this.paragraphs,
    required this.destinations,
    this.onBack,
  });

  final String title;
  final List<String> paragraphs;
  final SiteDestinations destinations;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SiteScaffold(
    title: title,
    destinations: destinations,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          TextButton.icon(
            key: const ValueKey('data-document-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text(AppStrings.personalDataConsentBack),
          ),
          const SizedBox(height: 12),
        ],
        for (final paragraph in paragraphs) ...[
          SelectableText(paragraph),
          const SizedBox(height: 12),
        ],
        const ContactLines(),
      ],
    ),
  );
}

class AboutAppPage extends ConsumerWidget {
  const AboutAppPage({required this.destinations, super.key});

  final SiteDestinations destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionLabel = ref.watch(appVersionLabelProvider);
    return SiteScaffold(
      title: AppStrings.aboutApp,
      destinations: destinations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${AppStrings.aboutAppVersion}: $versionLabel'),
          const SizedBox(height: 8),
          Text('${AppStrings.profilePhone}: ${SiteContent.phoneDisplay}'),
          const Text(SiteContent.email),
          const SizedBox(height: 12),
          TextButton(
            onPressed: destinations.onPrivacy,
            child: const Text(AppStrings.privacy),
          ),
        ],
      ),
    );
  }
}

class InstallPage extends StatelessWidget {
  const InstallPage({
    required this.destinations,
    required this.channel,
    super.key,
  });

  final SiteDestinations destinations;
  final InstallChannel channel;

  @override
  Widget build(BuildContext context) {
    final hint = switch (channel) {
      InstallChannel.web => AppStrings.installWebHint,
      InstallChannel.android => AppStrings.installAndroidHint,
      InstallChannel.ios => AppStrings.installIosHint,
      InstallChannel.other => AppStrings.installOtherHint,
    };
    return SiteScaffold(
      title: AppStrings.install,
      destinations: destinations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hint),
          const SizedBox(height: 12),
          const Text(AppStrings.installStoresPending),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('install-continue-browser'),
            onPressed: destinations.onMenu,
            child: const Text(AppStrings.installContinueInBrowser),
          ),
          const SizedBox(height: 12),
          const Text(AppStrings.installApkLater),
        ],
      ),
    );
  }
}
