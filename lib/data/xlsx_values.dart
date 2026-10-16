import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// Import values, not display formatting. Some mobile editors write 12.0 under
// an integer style and redefine built-in formats, which excel 4 rejects.
List<int> normalizeXlsxValues(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.files.length > 1000 || archive.files.fold<int>(0, (n, f) => n + f.size) > 50 * 1024 * 1024) {
    throw const FormatException('ملف Excel كبير بعد فك الضغط. قسّمه إلى ملفات أصغر.');
  }
  final styles = archive.findFile('xl/styles.xml');
  final percentageStyles = <int>{};
  XmlDocument? styleDoc;
  if (styles != null) {
    styleDoc = XmlDocument.parse(utf8.decode(styles.content as List<int>));
    final codes = <String, String>{'9': '0%', '10': '0.00%'};
    for (final node in styleDoc.findAllElements('numFmt')) {
      codes[node.getAttribute('numFmtId') ?? ''] = node.getAttribute('formatCode') ?? '';
    }
    final xfs = styleDoc.findAllElements('cellXfs').firstOrNull;
    if (xfs != null) {
      var i = 0;
      for (final xf in xfs.findElements('xf')) {
        if ((codes[xf.getAttribute('numFmtId')] ?? '').contains('%')) { percentageStyles.add(i); }
        i++;
      }
    }
    for (final xf in styleDoc.findAllElements('xf')) { xf.setAttribute('numFmtId', '0'); }
    for (final formats in styleDoc.findAllElements('numFmts').toList()) { formats.parent?.children.remove(formats); }
  }
  // Resolve the original shared-string indices before handing the workbook to
  // excel 4. It deduplicates identical entries but keeps cell indices unchanged.
  // Some editors leave duplicate and unused entries after adding more rows.
  final sharedFile = archive.findFile('xl/sharedStrings.xml');
  final shared = sharedFile == null ? <String>[] : XmlDocument.parse(
    utf8.decode(sharedFile.content as List<int>)).findAllElements('si').map(_xlsxText).toList();
  final output = Archive();
  for (final file in archive.files) {
    if (!file.isFile) { continue; }
    var data = file.content as List<int>;
    if (file.name == 'xl/styles.xml' && styleDoc != null) { data = utf8.encode(styleDoc.toXmlString()); }
    if (file.name.startsWith('xl/worksheets/') && file.name.endsWith('.xml')) {
      final doc = XmlDocument.parse(utf8.decode(data));
      for (final cell in doc.findAllElements('c')) {
        if (cell.getAttribute('t') == 's') {
          final index = int.tryParse(cell.findElements('v').firstOrNull?.innerText ?? '');
          if (index == null || index < 0 || index >= shared.length) {
            throw const FormatException('مرجع نص غير صالح داخل ملف Excel. أعد حفظ الملف بصيغة xlsx.');
          }
          cell.children.clear();
          cell.setAttribute('t', 'inlineStr');
          final prefix = cell.name.prefix;
          cell.children.add(XmlElement(XmlName('is', prefix), [], [XmlElement(
            XmlName('t', prefix), [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
            [XmlText(shared[index])])]));
          continue;
        }
        if (cell.getAttribute('t') != null && cell.getAttribute('t') != 'n') { continue; }
        final value = cell.findElements('v').firstOrNull;
        if (value == null || value.innerText.trim().isEmpty) { continue; }
        var text = value.innerText;
        final parsed = double.tryParse(text);
        if (parsed != null && percentageStyles.contains(int.tryParse(cell.getAttribute('s') ?? ''))) { text = '${parsed * 100}'; }
        cell.children.remove(value);
        cell.setAttribute('t', 'inlineStr');
        final prefix = cell.name.prefix;
        cell.children.add(XmlElement(XmlName('is', prefix), [], [XmlElement(XmlName('t', prefix), [], [XmlText(text)])]));
      }
      data = utf8.encode(doc.toXmlString());
    }
    output.addFile(ArchiveFile(file.name, data.length, data));
  }
  return ZipEncoder().encode(output)!;
}

String _xlsxText(XmlElement item) => item.children.whereType<XmlElement>()
  .expand((node) => node.name.local == 't' ? [node] :
    node.name.local == 'r' ? node.findElements('t') : <XmlElement>[])
  .map((node) => node.innerText).join();
