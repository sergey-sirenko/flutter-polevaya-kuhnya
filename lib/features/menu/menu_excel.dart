import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/shared/external_link.dart';

/// Excel-меню [Ж] FR-M5: внешние `data/download/1.xls` и `2.xls`.
/// Отсутствие файла не ломает заказ — пункт просто недоступен.
const menuExcelFiles = ['1.xls', '2.xls'];

final menuExcelAvailabilityProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
      final config = ref.watch(appConfigProvider);
      final client = ref.watch(httpClientProvider);
      final result = <String, bool>{};
      for (final name in menuExcelFiles) {
        final uri = config.dataBaseUri.resolve('download/$name');
        try {
          final response = await client
              .send(
                http.Request('GET', uri)
                  ..headers['Range'] = 'bytes=0-0'
                  ..followRedirects = false,
              )
              .timeout(const Duration(seconds: 8));
          await response.stream.drain<void>();
          result[name] =
              response.statusCode >= 200 && response.statusCode < 300;
        } catch (_) {
          result[name] = false;
        }
      }
      return result;
    });

Future<bool> openMenuExcel(Uri dataBaseUri, String fileName) {
  final uri = dataBaseUri.resolve('download/$fileName');
  return tryOpenExternal(uri);
}

/// Пункт верхнего меню. В адаптивном окне его не показывают.
class MenuDownloadButton extends ConsumerWidget {
  const MenuDownloadButton({super.key});

  static const buttonKey = ValueKey('menu-download');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(menuExcelAvailabilityProvider);
    return PopupMenuButton<String>(
      key: buttonKey,
      tooltip: AppStrings.menuDownload,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onSelected: (fileName) async {
        final config = ref.read(appConfigProvider);
        final opened = await openMenuExcel(config.dataBaseUri, fileName);
        if (!context.mounted) return;
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.menuExcelUnavailable)),
          );
        }
      },
      itemBuilder: (context) {
        final map = availability.asData?.value ?? const <String, bool>{};
        return [
          for (final name in menuExcelFiles)
            PopupMenuItem(
              value: name,
              enabled: map[name] ?? false,
              child: Text(
                map[name] == true
                    ? (name == '1.xls' ? 'Текущая неделя' : 'Следующая неделя')
                    : '${name == '1.xls' ? 'Текущая неделя' : 'Следующая неделя'} (${AppStrings.menuExcelMissing})',
              ),
            ),
        ];
      },
      child: const Text(AppStrings.menuDownload),
    );
  }
}
