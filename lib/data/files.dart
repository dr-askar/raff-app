import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:cross_file/cross_file.dart';
import '../domain/models.dart';
import 'xlsx_values.dart';

class ImportPlan {
  final List<Product> products;
  final List<String> warnings;
  final int added, updated;
  final int skipped, sheets;
  const ImportPlan(this.products, this.warnings, this.added, this.updated, {this.skipped = 0, this.sheets = 0});
  int get total => added + updated + skipped;
}

class StoreFiles {
  static Future<void> shareBytes(List<int> bytes, String name, String mime) async {
    await Share.shareXFiles([XFile.fromData(Uint8List.fromList(bytes), mimeType: mime, name: name)],
      fileNameOverrides: [name]);
  }
  static Future<void> shareJson(Json data) => shareBytes(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    'raff-backup-${DateTime.now().millisecondsSinceEpoch}.json', 'application/json');

  static List<int> productExcel(List<Product> products, StoreSettings settings) {
    final book = Excel.createExcel();
    final sheet = book['Products'];
    book.delete('Sheet1');
    sheet.appendRow(['id', 'name', 'barcode', 'category', 'pack', 'quantity', 'cost_usd',
      'margin_percent', 'manual_price', 'sale_price', 'exchange_rate', 'cost_currency', 'cost_syp', 'bargain_percent', 'unit'].map(TextCellValue.new).toList());
    for (final p in products) {
      sheet.appendRow([TextCellValue(p.id), TextCellValue(p.name), TextCellValue(p.barcode), TextCellValue(p.category),
        p.pack == p.pack.roundToDouble() ? IntCellValue(p.pack.toInt()) : DoubleCellValue(p.pack), DoubleCellValue(p.quantity), p.costUsd == null ? null : DoubleCellValue(p.costUsd!),
        p.margin == null ? null : DoubleCellValue(p.margin!), p.manualPrice == null ? null : DoubleCellValue(p.manualPrice!),
        p.ready ? DoubleCellValue(p.price(settings)) : null, DoubleCellValue(settings.rate), TextCellValue(p.costCurrency), p.costLocal == null ? null : DoubleCellValue(p.costLocal!), DoubleCellValue(p.bargainPercent), TextCellValue(p.unit)]);
    }
    return book.encode()!;
  }
  static List<int> stockExcel(Stocktake s) {
    final book = Excel.createExcel(); final sheet = book['الجرد']; book.delete('Sheet1');
    sheet.appendRow([TextCellValue('جلسة الجرد'), TextCellValue(s.at)]);
    sheet.appendRow([TextCellValue('سعر الصرف المثبت'), DoubleCellValue(s.rate), TextCellValue(s.currency)]);
    sheet.appendRow(['المادة', 'الباركود', 'العدد المسجل', 'العدد الفعلي', 'الفرق', 'تكلفة الوحدة محلياً', 'القيمة', 'الوحدة'].map(TextCellValue.new).toList());
    for (final row in s.snapshot.entries) {
      final j = row.value; final count = s.counts[row.key];
      final cost = j['costUsd'] == null && j['costLocal'] == null ? null : snapshotCost(j, s.rate);
      sheet.appendRow([TextCellValue(j['name'] ?? ''), TextCellValue(j['barcode'] ?? ''),
        DoubleCellValue(number(j['quantity'])), count == null ? null : DoubleCellValue(count),
        count == null ? null : DoubleCellValue(count - number(j['quantity'])),
        cost == null ? null : DoubleCellValue(cost), count == null || cost == null ? null : DoubleCellValue(count * cost), TextCellValue(j['unit'] == 'kg' ? 'كغ' : 'قطعة')]);
    }
    sheet.appendRow([TextCellValue('إجمالي المواد المعدودة ذات التكلفة المعروفة'), null, null, null, null, null, DoubleCellValue(s.value)]);
    return book.encode()!;
  }

