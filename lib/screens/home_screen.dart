import 'package:flutter/material.dart';

import '../core/session.dart';
import '../http/api_service.dart';
import '../http/auth_api.dart';
import '../utils/file_saver.dart';
import 'auth_style.dart';
import 'font_maker_screen.dart';
import 'input_screen.dart';
import 'login_screen.dart';

/// 앱 첫 화면.
/// - 로그인 전: 오른쪽 위 [로그인] 버튼. "시작하기"를 누르면 로그인 화면이 먼저 뜬다.
/// - 로그인 후: 오른쪽 위 "OOO님 ▾" 메뉴 (로그아웃 / 회원 탈퇴), 내 폰트 목록 + 다시 다운로드
/// - 개발자 테스트 화면(InputScreen)은 아래 작은 링크로
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<FontInfo>? _fonts;
  bool _loading = false;
  bool _loadFailed = false;
  int? _downloadingId;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    if (!Session.isLoggedIn) {
      setState(() {
        _fonts = null;
        _loading = false;
        _loadFailed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final fonts = await ApiService.getMyFonts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fonts = fonts;
      _loadFailed = fonts == null;
    });
  }

  /// 로그인 화면을 띄운다. 로그인에 성공하면 true.
  Future<bool> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return false;
    if (ok == true) {
      setState(() {}); // 오른쪽 위를 "OOO님"으로
      _loadFonts();
      return true;
    }
    return false;
  }

  Future<void> _openFontMaker() async {
    // 로그인해야 자모와 폰트가 내 계정에 저장된다
    if (!Session.isLoggedIn) {
      final ok = await _openLogin();
      if (!ok || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FontMakerScreen()),
    );
    // 돌아오면 새로 만든 폰트가 보이게 다시 불러온다
    if (mounted) _loadFonts();
  }

  Future<void> _download(FontInfo font) async {
    setState(() => _downloadingId = font.fontId);
    try {
      final bytes = await ApiService.downloadFont(font.fontId);
      await saveBytesAsFile('${font.fontName}.ttf', bytes);
    } catch (e) {
      _snack('$e');
    }
    if (mounted) setState(() => _downloadingId = null);
  }

  void _logout() {
    Session.logout();
    _loadFonts();
    _snack('로그아웃했습니다.');
  }

  /// 회원 탈퇴: 비밀번호를 한 번 더 받고, 확인하면 계정과 자모·폰트를 모두 지운다.
  Future<void> _withdraw() async {
    final pwController = TextEditingController();
    String? error;
    bool busy = false;

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('회원 탈퇴'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '탈퇴하면 저장한 자모와 만든 폰트가 모두 지워지고 되돌릴 수 없어요.\n'
                  '계속하려면 비밀번호를 입력하세요.',
                  style: TextStyle(color: Colors.black87, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pwController,
                  obscureText: true,
                  autofocus: true,
                  decoration: AuthStyle.input('비밀번호'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  busy ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      final result = await AuthApi.withdraw(pwController.text);
                      if (result == null) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                        return;
                      }
                      setDialogState(() {
                        busy = false;
                        error = result;
                      });
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('탈퇴하기', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    pwController.dispose();

    if (done == true && mounted) {
      Session.logout();
      _loadFonts();
      _snack('회원 탈퇴가 완료되었습니다.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _dateText(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  // ---------------------------------------------------------------- UI

  /// 오른쪽 위: 로그인 전 [로그인] / 로그인 후 "OOO님 ▾" 메뉴
  List<Widget> _appBarActions() {
    if (!Session.isLoggedIn) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ElevatedButton(
            onPressed: _openLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AuthStyle.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('로그인',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ];
    }
    return [
      PopupMenuButton<String>(
        tooltip: '내 계정',
        offset: const Offset(0, 48),
        onSelected: (v) {
          if (v == 'logout') _logout();
          if (v == 'withdraw') _withdraw();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'logout', child: Text('로그아웃')),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'withdraw',
            child: Text('회원 탈퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: AuthStyle.navy),
              const SizedBox(width: 6),
              Text('${Session.userName ?? ''}님',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AuthStyle.label)),
              const Icon(Icons.arrow_drop_down, color: AuthStyle.label),
            ],
          ),
        ),
      ),
      const SizedBox(width: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthStyle.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AuthStyle.navy,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: const Text('손글씨 폰트',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: _appBarActions(),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _makeCard(),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Text('내 폰트',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AuthStyle.label)),
                    const Spacer(),
                    if (Session.isLoggedIn)
                      IconButton(
                        tooltip: '새로고침',
                        onPressed: _loading ? null : _loadFonts,
                        icon: const Icon(Icons.refresh, color: AuthStyle.navy),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _fontList(),
                const SizedBox(height: 40),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InputScreen()),
                    ),
                    child: const Text('개발자 테스트 화면',
                        style: TextStyle(color: Colors.black38, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 위쪽 큰 카드: 폰트 만들기
  Widget _makeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.draw_outlined, size: 44, color: AuthStyle.navy),
          const SizedBox(height: 14),
          const Text('내 손글씨로 폰트 만들기',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AuthStyle.navy)),
          const SizedBox(height: 10),
          const Text(
            '자음 14개, 모음 12개를 쓰면\n11,172자 한글 TTF 폰트를 만들어 드려요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _openFontMaker,
            style: AuthStyle.primaryButton,
            child: const Text('시작하기'),
          ),
        ],
      ),
    );
  }

  Widget _fontList() {
    if (!Session.isLoggedIn) {
      return _EmptyBox(
        text: '로그인하면 내가 만든 폰트를 볼 수 있어요.',
        actionText: '로그인',
        onAction: _openLogin,
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return const _EmptyBox(text: '폰트 목록을 불러오지 못했습니다.');
    }
    final fonts = _fonts ?? [];
    if (fonts.isEmpty) {
      return const _EmptyBox(text: '아직 만든 폰트가 없어요.');
    }
    return Column(
      children: fonts.map((f) {
        final busy = _downloadingId == f.fontId;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AuthStyle.border),
          ),
          child: ListTile(
            leading: const Icon(Icons.font_download_outlined,
                color: AuthStyle.navy),
            title: Text(f.fontName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              [
                _dateText(f.createdAt),
                if (f.glyphCount != null) '글자 ${f.glyphCount}개',
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
            trailing: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: '다운로드',
                    icon: const Icon(Icons.download, color: AuthStyle.link),
                    onPressed:
                        _downloadingId == null ? () => _download(f) : null,
                  ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;

  const _EmptyBox({required this.text, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AuthStyle.border),
      ),
      child: Column(
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black45)),
          if (actionText != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              child: Text(actionText!,
                  style: const TextStyle(
                      color: AuthStyle.link, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}