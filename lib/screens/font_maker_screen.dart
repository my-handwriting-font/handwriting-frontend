import 'package:flutter/material.dart';

import '../http/api_service.dart';
import '../models/handwriting_model.dart';
import '../services/font_glyph_builder.dart' show kFontInputJamo;
import '../utils/file_saver.dart';
import '../widgets/drawing_canvas.dart';

/// 폰트 만들기 화면.
///
/// 0) 화면을 열면 예전에 저장한 자모(26개 세트)를 DB에서 불러온다.
/// 1) 자모 26개(자음 14 + 모음 12)를 하나씩 쓴다.
///    "검증하고 추가"를 누르면 Spring(/verify)이 CNN 인식 결과와 코사인 유사도를
///    교차 검증한다 (인식 글자 == 쓰려던 글자 AND 유사도 >= 기준값).
///    통과하면 이 화면에만 추가된다 (아직 DB에 저장하지 않는다). 통과 못 하면 이유를 보여 주고 다시 쓰게 한다.
/// 2) 26개가 모두 추가되면 "저장"과 "TTF 만들기" 버튼이 켜진다.
///    "저장"을 눌러야 26개가 한꺼번에 DB에 저장된다. 다 쓰지 않고 나가면 아무것도 저장되지 않는다.
/// 3) "TTF 만들기"를 누르면 (저장 안 했으면 먼저 저장하고) Spring(/api/font/make)에 요청한다.
///    서버가 DB의 자모 26개로 11,172자 + 낱자모 51자를 1~6번 규칙으로 배치하고(FastAPI)
///    TTF를 만들어 내 폰트에 저장한다. 이 화면은 만들어진 TTF를 받아서 다운로드만 한다.
class FontMakerScreen extends StatefulWidget {
  const FontMakerScreen({super.key});

  @override
  State<FontMakerScreen> createState() => _FontMakerScreenState();
}

enum _Phase { idle, building, done }

class _FontMakerScreenState extends State<FontMakerScreen> {
  final GlobalKey<DrawingCanvasState> _canvasKey =
      GlobalKey<DrawingCanvasState>();
  final TextEditingController _nameController =
      TextEditingController(text: '내손글씨');

  final double canvasSize = 300.0;

  /// 검증을 통과한 자모 → 원본 좌표
  final Map<String, List<StrokeData>> _passed = {};

  String _current = kFontInputJamo.first;
  bool _verifying = false;

  /// DB에 저장된 자모를 불러오는 중인가 (화면을 열 때 한 번)
  bool _loadingSaved = true;

  /// 마지막 저장(또는 불러오기) 이후 새로 통과한 자모가 있는가
  bool _dirty = false;

  /// 26개 저장 중
  bool _saving = false;

  /// 마지막 검증 결과 문구 (성공/실패 이유)
  String? _message;
  bool _messageIsError = false;

  // 폰트 만들기 진행 상태
  _Phase _phase = _Phase.idle;
  double _strokeWidth = 60;

  bool get _allPassed => kFontInputJamo.every(_passed.containsKey);
  bool get _busy => _saving || _phase == _Phase.building;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 저장된 자모 불러오기

  /// 예전에 저장한 자모를 불러온다.
  /// 불러온 자모는 ✓ 상태가 되어 다시 쓰지 않아도 된다.
  Future<void> _loadSaved() async {
    final saved = await ApiService.getSavedJamo();
    if (!mounted) return;
    setState(() {
      _loadingSaved = false;
      if (saved == null) {
        _message = '저장된 자모를 불러오지 못했습니다. 처음부터 써 주세요.';
        _messageIsError = true;
        return;
      }
      for (final j in kFontInputJamo) {
        final strokes = saved[j];
        if (strokes != null && strokes.isNotEmpty) _passed[j] = strokes;
      }
      if (_passed.isNotEmpty) {
        _message = '저장된 자모 ${_passed.length}개를 불러왔습니다.';
        _messageIsError = false;
      }
      // 아직 안 쓴 첫 자모부터 시작 (다 있으면 그대로)
      _current = kFontInputJamo.firstWhere(
        (j) => !_passed.containsKey(j),
        orElse: () => _current,
      );
    });
  }

  // ---------------------------------------------------------------- 자모 입력

  void _select(String jamo) {
    if (_verifying || _busy) return;
    setState(() {
      _current = jamo;
      _message = null;
    });
    _canvasKey.currentState?.clearPoints();
    // 이미 추가한 자모면 그 글씨를 보여 준다 (다시 쓰려면 지우고 새로 쓴다)
    final saved = _passed[jamo];
    if (saved != null) _canvasKey.currentState?.loadStrokes(saved);
  }

