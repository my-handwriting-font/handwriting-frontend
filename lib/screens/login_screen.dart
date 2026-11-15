import 'package:flutter/material.dart';

import '../http/auth_api.dart';
import 'auth_style.dart';
import 'signup_screen.dart';

/// 로그인 화면. 홈 오른쪽 위 [로그인]으로 열리고, 로그인하면 true를 돌려주며 닫힌다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final id = _idController.text.trim();
    final pw = _pwController.text;
    if (id.isEmpty || pw.isEmpty) {
      setState(() => _error = '아이디와 비밀번호를 입력하세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await AuthApi.login(loginId: id, password: pw);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true); // 홈으로 돌아가며 로그인 성공을 알린다
  }

  Future<void> _goSignup() async {
    // 회원가입에 성공하면 가입한 아이디를 돌려받아 채워 준다
    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
    if (newId != null && mounted) {
      setState(() {
        _idController.text = newId;
        _pwController.clear();
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canClose = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AuthStyle.background,
      body: AuthStyle.card(
        maxWidth: 400,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'LOGIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AuthStyle.navy,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _idController,
                  decoration: AuthStyle.input('아이디'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pwController,
                  decoration: AuthStyle.input('비밀번호'),
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: AuthStyle.primaryButton,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('로그인'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _goSignup,
                    child: const Text(
                      '회원가입 하기',
                      style: TextStyle(
                          color: AuthStyle.link, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            if (canClose)
              Positioned(
                top: -8,
                right: -8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}