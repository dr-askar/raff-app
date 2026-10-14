import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raff/data/files.dart';
import 'package:raff/domain/models.dart';

List<int> workbook(List<List<CellValue?>> rows) {
  final e = Excel.createExcel();
  for (final row in rows) { e['Sheet1'].appendRow(row); }
  return e.encode()!;
}
void main() {
  const settings = StoreSettings(rate: 10000, margin: 20);
  test('external editor workbook adds an unbarcoded item and updates existing rows', () {
    final bytes = base64Decode(File('test/fixtures/edited_excel.base64').readAsStringSync().trim());
    const existing = [
      Product(id: 'a', name: 'Old A', barcode: '1000000000001'),
      Product(id: 'b', name: 'Sample B', barcode: '1000000000002'),
      Product(id: 'c', name: 'Sample C', barcode: '1000000000003'),
    ];
    final plan = StoreFiles.preview(bytes, existing, settings, () => 'new');
    expect(plan.warnings, isEmpty);
    expect(plan.updated, 3); expect(plan.added, 1);
    expect(plan.products.first.name, 'Sample A');
    expect(plan.products.last.name, 'New sample');
    expect(plan.products.last.barcode, isEmpty);
    expect(plan.products.last.quantity, 10);
    expect(plan.products.last.costUsd, 0.8);
    expect(plan.products.last.margin, 8);
    expect(plan.products.last.manualPrice, 9000);
  });
  test('an edited export can rename an item without a barcode and add a new item', () {
    const old = Product(id: 'existing', name: 'اسم قديم', quantity: 7,
      costUsd: 2, saleBaseUsd: 2.4, ready: true, revision: 3);
    final book = Excel.decodeBytes(StoreFiles.productExcel([old], settings));
    book['Products'].cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('اسم جديد');
    book['Products'].appendRow([null, TextCellValue('مادة مضافة من Excel')]);
    final plan = StoreFiles.preview(book.encode()!, [old], settings, () => 'new');
    expect(plan.warnings, isEmpty); expect(plan.updated, 1); expect(plan.added, 1);
    expect(plan.products.first.id, old.id); expect(plan.products.first.name, 'اسم جديد');
    expect(plan.products.first.quantity, 7); expect(plan.products.first.revision, 4);
    expect(plan.products.last.id, 'new'); expect(plan.products.last.ready, false);
  });
  test('a barcode identifies a renamed item in old exports without an id', () {
    const old = Product(id: 'p', name: 'قديم', barcode: '00123', revision: 4);
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('name'), TextCellValue('barcode')],
      [TextCellValue('جديد'), TextCellValue('00123')],
    ]), [old], settings, () => 'new');
    expect(plan.updated, 1); expect(plan.added, 0);
    expect(plan.products.single.id, 'p'); expect(plan.products.single.name, 'جديد');
  });
  test('new rows accept Arabic digits and thousands separators', () {
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('اسم المنتج'), TextCellValue('quantity'), TextCellValue('manual_price')],
      [TextCellValue('جديد'), TextCellValue('١٢'), TextCellValue('12,500')],
    ]), [], settings, () => 'new');
    expect(plan.warnings, isEmpty); expect(plan.products.single.quantity, 12);
    expect(plan.products.single.manualPrice, 12500);
  });
  test('adding a barcode to an existing unique unbarcoded item updates it', () {
    const old = Product(id: 'p', name: 'حليب', revision: 1);
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('name'), TextCellValue('barcode')],
      [TextCellValue('حليب'), TextCellValue('123')],
    ]), [old], settings, () => 'new');
    expect(plan.products.single.id, 'p'); expect(plan.updated, 1);
  });
  test('conflicting id and barcode skip one row without stopping a valid addition', () {
    const a = Product(id: 'a', name: 'أ', barcode: '111');
    const b = Product(id: 'b', name: 'ب', barcode: '222');
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('id'), TextCellValue('name'), TextCellValue('barcode')],
      [TextCellValue('a'), TextCellValue('تعارض'), TextCellValue('222')],
      [null, TextCellValue('جديد'), TextCellValue('333')],
    ]), [a, b], settings, () => 'new');
    expect(plan.warnings.length, 1); expect(plan.products.single.id, 'new');
    expect(plan.added, 1);
  });
  test('name-only imports create unpriced products with safe defaults', () {
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('اسم المادة')], [TextCellValue('سكر')],
    ]), [], settings, () => 'new');
    expect(plan.added, 1); expect(plan.products.single.pack, 1);
    expect(plan.products.single.quantity, 0); expect(plan.products.single.ready, false);
    expect(plan.warnings, isEmpty);
  });
  test('empty imported cells preserve existing fields', () {
    final old = const Product(id: 'p', name: 'حليب', barcode: '000123', quantity: 12,
      costUsd: 2, saleBaseUsd: 2.4, ready: true, manualPrice: 25000, revision: 1);
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('barcode'), TextCellValue('name'), TextCellValue('cost_usd'), TextCellValue('quantity')],
      [TextCellValue('000123'), null, null, null],
    ]), [old], settings, () => 'new');
    expect(plan.updated, 1); expect(plan.products.single.quantity, 12);
    expect(plan.products.single.costUsd, 2); expect(plan.products.single.manualPrice, 25000);
  });
  test('one bad numeric row does not stop valid rows', () {
    var id = 0;
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('name'), TextCellValue('cost_usd')],
      [TextCellValue('صالح'), DoubleCellValue(1)],
      [TextCellValue('غير صالح'), TextCellValue('abc')],
      [TextCellValue('بدون تكلفة'), null],
    ]), [], settings, () => '${id++}');
    expect(plan.products.length, 2); expect(plan.warnings.length, 1);
  });
  test('export and import preserve barcode leading zeros and manual prices', () {
    const p = Product(id: 'p', name: 'مادة', barcode: '001234', pack: 12,
      quantity: 20, costUsd: 0.5, saleBaseUsd: 0.6, ready: true, manualPrice: 7000);
    final plan = StoreFiles.preview(StoreFiles.productExcel([p], settings), [], settings, () => 'new');
    expect(plan.products.single.barcode, '001234');
    expect(plan.products.single.manualPrice, 7000);
    expect(plan.products.single.pack, 12);
  });
  test('duplicate input barcode is flagged instead of applied twice', () {
    var id = 0;
    final plan = StoreFiles.preview(workbook([
      [TextCellValue('name'), TextCellValue('barcode')],
      [TextCellValue('أ'), TextCellValue('123')],
      [TextCellValue('ب'), TextCellValue('123')],
    ]), [], settings, () => '${id++}');
    expect(plan.products.length, 1); expect(plan.warnings.length, 1);
  });
}
import 'dart:convert';
import 'dart:io';
