import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/data/files.dart';
import 'package:raff/domain/models.dart';
import 'package:raff/domain/worker_access.dart';
import 'package:raff/main.dart';
import 'package:raff/ui/product_editor.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Excel accepts Arabic types, defaults blank cells to pack and preserves missing columns', () {
    List<int> book(List<String> headers, List<List<CellValue?>> rows) {
      final excel = Excel.createExcel();
      final sheet = excel['Products']; excel.delete('Sheet1');
      sheet.appendRow(headers.map(TextCellValue.new).toList());
      for (final row in rows) { sheet.appendRow(row); }
      return excel.encode()!;
    }
    const previous = Product(id: 'existing', name: 'صنف سابق', unit: 'kg', pack: 12);
    var id = 0;
    final plan = StoreFiles.preview(book(['id', 'اسم المادة', 'نوع الصنف', 'عدد القطع بالطرد'], [
      [TextCellValue('existing'), TextCellValue('صنف سابق'), null, IntCellValue(12)],
      [null, TextCellValue('صنف طرد'), TextCellValue('طرد'), IntCellValue(6)],
      [null, TextCellValue('صنف وزن'), TextCellValue(' وزن '), DoubleCellValue(12.5)],
      [null, TextCellValue('صنف افتراضي'), null, IntCellValue(1)],
      [null, TextCellValue('نوع غير معروف'), TextCellValue('other'), IntCellValue(1)],
    ]), [previous], const StoreSettings(), () => 'new${id++}');
    expect(plan.updated, 1); expect(plan.added, 3); expect(plan.skipped, 1);
    expect(plan.products.map((p) => p.unit), ['piece', 'piece', 'kg', 'piece']);
    final legacy = StoreFiles.preview(book(['id', 'name'], [
      [TextCellValue('existing'), TextCellValue('اسم جديد')],
    ]), [previous], const StoreSettings(), () => 'unused');
    expect(legacy.warnings, isEmpty); expect(legacy.products.single.unit, 'kg');
    final exported = Excel.decodeBytes(StoreFiles.productExcel(plan.products, const StoreSettings()));
    expect(exported['Products'].rows.first.last!.value.toString(), 'نوع الصنف');
    expect(exported['Products'].rows[1].last!.value.toString(), 'طرد');
    final roundtrip = StoreFiles.preview(exported.encode()!, [], const StoreSettings(), () => 'unused');
    expect(roundtrip.warnings, isEmpty);
    expect(roundtrip.products.map((p) => p.unit), plan.products.map((p) => p.unit));
    expect(Product.fromJson('old', {'name': 'قديم', 'unit': ' '}).unit, 'piece');
  });

  testWidgets('exchange summary stays compact on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 740); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
    await tester.pumpWidget(RaffApp(store: store)); await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('exchange-summary'))).height, lessThanOrEqualTo(88));
    expect(find.byTooltip('تعديل الصرف'), findsOneWidget);
    expect(find.text('حليب كامل الدسم').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); store.dispose();
  });

  for (final weighted in [false, true]) {
    testWidgets('owner enters SYP pack cost for ${weighted ? "weight" : "default pack"}', (tester) async {
      final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        TextButton(onPressed: () => editProduct(context, store), child: const Text('افتح')))));
      await tester.tap(find.text('افتح')); await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field); await tester.enterText(field, value); await tester.pumpAndSettle();
      }
      await fill('اسم المادة', weighted ? 'وزن سوري' : 'طرد سوري');
      if (weighted) {
        await tester.ensureVisible(find.text('وزن')); await tester.tap(find.text('وزن'));
        await tester.pumpAndSettle();
      }
      await fill(weighted ? 'وزن الطرد بالكيلوغرام' : 'عدد القطع بالطرد', weighted ? '٢٥' : '١٢');
      final currency = find.widgetWithText(DropdownButtonFormField<String>, 'عملة رأس المال');
      await tester.ensureVisible(currency); await tester.tap(currency); await tester.pumpAndSettle();
      await tester.tap(find.text('ليرة سورية SYP').last); await tester.pumpAndSettle();
      await fill('تكلفة الطرد بالسوري', weighted ? '٢٥٠٠٠' : '١٢٠٠٠٠');
      expect(find.text(weighted ? 'تكلفة الكيلوغرام المحسوبة: 1000 ل.س' : 'تكلفة القطعة المحسوبة: 10000 ل.س'), findsOneWidget);
      await tester.tap(find.text('حفظ المادة')); await tester.pumpAndSettle();
      final saved = store.products.singleWhere((p) => p.name == (weighted ? 'وزن سوري' : 'طرد سوري'));
      expect(saved.unit, weighted ? 'kg' : 'piece');
      expect(saved.costLocal, weighted ? 1000 : 10000);
      expect(saved.packCost, weighted ? 25000 : 120000);
      expect(saved.costCurrency, 'SYP');
      final price = saved.price(store.settings);
      await store.changeSettings(15000, store.settings.margin, store.settings.currency);
      expect(store.findId(saved.id)!.price(store.settings), price);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink()); store.dispose();
    });
  }

  testWidgets('restore actions follow the worker permission without exposing exports or cost', (tester) async {
    final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
    await store.setOwnerPassword('owner123');
    await store.setWorkerAccess('local', const WorkerAccess().withValue('restoreBackup', true));
    store.lockWorker();
    await tester.pumpWidget(RaffApp(store: store)); await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات')); await tester.pumpAndSettle();
    expect(find.text('استعادة نسخة احتياطية'), findsOneWidget);
    expect(find.text('استعادة نسخة JSON من Drive'), findsOneWidget);
    expect(find.text('تنزيل نسخة احتياطية'), findsNothing);
    expect(find.text('تصدير المواد إلى Excel'), findsNothing);
    expect(store.can('viewCost'), false); expect(store.owner, false);
    await store.unlockOwner('owner123');
    await store.setWorkerAccess('local', const WorkerAccess()); store.lockWorker();
    await tester.pumpAndSettle();
    expect(find.text('استعادة نسخة احتياطية'), findsNothing);
    expect(find.text('استعادة نسخة JSON من Drive'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); store.dispose();
  });
}
