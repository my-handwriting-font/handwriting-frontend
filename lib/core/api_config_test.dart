// lib/core/api_config_test.dart
// 이 파일을 api_config.dart로 복사한 뒤 서버 IP를 입력하세요.
class ApiConfig {
  static const String host = 'YOUR_SERVER_IP'; // 서버(노트북) IP

  static const String springPort = '8080';
  static const String fastApiPort = '8000';

  // Spring (/api 이하)
  static const String springBaseUrl = 'http://$host:$springPort/api';

  // FastAPI
  static const String fastApiBaseUrl = 'http://$host:$fastApiPort';
}