import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/domain/models.dart';
import 'package:raff/domain/worker_access.dart';

Future<AppStore> setup() async {
  final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize(); return s;
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('lock survives restart and backup restore cannot reset password or permissions', () async {
    final s = await setup(); final backup = s.backup();
    await s.setOwnerPassword('owner123');
    await s.setWorkerAccess('local', const WorkerAccess().withValue('editExchangeRate', true));
    s.lockWorker();
    await expectLater(s.unlockOwner('incorrect'), throwsFormatException);
    await expectLater(s.setWorkerAccess('local', const WorkerAccess()), throwsFormatException);
    final restarted = await setup();
    expect(restarted.owner, false); expect(restarted.can('editExchangeRate'), true);
    await restarted.unlockOwner('owner123');
    await restarted.restore(backup); restarted.lockWorker();
    expect(restarted.can('editExchangeRate'), true);
    await expectLater(restarted.unlockOwner('incorrect'), throwsFormatException);
    await restarted.unlockOwner('owner123'); expect(restarted.owner, true);
    s.dispose(); restarted.dispose();
  });
  test('granting exchange access does not grant global profit or product edits', () async {
    final s = await setup(); await s.setOwnerPassword('owner123');
    await s.setWorkerAccess('local', const WorkerAccess().withValue('editExchangeRate', true));
    s.lockWorker(); await s.changeSettings(12000, s.settings.margin, s.settings.currency);
    await expectLater(s.changeSettings(12000, 99, s.settings.currency), throwsFormatException);
    await expectLater(s.saveProduct(s.products.first.edit(quantity: 1, settings: s.settings)), throwsFormatException);
    s.dispose();
  });
  test('worker can change quantity while being unable to edit cost or name', () async {
    final s = await setup(); await s.setOwnerPassword('owner123');
    await s.setWorkerAccess('local', const WorkerAccess().withValue('editQuantity', true));
    s.lockWorker(); final old = s.products.first;
    await s.saveProduct(old.edit(quantity: 8, settings: s.settings));
    expect(s.findId(old.id)!.quantity, 8);
    final current = s.findId(old.id)!;
    await expectLater(s.saveProduct(current.edit(name: 'ممنوع', settings: s.settings)), throwsFormatException);
    await expectLater(s.saveProduct(current.edit(costUsd: 9, settings: s.settings)), throwsFormatException);
    s.dispose();
  });
  test('add and delete are separate; a deleted barcode can be used again', () async {
    final s = await setup(); await s.setOwnerPassword('owner123');
    final permissions = const WorkerAccess().withValue('addProduct', true);
    await s.setWorkerAccess('local', permissions); s.lockWorker();
    final p = Product(id: 'new', name: 'جديد', barcode: '00123', revision: 1);
    await s.saveProduct(p); await expectLater(s.deleteProduct(p), throwsFormatException);
    await s.unlockOwner('owner123'); await s.setWorkerAccess('local', permissions.withValue('deleteProduct', true)); s.lockWorker();
    await s.deleteProduct(p); expect(s.findBarcode('00123'), isNull);
    await s.saveProduct(const Product(id: 'replacement', name: 'بديل', barcode: '00123', revision: 1));
    expect(s.findBarcode('00123')!.id, 'replacement'); s.dispose();
  });
  test('stocktake visibility and count permission are enforced in the store', () async {
    final s = await setup(); await s.setOwnerPassword('owner123'); await s.startStocktake();
    await s.setWorkerAccess('local', const WorkerAccess().withValue('viewStocktake', false)); s.lockWorker();
    await expectLater(s.countProduct(s.products.first.id, 7), throwsFormatException); s.dispose();
  });
}
