import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import '../data/app_store.dart';
import '../data/files.dart';
import '../data/device_files.dart';
import '../domain/models.dart';
import 'common.dart';
import 'scanner.dart';
import 'product_editor.dart';
import 'access_settings.dart';

class Home extends StatefulWidget {
  final AppStore store;
  const Home({super.key, required this.store});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  AppStore get s => widget.store;
  final search = TextEditingController();
  final cart = <CartLine>[];
  final selected = <String>{};
  int tab = 0;
  String category = 'الكل'; bool busy = false;
  int importDone = 0, importTotal = 0;
  bool importing = false;
  double minimumFor(Product p) => s.can('applyBargain') ? p.minimumPrice(s.settings) : p.price(s.settings);
  @override
  void dispose() { search.dispose(); super.dispose(); }
  Future<void> action(Future<void> Function() task, [String message = 'تم الحفظ بنجاح']) async {
    if (busy) { return; } setState(() => busy = true);
    await perform(context, task, message);
    if (mounted) { setState(() => busy = false); }
  }
  List<Product> get filtered => s.products.where((p) =>
    (category == 'الكل' || p.category == category) &&
    (p.name.toLowerCase().contains(search.text.trim().toLowerCase()) || p.barcode.contains(search.text.trim()))).toList();
  Future<void> addToCart(Product p) async {
    if (!s.can('useCalculator')) { return; }
    if (!p.ready) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المادة تحتاج تسعيراً أولاً'))); return; }
    if (cart.any((line) => line.id == p.id && line.unit != p.unit)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغيرت وحدة المادة. احذفها من السلة ثم أضفها مجدداً.')));
      return;
    }
    final quantity = p.byWeight ? await numberDialog('وزن ${p.name}', 'الوزن بالكيلوغرام', initial: 1, quantity: true, positive: true) : 1.0;
    if (quantity == null || !mounted || !s.can('useCalculator')) { return; }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final i = cart.indexWhere((line) => line.id == p.id);
      if (i == -1) { cart.add(CartLine(id: p.id, name: p.name, unitPrice: p.price(s.settings), quantity: quantity, unit: p.unit)); }
      else if (cart[i].unit == p.unit) { cart[i].quantity += quantity; }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أضيفت ${p.name}'), duration: const Duration(milliseconds: 900)));
  }
  Future<void> scan({bool basket = false, bool counting = false}) async {
    final code = await scanBarcode(context);
    if (!mounted || code == null) { return; }
    final p = s.findBarcode(code);
    if (p == null) {
      if (s.can('addProduct') && await confirm(context, 'باركود جديد', 'هذا الباركود غير موجود. هل تريد إضافة مادته؟')) {
        if (mounted) { await editProduct(context, s, barcode: code); }
      } else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الباركود غير موجود في المواد'))); }
      return;
    }
    if (basket) { await addToCart(p); }
    else if (counting) { await count(p); }
    else { setState(() { tab = 0; category = 'الكل'; search.text = p.barcode; }); }
  }
  Future<void> count(Product p) async {
    if (!s.can('viewStocktake') || !s.can('countStock')) { return; }
    final value = await numberDialog('جرد: ${p.name}', 'الكمية الفعلية بـ${p.unitLabel}', initial: s.stocktake?.counts[p.id], quantity: true);
    if (value != null && mounted) { await action(() => s.countProduct(p.id, value), 'تم تسجيل العدد الفعلي'); }
  }
  Future<double?> numberDialog(String title, String label, {double? initial, bool quantity = false, bool positive = false, bool whole = false}) async {
    final c = TextEditingController(text: initial?.toString() ?? '');
    String? error;
    final result = await showDialog<double>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, change) =>
      AlertDialog(title: Text(title), content: TextField(controller: c, autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, errorText: error)), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
          FilledButton(onPressed: () {
            final n = quantity ? parseQuantity(c.text) : parseAmount(c.text);
            if (n == null || !n.isFinite || n < 0 || (positive && n == 0) || (whole && n != n.roundToDouble())) { change(() => error = whole ? 'أدخل عدداً صحيحاً موجباً' : positive ? 'أدخل كمية موجبة' : 'أدخل رقماً غير سالب'); }
            else { Navigator.pop(ctx, n); }
          }, child: const Text('حفظ')),
        ])));
    // Dispose after the dialog's closing animation completes.
    Future<void>.delayed(const Duration(milliseconds: 300), c.dispose);
    return result;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: s, builder: (context, _) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(title: Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.inventory_2_outlined, color: Colors.white)), const SizedBox(width: 10),
      const Text('رفّ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
      const SizedBox(width: 12), Text(s.owner ? 'صاحب المحل' : 'العامل', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
    ]), actions: [if (s.cloud) IconButton(tooltip: 'تسجيل الخروج', icon: const Icon(Icons.logout), onPressed: busy ? null : () async {
      if (await confirm(context, 'تسجيل الخروج', 'سيتم إغلاق حسابك وسلة الحساب الحالية.')) { await FirebaseAuth.instance.signOut(); }
    })]),
    body: SafeArea(child: Column(children: [
      Container(width: double.infinity, color: s.fromCache || !s.cloud ? const Color(0xfffff2d9) : const Color(0xffe3f2eb),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Text(s.syncLabel, style: const TextStyle(fontSize: 12))),
      if (busy) LinearProgressIndicator(value: importing && importTotal > 0 ? importDone / importTotal : null),
      if (importing) Padding(padding: const EdgeInsets.all(8), child: Text('جاري الاستيراد: $importDone من $importTotal صنف — اترك التطبيق مفتوحاً')),
      if (s.error.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(s.error, style: const TextStyle(color: Colors.red))),
      Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child:
        s.cloud && !s.loaded ? const Center(child: CircularProgressIndicator()) : switch (tab) {
          0 => materials(), 1 => basket(), 2 => inventory(), _ => settings(),
        }))),
    ])),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() { tab = i; search.clear(); }), destinations: const [
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'المواد'),
      NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), selectedIcon: Icon(Icons.shopping_basket), label: 'حساب زبون'),
      NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'الجرد'),
      NavigationDestination(icon: Icon(Icons.tune), label: 'الإعدادات'),
    ]),
  ));

  Widget exchangeCard() => Container(key: const ValueKey('exchange-summary'), margin: const EdgeInsets.fromLTRB(16, 8, 16, 4), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xff234f7b), Color(0xff3479b2)]), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('سعر صرف الدولار • ${s.products.length} مادة${s.can('viewMargin') ? ' • ربح عام ${money(s.settings.margin)}%' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      Text('${money(s.settings.rate)} ${s.settings.currency}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    ])), if (s.can('editExchangeRate')) IconButton.filledTonal(tooltip: 'تعديل الصرف', onPressed: busy ? null : () async {
      final n = await numberDialog('سعر صرف الدولار', 'السعر الجديد', initial: s.settings.rate);
      if (n != null && mounted && await confirm(context, 'تحديث الأسعار التلقائية', 'تتغير الأسعار التلقائية وفق الصرف ${money(n)}. الأسعار الثابتة تبقى كما هي.')) {
        await action(() => s.changeSettings(n, s.settings.margin, s.settings.currency), 'تم تحديث الصرف والأسعار التلقائية');
      }
    }, icon: const Icon(Icons.edit_outlined))]));

  Widget searchBar({bool basket = false, bool counting = false}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [Expanded(child: TextField(controller: search, onChanged: (_) => setState(() {}),
      decoration: InputDecoration(hintText: 'اسم المادة أو الباركود…', prefixIcon: const Icon(Icons.search),
        suffixIcon: search.text.isEmpty ? null : IconButton(tooltip: 'مسح البحث', onPressed: () => setState(search.clear), icon: const Icon(Icons.close))))),
      const SizedBox(width: 8), IconButton.filled(tooltip: 'مسح باركود', onPressed: busy ? null : () => scan(basket: basket, counting: counting), icon: const Icon(Icons.qr_code_scanner)),
    ]));

  Widget materials() {
    final categories = ['الكل', ...(s.products.map((p) => p.category).toSet().toList()..sort())];
    final rows = filtered;
    return Column(children: [exchangeCard(), searchBar(),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: categories.map((c) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c)))).toList()))),
        if (s.can('addProduct')) FilledButton.tonalIcon(onPressed: busy ? null : () => editProduct(context, s), icon: const Icon(Icons.add), label: const Text('مادة')),
      ])),
      if (s.owner && selected.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        Text('${selected.length} محددة'), const Spacer(), TextButton(onPressed: () => setState(selected.clear), child: const Text('إلغاء')),
        FilledButton.tonal(onPressed: busy ? null : bulk, child: const Text('تعديل الربح')),
      ])),
      Expanded(child: rows.isEmpty ? const EmptyState('لا توجد مواد', 'غيّر البحث أو أضف مادة جديدة.') : ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.viewInsetsOf(context).bottom), itemCount: rows.length, itemBuilder: (context, i) {
          final p = rows[i]; return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: s.owner ? Checkbox(value: selected.contains(p.id), onChanged: (_) => setState(() {
              if (!selected.add(p.id)) { selected.remove(p.id); }
            })) : const Icon(Icons.inventory_2_outlined),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text('${p.category} • ${quantityText(p.quantity)} ${p.unitLabel} • الطرد ${quantityText(p.pack)} ${p.unitLabel}\n${p.manualPrice == null ? 'سعر تلقائي' : 'سعر ثابت'}${s.can('viewCost') && p.hasCost ? ' • تكلفة ${p.unitLabel} ${money(p.costCurrency == 'SYP' ? p.costLocal! : p.costUsd!)} ${p.costCurrency == 'SYP' ? 'ل.س' : '\$'}' : ''}${p.ready ? '\nأقل سعر مسموح: ${money(minimumFor(p))} ${s.settings.currency}' : ''}')),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(p.ready ? '${money(p.price(s.settings))}\n${s.settings.currency}' : 'يحتاج\nتسعيراً', textAlign: TextAlign.center,
                style: TextStyle(color: p.ready ? Theme.of(context).colorScheme.primary : Colors.orange.shade800, fontWeight: FontWeight.bold)),
              if (s.can('deleteProduct')) IconButton(tooltip: 'حذف مادة', onPressed: busy ? null : () => deleteMaterial(p), icon: Icon(Icons.delete_outline, color: Colors.red.shade700)),
            ]),
            onTap: busy ? null : () { if (s.canEditProduct || s.can('deleteProduct')) { editProduct(context, s, product: p); } else { productDetails(p); } },
          ));
        })),
      if (s.owner && rows.isNotEmpty) TextButton(onPressed: () => setState(() => selected.addAll(rows.map((p) => p.id))), child: const Text('تحديد جميع نتائج البحث')),
    ]);
  }
  Future<void> deleteMaterial(Product p) async {
    if (!await confirm(context, 'حذف مادة', 'هل تريد حذف «${p.name}»؟ يبقى سجل تغييراته محفوظاً.')) { return; }
    await action(() async {
      await s.deleteProduct(p);
      selected.remove(p.id);
      if (!s.products.any((item) => item.category == category)) { category = 'الكل'; }
    }, 'تم حذف المادة');
  }
  Future<void> bargain(CartLine line) async {
    if (!s.can('applyBargain') || s.findId(line.id) == null) { return; }
    final controller = TextEditingController(text: line.sellingPrice.toString());
    String? error;
    final saved = await showDialog<bool>(context: context, builder: (ctx) =>
      ListenableBuilder(listenable: s, builder: (ctx, _) => StatefulBuilder(builder: (ctx, change) {
        final product = s.findId(line.id);
        final limit = s.can('applyBargain') ? product?.bargainPercent ?? 0 : 0.0;
        return AlertDialog(title: Text(line.byWeight ? 'تحديد سعر الكيلوغرام' : 'تحديد سعر القطعة'), scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.name), const SizedBox(height: 8),
            Text('سعر المبيع: ${money(line.unitPrice)} ${s.settings.currency}'),
            Text('أقل سعر مسموح: ${money(line.minimumPrice(limit))} ${s.settings.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16), TextField(key: const ValueKey('bargain-price'), controller: controller, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: line.byWeight ? 'السعر المتفق عليه للكيلوغرام' : 'السعر المتفق عليه للقطعة', errorText: error)),
          ]), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(onPressed: () {
              final price = parseAmount(controller.text);
              if (price == null || !price.isFinite) { change(() => error = 'أدخل سعراً صحيحاً'); return; }
              try { s.applyBargainPrice(line, price); Navigator.pop(ctx, true); }
              on FormatException catch (e) { change(() => error = e.message); }
            }, child: const Text('اعتماد السعر')),
          ]);
      })));
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (saved == true && mounted) { setState(() {}); }
  }

  Future<void> productDetails(Product product) => showDialog(context: context, builder: (ctx) =>
    ListenableBuilder(listenable: s, builder: (ctx, _) {
      final p = s.findId(product.id);
      return AlertDialog(title: Text(p?.name ?? 'الصنف محذوف'),
        content: p == null ? null : Text('الباركود: ${p.barcode.isEmpty ? 'غير محدد' : p.barcode}\nالتعبئة: ${quantityText(p.pack)} ${p.unitLabel}\nالمتوفر: ${quantityText(p.quantity)} ${p.unitLabel}\nالسعر: ${p.ready ? money(p.price(s.settings)) : 'يحتاج تسعيراً'} ${s.settings.currency}${s.can('viewCost') && p.hasCost ? '\nتكلفة ${p.unitLabel}: ${money(p.localCost(s.settings.rate)!)} ل.س' : ''}${s.can('viewMargin') ? '\nنسبة الربح: ${money(p.effectiveMargin(s.settings))}%' : ''}${p.ready ? '\nأقل سعر مسموح: ${money(minimumFor(p))} ${s.settings.currency}' : ''}'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))]);
    }));

  Future<void> bulk() async {
    final rows = s.products.where((p) => selected.contains(p.id)).toList();
    final increase = await numberDialog('تعديل الربح الجماعي', 'إضافة نقاط مئوية للربح، مثلاً 5');
    if (increase == null || !mounted) { return; }
    final preview = rows.take(5).map((p) => '${p.name}: ${money(p.price(s.settings))} ← ${money(p.edit(margin: p.effectiveMargin(s.settings) + increase, settings: s.settings).price(s.settings))}').join('\n');
    if (await confirm(context, 'تعديل ${rows.length} مادة', 'إضافة $increase نقاط مئوية للربح. مثلاً 20% تصبح ${20 + increase}%.\nالأسعار الثابتة تبقى ثابتة.\n\n$preview\n\nتُحفظ كل مادة على حدة، وقد تتوقف الدفعة عند تعارض تعديل.')) {
      await action(() => s.bulkMargin(rows, increase), 'تم تعديل نسب الربح');
      if (mounted) { setState(selected.clear); }
    }
  }

  Widget basket() {
    final total = s.basketTotal(cart);
    final matches = filtered;
    return !s.can('useCalculator') ? const EmptyState('حساب الزبون مقفل', 'اطلب من صاحب المحل تفعيل الصلاحية.') : Column(children: [
    const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 4), child: Align(alignment: AlignmentDirectional.centerStart,
      child: Text('حساب الزبون', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)))),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('امسح المادة، أو ابحث واضغط لإضافتها. السلة لا تخصم المخزون.')),
    searchBar(basket: true),
    if (search.text.trim().isNotEmpty) SizedBox(height: 160, child: ListView.builder(itemCount: matches.length, itemBuilder: (context, index) {
      final p = matches[index];
      return ListTile(title: Text(p.name), trailing: const Icon(Icons.add_circle_outline),
        subtitle: Text(p.ready ? 'سعر المبيع: ${money(p.price(s.settings))} ${s.settings.currency}\nأقل سعر مسموح: ${money(minimumFor(p))} ${s.settings.currency}' : 'يحتاج تسعيراً'), onTap: () => addToCart(p));
    })),
    Expanded(child: cart.isEmpty ? const EmptyState('السلة فارغة', 'ابدأ بمسح باركود أول مادة.', icon: Icons.shopping_basket_outlined) : ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: cart.length, itemBuilder: (context, i) {
        final line = cart[i]; return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          Row(children: [Expanded(child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.bold))), Text('${money(line.total)} ${s.settings.currency}')]),
          Align(alignment: AlignmentDirectional.centerStart, child: Text('سعر المبيع: ${money(line.unitPrice)} ${s.settings.currency}')),
          Align(alignment: AlignmentDirectional.centerStart, child: Text('أقل سعر مسموح: ${money(line.minimumPrice(s.can('applyBargain') ? s.findId(line.id)?.bargainPercent ?? 0 : 0))} ${s.settings.currency}')),
          if (s.can('applyBargain') && (s.findId(line.id)?.bargainPercent ?? 0) > 0) Align(alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: busy ? null : () => bargain(line), icon: const Icon(Icons.price_change_outlined), label: const Text('اختيار سعر للزبون'))),
          Row(children: [Expanded(child: Text('${money(line.sellingPrice)} ${line.byWeight ? 'للكيلوغرام' : 'للقطعة'}${line.discountPercent > 0 ? ' • مراعاة ${money(line.unitPrice - line.sellingPrice)} ${s.settings.currency}' : ''}')), IconButton(tooltip: 'إنقاص', onPressed: () => setState(() {
            final step = line.byWeight ? 0.1 : 1.0;
            if (line.quantity > step) { line.setQuantity(double.parse((line.quantity - step).toStringAsFixed(6))); } else { cart.removeAt(i); }
          }), icon: const Icon(Icons.remove_circle_outline)),
            TextButton(onPressed: busy ? null : () => editCartQuantity(line),
              child: Text('${quantityText(line.quantity)} ${line.unitLabel}', style: const TextStyle(fontSize: 18))),
            IconButton(tooltip: 'زيادة', onPressed: () => setState(() => line.setQuantity(double.parse((line.quantity + (line.byWeight ? 0.1 : 1)).toStringAsFixed(6)))), icon: const Icon(Icons.add_circle_outline)),
            IconButton(tooltip: 'حذف', onPressed: () => setState(() => cart.removeAt(i)), icon: const Icon(Icons.delete_outline)),
          ]),
        ])));
      })),
    Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xffe3eef9), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Expanded(child: Text('المجموع', style: TextStyle(fontSize: 20))), Text('${money(total)} ${s.settings.currency}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 6), const Text('تُثبت أسعار السلة عند الإضافة. تحديثها متاح قبل الحساب.', style: TextStyle(fontSize: 11)),
        Row(children: [Expanded(child: FilledButton.icon(onPressed: () => scan(basket: true), icon: const Icon(Icons.qr_code_scanner), label: const Text('مسح مادة'))),
          const SizedBox(width: 8), TextButton(onPressed: cart.isEmpty ? null : () async {
            if (await confirm(context, 'زبون جديد', 'مسح السلة الحالية وبدء حساب جديد؟') && mounted) { setState(cart.clear); }
          }, child: const Text('زبون جديد'))]),
        if (cart.isNotEmpty) TextButton(onPressed: () async {
          if (cart.any((line) { final product = s.findId(line.id); return product != null && product.unit != line.unit; })) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغيرت وحدة مادة. احذفها من السلة ثم أضفها مجدداً قبل تحديث الأسعار.')));
            return;
          }
          if (await confirm(context, 'تحديث أسعار السلة', 'سيتم استبدال أسعار السلة بأسعار المواد الحالية.') && mounted) {
            setState(() {
              for (var i = 0; i < cart.length; i++) {
                final p = s.findId(cart[i].id);
                if (p != null && p.ready) { cart[i] = CartLine(id: p.id, name: p.name, unitPrice: p.price(s.settings), quantity: cart[i].quantity, unit: p.unit); }
              }
            });
          }
        }, child: const Text('تحديث أسعار السلة')),
      ])),
  ]);

  }

  Widget inventory() {
    if (!s.can('viewStocktake')) { return const EmptyState('الجرد مقفل', 'اطلب من صاحب المحل تفعيل الصلاحية.'); }
    final stock = s.stocktake;
    final rows = filtered.where((p) => stock?.productIds.contains(p.id) ?? false).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(20), child: Row(children: [const Expanded(child: Text('جرد المحل', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
        if (s.owner && (stock == null || stock.closed)) FilledButton.tonal(onPressed: busy ? null : () => action(s.startStocktake, 'بدأت جلسة جرد جديدة'), child: const Text('بدء جرد'))])),
      if (stock == null) const Expanded(child: EmptyState('لا يوجد جرد مفتوح', 'صاحب المحل يبدأ الجرد، والعامل يدخل الأعداد الفعلية.'))
      else ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('${stock.closed ? 'جرد معتمد' : 'جرد مفتوح'} • تم عدّ ${stock.counts.length} مادة\nبدأ ${stock.at.split('T').first} • الصرف المثبت ${money(stock.rate)} ${stock.currency}')),
        searchBar(counting: true),
        Expanded(child: ListView.builder(padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom), itemCount: rows.length, itemBuilder: (context, i) {
          final p = rows[i]; final actual = stock.counts[p.id];
          return Card(child: ListTile(title: Text(p.name), subtitle: Text('المسجل: ${quantityText(p.quantity)} ${p.unitLabel}${actual == null ? '' : ' • الفرق: ${quantityText(actual - p.quantity)}'}'),
            trailing: Text(actual == null ? 'لم يُعدّ' : '${quantityText(actual)} ${p.unitLabel}', style: TextStyle(color: actual == null ? Colors.blueGrey : const Color(0xff237b66), fontWeight: FontWeight.bold)),
            onTap: busy || stock.closed || !s.can('countStock') ? null : () => count(p)));
        })),
        if (s.can('viewCost')) Container(padding: const EdgeInsets.all(16), color: const Color(0xffe3eef9), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('قيمة المعدود: ${money(stock.value)} ${stock.currency}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Text('المواد غير المعدودة أو دون تكلفة لا تدخل في المجموع. الاعتماد يحدّث المواد المعدودة فقط.', style: TextStyle(fontSize: 12)),
          Wrap(spacing: 8, children: [
            if (s.owner) OutlinedButton.icon(onPressed: busy ? null : () => action(() => StoreFiles.shareBytes(StoreFiles.stockExcel(stock), 'raff-stocktake.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), 'تقرير الجرد جاهز للمشاركة'), icon: const Icon(Icons.file_download_outlined), label: const Text('تقرير Excel')),
            if (s.owner && !stock.closed) FilledButton(onPressed: busy ? null : () async {
              if (await confirm(context, 'اعتماد الجرد', 'تحديث المخزون لأعداد ${stock.counts.length} مادة معدودة، وإغلاق الجلسة؟')) { await action(s.approveStocktake, 'تم اعتماد الجرد وتحديث الكميات'); }
            }, child: const Text('اعتماد الجرد')),
          ]),
        ])),
      ],
    ]);
  }

  Widget settings() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('إعدادات المحل', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10), Text('${s.actor} • ${s.owner ? 'صاحب المحل' : 'عامل'}'),
    if (!s.cloud) Card(color: const Color(0xfffff2d9), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      const Text('البيانات على هذا الجهاز. الرجوع إلى وضع المدير يحتاج كلمة سره، ويبدأ التطبيق بوضع العامل بعد إغلاقه إذا كانت كلمة السر محددة.'),
      ListTile(leading: Icon(s.owner ? Icons.lock_outline : Icons.lock_open), title: Text(s.owner ? 'قفل التطبيق بوضع العامل' : 'الدخول كصاحب المحل'),
        onTap: busy ? null : () async {
          if (s.owner) {
            if (!s.hasOwnerPassword) {
              final password = await passwordDialog(context, create: true);
              if (password == null || !mounted) { return; }
              await action(() => s.setOwnerPassword(password), 'تم تعيين كلمة السر');
              if (!s.hasOwnerPassword) { return; }
            }
            cart.clear(); selected.clear(); s.lockWorker();
          } else {
            final password = await passwordDialog(context);
            if (password != null && mounted) { await action(() => s.unlockOwner(password), 'تم فتح وضع المدير'); }
          }
        }),
    ]))),
    if (s.owner) ...[
      Card(child: ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text('صلاحيات العامل وكلمة السر'), subtitle: const Text('ما يستطيع رؤيته وإضافته وحذفه وتعديله'), onTap: busy ? null : () => openWorkerAccess(context, s))),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.percent), title: const Text('نسبة الربح العامة'), subtitle: Text('${money(s.settings.margin)}% زيادة على التكلفة'), trailing: const Icon(Icons.chevron_left), onTap: busy ? null : () async {
          final n = await numberDialog('الربح العام', 'النسبة %', initial: s.settings.margin);
          if (n != null && mounted && await confirm(context, 'تغيير الربح العام', 'تتحدث المواد التلقائية التي تتبع النسبة العامة.')) { await action(() => s.changeSettings(s.settings.rate, n, s.settings.currency)); }
        }),
        ListTile(leading: const Icon(Icons.currency_exchange), title: const Text('العملة المحلية'), subtitle: Text(s.settings.currency), onTap: busy ? null : currencyDialog),
      ])),
      const SizedBox(height: 12), const Text('الملفات والنسخ الاحتياطي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.download_outlined), title: const Text('تصدير المواد إلى Excel'), subtitle: const Text('سعر الطرد وعدده ومحتواه • الوزن بالكيلوغرام'), onTap: busy ? null : () => action(() => StoreFiles.shareBytes(StoreFiles.productExcel(s.products, s.settings), 'raff-products.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), 'ملف المواد جاهز للمشاركة')),
        ListTile(leading: const Icon(Icons.upload_file_outlined), title: const Text('استيراد Excel'), subtitle: const Text('أسعار الطرود • يدعم الملفات القديمة والكيلو • معاينة قبل الحفظ'), onTap: busy ? null : importExcel),
        ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('تنزيل نسخة احتياطية'), subtitle: const Text('مواد وإعدادات وآخر سجل أسعار والجرد الحالي'), onTap: busy ? null : () => action(() => StoreFiles.shareJson(s.backup()), 'النسخة جاهزة. احفظها في مكان آمن')),
      ])),
    ],
    if (s.can('restoreBackup')) Card(child: ListTile(leading: const Icon(Icons.restore),
      title: const Text('استعادة نسخة احتياطية'), subtitle: const Text('استرجاع المواد والأسعار والإعدادات • القفل والصلاحيات لا تتغير'),
      onTap: busy ? null : () => restore())),
    if (s.owner || s.can('restoreBackup')) ...[
      const SizedBox(height: 12), const Text('Google Drive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        if (s.owner) ...[
          ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('حفظ الأصناف Excel على Drive'),
            onTap: busy ? null : () => saveDrive(backup: false)),
          ListTile(leading: const Icon(Icons.cloud_download_outlined), title: const Text('استيراد Excel من Drive'),
            onTap: busy ? null : () => importExcel(fromDrive: true)),
          ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('حفظ نسخة JSON على Drive'),
            onTap: busy ? null : () => saveDrive(backup: true)),
        ],
        if (s.can('restoreBackup')) ListTile(leading: const Icon(Icons.restore_page_outlined), title: const Text('استعادة نسخة JSON من Drive'),
          onTap: busy ? null : () => restore(fromDrive: true)),
      ])),
    ],
    if (s.can('viewHistory')) ...[
      const SizedBox(height: 12), const Text('آخر تغيّرات الأسعار', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (s.history.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('تظهر تغيّرات الأسعار هنا بعد أول تعديل.')),
      ...s.history.take(30).map((h) => Card(child: ListTile(leading: Icon(h.after >= h.before ? Icons.trending_up : Icons.trending_down,
        color: h.after >= h.before ? const Color(0xffad7350) : const Color(0xff237b66)), title: Text(h.name),
        subtitle: Text('${h.kind} • ${h.actor}\n${h.at.replaceFirst('T', ' ').split('.').first} UTC'),
        trailing: Text('${money(h.before)}\n↓ ${money(h.after)}')))),
    ],
    if (!s.owner) const Padding(padding: EdgeInsets.all(24), child: Text('الميزات المتاحة تحددها صلاحياتك. اطلب من صاحب المحل تغييرها عند الحاجة.')),
    const SizedBox(height: 24), const Center(child: Text('رفّ • 0.4.2', style: TextStyle(color: Colors.blueGrey))),
  ]);

  Future<void> currencyDialog() async {
    final c = TextEditingController(text: s.settings.currency);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('العملة المحلية'),
      content: TextField(controller: c, decoration: const InputDecoration(labelText: 'مثلاً ل.س أو ل.ل')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ'))]));
    Future<void>.delayed(const Duration(milliseconds: 300), c.dispose);
    if (value != null && mounted) { await action(() => s.changeSettings(s.settings.rate, s.settings.margin, value)); }
  }
  Future<void> importExcel({bool fromDrive = false}) async {
    if (fromDrive && !await driveGuide(saving: false)) { return; }
    await action(() async {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (picked == null || !mounted) { return; }
      if (picked.files.single.size > 5 * 1024 * 1024) { throw const FormatException('استخدم ملفاً أصغر من 5 ميغابايت.'); }
      final settingsRevision = s.settings.revision;
      final plan = StoreFiles.preview(picked.files.single.bytes!, s.products, s.settings, s.newId);
      final preview = 'إجمالي الصفوف: ${plan.total} من ${plan.sheets} أوراق أصناف\n${plan.added} صنف جديد • ${plan.updated} تحديث\n${plan.skipped} صفوف متجاوزة\n\n${plan.warnings.take(10).join('\n')}\n\nعينة للمعاينة فقط؛ سيُحفظ كل ${plan.products.length} صنفاً صالحاً:\n${plan.products.take(5).map((p) => p.name).join('\n')}';
      if (!mounted) { return; }
      if (plan.products.isNotEmpty) {
        final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('معاينة الاستيراد'), scrollable: true, content: Text(preview), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('استيراد ${plan.products.length} صنف')),
          ]));
        if (accepted != true || !mounted) { return; }
      }
      setState(() { importing = true; importDone = 0; importTotal = plan.products.length; });
      late final ImportResult result;
      try {
        result = await s.importProducts(plan.products, settingsRevision: settingsRevision, onProgress: (done, total) {
          if (mounted) { setState(() { importDone = done; importTotal = total; }); }
        });
      } finally { if (mounted) { setState(() => importing = false); } }
      if (!mounted) { return; }
      setState(() { search.clear(); category = 'الكل'; });
      final issues = [...plan.warnings, ...result.errors];
      final report = 'إجمالي صفوف الملف: ${plan.total}\nأُضيفت ${result.added} أصناف جديدة\nتحدثت ${result.updated} أصناف موجودة\nتجاوزت المعاينة ${plan.skipped} صفوف\nتعذر حفظ ${result.failed} أصناف\nلم تُعالج ${result.unprocessed} أصناف\n${result.stoppedReason ?? ''}\n\n${issues.join('\n')}';
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(result.saved == 0 ? 'لم تُحفظ أصناف' : 'نتيجة الاستيراد'),
        content: SingleChildScrollView(child: Text(report)),
        actions: [
          TextButton(onPressed: () => perform(ctx, () => StoreFiles.shareBytes(utf8.encode(report), 'raff-import-report.txt', 'text/plain'), 'تقرير الاستيراد جاهز'), child: const Text('حفظ التقرير')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ));
    }, 'انتهت مراجعة الاستيراد');
  }
  Future<void> restore({bool fromDrive = false}) async {
    if (!s.can('restoreBackup')) { return; }
    if (fromDrive && !await driveGuide(saving: false)) { return; }
    await action(() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (picked == null || !mounted) { return; }
    if (picked.files.single.size > 10 * 1024 * 1024) { throw const FormatException('ملف النسخة أكبر من الحد المسموح.'); }
    final data = Json.from(jsonDecode(utf8.decode(picked.files.single.bytes!)));
    if (await confirm(context, 'استرجاع النسخة', s.cloud ? 'دمج مواد النسخة وتحديث إعدادات المحل. لن تُحذف المواد الأخرى. الاستعادة لا تشمل الجرد والسجل القديم في الوضع السحابي.' : 'سيتم استبدال بيانات هذا الجهاز بالنسخة. احفظ نسخة حالية قبل المتابعة.')) { await s.restore(data); }
  }, 'تم استرجاع النسخة');
  }

  Future<void> editCartQuantity(CartLine line) async {
    final value = await numberDialog('كمية ${line.name}', line.byWeight ? 'الوزن بالكيلوغرام' : 'عدد القطع',
      initial: line.quantity, quantity: true, positive: true, whole: !line.byWeight);
    if (value != null && mounted && s.can('useCalculator')) { setState(() => line.setQuantity(value)); }
  }
  Future<bool> driveGuide({required bool saving}) => confirm(context, 'Google Drive',
    'ستفتح نافذة ملفات أندرويد. افتح قائمة المواقع واختر Google Drive، ثم ${saving ? 'المجلد واضغط حفظ' : 'الملف المطلوب'}. يجب أن يكون تطبيق Drive مثبتاً وحسابك مفتوحاً. يمكنك اختيار تخزين الهاتف أيضاً.');
  Future<void> saveDrive({required bool backup}) async {
    if (!s.owner || busy || !await driveGuide(saving: true) || !mounted) { return; }
    if (!s.owner) { return; }
    setState(() => busy = true);
    try {
      final bytes = backup ? utf8.encode(const JsonEncoder.withIndent('  ').convert(s.backup())) : StoreFiles.productExcel(s.products, s.settings);
      final name = backup ? 'raff-backup-${DateTime.now().millisecondsSinceEpoch}.json' : 'raff-products.xlsx';
      final saved = await DeviceFiles.save(bytes, name);
      if (saved && mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الملف في المكان الذي اخترته'))); }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'تعذر حفظ الملف. تحقق من مكان الحفظ وDrive وحاول مجدداً.'))); }
    } finally { if (mounted) { setState(() => busy = false); } }
  }
}


