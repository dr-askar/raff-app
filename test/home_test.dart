import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/main.dart';
import 'package:raff/domain/worker_access.dart';
import 'package:raff/ui/product_editor.dart';

void main() {
  testWidgets('worker editor hides cost fields and disables disallowed fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await s.setOwnerPassword('owner123');
    await s.setWorkerAccess('local', const WorkerAccess().withValue('editQuantity', true)); s.lockWorker();
    await tester.pumpWidget(MaterialApp(home: ProductEditor(store: s, product: s.products.first)));
    await tester.pumpAndSettle();
    expect(find.text('عملة رأس المال'), findsNothing);
    expect(find.text('استخدام نسبة الربح العامة'), findsNothing);
    expect(find.text('سعر بيع ثابت يدوياً'), findsNothing);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields.first.enabled, false); expect(fields.last.enabled, true);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
  testWidgets('calculator stays usable on a phone while searching with the keyboard open', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize(); s.lockWorker();
    await tester.pumpWidget(RaffApp(store: s)); await tester.pumpAndSettle();
    await tester.tap(find.text('حساب زبون')); await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.enterText(find.byType(TextField).first, 'حليب'); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('حليب كامل الدسم')); await tester.pumpAndSettle();
    expect(find.text('السلة فارغة'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
  testWidgets('Arabic home opens and a worker can search and access the calculator', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize(); s.lockWorker();
    await tester.pumpWidget(RaffApp(store: s)); await tester.pumpAndSettle();
    expect(find.text('رفّ'), findsOneWidget);
    expect(find.text('حليب كامل الدسم'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'حليب'); await tester.pumpAndSettle();
    expect(find.text('أرز — 1 كغ'), findsNothing);
    await tester.tap(find.text('حساب زبون')); await tester.pumpAndSettle();
    expect(find.text('السلة فارغة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
}
