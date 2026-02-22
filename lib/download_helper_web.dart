// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

bool downloadBytes({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) {
  try {
    final blob = html.Blob([bytes], mimeType);
    final downloadUrl = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: downloadUrl)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(downloadUrl);
    return true;
  } catch (_) {
    return false;
  }
}
