// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// 웹: 브라우저 다운로드로 저장한다.
Future<bool> saveBytesAsFile(String filename, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  // 다운로드가 시작될 시간을 준 뒤 정리
  Future<void>.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}