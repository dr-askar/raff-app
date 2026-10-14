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
  @override
  void initState() {
    super.initState(); final p = widget.product;
    name = TextEditingController(text: p?.name ?? ''); category = TextEditingController(text: p?.category ?? 'عام');
    barcode = TextEditingController(text: p?.barcode ?? widget.barcode ?? ''); pack = TextEditingController(text: '${p?.pack ?? 1}');
    quantity = TextEditingController(text: '${p?.quantity ?? 0}'); cost = TextEditingController(text: p?.costUsd?.toString() ?? '');
    margin = TextEditingController(text: '${p?.margin ?? widget.store.settings.margin}');
    manual = TextEditingController(text: p?.manualPrice?.toString() ?? '');
    general = p?.margin == null; fixed = p?.manualPrice != null;
  }
  @override
  void dispose() { for (final c in [name, category, barcode, pack, quantity, cost, margin, manual]) { c.dispose(); } super.dispose(); }
  Widget field(TextEditingController c, String label, {bool numeric = false, bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: c,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label), onChanged: (_) => setState(() {}),
      validator: (value) {
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
      final base = widget.product ?? Product(id: widget.store.newId(), name: name.text.trim());
      final rawCost = double.tryParse(cost.text);
      final p = base.edit(name: name.text.trim(), category: category.text.trim().isEmpty ? 'عام' : category.text.trim(),
        barcode: barcode.text.trim(), pack: units,
        quantity: double.parse(quantity.text) * (cartonQuantity ? units : 1),
        costUsd: rawCost == null ? null : rawCost / (cartonCost ? units : 1),
        margin: general ? null : double.parse(margin.text), useGeneralMargin: general,
        manualPrice: fixed ? double.parse(manual.text) : null, automatic: !fixed,
        settings: widget.store.settings);
      await widget.store.saveProduct(p, expectedRevision: widget.product?.revision);
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المادة'))); }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'تعذر الحفظ. تحقق من الاتصال والصلاحيات.'))); }
    } finally { if (mounted) { setState(() => busy = false); } }
  }
  @override
  Widget build(BuildContext context) {
    final units = int.tryParse(pack.text) ?? 1;
    final unitCost = (double.tryParse(cost.text) ?? 0) / (cartonCost && units > 0 ? units : 1);
    final sale = fixed ? double.tryParse(manual.text) ?? 0 : unitCost * widget.store.settings.rate *
      (1 + (general ? widget.store.settings.margin : double.tryParse(margin.text) ?? 0) / 100);
    return Scaffold(appBar: AppBar(title: Text(widget.product == null ? 'مادة جديدة' : 'تعديل المادة')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Form(key: form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          field(name, 'اسم المادة'), field(category, 'التصنيف', optional: true),
          Row(children: [Expanded(child: field(barcode, 'الباركود', optional: true)), const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'قراءة الباركود', onPressed: () async { final code = await scanBarcode(context); if (code != null && mounted) { setState(() => barcode.text = code); } }, icon: const Icon(Icons.qr_code_scanner))]),
          field(pack, 'عدد القطع بالكرتونة', numeric: true),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال الكمية بالكرتونة'), value: cartonQuantity, onChanged: (v) => setState(() => cartonQuantity = v)),
          field(quantity, cartonQuantity ? 'عدد الكراتين المتوفرة' : 'عدد القطع المتوفرة', numeric: true),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إدخال تكلفة الكرتونة'), value: cartonCost, onChanged: (v) => setState(() => cartonCost = v)),
          field(cost, cartonCost ? 'تكلفة الكرتونة بالدولار' : 'تكلفة القطعة بالدولار', numeric: true, optional: true),
          const Text('ترك التكلفة فارغة لمادة جديدة يجعلها تحتاج تسعيراً. لا يمسح تكلفة مادة موجودة.'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('استخدام نسبة الربح العامة'), subtitle: Text('${widget.store.settings.margin}% زيادة على التكلفة'), value: general, onChanged: (v) => setState(() => general = v)),
          if (!general) field(margin, 'نسبة الربح الخاصة %', numeric: true),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('سعر بيع ثابت يدوياً'), subtitle: const Text('يبقى ثابتاً عند تغيير سعر الصرف'), value: fixed, onChanged: (v) => setState(() => fixed = v)),
          if (fixed) field(manual, 'سعر القطعة بالعملة المحلية', numeric: true),
          Card(color: const Color(0xffe3eef9), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Text('معاينة سعر القطعة'), Text('${money(sale)} ${widget.store.settings.currency}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]))), const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : save, child: Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ المادة'))),
        ])))));
  }
}
