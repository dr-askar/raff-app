import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raff/data/files.dart';
import 'package:raff/data/xlsx_values.dart';
import 'package:raff/domain/models.dart';

void main() {
  test('mobile formatting does not stop 113 rows in a single worksheet', () {
    final raw = base64Decode(File('test/fixtures/mobile_values_113.base64').readAsStringSync().trim());
    for (final normalize in [false, true]) {
      try {
        final book = Excel.decodeBytes(normalize ? normalizeXlsxValues(raw) : raw);
        print('normalize=$normalize rows=${book.tables.values.first.maxRows}');
      } catch (e, stack) { print('normalize=$normalize error=$e\n$stack'); }
    }
    var n = 0;
    final plan = StoreFiles.preview(raw, [], const StoreSettings(), () => 'new${n++}');
    expect(plan.warnings, isEmpty);
    expect(plan.sheets, 1);
    expect(plan.added, 113);
  });
}
