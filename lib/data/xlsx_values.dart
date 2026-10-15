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
  final output = Archive();
  for (final file in archive.files) {
    if (!file.isFile) { continue; }
    var data = file.content as List<int>;
    if (file.name == 'xl/styles.xml' && styleDoc != null) { data = utf8.encode(styleDoc.toXmlString()); }
    if (file.name.startsWith('xl/worksheets/') && file.name.endsWith('.xml')) {
      final doc = XmlDocument.parse(utf8.decode(data));
      for (final cell in doc.findAllElements('c')) {
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
