/// 바이트를 파일로 저장(다운로드)한다.
/// 웹에서는 브라우저 다운로드, 그 밖의 플랫폼에서는 아직 지원하지 않는다(false).
export 'file_saver_stub.dart' if (dart.library.html) 'file_saver_web.dart';