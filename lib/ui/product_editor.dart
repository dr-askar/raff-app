import 'package:flutter/material.dart';
import '../data/app_store.dart';
import '../domain/models.dart';
import 'common.dart';
import 'scanner.dart';

Future<void> editProduct(BuildContext context, AppStore store, {Product? product, String? barcode}) =>
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProductEditor(store: store, product: product, barcode: barcode)));

class ProductEditor extends StatefulWidget {
  final AppStore store;
  final Product? product;
  final String? barcode;
  const ProductEditor({super.key, required this.store, this.product, this.barcode});
  @override
  State<ProductEditor> createState() => _ProductEditorState();
}
class _ProductEditorState extends State<ProductEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, category, barcode, pack, quantity, cost, margin, manual, bargain;
  bool general = true, fixed = false, cartonCost = true, cartonQuantity = false, busy = false;
  String currency = 'USD', unit = 'piece';
  bool get byWeight => unit == 'kg';
  String get unitLabel => byWeight ? 'الكيلوغرام' : 'القطعة';
  double? get packAmount => parseQuantity(pack.text);
  AppStore get s => widget.store;
  bool get details => widget.product == null ? s.can('addProduct') : s.can('editDetails');
  @override
  void initState() {
    super.initState(); final p = widget.product;
    name = TextEditingController(text: p?.name ?? ''); category = TextEditingController(text: p?.category ?? 'عام');
    barcode = TextEditingController(text: p?.barcode ?? widget.barcode ?? ''); pack = TextEditingController(text: '${p?.pack ?? 1}');
    unit = p?.unit ?? 'piece';
    quantity = TextEditingController(text: quantityText(p?.quantity ?? 0)); currency = p?.costCurrency ?? 'USD';
    cost = TextEditingController(text: p?.packCost?.toString() ?? '');
    margin = TextEditingController(text: '${p?.margin ?? s.settings.margin}');
    manual = TextEditingController(text: p?.manualPrice?.toString() ?? '');
    bargain = TextEditingController(text: '${p?.bargainPercent ?? 0}');
    general = p?.margin == null; fixed = p?.manualPrice != null;
  }
  @override
  void dispose() { for (final c in [name, category, barcode, pack, quantity, cost, margin, manual, bargain]) { c.dispose(); } super.dispose(); }
  Widget field(TextEditingController c, String label, {bool numeric = false, bool quantityField = false, bool optional = false, bool enabled = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: c, enabled: enabled && !busy,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label), onChanged: (_) => setState(() {}),
      validator: (value) {
        if (!enabled) { return null; }
        if ((value ?? '').trim().isEmpty) { return optional ? null : 'هذا الحقل مطلوب'; }
        if (numeric) { final n = quantityField ? parseQuantity(value!) : parseAmount(value!); if (n == null || !n.isFinite || n < 0) { return 'أدخل رقماً غير سالب'; } }
        return null;
      }));
  Future<void> save() async {
    if (!form.currentState!.validate()) { return; }
    setState(() => busy = true);
    try {
      final units = packAmount;
      if (units == null || !units.isFinite || units <= 0 || (!byWeight && units != units.roundToDouble())) { throw const FormatException('أدخل عدد قطع صحيحاً موجباً أو وزناً موجباً للطرد.'); }
      final base = widget.product ?? Product(id: s.newId(), name: name.text.trim());
      final rawCost = s.can('editCost') ? parseAmount(cost.text) : null;
      final unitCost = rawCost == null ? null : rawCost / (cartonCost ? units : 1);
      final p = base.edit(name: details ? name.text.trim() : null, category: details ? (category.text.trim().isEmpty ? 'عام' : category.text.trim()) : null,
        barcode: details ? barcode.text.trim() : null, pack: details ? units : null, unit: details ? unit : null,
        quantity: s.can('editQuantity') ? parseQuantity(quantity.text)! * (cartonQuantity ? units : 1) : null,
        costCurrency: s.can('editCost') ? currency : null,
        costUsd: currency == 'USD' ? unitCost : null, costLocal: currency == 'SYP' ? unitCost : null,
        margin: s.can('editMargin') && !general ? parseAmount(margin.text)! : null, useGeneralMargin: s.can('editMargin') && general,
        bargainPercent: s.owner ? parseAmount(bargain.text)! : null,
        manualPrice: s.can('editSalePrice') && fixed ? parseAmount(manual.text)! : null,
        automatic: s.can('editSalePrice') && !fixed, settings: s.settings);
      await s.saveProduct(p, expectedRevision: widget.product?.revision);
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المادة'))); }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'تعذر الحفظ. تحقق من الاتصال والصلاحيات.'))); }
    } finally { if (mounted) { setState(() => busy = false); } }
  }
  Future<void> delete() async {
    if (!await confirm(context, 'حذف ${widget.product!.name}', 'سيُحذف الصنف من المواد، ويبقى سجل تغييراته. احفظ نسخة احتياطية إذا كنت تحتاج بياناته.')) { return; }
    if (!mounted) { return; }
    setState(() => busy = true);
    try {
      await s.deleteProduct(widget.product!);
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الصنف'))); }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'تعذر الحذف. تحقق من الاتصال والصلاحيات.'))); }
    } finally { if (mounted) { setState(() => busy = false); } }
  }
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: s, builder: (context, _) {
    final units = packAmount ?? 1;
    final base = widget.product;
    final rawCost = s.can('editCost') ? parseAmount(cost.text) : null;
    final unitCost = rawCost == null ? null : rawCost / (cartonCost && units > 0 ? units : 1);
    double sale = base?.price(s.settings) ?? 0;
    try {
      sale = (base ?? Product(id: 'preview', name: name.text)).edit(
        costCurrency: s.can('editCost') ? currency : null,
        costUsd: currency == 'USD' ? unitCost : null, costLocal: currency == 'SYP' ? unitCost : null,
        margin: s.can('editMargin') && !general ? parseAmount(margin.text) : null,
        useGeneralMargin: s.can('editMargin') && general,
        manualPrice: s.can('editSalePrice') && fixed ? parseAmount(manual.text) : null,
        automatic: s.can('editSalePrice') && !fixed, settings: s.settings).price(s.settings);
    } on FormatException { /* Keep the previous price until cost is entered. */ }
    return Scaffold(appBar: AppBar(title: Text(widget.product == null ? 'مادة جديدة' : 'بيانات المادة')),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        if (widget.product == null ? s.can('addProduct') : s.canEditProduct) Expanded(child: FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ المادة'))),
        if (widget.product != null && s.can('deleteProduct')) ...[
          const SizedBox(width: 8), OutlinedButton.icon(onPressed: busy ? null : delete, icon: const Icon(Icons.delete_outline), label: const Text('حذف مادة'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700)),
        ],
      ]))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Form(key: form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          field(name, 'اسم المادة', enabled: details), field(category, 'التصنيف', optional: true, enabled: details),
          Row(children: [Expanded(child: field(barcode, 'الباركود', optional: true, enabled: details)), const SizedBox(width: 8),
            if (details) IconButton.filledTonal(tooltip: 'قراءة الباركود', onPressed: busy ? null : () async { final code = await scanBarcode(context); if (code != null && mounted) { setState(() => barcode.text = code); } }, icon: const Icon(Icons.qr_code_scanner))]),
          DropdownButtonFormField<String>(initialValue: unit,
            decoration: const InputDecoration(labelText: 'وحدة البيع'),
            items: const [DropdownMenuItem(value: 'piece', child: Text('قطعة')),
              DropdownMenuItem(value: 'kg', child: Text('كيلوغرام — يقبل الكسور'))],
            onChanged: busy || !details ? null : (value) => setState(() => unit = value!)),
          const SizedBox(height: 16),
          field(pack, byWeight ? 'وزن الطرد بالكيلوغرام' : 'عدد القطع بالطرد', numeric: true, quantityField: true, enabled: details),
          if (s.can('editQuantity')) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال المخزون بعدد الطرود'), value: cartonQuantity, onChanged: busy ? null : (v) => setState(() => cartonQuantity = v)),
          field(quantity, cartonQuantity ? 'عدد الطرود المتوفرة' : byWeight ? 'الكمية المتوفرة بالكيلوغرام' : 'عدد القطع المتوفرة', numeric: true, quantityField: true, enabled: s.can('editQuantity')),
          if (s.can('viewCost')) ...[
            DropdownButtonFormField<String>(initialValue: currency, decoration: const InputDecoration(labelText: 'عملة رأس المال'),
              items: const [DropdownMenuItem(value: 'USD', child: Text('دولار USD')), DropdownMenuItem(value: 'SYP', child: Text('ليرة سورية SYP'))],
              onChanged: busy || !s.can('editCost') ? null : (v) => setState(() { currency = v!; cost.clear(); })),
            if (s.can('editCost')) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال سعر تكلفة الطرد'), value: cartonCost, onChanged: busy ? null : (v) => setState(() {
              final value = parseAmount(cost.text), units = packAmount;
              if (value != null && units != null && units > 0) { cost.text = (v ? value * units : value / units).toString(); }
              cartonCost = v;
            })),
            const SizedBox(height: 12), field(cost, 'تكلفة ${cartonCost ? 'الطرد' : unitLabel} ${currency == 'SYP' ? 'بالسوري' : 'بالدولار'}', numeric: true, optional: true, enabled: s.can('editCost')),
            if (unitCost != null) Text('تكلفة $unitLabel المحسوبة: ${quantityText(unitCost)} ${currency == 'SYP' ? 'ل.س' : '\$'}'),
            const Text('التكلفة بالسوري لا تتغير مع سعر الدولار. ترك التكلفة فارغة يحافظ على القيمة السابقة.'),
          ],
          if (s.can('viewMargin')) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('استخدام نسبة الربح العامة'), subtitle: Text('${s.settings.margin}% زيادة على التكلفة'), value: general, onChanged: busy || !s.can('editMargin') ? null : (v) => setState(() => general = v)),
            if (!general) field(margin, 'نسبة الربح الخاصة %', numeric: true, enabled: s.can('editMargin')),
          ],
          if (s.can('editSalePrice')) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('سعر بيع ثابت يدوياً'), subtitle: const Text('يبقى ثابتاً عند تغيير سعر الصرف'), value: fixed, onChanged: busy ? null : (v) => setState(() => fixed = v)),
            if (fixed) field(manual, 'سعر $unitLabel بالعملة المحلية', numeric: true),
          ],
          if (s.owner) field(bargain, 'نسبة المساومة % — من 0 إلى 100', numeric: true),
          const Text('المساومة تخفيض للزبون في السلة فقط، ولا تغيّر سعر الصنف المحفوظ.'),
          Card(color: const Color(0xffe3eef9), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            Text('سعر مبيع $unitLabel'), Text('${money(sale)} ${s.settings.currency}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text('أقل سعر مسموح: ${money(minimumSalePrice(sale, s.can('applyBargain') ? (parseAmount(bargain.text) ?? 0).clamp(0, 100).toDouble() : 0))} ${s.settings.currency}'),
          ]))), const SizedBox(height: 20),
        ])))));
  });
}

