import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/version_gate.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/auth/sign_in_page.dart';
import 'package:polevaya_kuhnya/features/auth/sign_up_page.dart';
import 'package:polevaya_kuhnya/features/auth/reset_password_page.dart';
import 'package:polevaya_kuhnya/features/profile/profile_page.dart';
import 'package:polevaya_kuhnya/features/site/site_pages.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';

void noop() {}
final destinations = SiteDestinations(
  onHome: noop,
  onMenu: noop,
  onAbout: noop,
  onDelivery: noop,
  onHowToOrder: noop,
  onContacts: noop,
  onOffer: noop,
  onPrivacy: noop,
  onAboutApp: noop,
);

Future<void> mount(WidgetTester tester, Widget page) async {
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
          MockClient((_) async => http.Response('{}', 500)),
        ),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
        sessionApiProvider.overrideWithValue(null),
        sessionProfileProvider.overrideWithValue(
          UserProfile.fromUserJson({
            'login': 'fixture-owner',
            'employee': 'Тестовый пользователь с длинным именем',
            'name': 'Организация с длинным названием для проверки переноса',
            'email': 'fixture@example.invalid',
          }),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void viewport(WidgetTester tester, double width, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('secondary pages fit $width with large text and scroll', (
      tester,
    ) async {
      viewport(tester, width, 1.6);
      final pages = <Widget>[
        SignInPage(onHome: noop),
        SignUpPage(onSignIn: noop, onPrivacy: noop, onConsent: noop),
        ResetPasswordPage(onSignIn: noop, onHome: noop),
        const ProfilePage(),
        AboutPage(destinations: destinations),
        DeliveryPage(destinations: destinations),
        HowToOrderPage(destinations: destinations),
        ContactsPage(destinations: destinations),
        OfferPage(destinations: destinations),
        PrivacyPage(destinations: destinations),
        RoutePage(
          title: 'Состояние',
          message: 'Проверка соединения недоступна. Повторите попытку.',
          onHome: noop,
          onRetry: noop,
        ),
        VersionGatePage(
          version: const AppVersionCheck(
            AppVersionStatus.unknown,
            failure: AppVersionFailure.transport,
          ),
          onContinue: noop,
        ),
      ];
      for (final page in pages) {
        await mount(tester, page);
        expect(
          tester.takeException(),
          isNull,
          reason: page.runtimeType.toString(),
        );
        final scrolls = find.byType(SingleChildScrollView);
        if (scrolls.evaluate().isNotEmpty) {
          await tester.drag(scrolls.last, const Offset(0, -1800));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: page.runtimeType.toString(),
          );
        }
      }
    });
  }

  testWidgets(
    'sign-in retains input on keyboard/resize and submit remains reachable',
    (tester) async {
      viewport(tester, 390, 1.6);
      addTearDown(tester.view.resetViewInsets);
      await mount(tester, SignInPage(onHome: noop));
      final login = find.byKey(const ValueKey('sign-in-login'));
      await tester.enterText(login, 'fixture-owner');
      tester.view.physicalSize = const Size(320, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('sign-in-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(find.text('fixture-owner'), findsOneWidget);
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(544));
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(44));
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('fixture-owner'), findsOneWidget);
    },
  );

  testWidgets(
    'profile disconnect confirmation scrolls and can cancel on narrow screen',
    (tester) async {
      viewport(tester, 320, 1.6);
      await mount(tester, const ProfilePage());
      final action = find.byKey(const ValueKey('device-disconnect'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      final cancel = find.widgetWithText(
        TextButton,
        AppStrings.deviceDisconnectCancel,
      );
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
