import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/data/files.dart';
import 'package:raff/domain/models.dart';

class FailingPreferences implements SharedPreferences {
  final SharedPreferences delegate;
  int writes = 0;
  FailingPreferences(this.delegate);
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  bool containsKey(String key) => delegate.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async {
    if (key == 'raff.demo.v1' && ++writes == 3) { return false; }
    return delegate.setString(key, value);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('all 1000 new items and a rename across sheets persist beyond 30 and 50', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs: prefs); await store.initialize();
    final old = store.products.first;
    final book = Excel.createExcel();
    for (var sheetIndex = 0; sheetIndex < 2; sheetIndex++) {
      final sheet = book[sheetIndex == 0 ? 'Products' : 'أصناف إضافية'];
      sheet.appendRow(['name', 'barcode', 'quantity'].map(TextCellValue.new).toList());
      for (var i = 0; i < 500; i++) {
        final n = sheetIndex * 500 + i;
        sheet.appendRow([TextCellValue('صنف $n'), TextCellValue('001$n'), IntCellValue(n)]);
      }
    }
    book.delete('Sheet1');
    book['Products'].appendRow([TextCellValue('رقم غير صالح'), null, TextCellValue('abc')]);
    book['أصناف إضافية'].appendRow([TextCellValue('باركود مكرر'), TextCellValue('0010')]);
    final rename = book['تعديلات'];
    rename.appendRow([TextCellValue('id'), TextCellValue('name')]);
    rename.appendRow([TextCellValue(old.id), TextCellValue('اسم معدل')]);
    final plan = StoreFiles.preview(book.encode()!, store.products, store.settings, store.newId);
    expect(plan.added, 1000); expect(plan.updated, 1);
    expect(plan.sheets, 3); expect(plan.skipped, 2); expect(plan.total, 1003);
    expect(plan.warnings.join('\n'), contains('رقم غير صالح'));
    final progress = <int>[];
    final result = await store.importProducts(plan.products, settingsRevision: store.settings.revision,
      onProgress: (done, total) { expect(total, 1001); progress.add(done); });
    expect(result.added, 1000); expect(result.updated, 1); expect(result.failed, 0); expect(result.unprocessed, 0);
    expect(progress, containsAllInOrder([0, 50, 100, 1000, 1001]));
    final reopened = AppStore(prefs: prefs); await reopened.initialize();
    expect(reopened.products.length, 1003); expect(reopened.findId(old.id)!.name, 'اسم معدل');
    expect(reopened.findBarcode('001999')!.name, 'صنف 999');
    expect(reopened.findBarcode('0010')!.quantity, 0);
    expect(store.products.length, reopened.products.length);
    store.dispose(); reopened.dispose();
  });
  test('storage failure rolls back the uncommitted checkpoint and reports every row', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs: FailingPreferences(prefs)); await store.initialize();
    final rows = List.generate(120, (n) => Product(id: 'new$n', name: 'صنف $n', revision: 1));
    final result = await store.importProducts(rows, settingsRevision: store.settings.revision);
    expect(result.saved, 50); expect(result.failed, 50); expect(result.unprocessed, 20);
    expect(result.stoppedReason, isNotNull); expect(store.products.length, 53);
    expect(store.findId('new49'), isNotNull); expect(store.findId('new50'), isNull);
    final reopened = AppStore(prefs: prefs); await reopened.initialize();
    expect(reopened.products.length, 53); expect(reopened.findId('new50'), isNull);
    store.dispose(); reopened.dispose();
  });
  test('a changed exchange-rate revision stops with an accurate remaining count', () async {
    final store = AppStore(prefs: await SharedPreferences.getInstance()); await store.initialize();
    final rows = List.generate(120, (n) => Product(id: 'new$n', name: 'صنف $n', revision: 1));
    final revision = store.settings.revision;
    final result = await store.importProducts(rows, settingsRevision: revision, onProgress: (done, _) {
      if (done == 50) { store.settings = StoreSettings(revision: revision + 1); }
    });
    expect(result.saved, 50); expect(result.failed, 0); expect(result.unprocessed, 70);
    expect(result.stoppedReason, contains('إعدادات الأسعار')); expect(store.findId('new50'), isNull);
    store.dispose();
  });
}
