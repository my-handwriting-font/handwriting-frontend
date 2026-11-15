import 'package:flutter/material.dart';

/// 로그인 / 회원가입 / 홈 화면 공통 스타일
class AuthStyle {
  static const Color navy = Color(0xFF343E4F);
  static const Color link = Color(0xFF4A86D4);
  static const Color background = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFD9DCE1);
  static const Color label = Color(0xFF3A3F47);

  static InputDecoration input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8A9099)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: navy, width: 1.4),
        ),
        counterText: '',
      );

  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: navy,
    foregroundColor: Colors.white,
    disabledBackgroundColor: navy.withOpacity(0.5),
    minimumSize: const Size.fromHeight(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  );

  /// 가운데 흰 카드
  static Widget card({required Widget child, double maxWidth = 420}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, 4)),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}