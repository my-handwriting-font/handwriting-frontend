import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../core/session.dart';

/// 회원가입 / 로그인 / 이메일 인증 / 탈퇴 API (Spring /api/user)
class AuthApi {
  static const String baseUrl = '${ApiConfig.springBaseUrl}/user';

  /// 이메일로 인증번호 보내기. 성공하면 null, 실패하면 문구.
  static Future<String?> sendEmailCode(String email) =>
      _post('/email/send', {'email': email}, '인증번호를 보내지 못했습니다');

  /// 인증번호 확인. 성공하면 null, 실패하면 문구.
  static Future<String?> verifyEmailCode(String email, String code) =>
      _post('/email/verify', {'email': email, 'code': code}, '인증에 실패했습니다');

  /// 회원가입 (이메일 인증을 마친 뒤). 성공하면 null, 실패하면 문구.
  static Future<String?> signup({
    required String loginId,
    required String password,
    required String name,
    required String email,
  }) =>
      _post(
        '/signup',
        {
          'loginId': loginId,
          'password': password,
          'name': name,
          'email': email,
        },
        '회원가입에 실패했습니다',
      );

  /// 회원 탈퇴 (비밀번호 확인). 성공하면 null, 실패하면 문구.
  static Future<String?> withdraw(String password) async {
    if (Session.userId == null) return '로그인 상태가 아닙니다.';
    return _post(
      '/withdraw',
      {'userId': Session.userId, 'password': password},
      '탈퇴에 실패했습니다',
    );
  }

  /// 로그인. 성공하면 Session에 사용자 정보를 넣고 null, 실패하면 문구를 돌려준다.
  static Future<String?> login({
    required String loginId,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'loginId': loginId, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        Session.login(
          (data['userId'] as num).toInt(),
          (data['userName'] ?? '') as String,
        );
        return null;
      }
      return _message(response) ?? '로그인에 실패했습니다 (${response.statusCode}).';
    } catch (e) {
      return '서버에 연결하지 못했습니다.';
    }
  }

  /// POST 공통: 200이면 null, 아니면 서버 message (없으면 기본 문구)
  static Future<String?> _post(
    String path,
    Map<String, dynamic> body,
    String fallback,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) return null;
      return _message(response) ?? '$fallback (${response.statusCode}).';
    } catch (e) {
      return '서버에 연결하지 못했습니다.';
    }
  }

  static String? _message(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data['message'] is String) return data['message'] as String;
    } catch (_) {}
    return null;
  }
}