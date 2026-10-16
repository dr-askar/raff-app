import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/data/files.dart';
import 'package:raff/domain/models.dart';
import 'package:raff/domain/worker_access.dart';
import 'package:raff/ui/common.dart';
import 'package:raff/ui/product_editor.dart';
import 'package:raff/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('old JSON stays piece-based; weighted pack, cost and quantity roundtrip in Excel', () {
    final legacy = Product.fromJson('old', {'name': 'قديم', 'pack': 12});
    expect(legacy.unit, 'piece'); expect(legacy.pack, 12);
    final product = const Product(id: 'kg', name: 'رز فلت', unit: 'kg', pack: 12.5, quantity: 0.125)
      .edit(costCurrency: 'SYP', costLocal: 2000, settings: const StoreSettings());
    expect(product.packCost, 25000);
    final plan = StoreFiles.preview(StoreFiles.productExcel([product], const StoreSettings()), [], const StoreSettings(), () => 'new');
    expect(plan.warnings, isEmpty); expect(plan.products.single.unit, 'kg');
    expect(plan.products.single.pack, 12.5); expect(plan.products.single.quantity, 0.125);
    expect(plan.products.single.costLocal, 2000);
    expect(parseQuantity('٠٫١٢٥'), 0.125); expect(parseQuantity('0,750'), 0.75);
    expect(quantityText(0.125), '0.125');
  });
  test('Excel pack costs in either currency divide by pack content', () {
    final book = Excel.createExcel();
    final sheet = book['Products']; book.delete('Sheet1');
    sheet.appendRow(['name', 'pack', 'cost_per_pack', 'cost_currency', 'unit'].map(TextCellValue.new).toList());
    sheet.appendRow([TextCellValue('قطعة دولار'), IntCellValue(12), IntCellValue(24), TextCellValue('USD'), TextCellValue('piece')]);
    sheet.appendRow([TextCellValue('وزن سوري'), DoubleCellValue(12.5), IntCellValue(25000), TextCellValue('SYP'), TextCellValue('kg')]);
    var n = 0;
    final plan = StoreFiles.preview(book.encode()!, [], const StoreSettings(), () => 'new${n++}');
    expect(plan.warnings, isEmpty); expect(plan.products.first.costUsd, 2);
    expect(plan.products.last.costLocal, 2000);
  });
  test('fractional sale uses exact weight and bargaining applies per kilogram', () {
    final line = CartLine(id: 'kg', name: 'جبنة', unitPrice: 5000, unit: 'kg');
    line.setQuantity(0.125); expect(line.total, 625);
    line.setSellingPrice(4900, 2); expect(line.total, 612.5);
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => line.setQuantity(invalid), throwsFormatException);
    }
    expect(() => CartLine(id: 'p', name: 'قطعة', unitPrice: 1).setQuantity(0.5), throwsFormatException);
  });
  test('worker restore permission is separate and never restores owner lock or permissions', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs: prefs); await store.initialize(); final backup = store.backup();
    await store.setOwnerPassword('owner123'); store.lockWorker();
    await expectLater(store.restore(backup), throwsFormatException);
    await store.unlockOwner('owner123');
    await store.setWorkerAccess('local', const WorkerAccess().withValue('restoreBackup', true)); store.lockWorker();
    final data = {...backup, 'owner': true, 'permissions': {'viewCost': true}};
    await store.restore(data); expect(store.owner, false); expect(store.can('viewCost'), false);
    expect(() => store.backup(), throwsFormatException);
    await expectLater(store.setWorkerAccess('local', const WorkerAccess()), throwsFormatException);
    final restarted = AppStore(prefs: prefs); await restarted.initialize();
    expect(restarted.owner, false); expect(restarted.can('restoreBackup'), true); expect(restarted.can('viewCost'), false);
    await expectLater(restarted.unlockOwner('wrongpass'), throwsFormatException);
    await restarted.unlockOwner('owner123');
    await restarted.setWorkerAccess('local', const WorkerAccess()); restarted.lockWorker();
    await expectLater(restarted.restore(backup), throwsFormatException);
    store.dispose(); restarted.dispose();
  });
  testWidgets('editor defaults to a pack price and calculates USD unit cost', (tester) async {
    final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => editProduct(context, store), child: const Text('افتح')))));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field); await tester.enterText(field, value); await tester.pumpAndSettle();
    }
    await fill('اسم المادة', 'صنف طرد'); await fill('عدد القطع بالطرد', '١٢');
    await fill('تكلفة الطرد بالدولار', '٢٤');
    expect(find.text('تكلفة القطعة المحسوبة: 2 \$'), findsOneWidget);
    await tester.tap(find.text('حفظ المادة')); await tester.pumpAndSettle();
    expect(store.products.singleWhere((p) => p.name == 'صنف طرد').costUsd, 2);
    await tester.pumpWidget(const SizedBox.shrink()); store.dispose();
  });
  testWidgets('weighted basket accepts Arabic decimal weight on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
    await store.saveProduct(const Product(id: 'weight', name: 'جبنة وزن', unit: 'kg', pack: 10, manualPrice: 5000, ready: true, revision: 1));
    await tester.pumpWidget(RaffApp(store: store)); await tester.pumpAndSettle();
    await tester.tap(find.text('حساب زبون')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'جبنة وزن'); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'جبنة وزن')); await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'الوزن بالكيلوغرام');
    await tester.enterText(field, '٠٫١٢٥'); await tester.tap(find.text('حفظ')); await tester.pumpAndSettle();
    expect(find.text('0.125 كغ'), findsOneWidget); expect(find.text('625 ل.س'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); store.dispose();
  });
}
