import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raff/data/files.dart';
import 'package:raff/domain/models.dart';

const settings = StoreSettings(rate: 10000, margin: 20);

List<int> book(List<String> headers, List<List<CellValue?>> rows) {
  final e = Excel.createExcel();
  e.delete('Sheet1');
  final sheet = e['Products'];
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  for (final row in rows) { sheet.appendRow(row); }
  return e.encode()!;
}

void main() {
  test('six pieces and thirty dollars export as pack price, not five dollars', () {
    final p = const Product(id: 'p', name: 'صنف الصورة', barcode: '001234', pack: 6, quantity: 20)
      .edit(costUsd: 5, manualPrice: 60000, settings: settings);
    final bytes = StoreFiles.productExcel([p], settings);
    final rows = Excel.decodeBytes(bytes)['Products'].rows;
    final headers = rows.first.map((c) => c!.value.toString()).toList();
    double? cell(String name) => double.tryParse(rows[1][headers.indexOf(name)]?.value.toString() ?? '');
    expect(headers, isNot(contains('cost_usd')));
    expect(headers, isNot(contains('quantity')));
    expect(cell('سعر الطرد'), 30);
    expect(cell('عدد القطع بالطرد'), 6);
    expect(cell('عدد الطرود'), 3);
    expect(cell('قطع إضافية'), 2);
    expect(cell('سعر مبيع الطرد الثابت'), 360000);
    final plan = StoreFiles.preview(bytes, [], settings, () => 'unused');
    expect(plan.warnings, isEmpty);
    final result = plan.products.single;
    expect(result.costUsd, 5); expect(result.quantity, 20);
    expect(result.manualPrice, 60000); expect(result.barcode, '001234');
  });

  test('editing pack price, content, count and loose pieces recalculates the product', () {
    final p = const Product(id: 'p', name: 'طرد', pack: 6, quantity: 20)
      .edit(costUsd: 5, settings: settings);
    final e = Excel.decodeBytes(StoreFiles.productExcel([p], settings));
    final sheet = e['Products'];
    final headers = sheet.rows.first.map((c) => c!.value.toString()).toList();
    void set(String key, double value) => sheet.cell(CellIndex.indexByColumnRow(
      columnIndex: headers.indexOf(key), rowIndex: 1)).value = DoubleCellValue(value);
    set('سعر الطرد', 60); set('عدد القطع بالطرد', 12);
    set('عدد الطرود', 4); set('قطع إضافية', 3);
    final plan = StoreFiles.preview(e.encode()!, [p], settings, () => 'unused');
    expect(plan.warnings, isEmpty); expect(plan.updated, 1);
    expect(plan.products.single.quantity, 51); expect(plan.products.single.packCost, 60);
    expect(plan.products.single.costUsd, 5);
  });

  test('new Arabic pack rows support either currency, names only, and blank defaults', () {
    var id = 0;
    final plan = StoreFiles.preview(book(
      ['اسم المادة', 'عدد الطرود', 'عدد القطع بالطرد', 'سعر الطرد', 'عملة التكلفة', 'نوع الصنف'], [
      [TextCellValue('سوري'), TextCellValue('٢'), IntCellValue(12), IntCellValue(120000), TextCellValue('سوري'), null],
      [TextCellValue('دولار'), IntCellValue(3), IntCellValue(6), IntCellValue(30), TextCellValue('USD'), null],
      [TextCellValue('اسم فقط')],
    ]), [], settings, () => 'p${id++}');
    expect(plan.warnings, isEmpty); expect(plan.added, 3);
    expect(plan.products[0].costLocal, 10000); expect(plan.products[0].quantity, 24);
    expect(plan.products[0].price(const StoreSettings(rate: 20000)), 12000);
    expect(plan.products[1].costUsd, 5); expect(plan.products[1].quantity, 18);
    expect(plan.products[2].pack, 1); expect(plan.products[2].ready, false);
  });

  test('kilogram products export pack price with fractional weight and kg stock', () {
    final p = const Product(id: 'kg', name: 'رز فلت', unit: 'kg', pack: 12.5, quantity: 0.125)
      .edit(costCurrency: 'SYP', costLocal: 2000, settings: settings);
    final e = Excel.decodeBytes(StoreFiles.productExcel([p], settings));
    final sheet = e['Products'];
    final headers = sheet.rows.first.map((c) => c!.value.toString()).toList();
    double? cell(String name) => double.tryParse(sheet.rows[1][headers.indexOf(name)]?.value.toString() ?? '');
    expect(cell('عدد الطرود'), isNull); expect(cell('عدد القطع بالطرد'), isNull);
    expect(cell('وزن الطرد بالكيلوغرام'), 12.5);
    expect(cell('الكمية بالكيلوغرام'), 0.125);
    expect(cell('سعر الطرد'), 25000);
    final plan = StoreFiles.preview(e.encode()!, [], settings, () => 'unused');
    expect(plan.warnings, isEmpty); expect(plan.products.single.unit, 'kg');
    expect(plan.products.single.costLocal, 2000); expect(plan.products.single.quantity, 0.125);
  });

  test('weighted pack counts can be fractional and bad rows do not block good ones', () {
    var id = 0;
    final plan = StoreFiles.preview(book(
      ['اسم المادة', 'نوع الصنف', 'وزن الطرد بالكيلوغرام', 'عدد الطرود', 'سعر الطرد', 'قطع إضافية'], [
      [TextCellValue('صالح'), TextCellValue('وزن'), DoubleCellValue(12.5), DoubleCellValue(0.25), IntCellValue(25)],
      [TextCellValue('خطأ'), TextCellValue('وزن'), DoubleCellValue(12.5), IntCellValue(1), IntCellValue(25), IntCellValue(1)],
    ]), [], settings, () => 'p${id++}');
    expect(plan.added, 1); expect(plan.skipped, 1);
    expect(plan.products.single.quantity, 3.125); expect(plan.products.single.costUsd, 2);
  });

  test('legacy per-unit columns retain their meaning and conflicting mixes are isolated', () {
    var id = 0;
    final legacy = StoreFiles.preview(book(['name', 'pack', 'quantity', 'cost_usd'], [
      [TextCellValue('قديم'), IntCellValue(6), IntCellValue(20), IntCellValue(5)],
    ]), [], settings, () => 'old');
    expect(legacy.warnings, isEmpty); expect(legacy.products.single.costUsd, 5);
    expect(legacy.products.single.quantity, 20); expect(legacy.products.single.packCost, 30);
    final conflict = StoreFiles.preview(book(['name', 'pack', 'quantity', 'عدد الطرود', 'cost_usd', 'سعر الطرد'], [
      [TextCellValue('صالح'), IntCellValue(6), IntCellValue(12), IntCellValue(2), IntCellValue(5), IntCellValue(30)],
      [TextCellValue('تعارض كمية'), IntCellValue(6), IntCellValue(20), IntCellValue(2), IntCellValue(5), IntCellValue(30)],
      [TextCellValue('تعارض سعر'), IntCellValue(6), IntCellValue(12), IntCellValue(2), IntCellValue(5), IntCellValue(5)],
    ]), [], settings, () => 'p${id++}');
    expect(conflict.added, 1); expect(conflict.skipped, 2);
  });

  test('blank pack values preserve existing stock and cost, zero values are applied', () {
    final old = const Product(id: 'p', name: 'مادة', pack: 6, quantity: 20)
      .edit(costUsd: 5, settings: settings);
    final blank = StoreFiles.preview(book(['id', 'عدد الطرود', 'سعر الطرد'], [[TextCellValue('p')]]),
      [old], settings, () => 'unused');
    expect(blank.warnings, isEmpty); expect(blank.products.single.quantity, 20);
    expect(blank.products.single.packCost, 30);
    final zero = StoreFiles.preview(book(['id', 'عدد الطرود', 'سعر الطرد'], [
      [TextCellValue('p'), IntCellValue(0), IntCellValue(0)],
    ]), [old], settings, () => 'unused');
    expect(zero.warnings, isEmpty); expect(zero.products.single.quantity, 0);
    expect(zero.products.single.costUsd, 0);
  });

  test('one sheet with 1200 pack and weighted rows roundtrips without a row cap', () {
    final products = List.generate(1200, (i) => Product(id: 'p$i', name: 'مادة $i',
      barcode: '00$i', unit: i.isEven ? 'piece' : 'kg', pack: i.isEven ? 6 : 12.5,
      quantity: i.isEven ? 20 : 0.125).edit(costUsd: 5, settings: settings));
    final plan = StoreFiles.preview(StoreFiles.productExcel(products, settings), [], settings, () => 'unused');
    expect(plan.warnings, isEmpty); expect(plan.added, 1200); expect(plan.sheets, 1);
    expect(plan.products.last.quantity, 0.125); expect(plan.products.first.quantity, 20);
    expect(plan.products.first.costUsd, 5); expect(plan.products.last.packCost, 62.5);
  });
}
