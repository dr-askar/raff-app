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
