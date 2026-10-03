import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';

void main() {
  final config = AppConfig.parse(
    appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
    environment: 'test',
    apiBaseUrl: 'https://api.example.test/Obmen/',
    dataBaseUrl: 'https://data.example.test/data/',
  );

  test('строит URL pictures/<path>.jpg без токена', () {
    expect(
      menuImageUri(config, 'fixture-soup').toString(),
      'https://data.example.test/data/pictures/fixture-soup.jpg',
    );
    expect(
      menuImageUri(config, 'fixture-soup', version: '1').toString(),
      'https://data.example.test/data/pictures/fixture-soup.jpg?v=1',
    );
    expect(menuImageUri(config, null), isNull);
    expect(menuImageUri(config, ''), isNull);
    expect(menuImageUri(config, '../secret'), isNull);
  });

  testWidgets('фото блюда без затухания и без низкого качества', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MenuNetworkImage(
          config: config,
          imagePath: 'fixture-soup',
          version: '1',
          width: 40,
          height: 40,
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.filterQuality, FilterQuality.medium);
    expect(image.fadeInDuration, Duration.zero);
    expect(
      image.imageUrl,
      'https://data.example.test/data/pictures/fixture-soup.jpg?v=1',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('пустой адрес показывает заглушку', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MenuNetworkImage(
          config: config,
          imagePath: null,
          width: 40,
          height: 40,
        ),
      ),
    );
    expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