  static ImportPlan preview(List<int> bytes, List<Product> existing, StoreSettings settings, String Function() newId) {
    late final Excel book;
    try { book = Excel.decodeBytes(normalizeXlsxValues(bytes)); }
    on FormatException { rethrow; }
    catch (_) { throw const FormatException('تعذر قراءة ملف Excel. احفظه بصيغة xlsx وأعد المحاولة؛ تنسيق الملف غير مدعوم أو الملف تالف.'); }
    if (book.tables.isEmpty) { throw const FormatException('ملف Excel فارغ.'); }
    const aliases = {
      'معرف المادة': 'id', 'معرّف المادة': 'id', 'معرف': 'id', 'product_id': 'id',
      'اسم المادة': 'name', 'الاسم': 'name', 'الباركود': 'barcode', 'التصنيف': 'category',
      'اسم': 'name', 'المادة': 'name', 'اسم المنتج': 'name', 'اسم الصنف': 'name',
      'باركود': 'barcode', 'رقم الباركود': 'barcode', 'الفئة': 'category',
      'التعبئة': 'pack', 'الكمية': 'quantity', 'التكلفة': 'cost_usd',
      'تكلفة بالسوري': 'cost_syp', 'رأس المال بالسوري': 'cost_syp', 'عملة التكلفة': 'cost_currency',
      'وحدة البيع': 'unit', 'الوحدة': 'unit', 'سعر الطرد': 'cost_per_pack', 'تكلفة الطرد': 'cost_per_pack',
      'نسبة المساومة': 'bargain_percent', 'نسبة الربح': 'margin_percent', 'سعر ثابت': 'manual_price',
    };
    final planned = <Product>[], warnings = <String>[];
    final byId = <String, Product>{};
    final byBarcode = <String, Product>{};
    final byName = <String, Set<String>>{};
    final plannedIds = <String>{};
    void index(Product p) {
      byId[p.id] = p;
      if (p.barcode.isNotEmpty) { byBarcode[p.barcode] = p; }
      (byName[p.name] ??= <String>{}).add(p.id);
    }
    for (final p in existing) { index(p); }
    var added = 0, updated = 0, skipped = 0, recognisedSheets = 0;
    final sheets = [...book.tables.entries.where((e) => e.key == 'Products'),
      ...book.tables.entries.where((e) => e.key != 'Products')];
    for (final entry in sheets) {
    // Cache rows once: the Excel getter constructs a cell matrix.
    final rows = entry.value.rows;
    if (rows.isEmpty) { continue; }
    final headers = rows.first.map((c) {
      final s = (c?.value?.toString() ?? '').replaceAll(RegExp('[\u200e\u200f\ufeff]'), '').trim().toLowerCase();
      return aliases[s] ?? s;
    }).toList();
    if (!headers.contains('name') && !headers.contains('barcode') && !headers.contains('id')) {
      final count = rows.skip(1).where((r) => r.any((c) => (c?.value?.toString().trim() ?? '').isNotEmpty)).length;
      if (count > 0) { warnings.add('الورقة «${entry.key}»: تم تجاوز $count صفاً لعدم وجود عمود اسم أو باركود أو معرف في أول صف.'); }
      skipped += count;
      continue;
    }
    recognisedSheets++;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String? field(String key) {
        final i = headers.indexOf(key);
        if (i < 0 || i >= row.length) { return null; }
        final value = row[i]?.value?.toString().trim();
        return value == null || value.isEmpty ? null : value;
      }
      if (row.every((c) => (c?.value?.toString().trim() ?? '').isEmpty)) { continue; }
      try {
        final importedId = field('id');
        final barcode = field('barcode'); final name = field('name');
        Product? old = importedId == null ? null : byId[importedId];
        final barcodeMatch = barcode == null ? null : byBarcode[barcode];
        if (barcodeMatch != null) {
          if (old != null && old.id != barcodeMatch.id) { throw const FormatException('معرف المادة والباركود يخصان مادتين مختلفتين'); }
          old ??= barcodeMatch;
        }
        if (old == null && name != null) {
          final matches = byName[name] ?? <String>{};
          if (barcode == null && matches.length > 1) { throw const FormatException('اسم مكرر؛ استخدم الباركود أو المعرف للمطابقة'); }
          if (matches.length == 1) {
            final match = byId[matches.single]!;
            if (barcode == null || match.barcode.isEmpty) { old = match; }
          }
        }
        if (old == null && name == null) { throw const FormatException('المادة الجديدة تحتاج اسماً'); }
        if (old != null && plannedIds.contains(old.id)) { throw const FormatException('المادة مكررة داخل الملف؛ اترك معرف المادة فارغاً للصنف الجديد'); }
        double? numeric(String key) {
          final value = field(key); if (value == null) { return null; }
          final parsed = double.tryParse(_normalizeNumber(value, percent: key.endsWith('_percent')));
          if (parsed == null || !parsed.isFinite || parsed < 0) { throw FormatException('قيمة غير صالحة في $key'); }
          return parsed;
        }
        var unit = field('unit') ?? old?.unit ?? 'piece';
        unit = {'كغ': 'kg', 'كيلو': 'kg', 'كيلوغرام': 'kg', 'قطعة': 'piece', 'عدد': 'piece'}[unit] ?? unit.toLowerCase();
        final pack = numeric('pack');
        final units = pack ?? old?.pack ?? 1.0;
        if (!['kg', 'piece'].contains(unit) || units <= 0 || (unit == 'piece' && (units < 1 || units != units.roundToDouble()))) {
          throw const FormatException('تحقق من وحدة البيع ومحتوى الطرد الموجب');
        }
        var usd = numeric('cost_usd'), local = numeric('cost_syp');
        if (usd != null && local != null) { throw const FormatException('أدخل التكلفة بالدولار أو بالسوري في الصف، لا الاثنين معاً'); }
        var currency = field('cost_currency')?.toUpperCase();
        if (currency == 'سوري' || currency == 'ل.س') { currency = 'SYP'; }
        if (currency == 'دولار' || currency == '\$') { currency = 'USD'; }
        currency ??= local != null ? 'SYP' : usd != null ? 'USD' : old?.costCurrency ?? 'USD';
        if (!['USD', 'SYP'].contains(currency) || (currency == 'USD' && local != null) || (currency == 'SYP' && usd != null)) { throw const FormatException('عملة التكلفة لا تتوافق مع عمود التكلفة'); }
        final bundle = numeric('cost_per_pack');
        if (bundle != null) {
          final single = bundle / units;
          final supplied = currency == 'SYP' ? local : usd;
          if (supplied != null && (supplied - single).abs() > 0.00000001 * (1 + supplied.abs())) {
            throw const FormatException('تكلفة الطرد لا تتطابق مع تكلفة الوحدة ومحتوى الطرد');
          }
          if (currency == 'SYP') { local = single; } else { usd = single; }
        }
        final base = old ?? Product(id: importedId ?? newId(), name: name!);
        if (old == null && byId.containsKey(base.id)) { throw const FormatException('معرف مكرر؛ أعد معاينة الملف'); }
        final p = base.edit(name: name, barcode: barcode, category: field('category'),
          pack: pack, unit: unit, quantity: numeric('quantity'), costUsd: usd, costLocal: local, costCurrency: currency,
          bargainPercent: numeric('bargain_percent'), margin: numeric('margin_percent'), manualPrice: numeric('manual_price'), settings: settings);
        p.validate();
        planned.add(p); plannedIds.add(p.id);
        if (old != null) {
          byName[old.name]?.remove(old.id);
          if (old.barcode.isNotEmpty && byBarcode[old.barcode]?.id == old.id) { byBarcode.remove(old.barcode); }
        }
        index(p);
        if (old == null) { added++; } else { updated++; }
      } catch (e) {
        skipped++;
        final label = field('name') ?? field('barcode') ?? field('id') ?? 'بدون اسم';
        warnings.add('الورقة «${entry.key}» — الصف ${rowIndex + 1} ($label): ${e is FormatException ? e.message : 'تعذر قراءة الصف'}');
      }
    }
    }
    if (recognisedSheets == 0) { throw const FormatException('ضع عمود name / اسم المادة أو barcode / الباركود أو id / المعرف في أول صف من ورقة الأصناف.'); }
    return ImportPlan(planned, warnings, added, updated, skipped: skipped, sheets: recognisedSheets);
  }

  static String _normalizeNumber(String value, {bool percent = false}) {
    var normalized = value.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
      final code = m[0]!.codeUnitAt(0);
      return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
    }).replaceAll(RegExp(r'[\s\u00a0\u200e\u200f]'), '')
      .replaceAll('٬', '').replaceAll('٫', '.');
    if (percent) { normalized = normalized.replaceAll('%', '').replaceAll('٪', ''); }
    if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(normalized)) {
      normalized = normalized.replaceAll(',', '');
    } else if (!normalized.contains('.') && ','.allMatches(normalized).length == 1) {
      normalized = normalized.replaceAll(',', '.');
    }
    return normalized;
  }
}

