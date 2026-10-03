{{flutter_js}}
{{flutter_build_config}}

// Новому index соответствует новый inline bootstrap. Код приложения имеет
// отдельный URL выпуска, поэтому прежний HTTP-кэш его не подменяет.
const updateRelease = new URLSearchParams(window.location.search).get('_app_update');
const compiledStamp = String({{flutter_service_worker_version}});
const validRelease = updateRelease && /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+[1-9]\d*$/.test(updateRelease);
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    const entrypoint = new URL(build.mainJsPath, document.baseURI);
    entrypoint.searchParams.set('_app_code', compiledStamp);
    if (validRelease) {
      entrypoint.searchParams.set('_app_update', updateRelease);
    }
    build.mainJsPath = entrypoint.href;
  }
}
// Новый worker не регистрируется: перезагрузка управляется текущей вкладкой.
_flutter.loader.load();
