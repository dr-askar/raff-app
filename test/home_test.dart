import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raff/data/app_store.dart';
import 'package:raff/main.dart';
import 'package:raff/domain/worker_access.dart';
import 'package:raff/ui/product_editor.dart';
import 'package:raff/ui/access_settings.dart';

void main() {
  testWidgets('delete button is visible without scrolling on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await tester.pumpWidget(MaterialApp(home: ProductEditor(store: s, product: s.products.first)));
    await tester.pumpAndSettle(); expect(find.text('حذف مادة').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
  testWidgets('cost visibility does not render profit controls and vice versa', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await tester.runAsync(() async { await s.setOwnerPassword('owner123'); await s.setWorkerAccess('local', const WorkerAccess().withValue('viewMargin', true)); });
    s.lockWorker();
    await tester.pumpWidget(MaterialApp(home: ProductEditor(store: s, product: s.products.first)));
    await tester.pumpAndSettle(); expect(find.text('عملة رأس المال'), findsNothing);
    await tester.scrollUntilVisible(find.text('استخدام نسبة الربح العامة'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('استخدام نسبة الربح العامة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async { await s.unlockOwner('owner123'); await s.setWorkerAccess('local', const WorkerAccess().withValue('viewCost', true)); }); s.lockWorker();
    await tester.pumpWidget(MaterialApp(home: ProductEditor(store: s, product: s.products.first)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('عملة رأس المال'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('عملة رأس المال'), findsOneWidget); expect(find.text('استخدام نسبة الربح العامة'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });
  testWidgets('changing password displays old new and confirmation fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => changePasswordDialog(context, s), child: const Text('open')))));
    await tester.tap(find.text('open')); await tester.pumpAndSettle();
    expect(find.text('كلمة السر الحالية'), findsOneWidget); expect(find.text('كلمة السر الجديدة'), findsOneWidget);
    expect(find.text('تأكيد كلمة السر الجديدة'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'newpass123');
    await tester.enterText(find.byType(TextField).at(2), 'different');
    await tester.tap(find.text('تغيير كلمة السر')); await tester.pumpAndSettle();
    expect(find.text('تأكيد مطابق وكلمة سر من 6 أحرف أو أرقام على الأقل'), findsOneWidget);
    await tester.tap(find.text('رجوع')); await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink()); s.dispose();
  });

  testWidgets('worker editor hides cost fields and disables disallowed fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(prefs: await SharedPreferences.getInstance()); await s.initialize();
    await tester.runAsync(() async {
      await s.setOwnerPassword('owner123');
      await s.setWorkerAccess('local', const WorkerAccess().withValue('editQuantity', true));
    });
    s.lockWorker();
    await tester.pumpWidget(MaterialApp(home: ProductEditor(store: s, product: s.products.first)));
    await tester.pumpAndSettle();
    expect(find.text('عملة رأس المال'), findsNothing);
    expect(find.text('استخدام نسبة الربح العامة'), findsNothing);
    expect(find.text('سعر بيع ثابت يدوياً'), findsNothing);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'اسم المادة')).enabled, false);
    final quantity = find.widgetWithText(TextFormField, 'عدد القطع المتوفرة');
    await tester.scrollUntilVisible(quantity, 250, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextFormField>(quantity).enabled, true);
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

