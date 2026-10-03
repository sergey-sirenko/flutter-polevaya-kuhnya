import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

void main() {
  test(
    'день источника сохраняется с timezone, неверные даты не показываются',
    () {
      expect(formatCalendarDate('2030-01-02T23:59:00-12:00'), '02.01.2030');
      expect(
        formatCalendarDate('2030-01-02T00:00:00+14:00', includeYear: false),
        '02.01',
      );
      expect(formatCalendarDate('2028-02-29'), '29.02.2028');
      expect(formatCartDayTitle('2026-10-01'), 'Чт 01.10.26');
      expect(formatCartDayTitle('2030-01-02T23:59:00-12:00'), 'Ср 02.01.30');
      expect(formatCartDayTitle('2026-10-04'), 'Вс 04.10.26');
      expect(formatCartDayTitle('вчера'), AppStrings.profileValueMissing);
      for (final raw in [null, '', '2030-02-29', '2030-13-01', 'вчера']) {
        expect(formatCalendarDate(raw), AppStrings.profileValueMissing);
      }
    },
  );

  test('дробные рубли сохраняют копейки, целые без .0, тысячи разделены', () {
    expect(formatRubles(190.5), '190,50 ₽');
    expect(formatRubles(100.0), '100 ₽');
    expect(formatRubles(0), '0 ₽');
    expect(formatRubles(0.01), '0,01 ₽');
    expect(formatRubles(-10.5), '-10,50 ₽');
    expect(formatRubles(1234.56), '1\u00a0234,56 ₽');
    expect(formatRubles(99.999), '100 ₽');
    expect(formatRubles(null), AppStrings.profileValueMissing);
    expect(formatRubles(double.nan), AppStrings.profileValueMissing);
    expect(formatQuantity(2.0), '2');
  });
}
