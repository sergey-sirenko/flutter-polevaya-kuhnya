import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_repository.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/web_auto_update.dart';

import '../core/platform/web_auto_update_test.dart' show Browser;

import 'package:polevaya_kuhnya/features/site/site_content.dart';

import '../core/platform/app_version_policy_test.dart'
    show versionConfig, policyDocument;

class _PendingVersions implements AppVersionRepository {
  final calls = <Completer<AppVersionPolicy>>[];
  @override
  Future<AppVersionPolicy> fetch() {
    final call = Completer<AppVersionPolicy>();
    calls.add(call);
    return call.future;
  }

  void complete({int minimum = 1, int release = 8}) => calls.last.complete(
    AppVersionPolicy.parse(
      policyDocument(minimum: minimum, release: release),
      config: versionConfig,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PendingVersions versions;
  late ProviderContainer container;
  late SessionStorage storage;
  late List<http.Request> businessRequests;

  Future<void> mount(
    WidgetTester tester, {
    String path = '/sign-in?from=%2Fmenu#section',
    InstallChannel channel = InstallChannel.web,
    bool savedToken = false,
    bool explicitAddress = false,
    Size size = const Size(360, 800),
    double scale = 1,
    Future<http.Response> Function(http.Request)? responseFor,
    Browser? autoBrowser,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (explicitAddress) {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = path;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
    }
    FlutterSecureStorage.setMockInitialValues({});
    storage = SessionStorage(config: versionConfig);
    if (savedToken) await storage.writeToken('synthetic-saved-token');
    versions = _PendingVersions();
    final autoUpdate = autoBrowser == null
        ? null
        : WebAutoUpdate(
            repository: versions,
            current: AppVersion.tryParse('0.1.0', 8),
            browser: autoBrowser,
            enabled: channel == InstallChannel.web,
          );
    if (autoUpdate != null) addTearDown(autoUpdate.dispose);
    businessRequests = [];
    container = ProviderContainer(
      overrides: [
        if (autoUpdate != null)
          webAutoUpdateProvider.overrideWithValue(autoUpdate),
        appConfigProvider.overrideWithValue(versionConfig),
        currentAppVersionProvider.overrideWithValue(
          AppVersion.tryParse('0.1.0', 8),
        ),
        appVersionRepositoryProvider.overrideWithValue(versions),
        sessionStorageProvider.overrideWithValue(storage),
        initialLocationProvider.overrideWithValue(explicitAddress ? '/' : path),
        installChannelProvider.overrideWithValue(channel),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            businessRequests.add(request);
            if (responseFor != null) return responseFor(request);
            return http.Response(
              '{"success":true,"user":{"name":"Synthetic"}}',
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const FieldKitchenApp(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Web на старте и после ручного retry сразу применяет новый release без второго GET',
    (tester) async {
      final browser = Browser();
      await mount(tester, autoBrowser: browser);
      versions.complete(release: 9);
      await tester.pump();
      await tester.pump();
      expect(browser.reloads, ['0.1.0+9']);
      expect(versions.calls, hasLength(1));
      final checking = container
          .read(appVersionControllerProvider.notifier)
          .check();
      versions.complete(release: 10);
      await checking;
      await tester.pump();
      expect(browser.reloads, ['0.1.0+9', '0.1.0+10']);
      container.read(webAutoUpdateProvider).dispose();
    },
  );

  testWidgets(
    'cold checking and required create no router/session/API, storage retained',
    (tester) async {
      await mount(tester, savedToken: true);
      expect(versions.calls, hasLength(1));
      expect(find.text(AppStrings.versionChecking), findsOneWidget);
      expect(container.exists(routerProvider), isFalse);
      expect(container.exists(sessionControllerProvider), isFalse);
      expect(businessRequests, isEmpty);
      versions.complete(minimum: 9, release: 9);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.versionRequired), findsOneWidget);
      expect(find.text('Текущая версия: 0.1.0+8'), findsOneWidget);
      expect(find.text('Минимальная версия: 0.1.0+9'), findsOneWidget);
      expect(find.byKey(const ValueKey('version-continue')), findsNothing);
      expect(find.byKey(const ValueKey('sign-in-submit')), findsNothing);
      expect(container.exists(routerProvider), isFalse);
      expect(container.exists(sessionControllerProvider), isFalse);
      expect(await storage.readToken(), 'synthetic-saved-token');
      expect(businessRequests, isEmpty);
    },
  );
  testWidgets(
    'required support/privacy do not start business; failed retry retains block',
    (tester) async {
      await mount(tester, channel: InstallChannel.android);
      versions.complete(minimum: 9, release: 9);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.versionNoRelease), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version-support')));
      await tester.pumpAndSettle();
      expect(find.text(SiteContent.phoneDisplay), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version-info-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('version-privacy')));
      await tester.pumpAndSettle();
      expect(find.text(SiteContent.privacyParagraphs.first), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('version-info-back')),
      );
      await tester.tap(find.byKey(const ValueKey('version-info-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('version-retry')));
      await tester.pump();
      expect(find.byKey(const ValueKey('version-continue')), findsNothing);
      versions.calls.last.completeError(TimeoutException('test'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.versionRetryFailed), findsOneWidget);
      expect(container.exists(routerProvider), isFalse);
      expect(businessRequests, isEmpty);
    },
  );
  testWidgets(
    'first unknown allows explicit continue to original address, retry still possible',
    (tester) async {
      await mount(tester);
      versions.calls.last.completeError(const FormatException('legacy'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.versionUnknown), findsOneWidget);
      expect(container.exists(routerProvider), isFalse);
      await tester.tap(find.byKey(const ValueKey('version-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-in-login')), findsOneWidget);
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .toString(),
        '/sign-in?from=%2Fmenu#section',
      );
      expect(
        find.byKey(const ValueKey('version-notice-retry')),
        findsOneWidget,
      );
      expect(versions.calls, hasLength(1));
    },
  );
  testWidgets(
    'explicit platform address with query/fragment retained after startup',
    (tester) async {
      final updates = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          updates.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      await mount(tester, path: '/sign-up?probe=1#form', explicitAddress: true);
      expect(
        updates.where((call) => call.method == 'routeInformationUpdated'),
        isEmpty,
      );
      versions.complete();
      await tester.pumpAndSettle();
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .toString(),
        '/sign-up?probe=1#form',
      );
      expect(find.byKey(const ValueKey('sign-up-consent')), findsOneWidget);
    },
  );
  testWidgets(
    'available is nonblocking; dismiss and repeats retain router and password form',
    (tester) async {
      await mount(tester);
      versions.complete(release: 9);
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      final field = find.byKey(const ValueKey('sign-in-password'));
      await tester.enterText(field, 'synthetic-draft-password');
      final input = tester.widget<TextFormField>(field).controller;
      await tester.tap(find.byKey(const ValueKey('version-notice-dismiss')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller, same(input));
      final pending = container
          .read(appVersionControllerProvider.notifier)
          .check();
      await tester.pump();
      expect(find.byKey(const ValueKey('sign-in-submit')), findsNothing);
      versions.complete(minimum: 9, release: 9);
      await pending;
      await tester.pumpAndSettle();
      router.go('/sign-up');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/sign-in');
      expect(find.byKey(const ValueKey('sign-up-consent')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('version-retry')));
      await tester.pump();
      versions.calls.last.completeError(Exception('test'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.versionRequired), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version-retry')));
      await tester.pump();
      versions.complete();
      await tester.pumpAndSettle();
      expect(container.read(routerProvider), same(router));
      expect(tester.widget<TextFormField>(field).controller, same(input));
      expect(input!.text, 'synthetic-draft-password');
      expect(businessRequests, isEmpty);
    },
  );
  testWidgets('native null release opens compatible app without false update', (
    tester,
  ) async {
    await mount(tester, channel: InstallChannel.ios);
    versions.complete(release: 99);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('version-notice-dismiss')), findsNothing);
  });
  testWidgets(
    'required screen scrolls at 320px and large text with no overflow',
    (tester) async {
      await mount(tester, size: const Size(320, 568), scale: 1.6);
      versions.complete(minimum: 9, release: 9);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('version-privacy')));
      await tester.tap(find.byKey(const ValueKey('version-privacy')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'required blocks imperative pop and system Back without discarding route stack',
    (tester) async {
      await mount(tester);
      versions.complete();
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      router.push('/privacy');
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);
      final pending = container
          .read(appVersionControllerProvider.notifier)
          .check();
      versions.complete(minimum: 9, release: 9);
      await pending;
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/privacy',
      );
      expect(router.canPop(), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/privacy',
      );
      expect(router.canPop(), isTrue);
      await tester.tap(find.byKey(const ValueKey('version-retry')));
      await tester.pump();
      versions.complete();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/sign-in',
      );
    },
  );
  testWidgets(
    'already started login finishes under required without reopening business routes',
    (tester) async {
      final login = Completer<http.Response>();
      await mount(
        tester,
        responseFor: (request) async {
          final body = jsonDecode(request.body) as Map;
          if (body.containsKey('password')) return login.future;
          return http.Response(
            '{"success":true,"user":{"name":"Synthetic"}}',
            200,
          );
        },
      );
      versions.complete();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-login')),
        '001.03',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-password')),
        'synthetic-password',
      );
      await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
      await tester.pump();
      expect(businessRequests, hasLength(1));
      final check = container
          .read(appVersionControllerProvider.notifier)
          .check();
      versions.complete(minimum: 9, release: 9);
      await check;
      await tester.pumpAndSettle();
      login.complete(
        http.Response(
          '{"success":true,"token":"synthetic-token","user":{"name":"Synthetic"}}',
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(await storage.readToken(), 'synthetic-token');
      expect(businessRequests, hasLength(2));
      expect(find.text(AppStrings.versionRequired), findsOneWidget);
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        '/sign-in',
      );
    },
  );
  testWidgets(
    'stale Continue cannot admit business during cold retry or required',
    (tester) async {
      await mount(tester);
      versions.calls.last.completeError(const FormatException('legacy'));
      await tester.pumpAndSettle();
      final staleContinue = tester
          .widget<FilledButton>(find.byKey(const ValueKey('version-continue')))
          .onPressed!;
      await tester.tap(find.byKey(const ValueKey('version-retry')));
      staleContinue();
      await tester.pump();
      expect(container.exists(routerProvider), isFalse);
      versions.complete(minimum: 9, release: 9);
      await tester.pumpAndSettle();
      staleContinue();
      await tester.pumpAndSettle();
      expect(container.exists(routerProvider), isFalse);
      expect(container.exists(sessionControllerProvider), isFalse);
      expect(businessRequests, isEmpty);
    },
  );
}
