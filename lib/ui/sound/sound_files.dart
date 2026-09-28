import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Lets the user pick one file with one of [extensions] and returns a local path to it.
/// Content-URI results (Android) are copied into the temporary directory first.
Future<String?> pickLocalFile(List<String> extensions) async {
  PlatformFile? file;
  try {
    file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
  } on PlatformException {
    // Some pickers reject custom extension filters (unknown MIME type): fall back to any.
    file = await FilePicker.pickFile();
  }
  if (file == null) return null;
  final direct = file.path;
  if (direct != null && File(direct).existsSync()) return direct;
  final dir = await getTemporaryDirectory();
  final safe = file.name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
  final out = File(p.join(dir.path, 'import_${DateTime.now().millisecondsSinceEpoch}_$safe'));
  await out.writeAsBytes(await file.readAsBytes(), flush: true);
  return out.path;
}

/// Opens the system share sheet for a local file.
Future<void> shareLocalFile(BuildContext context, String path, {String? subject}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path)], subject: subject ?? p.basename(path), sharePositionOrigin: origin),
  );
}
