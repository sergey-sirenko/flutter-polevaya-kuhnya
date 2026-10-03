import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() {
  const api = 'https://hleb-sol.su/Zakaz_http/hs/Obmen/';
  const data = 'https://flutter-test.obedmoscow.ru/data/';

  test('test и prod различаются, адреса разрешаются от базовых путей', () {
    final testConfig = AppConfig.parse(
      appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
      environment: 'test',
      apiBaseUrl: api,
      dataBaseUrl: data,
    );
    final prodConfig = AppConfig.parse(
      appVersionUrl: 'https://new.obedmoscow.ru/version.json',
      environment: 'prod',
      apiBaseUrl: api,
      dataBaseUrl: 'https://obedmoscow.ru/data/',
    );

    expect(testConfig.isTest, isTrue);
    expect(prodConfig.isTest, isFalse);
    expect(
      testConfig.apiBaseUri.resolve('V1/User/login').toString(),
      '${api}V1/User/login',
    );
    expect(testConfig.menuUri.toString(), '${data}dishes.json');
  });

  test('неизвестное окружение и отсутствующие адреса отвергаются', () {
    expect(
      () => AppConfig.parse(
        appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
        environment: '',
        apiBaseUrl: api,
        dataBaseUrl: data,
      ),
      throwsStateError,
    );
    expect(
      () => AppConfig.parse(
        appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
        environment: 'test',
        apiBaseUrl: '',
        dataBaseUrl: data,
      ),
      throwsStateError,
    );
  });

  test('небезопасный или двусмысленный базовый адрес отвергается', () {
    for (final invalid in <String>[
      'http://hleb-sol.su/Zakaz_http/hs/Obmen/',
      'https://user@hleb-sol.su/Zakaz_http/hs/Obmen/',
      'https://hleb-sol.su/Zakaz_http/hs/Obmen',
      'https://hleb-sol.su/Zakaz_http/hs/Obmen/?source=test',
    ]) {
      expect(
        () => AppConfig.parse(
          appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
          environment: 'test',
          apiBaseUrl: invalid,
          dataBaseUrl: data,
        ),
        throwsStateError,
      );
    }
  });
}
