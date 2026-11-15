import 'dart:typed_data';

/// 웹이 아닌 플랫폼: 아직 지원하지 않는다.
Future<bool> saveBytesAsFile(String filename, Uint8List bytes) async => false;