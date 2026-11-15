import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../http/auth_api.dart';
import 'auth_style.dart';

/// 회원가입 화면. 이메일 인증을 마쳐야 가입할 수 있다.
/// 성공하면 가입한 아이디를 돌려주며 로그인 화면으로 돌아간다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  final _pw2Controller = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _loading = false;
  String? _error;

  // 이메일 인증 상태
  bool _codeSent = false; // 인증번호를 보냈는가 (번호 입력칸 표시)
  bool _sending = false;
  bool _checking = false;
  bool _verified = false; // 인증 완료 (이메일 수정 잠금)
  String? _emailMessage; // 이메일 칸 아래 안내 문구
  bool _emailMessageIsError = false;

  // 인증번호 유효 시간 (5분) 카운트다운
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [
      _idController,
      _pwController,
      _pw2Controller,
      _nameController,
      _emailController,
      _codeController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _emailLooksValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailController.text.trim());

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 300);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
          if (!_verified) {
            _emailMessage = '인증번호가 만료되었습니다. 다시 받아 주세요.';
            _emailMessageIsError = true;
          }
        }
      });
    });
  }

  String get _timeText =>
      '${(_secondsLeft ~/ 60)}:${(_secondsLeft % 60).toString().padLeft(2, '0')}';

  Future<void> _sendCode() async {
    if (!_emailLooksValid) {
      setState(() {
        _emailMessage = '이메일 형식이 올바르지 않습니다.';
        _emailMessageIsError = true;
      });
      return;
    }
    setState(() {
      _sending = true;
      _emailMessage = null;
    });
    final error = await AuthApi.sendEmailCode(_emailController.text.trim());
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error == null) {
        _codeSent = true;
        _codeController.clear();
        _emailMessage = '인증번호를 보냈습니다. 메일함을 확인해 주세요.';
        _emailMessageIsError = false;
      } else {
        _emailMessage = error;
        _emailMessageIsError = true;
      }
    });
    if (error == null) _startTimer();
  }

  Future<void> _checkCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _emailMessage = '인증번호 6자리를 입력하세요.';
        _emailMessageIsError = true;
      });
      return;
    }
    setState(() => _checking = true);
    final error =
        await AuthApi.verifyEmailCode(_emailController.text.trim(), code);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (error == null) {
        _verified = true;
        _timer?.cancel();
        _emailMessage = '✓ 이메일 인증이 완료되었습니다.';
        _emailMessageIsError = false;
      } else {
        _emailMessage = error;
        _emailMessageIsError = true;
      }
    });
  }

  Future<void> _signup() async {
    final id = _idController.text.trim();
    final pw = _pwController.text;
    final pw2 = _pw2Controller.text;
    final name = _nameController.text.trim();

    String? error;
    if (id.isEmpty) {
      error = '아이디를 입력하세요.';
    } else if (pw.length < 4) {
      error = '비밀번호는 4자 이상이어야 합니다.';
    } else if (pw != pw2) {
      error = '비밀번호가 서로 다릅니다.';
    } else if (name.isEmpty) {
      error = '이름을 입력하세요.';
    } else if (!_verified) {
      error = '이메일 인증을 먼저 완료해 주세요.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthApi.signup(
      loginId: id,
      password: pw,
      name: name,
      email: _emailController.text.trim(),
    );
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _loading = false;
        _error = result;
      });
      return;
    }
    Navigator.of(context).pop(id); // 로그인 화면에 아이디를 돌려준다
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AuthStyle.label)),
      );

  Widget _field(String label, Widget input) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_label(label), input],
        ),
      );

  /// 입력칸 오른쪽의 작은 버튼 (인증번호 받기 / 확인)
  Widget _sideButton(String text, VoidCallback? onPressed, {bool busy = false}) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AuthStyle.navy,
          side: const BorderSide(color: AuthStyle.navy),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthStyle.background,
      body: AuthStyle.card(
        maxWidth: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '회원가입',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2B2F36),
              ),
            ),
            const SizedBox(height: 28),
            _field(
              '아이디',
              TextField(
                controller: _idController,
                decoration: AuthStyle.input('사용할 아이디를 입력하세요'),
              ),
            ),
            _field(
              '비밀번호',
              TextField(
                controller: _pwController,
                obscureText: true,
                decoration: AuthStyle.input('비밀번호를 입력하세요'),
              ),
            ),
            _field(
              '비밀번호 확인',
              TextField(
                controller: _pw2Controller,
                obscureText: true,
                decoration: AuthStyle.input('비밀번호를 다시 입력하세요'),
              ),
            ),
            const SizedBox(height: 12),
            _field(
              '이름',
              TextField(
                controller: _nameController,
                decoration: AuthStyle.input('본명을 입력하세요'),
              ),
            ),

            // 이메일 + 인증번호 받기
            _label('이메일'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    enabled: !_verified,
                    keyboardType: TextInputType.emailAddress,
                    decoration: AuthStyle.input('example@email.com'),
                  ),
                ),
                const SizedBox(width: 8),
                _sideButton(
                  _codeSent ? '다시 받기' : '인증번호 받기',
                  _verified || _sending ? null : _sendCode,
                  busy: _sending,
                ),
              ],
            ),

            // 인증번호 입력 + 확인 (보낸 뒤에만)
            if (_codeSent && !_verified) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: AuthStyle.input('인증번호 6자리').copyWith(
                        suffixText: _secondsLeft > 0 ? _timeText : '만료',
                        suffixStyle: TextStyle(
                          color: _secondsLeft > 0 ? Colors.red : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onSubmitted: (_) => _checkCode(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sideButton(
                    '확인',
                    _checking || _secondsLeft <= 0 ? null : _checkCode,
                    busy: _checking,
                  ),
                ],
              ),
            ],
            if (_emailMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _emailMessage!,
                style: TextStyle(
                  fontSize: 13,
                  color: _emailMessageIsError
                      ? Colors.red
                      : Colors.green.shade700,
                ),
              ),
            ],
            const SizedBox(height: 24),

            if (_error != null) ...[
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _loading || !_verified ? null : _signup,
              style: AuthStyle.primaryButton,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('가입하기'),
            ),
            if (!_verified) ...[
              const SizedBox(height: 6),
              const Text('이메일 인증을 마치면 가입할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('이미 계정이 있으신가요? ',
                    style: TextStyle(color: Colors.black54)),
                GestureDetector(
                  onTap: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('로그인하러 가기',
                      style: TextStyle(
                          color: AuthStyle.link,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}