import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:cross_file/cross_file.dart';
import '../domain/models.dart';

class ImportPlan {
  final List<Product> products;
  final List<String> warnings;
  final int added, updated;
  const ImportPlan(this.products, this.warnings, this.added, this.updated);
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
      'margin_percent', 'manual_price', 'sale_price', 'exchange_rate', 'cost_currency', 'cost_syp'].map(TextCellValue.new).toList());
    for (final p in products) {
      sheet.appendRow([TextCellValue(p.id), TextCellValue(p.name), TextCellValue(p.barcode), TextCellValue(p.category),
        IntCellValue(p.pack), DoubleCellValue(p.quantity), p.costUsd == null ? null : DoubleCellValue(p.costUsd!),
        p.margin == null ? null : DoubleCellValue(p.margin!), p.manualPrice == null ? null : DoubleCellValue(p.manualPrice!),
        p.ready ? DoubleCellValue(p.price(settings)) : null, DoubleCellValue(settings.rate), TextCellValue(p.costCurrency), p.costLocal == null ? null : DoubleCellValue(p.costLocal!)]);
    }
    return book.encode()!;
  }
  static List<int> stockExcel(Stocktake s) {
    final book = Excel.createExcel(); final sheet = book['الجرد']; book.delete('Sheet1');
    sheet.appendRow([TextCellValue('جلسة الجرد'), TextCellValue(s.at)]);
    sheet.appendRow([TextCellValue('سعر الصرف المثبت'), DoubleCellValue(s.rate), TextCellValue(s.currency)]);
    sheet.appendRow(['المادة', 'الباركود', 'العدد المسجل', 'العدد الفعلي', 'الفرق', 'تكلفة القطعة محلياً', 'القيمة'].map(TextCellValue.new).toList());
    for (final row in s.snapshot.entries) {
      final j = row.value; final count = s.counts[row.key];
      final cost = j['costUsd'] == null && j['costLocal'] == null ? null : snapshotCost(j, s.rate);
      sheet.appendRow([TextCellValue(j['name'] ?? ''), TextCellValue(j['barcode'] ?? ''),
        DoubleCellValue(number(j['quantity'])), count == null ? null : DoubleCellValue(count),
        count == null ? null : DoubleCellValue(count - number(j['quantity'])),
        cost == null ? null : DoubleCellValue(cost), count == null || cost == null ? null : DoubleCellValue(count * cost)]);
    }
    sheet.appendRow([TextCellValue('إجمالي المواد المعدودة ذات التكلفة المعروفة'), null, null, null, null, null, DoubleCellValue(s.value)]);
    return book.encode()!;
  }

  static ImportPlan preview(List<int> bytes, List<Product> existing, StoreSettings settings, String Function() newId) {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) { throw const FormatException('ملف Excel فارغ.'); }
    final sheet = book.tables['Products'] ?? book.tables.values.first;
    if (sheet.rows.isEmpty) { throw const FormatException('لا توجد صفوف للاستيراد.'); }
    const aliases = {
      'معرف المادة': 'id', 'معرّف المادة': 'id', 'معرف': 'id', 'product_id': 'id',
      'اسم المادة': 'name', 'الاسم': 'name', 'الباركود': 'barcode', 'التصنيف': 'category',
      'اسم': 'name', 'المادة': 'name', 'اسم المنتج': 'name', 'اسم الصنف': 'name',
      'باركود': 'barcode', 'رقم الباركود': 'barcode', 'الفئة': 'category',
      'التعبئة': 'pack', 'الكمية': 'quantity', 'التكلفة': 'cost_usd',
      'تكلفة بالسوري': 'cost_syp', 'رأس المال بالسوري': 'cost_syp', 'عملة التكلفة': 'cost_currency',
      'نسبة الربح': 'margin_percent', 'سعر ثابت': 'manual_price',
    };
    final headers = sheet.rows.first.map((c) {
      final s = (c?.value?.toString() ?? '').replaceAll(RegExp('[\u200e\u200f\ufeff]'), '').trim().toLowerCase();
      return aliases[s] ?? s;
    }).toList();
    if (!headers.contains('name') && !headers.contains('barcode') && !headers.contains('id')) {
      throw const FormatException('ضع عمود name / اسم المادة أو barcode / الباركود في أول صف.');
    }
    final planned = <Product>[], warnings = <String>[];
    final working = [...existing]; var added = 0, updated = 0;
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
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
        Product? old;
        if (importedId != null) {
          for (final p in working) { if (p.id == importedId) { old = p; break; } }
        }
        if (barcode != null) {
          for (final p in working) {
            if (p.barcode == barcode) {
              if (old != null && old.id != p.id) { throw const FormatException('معرف المادة والباركود يخصان مادتين مختلفتين'); }
              old ??= p; break;
            }
          }
        }
        if (old == null && name != null) {
          final matches = working.where((p) => p.name == name).toList();
          if (barcode == null && matches.length > 1) { throw const FormatException('اسم مكرر؛ استخدم الباركود أو المعرف للمطابقة'); }
          if (matches.length == 1 && (barcode == null || matches.first.barcode.isEmpty)) { old = matches.first; }
        }
        if (old == null && name == null) { throw const FormatException('المادة الجديدة تحتاج اسماً'); }
        final matched = old;
        if (matched != null && planned.any((p) => p.id == matched.id)) { throw const FormatException('المادة مكررة داخل الملف'); }
        double? numeric(String key) {
          final value = field(key); if (value == null) { return null; }
          final parsed = double.tryParse(_normalizeNumber(value, percent: key == 'margin_percent'));
          if (parsed == null || !parsed.isFinite || parsed < 0) { throw FormatException('قيمة غير صالحة في $key'); }
          return parsed;
        }
        final pack = numeric('pack');
        if (pack != null && (pack < 1 || pack != pack.roundToDouble())) { throw const FormatException('عدد التعبئة يجب أن يكون عدداً صحيحاً موجباً'); }
        final usd = numeric('cost_usd'), local = numeric('cost_syp');
        if (usd != null && local != null) { throw const FormatException('أدخل التكلفة بالدولار أو بالسوري في الصف، لا الاثنين معاً'); }
        var currency = field('cost_currency')?.toUpperCase();
        if (currency == 'سوري' || currency == 'ل.س') { currency = 'SYP'; }
        if (currency == 'دولار' || currency == '\$') { currency = 'USD'; }
        currency ??= local != null ? 'SYP' : usd != null ? 'USD' : old?.costCurrency ?? 'USD';
        if (!['USD', 'SYP'].contains(currency) || (currency == 'USD' && local != null) || (currency == 'SYP' && usd != null)) { throw const FormatException('عملة التكلفة لا تتوافق مع عمود التكلفة'); }
        final base = old ?? Product(id: importedId ?? newId(), name: name!);
        final p = base.edit(name: name, barcode: barcode, category: field('category'),
          pack: pack?.toInt(), quantity: numeric('quantity'), costUsd: usd, costLocal: local, costCurrency: currency,
          margin: numeric('margin_percent'), manualPrice: numeric('manual_price'), settings: settings);
        p.validate();
        planned.add(p); working.removeWhere((e) => e.id == p.id); working.add(p);
        if (old == null) { added++; } else { updated++; }
      } catch (e) { warnings.add('الصف ${rowIndex + 1}: ${e is FormatException ? e.message : 'تعذر قراءة الصف'}'); }
    }
    return ImportPlan(planned, warnings, added, updated);
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
