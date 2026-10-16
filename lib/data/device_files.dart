import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

// Android's document provider handles Drive authentication and upload/download.
// The user chooses the provider and destination; no broad Google account access.
class DeviceFiles {
  static Future<bool> save(List<int> bytes, String name) async {
    final extension = name.split('.').last;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر Google Drive أو مكان الحفظ', fileName: name,
      type: FileType.custom, allowedExtensions: [extension],
      bytes: Uint8List.fromList(bytes));
    return result != null;
  }
}
