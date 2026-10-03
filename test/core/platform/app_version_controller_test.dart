import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_repository.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

import 'app_version_policy_test.dart' show versionConfig, policyDocument;

class PendingRepository implements AppVersionRepository {
  final calls = <Completer<AppVersionPolicy>>[];
  @override
  Future<AppVersionPolicy> fetch() {
    final call = Completer<AppVersionPolicy>();
    calls.add(call);
    return call.future;
  }
}

AppVersionPolicy policy({int minimum = 1, int release = 8}) =>
    AppVersionPolicy.parse(
      policyDocument(minimum: minimum, release: release),
      config: versionConfig,
    );

void main() {
  late PendingRepository repo;
  late ProviderContainer container;
  late AppVersionController controller;
  AppVersionCheck read() => container.read(appVersionControllerProvider);
  void setup({
    InstallChannel channel = InstallChannel.web,
    AppVersion? current,
  }) {
    repo = PendingRepository();
    container = ProviderContainer(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(repo),
        currentAppVersionProvider.overrideWithValue(
          current ?? AppVersion.tryParse('0.1.0', 8),
        ),
        installChannelProvider.overrideWithValue(channel),
      ],
    );
    controller = container.read(appVersionControllerProvider.notifier);
    addTearDown(container.dispose);
  }

  test('construction does not start requests; current, available, required separately', () async {
    setup();
    expect(repo.calls, isEmpty);
    final current = controller.check();
    expect(read().status, AppVersionStatus.checking);
    repo.calls.last.complete(policy());
    await current;
    expect(read().status, AppVersionStatus.current);
    final available = controller.check();
    repo.calls.last.complete(policy(release: 9));
    await available;
    expect(read().status, AppVersionStatus.available);
    final required = controller.check();
    repo.calls.last.complete(policy(minimum: 9, release: 9));
    await required;
    expect(read().requiresUpdate, isTrue);
  });
  test('first failure unknown; required retained during retry and error, valid rollback clears', () async {
    setup();
    var pending = controller.check();
    repo.calls.last.completeError(TimeoutException('test'));
    await pending;
    expect(read().status, AppVersionStatus.unknown);
    expect(read().failure, AppVersionFailure.transport);
    pending = controller.check();
    repo.calls.last.complete(policy(minimum: 9, release: 9));
    await pending;
    pending = controller.check();
    expect(read().requiresUpdate, isTrue);
    expect(read().checking, isTrue);
    repo.calls.last.completeError(const FormatException('legacy'));
    await pending;
    expect(read().requiresUpdate, isTrue);
    expect(read().policy!.minimum.toString(), '0.1.0+9');
    expect(read().failure, AppVersionFailure.invalidPolicy);
    pending = controller.check();
    repo.calls.last.complete(policy());
    await pending;
    expect(read().status, AppVersionStatus.current);
  });
  test('native null release current, higher current not downgraded', () async {
    setup(
      channel: InstallChannel.android,
      current: AppVersion.tryParse('0.2.0', 1),
    );
    final pending = controller.check();
    repo.calls.last.complete(policy(release: 99));
    await pending;
    expect(read().status, AppVersionStatus.current);
    expect(read().release, isNull);
  });
  test('late older success and failure never overwrite newer check', () async {
    setup();
    final old = controller.check();
    final next = controller.check();
    repo.calls[1].complete(policy());
    await next;
    repo.calls[0].complete(policy(minimum: 9, release: 9));
    await old;
    expect(read().status, AppVersionStatus.current);
    final older = controller.check();
    final newer = controller.check();
    repo.calls[3].complete(policy(release: 9));
    await newer;
    repo.calls[2].completeError(Exception('late'));
    await older;
    expect(read().status, AppVersionStatus.available);
    expect(read().failure, isNull);
  });
  test(
    'dependency replacement discards old required and in-flight response',
    () async {
      setup();
      var pending = controller.check();
      repo.calls.last.complete(policy(minimum: 9, release: 9));
      await pending;
      pending = controller.check();
      final replacement = PendingRepository();
      container.updateOverrides([
        appVersionRepositoryProvider.overrideWithValue(replacement),
        currentAppVersionProvider.overrideWithValue(
          AppVersion.tryParse('0.1.0', 8),
        ),
        installChannelProvider.overrideWithValue(InstallChannel.web),
      ]);
      expect(read().status, AppVersionStatus.unknown);
      repo.calls.last.complete(policy(minimum: 9, release: 9));
      await pending;
      expect(read().status, AppVersionStatus.unknown);
    },
  );
  test(
    'invalid local metadata not substituted with published version',
    () async {
      setup();
      container.updateOverrides([
        appVersionRepositoryProvider.overrideWithValue(repo),
        currentAppVersionProvider.overrideWithValue(null),
        installChannelProvider.overrideWithValue(InstallChannel.web),
      ]);
      controller = container.read(appVersionControllerProvider.notifier);
      await controller.check();
      expect(read().failure, AppVersionFailure.invalidCurrent);
      expect(repo.calls, isEmpty);
    },
  );
  test('disposed controller ignores pending completion', () async {
    final repo = PendingRepository();
    final c = ProviderContainer(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(repo),
        currentAppVersionProvider.overrideWithValue(
          AppVersion.tryParse('0.1.0', 8),
        ),
        installChannelProvider.overrideWithValue(InstallChannel.web),
      ],
    );
    final pending = c.read(appVersionControllerProvider.notifier).check();
    c.dispose();
    repo.calls.last.complete(policy());
    await pending;
  });
}
