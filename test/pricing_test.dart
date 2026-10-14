import 'package:flutter_test/flutter_test.dart';
import 'package:raff/domain/models.dart';

void main() {
  const settings = StoreSettings(rate: 10000, margin: 20);
  test('automatic prices follow exchange rate; fixed prices remain fixed', () {
    final p = const Product(id: 'p', name: 'حليب').edit(costUsd: 2, settings: settings);
    expect(p.price(settings), 24000);
    expect(p.price(const StoreSettings(rate: 12000)), 28800);
    final fixed = p.edit(manualPrice: 25000, settings: settings);
    expect(fixed.price(const StoreSettings(rate: 12000)), 25000);
    expect(fixed.edit(automatic: true, settings: settings).price(settings), 24000);
  });
  test('a new product without cost remains unpriced', () {
    final p = const Product(id: 'p', name: 'جديد').edit(settings: settings);
    expect(p.ready, false);
    final fixed = p.edit(manualPrice: 1000, settings: settings);
    expect(fixed.ready, true);
  });
  test('private margin can return to the store default', () {
    final p = const Product(id: 'p', name: 'أرز').edit(costUsd: 1, margin: 50, settings: settings);
    expect(p.price(settings), 15000);
    final general = p.edit(useGeneralMargin: true, settings: settings);
    expect(general.margin, isNull);
    expect(general.price(settings), 12000);
  });
  test('invalid negative quantity cannot be saved', () {
    expect(() => const Product(id: 'p', name: 'مادة', quantity: -1).validate(), throwsFormatException);
  });
  test('stocktake totals use the frozen exchange rate and counted items', () {
    final s = Stocktake(id: 's', at: '2026-10-14', rate: 10000, currency: 'ل.س',
      counts: const {'p': 3, 'unknown': 10},
      snapshot: const {'p': {'costUsd': 2}, 'uncounted': {'costUsd': 7}});
    expect(s.value, 60000);
    expect(Stocktake.fromJson(s.toJson()).value, 60000);
  });
  test('cart quantities use the captured price', () {
    final line = CartLine(id: 'p', name: 'مادة', unitPrice: 12000, quantity: 3);
    expect(line.total, 36000);
  });
}
