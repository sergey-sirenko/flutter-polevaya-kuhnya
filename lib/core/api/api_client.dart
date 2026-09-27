import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

/// Общий транспорт. Поля авторизации передаются конкретным Repository в body.
final class ApiClient {
  ApiClient({
    required AppConfig config,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _apiBaseUri = config.apiBaseUri,
       _dataBaseUri = config.dataBaseUri,
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Должен быть положительным',
      );
    }
  }

  final Uri _apiBaseUri;
  final Uri _dataBaseUri;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// Один POST на вызов. При потере ответа результат записи неизвестен.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final uri = _resolvePath(_apiBaseUri, path);
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll(const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      })
      ..body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        kind: ApiErrorKind.timeout,
        message: 'Время ожидания ответа истекло.',
        outcomeUnknown: true,
      );
    } on http.ClientException {
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Не удалось связаться с сервером.',
        outcomeUnknown: true,
      );
    }

    final value = _decodeApi(response);
    if (value is! Map<String, dynamic>) {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный формат ответа API.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 401) {
      throw _serverError(ApiErrorKind.unauthorized, response.statusCode, value);
    }
    if (response.statusCode == 403) {
      throw _serverError(ApiErrorKind.forbidden, response.statusCode, value);
    }
    if (response.statusCode >= 500 || response.statusCode < 200) {
      throw _serverError(ApiErrorKind.http, response.statusCode, value);
    }
    if (response.statusCode >= 400) {
      throw _serverError(ApiErrorKind.business, response.statusCode, value);
    }
    if (response.statusCode >= 300) {
      throw _serverError(ApiErrorKind.http, response.statusCode, value);
    }
    final success = value['success'];
    if (success is! bool) {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'В ответе API отсутствует признак результата.',
        statusCode: response.statusCode,
      );
    }
    if (!success) {
      throw _serverError(ApiErrorKind.business, response.statusCode, value);
    }
    return value;
  }

  /// Публичный JSON с отдельной базы. Токен и тело API сюда не попадают.
  Future<Object?> getDataJson(String path) async {
    final uri = _resolvePath(_dataBaseUri, path);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        kind: ApiErrorKind.timeout,
        message: 'Время ожидания ответа истекло.',
      );
    } on http.ClientException {
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Не удалось загрузить данные.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        kind: ApiErrorKind.http,
        message: 'Не удалось загрузить данные.',
        statusCode: response.statusCode,
      );
    }
    return _decode(response);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static Uri _resolvePath(Uri base, String path) {
    final segments = path.split('/');
    if (path.isEmpty ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(segment),
        )) {
      throw ArgumentError.value(
        path,
        'path',
        'Нужен относительный путь без параметров',
      );
    }
    return base.resolve(path);
  }

  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'Ответ сервера не является корректным JSON.',
        statusCode: response.statusCode,
      );
    }
  }

  static Object? _decodeApi(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final value = _decode(response);
        return value is Map<String, dynamic> ? value : <String, dynamic>{};
      } on ApiException {
        return <String, dynamic>{};
      }
    }
    return _decode(response);
  }

  static ApiException _serverError(
    ApiErrorKind kind,
    int statusCode,
    Map<String, dynamic> value,
  ) {
    final code = value['code'];
    final message = value['message'];
    final error = value['error'];
    return ApiException(
      kind: kind,
      statusCode: statusCode,
      code: code is String && code.isNotEmpty ? code : null,
      message: error is String && error.isNotEmpty
          ? error
          : message is String && message.isNotEmpty
          ? message
          : 'Сервер отклонил запрос.',
    );
  }
}
