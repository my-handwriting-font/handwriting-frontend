/// 로그인한 사용자 정보 (앱이 켜져 있는 동안만 기억한다).
/// 웹에서 새로고침하면 사라지므로 다시 로그인하면 된다.
class Session {
  static int? userId;
  static String? userName;

  static bool get isLoggedIn => userId != null;

  static void login(int id, String name) {
    userId = id;
    userName = name;
  }

  static void logout() {
    userId = null;
    userName = null;
  }
}