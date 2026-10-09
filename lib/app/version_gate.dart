import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/boot_loading.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';

/// Экран вне бизнес-router; публичная справка не запускает сессию/меню.
class VersionGatePage extends ConsumerStatefulWidget {
  const VersionGatePage({required this.version, this.onContinue, super.key});
  final AppVersionCheck version;
  final VoidCallback? onContinue;
  @override
  ConsumerState<VersionGatePage> createState() => _VersionGatePageState();
}

class _VersionGatePageState extends ConsumerState<VersionGatePage> {
  String? _information;
  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    final loading =
        version.checking ||
        version.status == AppVersionStatus.checking ||
        (version.status == AppVersionStatus.unknown && version.failure == null);
    if (loading && !version.requiresUpdate && _information == null) {
      return const BootLoading();
    }
    final title =
        _information ??
        (version.requiresUpdate
            ? AppStrings.versionRequired
            : loading
            ? AppStrings.versionChecking
            : AppStrings.versionUnknown);
    return Scaffold(
      key: const ValueKey('version-gate'),
      appBar: AppBar(
        title: const Text(
          AppStrings.appTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ContentPanel(
                maxWidth: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_information == AppStrings.privacy) ...[
                      for (final paragraph
                          in SiteContent.privacyParagraphs) ...[
                        Text(paragraph),
                        const SizedBox(height: 12),
                      ],
                    ] else if (_information == AppStrings.versionSupport) ...[
                      const Text(SiteContent.companyName),
                      const Text(SiteContent.phoneDisplay),
                      const Text(SiteContent.email),
                      const Text(SiteContent.hoursWeekday),
                      const Text(SiteContent.hoursFriday),
                    ] else ...[
                      if (loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                      ],
                      if (version.requiresUpdate) ...[
                        const Text(AppStrings.versionRequiredMessage),
                        const SizedBox(height: 12),
                        Text('Текущая версия: ${version.current}'),
                        Text('Минимальная версия: ${version.policy!.minimum}'),
                        const SizedBox(height: 12),
                        Text(
                          version.release == null
                              ? AppStrings.versionNoRelease
                              : AppStrings.versionRequiredHelp,
                        ),
                        if (version.failure != null) ...[
                          const SizedBox(height: 12),
                          const Text(AppStrings.versionRetryFailed),
                        ],
                      ] else if (!loading)
                        const Text(AppStrings.versionUnknownMessage),
                      if (!loading || version.requiresUpdate) ...[
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton(
                              key: const ValueKey('version-retry'),
                              onPressed: loading
                                  ? null
                                  : () => ref
                                        .read(
                                          appVersionControllerProvider.notifier,
                                        )
                                        .check(),
                              child: const Text(AppStrings.versionRetry),
                            ),
                            if (!version.requiresUpdate &&
                                widget.onContinue != null)
                              FilledButton(
                                key: const ValueKey('version-continue'),
                                onPressed: widget.onContinue,
                                child: const Text(AppStrings.versionContinue),
                              ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    if (_information != null)
                      TextButton(
                        key: const ValueKey('version-info-back'),
                        onPressed: () => setState(() => _information = null),
                        child: const Text('Назад'),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            key: const ValueKey('version-support'),
                            onPressed: () => setState(
                              () => _information = AppStrings.versionSupport,
                            ),
                            child: const Text(AppStrings.versionSupport),
                          ),
                          TextButton(
                            key: const ValueKey('version-privacy'),
                            onPressed: () => setState(
                              () => _information = AppStrings.privacy,
                            ),
                            child: const Text(AppStrings.privacy),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Бизнес-дерево остаётся mounted при повторе, но недоступно для ввода/фокуса.
class VersionGuard extends ConsumerStatefulWidget {
  const VersionGuard({required this.version, required this.child, super.key});
  final AppVersionCheck version;
  final Widget child;
  @override
  ConsumerState<VersionGuard> createState() => _VersionGuardState();
}

class _VersionGuardState extends ConsumerState<VersionGuard> {
  AppVersionCheck? _dismissed;
  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    final blocked = versionBlocksWork(version);
    final notice =
        (version.status == AppVersionStatus.unknown &&
            ref.watch(installChannelProvider) != InstallChannel.android) ||
        version.status == AppVersionStatus.available;
    return Stack(
      children: [
        Offstage(
          offstage: blocked,
          child: ExcludeFocus(
            excluding: blocked,
            child: TickerMode(
              enabled: !blocked,
              child: Column(
                children: [
                  if (!blocked && notice && !identical(version, _dismissed))
                    Material(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  version.status == AppVersionStatus.available
                                      ? 'Доступна новая версия: ${version.release!.version}. Вы можете продолжить работу.'
                                      : AppStrings.versionUnknownMessage,
                                ),
                              ),
                              Wrap(
                                children: [
                                  if (version.status ==
                                      AppVersionStatus.unknown)
                                    IconButton(
                                      key: const ValueKey(
                                        'version-notice-retry',
                                      ),
                                      tooltip: AppStrings.versionRetry,
                                      onPressed: () => ref
                                          .read(
                                            appVersionControllerProvider
                                                .notifier,
                                          )
                                          .check(),
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  IconButton(
                                    key: const ValueKey(
                                      'version-notice-dismiss',
                                    ),
                                    tooltip:
                                        version.status ==
                                            AppVersionStatus.available
                                        ? AppStrings.versionLater
                                        : AppStrings.close,
                                    onPressed: () =>
                                        setState(() => _dismissed = version),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('version-business-content'),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (blocked) Positioned.fill(child: VersionGatePage(version: version)),
      ],
    );
  }
}
