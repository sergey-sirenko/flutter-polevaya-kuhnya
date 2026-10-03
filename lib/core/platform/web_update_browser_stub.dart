import 'web_update_browser_api.dart';

WebUpdateBrowser createWebUpdateBrowser() => _UnsupportedBrowser();

class _UnsupportedBrowser implements WebUpdateBrowser {
  @override
  bool get supported => false;
  @override
  bool get visible => false;
  @override
  void Function() watchForeground(void Function() onForeground) => () {};
  @override
  Future<bool> reloadRelease(String release) async => false;
}
