import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raff/data/files.dart';
import 'package:raff/data/xlsx_values.dart';
import 'package:raff/domain/models.dart';
import 'package:raff/data/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('mobile formatting does not stop 113 rows in a single worksheet', () async {
    final raw = base64Decode(File('test/fixtures/mobile_values_113.base64').readAsStringSync().trim());
    expect(() => Excel.decodeBytes(raw), throwsA(anything));
    expect(Excel.decodeBytes(normalizeXlsxValues(raw)).tables.values.single.maxRows, 114);
    var n = 0;
    final plan = StoreFiles.preview(raw, [], const StoreSettings(), () => 'new${n++}');
    expect(plan.warnings, isEmpty);
    expect(plan.sheets, 1);
    expect(plan.added, 113);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs: prefs);
    await store.initialize();
    final result = await store.importProducts(plan.products, settingsRevision: store.settings.revision);
    expect(result.added, 113);
    expect(result.failed, 0);
    expect(result.unprocessed, 0);
    final reopened = AppStore(prefs: prefs);
    await reopened.initialize();
    for (final product in plan.products) {
      expect(reopened.findId(product.id)?.name, product.name);
    }
    store.dispose();
    reopened.dispose();
  });
  test('1200 products import and reopen from one worksheet without a row cap', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs: prefs);
    await store.initialize();
    final book = Excel.createExcel();
    final sheet = book['Products'];
    book.delete('Sheet1');
    sheet.appendRow(['name', 'barcode', 'quantity'].map(TextCellValue.new).toList());
    for (var i = 0; i < 1200; i++) {
      sheet.appendRow([TextCellValue('صنف اختبار $i'),
        TextCellValue('000$i'), IntCellValue(i)]);
    }
    final plan = StoreFiles.preview(book.encode()!, store.products, store.settings, store.newId);
    expect(plan.sheets, 1);
    expect(plan.added, 1200);
    expect(plan.warnings, isEmpty);
    final progress = <int>[];
    final result = await store.importProducts(plan.products,
      settingsRevision: store.settings.revision,
      onProgress: (done, total) { expect(total, 1200); progress.add(done); });
    expect(result.saved, 1200);
    expect(result.failed, 0);
    expect(result.unprocessed, 0);
    expect(progress.last, 1200);
    final reopened = AppStore(prefs: prefs);
    await reopened.initialize();
    expect(reopened.products.length, 1203);
    for (var i = 0; i < 1200; i++) {
      expect(reopened.findBarcode('000$i')?.quantity, i.toDouble());
    }
    store.dispose();
    reopened.dispose();
  });

}