  String? _nextMissing() {
    final start = kFontInputJamo.indexOf(_current);
    for (var k = 1; k <= kFontInputJamo.length; k++) {
      final j = kFontInputJamo[(start + k) % kFontInputJamo.length];
      if (!_passed.containsKey(j)) return j;
    }
    return null;
  }

  Future<void> _verifyAndAdd() async {
    final strokes = _canvasKey.currentState?.getValidPoints() ?? [];
    if (strokes.isEmpty) {
      _showSnack('먼저 $_current을(를) 써 주세요.');
      return;
    }

    setState(() {
      _verifying = true;
      _message = null;
    });

    // CNN + 코사인 유사도 교차 검증 (Spring /verify → FastAPI /predict). 저장은 하지 않는다.
    final passed = await ApiService.verifyRawCoordinates(_current, strokes);

    if (!mounted) return;

    if (passed == null) {
      setState(() {
        _verifying = false;
        _message = '서버에 연결하지 못했습니다. Spring/FastAPI 서버를 확인해 주세요.';
        _messageIsError = true;
      });
      return;
    }

    if (passed) {
      final jamo = _current;
      final next = _nextMissing();
      setState(() {
        _passed[jamo] = strokes;
        _dirty = true;
        _verifying = false;
        _message = '✓ $jamo 통과 — 추가했습니다.';
        _messageIsError = false;
        if (next != null && next != jamo) _current = next;
      });
      _canvasKey.currentState?.clearPoints();
      if (_allPassed) {
        _showSnack('🎉 26개를 모두 추가했습니다. "저장"을 눌러 저장하세요.');
      }
      return;
    }

    // 통과 못 함: 이유를 보여 주기 위해 FastAPI 결과를 한 번 더 받아 온다
    final detail = await ApiService.checkBadWriting(_current, strokes);
    if (!mounted) return;

    setState(() {
      _verifying = false;
      _message = '✗ $_current 통과 못 함 — 다시 써 주세요.\n${_failReason(detail)}';
      _messageIsError = true;
    });
    _canvasKey.currentState?.clearPoints();
  }

