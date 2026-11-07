import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> savePrivateFile(Uint8List bytes, String name) async {
  final path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
  if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await File(path).writeAsBytes(bytes);
  }
}
