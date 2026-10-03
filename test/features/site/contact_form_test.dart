import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/site/contact_message.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';
import 'package:polevaya_kuhnya/features/site/site_pages.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';

void main() {
  testWidgets('номер без префикса открывает tel-ссылку', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContactLines(showHours: false))),
    );
    expect(find.text(AppStrings.profilePhone), findsOneWidget);
    expect(find.text(AppStrings.sitePhones), findsNothing);
    expect(
      find.text('${AppStrings.profilePhone}: ${SiteContent.phoneDisplay}'),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(TextButton, SiteContent.phoneDisplay));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(
      (calls.single.arguments as Map)['url'],
      'tel:${SiteContent.phoneTel}',
    );
    expect(find.text(AppStrings.externalLinkUnavailable), findsNothing);
  });
  test('имя и телефон обязательны, email проверяется только если заполнен', () {
    expect(
      validateContactMessage(
        const ContactMessageDraft(name: ' ', phone: '', email: '', message: ''),
      ).isValid,
      isFalse,
    );
    expect(
      validateContactMessage(
        const ContactMessageDraft(
          name: 'Анна',
          phone: '1',
          email: 'не почта',
          message: '',
        ),
      ).emailError,
      AppStrings.siteContactEmailInvalid,
    );
    expect(
      validateContactMessage(
        const ContactMessageDraft(
          name: 'Анна',
          phone: '1',
          email: '  ',
          message: '',
        ),
      ).isValid,
      isTrue,
    );
  });

  testWidgets('на широком экране сведения и форма стоят в двух блоках', (
    tester,
  ) async {
    await _mount(tester, width: 1200);
    expect(find.text(SiteContent.companyName), findsWidgets);
    expect(find.text(AppStrings.siteContactTitle), findsOneWidget);
    expect(
      find.text('${AppStrings.siteMax}: ${SiteContent.phoneDisplay}'),
      findsNothing,
    );
    expect(find.text(SiteContent.hoursWeekend), findsOneWidget);
    final details = find.byKey(const ValueKey('contact-details'));
    final form = find.byKey(const ValueKey('contact-form'));
    expect(
      tester.getTopLeft(form).dx,
      greaterThan(tester.getTopLeft(details).dx),
    );
    expect(
      (tester.getTopLeft(form).dy - tester.getTopLeft(details).dy).abs(),
      lessThan(2),
    );
    expect(find.byType(Card), findsNothing);
    await _unmount(tester);
  });

  testWidgets('на узком экране форма стоит под сведениями', (tester) async {
    await _mount(tester, width: 390);
    final details = find.byKey(const ValueKey('contact-details'));
    final form = find.byKey(const ValueKey('contact-form'));
    expect(
      tester.getTopLeft(form).dy,
      greaterThan(tester.getTopLeft(details).dy + 40),
    );
    await _unmount(tester);
  });

  testWidgets('пустые обязательные поля и неверный email не уходят на сервер', (
    tester,
  ) async {
    var calls = 0;
    await _mount(
      tester,
      width: 1200,
      onRequest: (_) async {
        calls++;
        return http.Response('{"success":true}', 200);
      },
    );
    await tester.tap(find.byKey(const ValueKey('contact-send')));
    await tester.pump();
    expect(find.text(AppStrings.siteContactNameRequired), findsOneWidget);
    expect(find.text(AppStrings.siteContactPhoneRequired), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(find.byKey(const ValueKey('contact-name')), 'Анна');
    await tester.enterText(find.byKey(const ValueKey('contact-phone')), '123');
    await tester.enterText(
      find.byKey(const ValueKey('contact-email')),
      'не почта',
    );
    await tester.tap(find.byKey(const ValueKey('contact-send')));
    await tester.pump();
    expect(find.text(AppStrings.siteContactEmailInvalid), findsOneWidget);
    expect(calls, 0);
    await _unmount(tester);
  });

  testWidgets('успех очищает форму и закрывает повтор на 60 секунд', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final gate = Completer<http.Response>();
    await _mount(
      tester,
      width: 1200,
      onRequest: (request) {
        requests.add(request);
        return gate.future;
      },
    );
    await _fill(tester, email: 'anna@example.com', message: 'Нужен обед');
    await tester.tap(find.byKey(const ValueKey('contact-send')));
    await tester.pump();
    expect(find.text(AppStrings.siteContactSending), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('contact-send')))
          .onPressed,
      isNull,
    );

    gate.complete(http.Response('{"success":true,"message":"queued"}', 200));
    await tester.pump();
    await tester.pump();

    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, endsWith('/V1/User/message'));
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.url.queryParameters, {
      'name': 'Анна',
      'phone': '8-903-000-00-00',
      'email': 'anna@example.com',
      'message': 'Нужен обед',
    });
    expect(find.text(AppStrings.siteContactDelivered), findsOneWidget);
    expect(find.text('queued'), findsNothing);
    expect(_text(tester, 'contact-name'), isEmpty);
    expect(_text(tester, 'contact-phone'), isEmpty);
    expect(_text(tester, 'contact-email'), isEmpty);
    expect(_text(tester, 'contact-message'), isEmpty);
    expect(find.text(AppStrings.siteContactRetryIn(60)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('contact-send')));
    await tester.pump();
    expect(requests, hasLength(1));

    for (var second = 59; second >= 1; second--) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(AppStrings.siteContactRetryIn(second)), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('contact-retry')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('contact-send')))
          .onPressed,
      isNotNull,
    );
    await _unmount(tester);
  });

  testWidgets('ошибка сервера возвращает кнопку и не очищает поля', (
    tester,
  ) async {
    await _mount(
      tester,
      width: 1200,
      onRequest: (request) async {
        return http.Response('{"success":false,"error":"секрет сервера"}', 400);
      },
    );
    await _fill(tester, message: 'Текст');
    await tester.tap(find.byKey(const ValueKey('contact-send')));
    await tester.pump();
    await tester.pump();
    expect(find.text(AppStrings.siteContactFailed), findsOneWidget);
    expect(find.text('секрет сервера'), findsNothing);
    expect(_text(tester, 'contact-name'), 'Анна');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('contact-send')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('contact-retry')), findsNothing);
    await _unmount(tester);
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required double width,
  Future<http.Response> Function(http.Request request)? onRequest,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final destinations = SiteDestinations(
    onHome: () {},
    onMenu: () {},
    onAbout: () {},
    onDelivery: () {},
    onHowToOrder: () {},
    onContacts: () {},
    onOffer: () {},
    onPrivacy: () {},
    onAboutApp: () {},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.parse(
            environment: 'test',
            apiBaseUrl: 'https://example.invalid/api/',
            dataBaseUrl: 'https://example.invalid/data/',
            appVersionUrl: 'https://example.invalid/version.json',
          ),
        ),
        httpClientProvider.overrideWithValue(
          MockClient(
            onRequest ?? (_) async => http.Response('{"success":false}', 500),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: ContactsPage(destinations: destinations),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _fill(
  WidgetTester tester, {
  String email = '',
  String message = '',
}) async {
  await tester.enterText(find.byKey(const ValueKey('contact-name')), 'Анна');
  await tester.enterText(
    find.byKey(const ValueKey('contact-phone')),
    '8-903-000-00-00',
  );
  await tester.enterText(find.byKey(const ValueKey('contact-email')), email);
  await tester.enterText(
    find.byKey(const ValueKey('contact-message')),
    message,
  );
}

String _text(WidgetTester tester, String key) {
  return tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}
