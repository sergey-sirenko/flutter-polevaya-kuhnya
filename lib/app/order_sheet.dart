import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OrderSheet { day, categories }

class OrderSheetController extends Notifier<OrderSheet?> {
  @override
  OrderSheet? build() => null;

  void toggle(OrderSheet next) {
    state = state == next ? null : next;
  }

  void close() => state = null;
}

final orderSheetProvider = NotifierProvider<OrderSheetController, OrderSheet?>(
  OrderSheetController.new,
);
