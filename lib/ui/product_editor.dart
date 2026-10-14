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
  late final TextEditingController name, category, barcode, pack, quantity, cost, margin, manual;
  bool general = true, fixed = false, cartonCost = false, cartonQuantity = false, busy = false;
  String currency = 'USD';
  AppStore get s => widget.store;
  bool get details => widget.product == null ? s.can('addProduct') : s.can('editDetails');
  @override
  void initState() {
    super.initState(); final p = widget.product;
    name = TextEditingController(text: p?.name ?? ''); category = TextEditingController(text: p?.category ?? 'عام');
    barcode = TextEditingController(text: p?.barcode ?? widget.barcode ?? ''); pack = TextEditingController(text: '${p?.pack ?? 1}');
    quantity = TextEditingController(text: '${p?.quantity ?? 0}'); currency = p?.costCurrency ?? 'USD';
    cost = TextEditingController(text: (currency == 'SYP' ? p?.costLocal : p?.costUsd)?.toString() ?? '');
    margin = TextEditingController(text: '${p?.margin ?? s.settings.margin}');
    manual = TextEditingController(text: p?.manualPrice?.toString() ?? '');
    general = p?.margin == null; fixed = p?.manualPrice != null;
  }
  @override
  void dispose() { for (final c in [name, category, barcode, pack, quantity, cost, margin, manual]) { c.dispose(); } super.dispose(); }
  Widget field(TextEditingController c, String label, {bool numeric = false, bool optional = false, bool enabled = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: c, enabled: enabled && !busy,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label), onChanged: (_) => setState(() {}),
      validator: (value) {
        if (!enabled) { return null; }
        if ((value ?? '').trim().isEmpty) { return optional ? null : 'هذا الحقل مطلوب'; }
        if (numeric) { final n = double.tryParse(value!); if (n == null || !n.isFinite || n < 0) { return 'أدخل رقماً غير سالب'; } }
        return null;
      }));
  Future<void> save() async {
    if (!form.currentState!.validate()) { return; }
    setState(() => busy = true);
    try {
      final units = int.tryParse(pack.text);
      if (units == null || units < 1) { throw const FormatException('عدد القطع بالكرتونة يجب أن يكون عدداً صحيحاً موجباً.'); }
      final base = widget.product ?? Product(id: s.newId(), name: name.text.trim());
      final rawCost = s.can('editCost') ? double.tryParse(cost.text) : null;
      final unitCost = rawCost == null ? null : rawCost / (cartonCost ? units : 1);
      final p = base.edit(name: details ? name.text.trim() : null, category: details ? (category.text.trim().isEmpty ? 'عام' : category.text.trim()) : null,
        barcode: details ? barcode.text.trim() : null, pack: details ? units : null,
        quantity: s.can('editQuantity') ? double.parse(quantity.text) * (cartonQuantity ? units : 1) : null,
        costCurrency: s.can('editCost') ? currency : null,
        costUsd: currency == 'USD' ? unitCost : null, costLocal: currency == 'SYP' ? unitCost : null,
        margin: s.can('editCost') && !general ? double.parse(margin.text) : null, useGeneralMargin: s.can('editCost') && general,
        manualPrice: s.can('editSalePrice') && fixed ? double.parse(manual.text) : null,
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
    final units = int.tryParse(pack.text) ?? 1;
    final enteredCost = (double.tryParse(cost.text) ?? 0) / (cartonCost && units > 0 ? units : 1);
    final sale = s.can('editSalePrice') && fixed ? double.tryParse(manual.text) ?? 0 :
      s.can('viewCost') && (s.can('editCost') || widget.product?.manualPrice == null) ? enteredCost * (currency == 'SYP' ? 1 : s.settings.rate) *
      (1 + (general ? s.settings.margin : double.tryParse(margin.text) ?? 0) / 100) : widget.product?.price(s.settings) ?? 0;
    return Scaffold(appBar: AppBar(title: Text(widget.product == null ? 'مادة جديدة' : 'بيانات المادة')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Form(key: form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          field(name, 'اسم المادة', enabled: details), field(category, 'التصنيف', optional: true, enabled: details),
          Row(children: [Expanded(child: field(barcode, 'الباركود', optional: true, enabled: details)), const SizedBox(width: 8),
            if (details) IconButton.filledTonal(tooltip: 'قراءة الباركود', onPressed: busy ? null : () async { final code = await scanBarcode(context); if (code != null && mounted) { setState(() => barcode.text = code); } }, icon: const Icon(Icons.qr_code_scanner))]),
          field(pack, 'عدد القطع بالكرتونة', numeric: true, enabled: details),
          if (s.can('editQuantity')) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال الكمية بالكرتونة'), value: cartonQuantity, onChanged: busy ? null : (v) => setState(() => cartonQuantity = v)),
          field(quantity, cartonQuantity ? 'عدد الكراتين المتوفرة' : 'عدد القطع المتوفرة', numeric: true, enabled: s.can('editQuantity')),
          if (s.can('viewCost')) ...[
            DropdownButtonFormField<String>(initialValue: currency, decoration: const InputDecoration(labelText: 'عملة رأس المال'),
              items: const [DropdownMenuItem(value: 'USD', child: Text('دولار USD')), DropdownMenuItem(value: 'SYP', child: Text('ليرة سورية SYP'))],
              onChanged: busy || !s.can('editCost') ? null : (v) => setState(() { currency = v!; cost.clear(); })),
            if (s.can('editCost')) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال تكلفة الكرتونة'), value: cartonCost, onChanged: busy ? null : (v) => setState(() => cartonCost = v)),
            const SizedBox(height: 12), field(cost, 'تكلفة ${cartonCost ? 'الكرتونة' : 'القطعة'} ${currency == 'SYP' ? 'بالسوري' : 'بالدولار'}', numeric: true, optional: true, enabled: s.can('editCost')),
            const Text('التكلفة بالسوري لا تتغير مع سعر الدولار. ترك التكلفة فارغة يحافظ على القيمة السابقة.'),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('استخدام نسبة الربح العامة'), subtitle: Text('${s.settings.margin}% زيادة على التكلفة'), value: general, onChanged: busy || !s.can('editCost') ? null : (v) => setState(() => general = v)),
            if (!general) field(margin, 'نسبة الربح الخاصة %', numeric: true, enabled: s.can('editCost')),
          ],
          if (s.can('editSalePrice')) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('سعر بيع ثابت يدوياً'), subtitle: const Text('يبقى ثابتاً عند تغيير سعر الصرف'), value: fixed, onChanged: busy ? null : (v) => setState(() => fixed = v)),
            if (fixed) field(manual, 'سعر القطعة بالعملة المحلية', numeric: true),
          ],
          Card(color: const Color(0xffe3eef9), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Text('معاينة سعر القطعة'), Text('${money(sale)} ${s.settings.currency}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]))), const SizedBox(height: 20),
          if (widget.product == null ? s.can('addProduct') : s.canEditProduct) FilledButton(onPressed: busy ? null : save, child: Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ المادة'))),
          if (widget.product != null && s.can('deleteProduct')) TextButton.icon(onPressed: busy ? null : delete, icon: const Icon(Icons.delete_outline), label: const Text('حذف الصنف'), style: TextButton.styleFrom(foregroundColor: Colors.red.shade700)),
        ])))));
  });
}
