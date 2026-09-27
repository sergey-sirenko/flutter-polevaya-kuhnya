// Снимок профиля из ответа `POST V1/User/login` (пароль или token).
// Не хранится на диске; только в памяти сессии / вызывающего кода (NFR-SEC-1/2).

import 'package:polevaya_kuhnya/core/auth/session_state.dart';

/// Одна позиция в истории заказа (`user.order[].dishes[]`).
final class UserOrderDish {
  const UserOrderDish({
    required this.dishId,
    required this.name,
    required this.menuNumber,
    required this.quantity,
    required this.sum,
    required this.discountPercentage,
    required this.discountClient,
  });

  final String dishId;
  final String name;
  final int menuNumber;
  final num quantity;
  final num sum;
  final num discountPercentage;
  final num discountClient;

  static UserOrderDish fromJson(Map<String, Object?> json) {
    return UserOrderDish(
      dishId: json['dish']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      menuNumber: _asInt(json['menunumber']),
      quantity: _asNum(json['quantity']),
      sum: _asNum(json['sum']),
      discountPercentage: _asNum(json['DiscountPercentage']),
      discountClient: _asNum(json['DiscountClient']),
    );
  }
}

/// День истории (`user.order[]`).
final class UserOrderDay {
  const UserOrderDay({
    required this.dateRaw,
    required this.weekType,
    required this.changes,
    required this.status,
    required this.dishes,
    required this.discount,
    required this.sum,
  });

  final String dateRaw;
  final String weekType;
  final bool changes;
  final String status;
  final List<UserOrderDish> dishes;
  final num discount;
  final num sum;

  static UserOrderDay fromJson(Map<String, Object?> json) {
    final dishesRaw = json['dishes'];
    return UserOrderDay(
      dateRaw: json['date']?.toString() ?? '',
      weekType: json['weekType']?.toString() ?? '',
      changes: json['changes'] == true,
      status: json['status']?.toString() ?? '',
      dishes: [
        if (dishesRaw is List)
          for (final item in dishesRaw)
            if (item is Map)
              UserOrderDish.fromJson({
                for (final e in item.entries) e.key.toString(): e.value,
              }),
      ],
      discount: _asNum(json['discount']),
      sum: _asNum(json['sum']),
    );
  }
}

/// Профиль и условия клиента из `user` ответа login.
final class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.login,
    required this.employee,
    required this.rawUser,
    required this.orders,
  });

  final String name;
  final String email;
  final String phone;
  final String login;
  final String employee;

  /// Сырой объект `user` (условия скидок/лимитов — через `clientPricingConditionsFromUser`).
  final Map<String, Object?> rawUser;

  final List<UserOrderDay> orders;

  static UserProfile fromUserJson(Object? user) {
    if (user is! Map) {
      throw const FormatException(
        'Ответ login: user отсутствует или не объект.',
      );
    }
    final map = <String, Object?>{
      for (final e in user.entries) e.key.toString(): e.value,
    };
    final ordersRaw = map['order'];
    return UserProfile(
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      login: map['login']?.toString() ?? '',
      employee: map['employee']?.toString() ?? '',
      rawUser: map,
      orders: [
        if (ordersRaw is List)
          for (final item in ordersRaw)
            if (item is Map)
              UserOrderDay.fromJson({
                for (final e in item.entries) e.key.toString(): e.value,
              }),
      ],
    );
  }
}

/// Результат подтверждения сессии / профиля по токену.
final class SessionVerification {
  const SessionVerification({
    required this.credentials,
    required this.profile,
  });

  final SessionCredentials credentials;
  final UserProfile profile;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

num _asNum(Object? value) {
  if (value is num) {
    return value;
  }
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
