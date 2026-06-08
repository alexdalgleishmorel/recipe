import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Trigger a browser download of [text] as a file named [filename] with the
/// given [mimeType]. Builds a Blob, wires it to a temporary anchor, clicks it,
/// then revokes the object URL. Web-only (the upload screen is web-first).
void downloadText(
  String text,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  final bytes = utf8.encode(text).toJS;
  final blob = web.Blob(
    [bytes].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Open [url] in a new browser tab.
void openUrl(String url) {
  web.window.open(url, '_blank');
}
