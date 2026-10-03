import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// URL изображения блюда/категории по правилу сайта:
/// `data/pictures/<imagePath>.jpg` (расширение дописывает клиент).
Uri? menuImageUri(AppConfig config, String? imagePath, {String? version}) {
  if (imagePath == null || imagePath.isEmpty) return null;
  if (imagePath.contains('/') ||
      imagePath.contains('\\') ||
      imagePath.contains('..') ||
      imagePath.contains('?') ||
      imagePath.contains('#')) {
    return null;
  }
  final base = config.dataBaseUri.resolve('pictures/$imagePath.jpg');
  if (version == null || version.isEmpty) return base;
  return base.replace(queryParameters: {'v': version});
}

class MenuNetworkImage extends StatefulWidget {
  const MenuNetworkImage({
    required this.config,
    required this.imagePath,
    this.version,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    super.key,
  });

  final AppConfig config;
  final String? imagePath;
  final String? version;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<MenuNetworkImage> createState() => _MenuNetworkImageState();
}

class _MenuNetworkImageState extends State<MenuNetworkImage> {
  /// Два повтора после сбоя: первый заход часто не успевает отдать файл,
  /// а обновление страницы уже берёт его из кэша браузера.
  static const _maxRetries = 2;

  int _attempt = 0;
  Timer? _retry;
  bool _closed = false;

  @override
  void didUpdateWidget(MenuNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.version != widget.version ||
        oldWidget.config.dataBaseUri != widget.config.dataBaseUri) {
      _retry?.cancel();
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry(String url) {
    if (_closed || !mounted || _attempt >= _maxRetries) return;
    _retry?.cancel();
    final attempt = _attempt;
    _retry = Timer(Duration(milliseconds: 400 * (attempt + 1)), () async {
      if (_closed || !mounted) return;
      await CachedNetworkImage.evictFromCache(url);
      if (_closed || !mounted) return;
      setState(() => _attempt = attempt + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uri = menuImageUri(
      widget.config,
      widget.imagePath,
      version: widget.version,
    );
    final placeholder = _MenuImagePlaceholder(
      width: widget.width,
      height: widget.height,
    );
    if (uri == null) return placeholder;
    final url = uri.toString();
    return ColoredBox(
      color: Colors.white,
      child: CachedNetworkImage(
        key: ValueKey('$url#$_attempt'),
        imageUrl: url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // Web по умолчанию рисует HTML-картинку ленивой текстурой.
        // Пока файл не в кэше браузера, круг категории и фото блюда часто
        // остаются чёрными; после обновления страницы текстура уже готова.
        // Байты декодируются целиком. Среднее качество — как у Image.network:
        // низкое на Web даёт чёрный круг при уменьшении большого JPEG.
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
        filterQuality: FilterQuality.medium,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, imageUrl) => placeholder,
        errorWidget: (context, imageUrl, error) => placeholder,
        errorListener: (error) => _scheduleRetry(url),
      ),
    );
  }
}

/// Круглая миниатюра категории, как `.category-img-container` рабочего сайта: 40 px.
class MenuCategoryThumb extends ConsumerWidget {
  const MenuCategoryThumb({
    required this.category,
    this.dimension = size,
    super.key,
  });

  final MenuCategory category;
  final double dimension;

  static const size = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final path = category.categoryImagePath;
    final image = path == null || path.isEmpty
        ? _MenuImagePlaceholder(width: dimension, height: dimension)
        : MenuNetworkImage(
            config: config,
            imagePath: path,
            version: category.imageVersion,
            width: dimension,
            height: dimension,
          );
    return ClipOval(
      key: ValueKey('menu-category-thumb-${category.categoryId}'),
      child: SizedBox(width: dimension, height: dimension, child: image),
    );
  }
}

class _MenuImagePlaceholder extends StatelessWidget {
  const _MenuImagePlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.white,
      alignment: Alignment.center,
      child: Icon(
        Icons.restaurant_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