  String _failReason(Map<String, dynamic>? d) {
    if (d == null) return '(자세한 이유를 받아오지 못했습니다)';
    if (d['error'] != null) return '서버 메시지: ${d['error']}';
    final predicted = d['predictedChar'];
    final similarity = (d['similarity'] as num?)?.toDouble();
    final confidence = (d['confidence'] as num?)?.toDouble();
    final parts = <String>[];
    if (predicted != null) {
      parts.add(predicted == _current
          ? '인식 결과: $predicted (일치)'
          : '인식 결과: $predicted (쓰려던 글자 $_current와 다름)');
    }
    if (confidence != null) {
      parts.add('확신도 ${confidence.toStringAsFixed(1)}%');
    }
    if (similarity != null) {
      parts.add('유사도 ${similarity.toStringAsFixed(3)} (기준 0.6 이상)');
    }
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  void _clearCanvas() {
    _canvasKey.currentState?.clearPoints();
    setState(() => _message = null);
  }

  // ---------------------------------------------------------------- 저장

  /// 26개를 한꺼번에 DB에 저장한다 (다 채웠을 때만). 성공하면 true.
  Future<bool> _saveAll() async {
    if (!_allPassed || _busy) return false;
    setState(() {
      _saving = true;
      _message = null;
    });
    final error = await ApiService.saveAllJamo(_passed);
    if (!mounted) return false;
    setState(() {
      _saving = false;
      if (error == null) {
        _dirty = false;
        _message = '✓ 자모 ${_passed.length}개를 저장했습니다.';
        _messageIsError = false;
      } else {
        _message = '✗ 저장 실패: $error';
        _messageIsError = true;
      }
    });
    return error == null;
  }

  /// 뒤로 가기 전에: 저장하지 않은 자모가 있으면 한 번 물어본다
  Future<bool> _confirmLeave() async {
    if (_busy) return false; // 저장/폰트 만들기 중에는 나가지 않는다
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('저장하지 않고 나갈까요?'),
        content: Text(
          _allPassed
              ? '아직 "저장"을 누르지 않았어요.\n나가면 이번에 쓴 자모는 저장되지 않아요.'
              : '자모 26개를 모두 써야 저장할 수 있어요.\n나가면 이번에 쓴 자모는 저장되지 않아요.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속 쓰기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ---------------------------------------------------------------- 폰트 만들기

  Future<void> _makeFont() async {
    if (!_allPassed || _busy) return;

    final fontName = _nameController.text.trim().isEmpty
        ? '내손글씨'
        : _nameController.text.trim();

    // 서버는 DB에 저장된 자모로 만들기 때문에, 저장 안 한 게 있으면 먼저 저장한다
    if (_dirty) {
      final ok = await _saveAll();
      if (!ok || !mounted) return;
    }

    setState(() {
      _phase = _Phase.building;
      _message = null;
    });

    try {
      // 1) 서버에서 배치 + TTF 만들기 + 내 폰트에 저장
      final made = await ApiService.makeFontOnServer(
        fontName: fontName,
        strokeWidth: _strokeWidth,
      );
      if (!mounted) return;

      // 2) 만든 TTF 받아서 다운로드
      final ttf = await ApiService.downloadFont(made.fontId);
      final filename = '$fontName.ttf';
      final saved = await saveBytesAsFile(filename, ttf);
      if (!mounted) return;

      setState(() {
        _phase = _Phase.done;
        _message = saved
            ? '✓ $filename 다운로드 완료 (${(ttf.length / 1024 / 1024).toStringAsFixed(1)}MB'
                '${made.glyphCount != null ? ', 글자 ${made.glyphCount}개' : ''})\n'
                '✓ 내 폰트에 저장했습니다'
            : '✓ 내 폰트에 저장했습니다 (이 플랫폼에서는 다운로드를 지원하지 않습니다)';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _message = '✗ 폰트 만들기 실패: $e';
        _messageIsError = true;
      });
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------- UI

  Widget _jamoChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: kFontInputJamo.map((j) {
        final ok = _passed.containsKey(j);
        return ChoiceChip(
          label: Text(ok ? '$j ✓' : j, style: const TextStyle(fontSize: 18)),
          selected: j == _current,
          backgroundColor: ok ? Colors.green.withOpacity(0.15) : null,
          onSelected: (_) => _select(j),
        );
      }).toList(),
    );
  }

  Widget _statusText() {
    if (_phase != _Phase.building) return const SizedBox.shrink();
    return const Text('서버에서 11,172자 배치 + TTF 만드는 중... (30초~1분 정도 걸릴 수 있어요)',
        style: TextStyle(fontWeight: FontWeight.bold));
  }

  @override
  Widget build(BuildContext context) {
    final count = _passed.length;
    final already = _passed.containsKey(_current);

    // 뒤로 가기 전에 저장 안 한 자모가 있으면 물어본다
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        appBar: AppBar(title: const Text('폰트 만들기')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            children: [
              // 진행 상황
              Text('자모 $count / ${kFontInputJamo.length}',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SizedBox(
                width: 420,
                child: LinearProgressIndicator(
                  value: count / kFontInputJamo.length,
                  minHeight: 8,
                ),
              ),
              if (_loadingSaved) ...[
                const SizedBox(height: 6),
                const Text('저장된 자모 불러오는 중...',
                    style: TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 16),
              _jamoChips(),
              const SizedBox(height: 20),

              // 쓰기
              Text(
                already
                    ? '$_current — 이미 추가됨 (다시 쓰려면 지우고 새로 쓴 뒤 검증하세요)'
                    : '$_current 을(를) 써 주세요',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DrawingCanvas(key: _canvasKey, size: canvasSize),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _verifying || _busy ? null : _verifyAndAdd,
                    icon: _verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: Text(_verifying ? '검증 중...' : '검증하고 추가'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(150, 45),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _verifying || _busy ? null : _clearCanvas,
                    child: const Text('지우기'),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _messageIsError ? Colors.red : Colors.green.shade700,
                  ),
                ),
              ],

              const Divider(height: 40),

              // 저장 / TTF 만들기
              SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: '폰트 이름',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('획 두께: ${_strokeWidth.round()} (글자 한 칸 = 1000)',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Slider(
                      value: _strokeWidth,
                      min: 30,
                      max: 120,
                      divisions: 18,
                      label: '${_strokeWidth.round()}',
                      onChanged:
                          _busy ? null : (v) => setState(() => _strokeWidth = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _allPassed && !_busy ? _saveAll : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? '저장 중...' : '저장'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 50),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _allPassed && !_busy ? _makeFont : null,
                    icon: const Icon(Icons.font_download),
                    label: const Text('TTF 만들기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 50),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (!_allPassed) ...[
                const SizedBox(height: 6),
                Text(
                    '자모 26개를 모두 추가하면 저장 / TTF 만들기가 켜집니다 (남은 자모 ${kFontInputJamo.length - count}개)',
                    style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 12),
              if (_phase == _Phase.building)
                const SizedBox(width: 420, child: LinearProgressIndicator()),
              const SizedBox(height: 6),
              _statusText(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}