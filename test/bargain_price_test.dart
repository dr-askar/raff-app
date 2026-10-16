import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/domain/models.dart';
import 'package:raff/domain/worker_access.dart';
import 'package:raff/main.dart';

void main() {
  test('5000 with 2 percent permits 4900 through 5000, with no automatic discount', () {
    const product = Product(id: 'p', name: 'صنف', manualPrice: 5000, ready: true, bargainPercent: 2);
    final line = CartLine(id: 'p', name: 'صنف', unitPrice: 5000, quantity: 2);
    expect(product.minimumPrice(const StoreSettings()), 4900);
    expect(line.sellingPrice, 5000); expect(line.total, 10000);
    line.setSellingPrice(4950, 2); expect(line.sellingPrice, 4950); expect(line.total, 9900);
    line.setSellingPrice(4900, 2); expect(line.total, 9800);
    for (final invalid in [4899.99, 5000.01, double.nan, double.infinity]) {
      expect(() => line.setSellingPrice(invalid, 2), throwsFormatException);
      expect(line.sellingPrice, 4900);
    }
    final zero = CartLine(id: 'zero', name: 'مجاني', unitPrice: 0);
    zero.setSellingPrice(0, 2); expect(zero.discountPercent, 0);
    expect(() => zero.setSellingPrice(1, 2), throwsFormatException);
  });
  test('fractional floors round upward and remain enterable at displayed precision', () {
    const product = Product(id: 'p', name: 'fraction', manualPrice: 12.34, ready: true, bargainPercent: 2);
    final line = CartLine(id: 'p', name: 'fraction', unitPrice: 12.34);
    expect(product.minimumPrice(const StoreSettings()), 12.10);
    expect(line.minimumPrice(2), 12.10);
    expect(() => line.setSellingPrice(12.09, 2), throwsFormatException);
    line.setSellingPrice(12.10, 2); expect(line.sellingPrice, 12.10);
    line.setDiscount(2, 2); expect(line.sellingPrice, 12.10);
  });
  test('lowering the owner limit or revoking permission removes an excessive chosen price', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await s.setOwnerPassword('owner123');
    var p = s.products.first.edit(manualPrice: 5000, bargainPercent: 2, settings: s.settings);
    await s.saveProduct(p); await s.setWorkerAccess('local', const WorkerAccess().withValue('applyBargain', true)); s.lockWorker();
    final line = CartLine(id: p.id, name: p.name, unitPrice: 5000);
    s.applyBargainPrice(line, 4900); expect(s.basketTotal([line]), 4900);
    expect(() => s.applyBargainPrice(line, 4899), throwsFormatException);
    await s.unlockOwner('owner123'); p = s.findId(p.id)!.edit(bargainPercent: 1, settings: s.settings); await s.saveProduct(p); s.lockWorker();
    expect(s.basketTotal([line]), 4950);
    await s.unlockOwner('owner123'); await s.setWorkerAccess('local', const WorkerAccess()); s.lockWorker();
    expect(() => s.applyBargainPrice(line, 4950), throwsFormatException);
    expect(s.basketTotal([line]), 5000); expect(s.findId(p.id)!.price(s.settings), 5000);
    s.dispose();
  });
  testWidgets('worker sees minimum amount and enters an Arabic price within the two bounds', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    final p = s.products.first.edit(manualPrice: 5000, bargainPercent: 2, settings: s.settings);
    await tester.runAsync(() async {
      await s.saveProduct(p); await s.setOwnerPassword('owner123');
      await s.setWorkerAccess('local', const WorkerAccess().withValue('applyBargain', true));
    });
    s.lockWorker();
    await tester.pumpWidget(RaffApp(store: s)); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, p.name); await tester.pumpAndSettle();
    expect(find.textContaining('أقل سعر مسموح: 4,900'), findsOneWidget);
    await tester.tap(find.text('حساب زبون')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, p.name); await tester.pumpAndSettle();
    await tester.tap(find.text(p.name)); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('مسح البحث')); await tester.pumpAndSettle();
    expect(find.text('5,000 ل.س'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('اختيار سعر للزبون')); await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('bargain-price'));
    await tester.enterText(field, '4899'); await tester.tap(find.text('اعتماد السعر')); await tester.pumpAndSettle();
    expect(find.text('اختر سعراً بين أقل سعر مسموح وسعر المبيع.'), findsOneWidget);
    await tester.enterText(field, '٤٩٥٠'); await tester.tap(find.text('اعتماد السعر')); await tester.pumpAndSettle();
    expect(find.textContaining('4,950 للقطعة'), findsOneWidget);
    expect(find.text('4,950 ل.س'), findsNWidgets(2)); expect(tester.takeException(), isNull);
    expect(s.findId(p.id)!.price(s.settings), 5000);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
}
