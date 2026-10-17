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
    sheet.appendRow(['id', 'اسم المادة', 'الباركود', 'التصنيف', 'عدد القطع بالطرد',
      'عدد الطرود', 'سعر الطرد', 'عملة التكلفة', 'نسبة الربح',
      'سعر مبيع الطرد الثابت', 'سعر مبيع الطرد', 'سعر الصرف', 'نسبة المساومة',
      'قطع إضافية', 'وزن الطرد بالكيلوغرام', 'الكمية بالكيلوغرام', 'نوع الصنف']
      .map(TextCellValue.new).toList());
    for (final p in products) {
      final cartons = p.byWeight ? 0 : (p.quantity / p.pack).floor();
      final loose = p.quantity - cartons * p.pack;
      sheet.appendRow([TextCellValue(p.id), TextCellValue(p.name), TextCellValue(p.barcode), TextCellValue(p.category),
        p.byWeight ? null : IntCellValue(p.pack.toInt()), p.byWeight ? null : IntCellValue(cartons),
        p.packCost == null ? null : DoubleCellValue(p.packCost!), TextCellValue(p.costCurrency),
        p.margin == null ? null : DoubleCellValue(p.margin!),
        p.manualPrice == null ? null : DoubleCellValue(p.manualPrice! * p.pack),
        p.ready ? DoubleCellValue(p.price(settings) * p.pack) : null,
        DoubleCellValue(settings.rate), DoubleCellValue(p.bargainPercent),
        p.byWeight ? null : DoubleCellValue(loose), p.byWeight ? DoubleCellValue(p.pack) : null,
        p.byWeight ? DoubleCellValue(p.quantity) : null, TextCellValue(p.byWeight ? 'وزن' : 'طرد')]);
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
      'نوع الصنف': 'unit', 'نوع المادة': 'unit', 'طريقة البيع': 'unit',
      'عدد القطع بالطرد': 'pack_pieces', 'عدد القطع في الطرد': 'pack_pieces',
      'وزن الطرد بالكيلوغرام': 'pack_weight', 'وزن الطرد': 'pack_weight',
      'عدد الطرود': 'pack_quantity', 'عدد الطرود المتوفرة': 'pack_quantity', 'عدد الكراتين': 'pack_quantity',
      'قطع إضافية': 'loose_pieces', 'قطع اضافية': 'loose_pieces', 'القطع الإضافية': 'loose_pieces',
      'الكمية بالكيلوغرام': 'quantity_kg', 'الكمية بالكيلو': 'quantity_kg',
      'سعر مبيع الطرد الثابت': 'manual_pack_price', 'سعر بيع الطرد الثابت': 'manual_pack_price',
      'سعر الطرد بالدولار': 'pack_cost_usd', 'سعر الطرد بالسوري': 'pack_cost_syp',
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
        // A blank type cell explicitly selects the default (pack). Older files
        // without the column preserve an existing product's unit.
        final unit = headers.contains('unit') ? productUnit(field('unit')) : old?.unit ?? 'piece';
        final pieces = numeric('pack_pieces'), weight = numeric('pack_weight');
        if ((unit == 'piece' && weight != null) ||
            (unit == 'kg' && pieces != null && weight != null && pieces != weight)) {
          throw const FormatException('تحقق من نوع الصنف وتطابق محتوى الطرد ووزنه');
        }
        // Older Arabic files used the pieces header for weighted pack content too.
        final pack = (unit == 'kg' ? weight ?? pieces : pieces) ?? numeric('pack');
        final units = pack ?? old?.pack ?? 1.0;
        if (!['kg', 'piece'].contains(unit) || units <= 0 || (unit == 'piece' && (units < 1 || units != units.roundToDouble()))) {
          throw const FormatException('تحقق من وحدة البيع ومحتوى الطرد الموجب');
        }
        bool differs(double a, double b) => (a - b).abs() > 0.00000001 * (1 + a.abs());
        var quantity = numeric('quantity'); // Legacy files count pieces or kg.
        final cartons = numeric('pack_quantity'), loose = numeric('loose_pieces');
        final kilos = numeric('quantity_kg');
        if ((unit == 'piece' && kilos != null) || (unit == 'kg' && loose != null)) {
          throw const FormatException('الكمية بالكيلو للصنف الموزون والقطع الإضافية للطرد');
        }
        final packedQuantity = cartons == null && loose == null ? null : (cartons ?? 0) * units + (loose ?? 0);
        final suppliedQuantity = kilos ?? packedQuantity;
        if ((kilos != null && packedQuantity != null && differs(kilos, packedQuantity)) ||
            (quantity != null && suppliedQuantity != null && differs(quantity, suppliedQuantity))) {
          throw const FormatException('تعارض بين الكمية وعدد الطرود؛ املأ طريقة واحدة أو قيماً متطابقة');
        }
        quantity = suppliedQuantity ?? quantity;
        var usd = numeric('cost_usd'), local = numeric('cost_syp');
        final bundleUsd = numeric('pack_cost_usd'), bundleLocal = numeric('pack_cost_syp');
        if (bundleUsd != null && bundleLocal != null) { throw const FormatException('أدخل سعر الطرد بعملة واحدة'); }
        if (usd != null && local != null) { throw const FormatException('أدخل التكلفة بالدولار أو بالسوري في الصف، لا الاثنين معاً'); }
        var currency = field('cost_currency')?.toUpperCase();
        if (currency == 'سوري' || currency == 'ل.س') { currency = 'SYP'; }
        if (currency == 'دولار' || currency == '\$') { currency = 'USD'; }
        currency ??= local != null || bundleLocal != null ? 'SYP' : usd != null || bundleUsd != null ? 'USD' : old?.costCurrency ?? 'USD';
        if (!['USD', 'SYP'].contains(currency) || (currency == 'USD' && (local != null || bundleLocal != null)) ||
            (currency == 'SYP' && (usd != null || bundleUsd != null))) { throw const FormatException('عملة التكلفة لا تتوافق مع عمود التكلفة'); }
        var bundle = numeric('cost_per_pack');
        final currencyBundle = bundleUsd ?? bundleLocal;
        if (bundle != null && currencyBundle != null && differs(bundle, currencyBundle)) {
          throw const FormatException('تعارض في قيم سعر الطرد');
        }
        bundle ??= currencyBundle;
        if (bundle != null) {
          final single = bundle / units;
          final supplied = currency == 'SYP' ? local : usd;
          if (supplied != null && differs(supplied, single)) {
            throw const FormatException('تكلفة الطرد لا تتطابق مع تكلفة الوحدة ومحتوى الطرد');
          }
          if (currency == 'SYP') { local = single; } else { usd = single; }
        }
        var manual = numeric('manual_price');
        final manualPack = numeric('manual_pack_price');
        if (manualPack != null) {
          if (manual != null && differs(manual, manualPack / units)) {
            throw const FormatException('تعارض بين سعر مبيع الطرد الثابت وسعر الوحدة القديم');
          }
          manual = manualPack / units;
        }
        final base = old ?? Product(id: importedId ?? newId(), name: name!);
        if (old == null && byId.containsKey(base.id)) { throw const FormatException('معرف مكرر؛ أعد معاينة الملف'); }
        final p = base.edit(name: name, barcode: barcode, category: field('category'),
          pack: pack, unit: unit, quantity: quantity, costUsd: usd, costLocal: local, costCurrency: currency,
          bargainPercent: numeric('bargain_percent'), margin: numeric('margin_percent'), manualPrice: manual, settings: settings);
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

