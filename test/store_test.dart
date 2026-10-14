import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/domain/models.dart';

Future<AppStore> localStore() async {
  final s = AppStore(prefs: await SharedPreferences.getInstance());
  await s.initialize(); return s;
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('local edits survive a new store instance', () async {
    final s = await localStore(); final old = s.products.first;
    await s.saveProduct(old.edit(quantity: 17, manualPrice: 12345, settings: s.settings));
    final reopened = await localStore();
    expect(reopened.findId(old.id)!.quantity, 17);
    expect(reopened.findId(old.id)!.manualPrice, 12345);
    s.dispose(); reopened.dispose();
  });
  test('worker cannot modify pricing or restore backups', () async {
    final s = await localStore(); s.demoRole(false);
    await expectLater(s.changeSettings(2, 20, 'ل.س'), throwsFormatException);
    await expectLater(s.saveProduct(s.products.first), throwsFormatException);
    await expectLater(s.restore({'schema': 1}), throwsFormatException);
    s.dispose();
  });
  test('counting does not change inventory until owner approval', () async {
    final s = await localStore(); final p = s.products.first;
    await s.startStocktake(); s.demoRole(false);
    await s.countProduct(p.id, 7); expect(s.findId(p.id)!.quantity, p.quantity);
    s.demoRole(true); await s.approveStocktake();
    expect(s.findId(p.id)!.quantity, 7); expect(s.stocktake!.closed, true);
    await expectLater(s.countProduct(p.id, 8), throwsFormatException);
    s.dispose();
  });
  test('backup roundtrip retains settings and stocktake', () async {
    final s = await localStore(); await s.startStocktake();
    final backup = s.backup(); await s.changeSettings(12000, 25, 'ل.ل');
    await s.restore(backup); expect(s.settings.rate, 10000); expect(s.stocktake, isNotNull);
    s.dispose();
  });
  test('duplicate barcodes are rejected', () async {
    final s = await localStore();
    final p = Product(id: s.newId(), name: 'مكرر', barcode: s.products.first.barcode);
    await expectLater(s.saveProduct(p), throwsFormatException); s.dispose();
  });
}
