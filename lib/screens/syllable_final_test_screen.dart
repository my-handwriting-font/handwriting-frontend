import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart' show ComposeBox;
import '../services/syllable_composer.dart';
import '../widgets/drawing_canvas.dart';

/// 세로형 + 받침 있음 (2번 틀: 각, 닭, 간 ...) 합성 테스트 화면.
///
/// 초성+중성은 1번(세로형 받침 없음)의 케이스별 규칙값(kVerticalRuleParams)을
/// 그대로 써서 합성하고, 그 결과를 위쪽 박스에 넣는다. 종성은 아래 박스에 넣는다.
/// 1번의 gap 등은 여기서 바꾸지 않는다 (1번 화면에서 맞춘 값 그대로).
/// 이 화면의 슬라이더는 위/아래 박스의 크기와 위치, 종성 모양만 조절한다.
/// 받침 박스 값은 syllable_composer.dart의 kVerticalFinalRuleParams(2번 규칙)에서
/// 케이스별로 가져오고, 슬라이더로 바꾼 값은 케이스별로 따로 보관한다.
///
/// 초성과 종성이 같은 글자(예: 각)면 한 번만 쓰고, 종성은 초성 글씨를 그대로 쓴다.
///
/// 서버 저장 없이 프론트에서만 계산한다.
class SyllableFinalTestScreen extends StatefulWidget {
  const SyllableFinalTestScreen({super.key});

  @override
  State<SyllableFinalTestScreen> createState() =>
      _SyllableFinalTestScreenState();
}

class _FinalLayout {
  final ComposeBox upper;
  final ComposeBox jong;
  const _FinalLayout(this.upper, this.jong);
}

/// 완성형 글자의 종성 순서 (유니코드 한글 음절 계산용)
const List<String> _kJongseongOrder = [
  '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ',
  'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ',
  'ㅍ', 'ㅎ',
];

/// 이 화면에서 쓰는 세로 모음 (ㅏ ㅐ ㅑ ㅓ ㅔ ㅕ ㅣ)
final List<String> _kVerticalVowels = kVowelChoices
    .where((v) => orientationOf(v) == VowelOrientation.vertical)
    .toList();

class _SyllableFinalTestScreenState extends State<SyllableFinalTestScreen> {
  final GlobalKey<DrawingCanvasState> _choKey = GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _vowelKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _jongKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _resultKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 240.0;

  String _cho = 'ㄱ';
  String _vowel = 'ㅏ';
  String _jong = 'ㄱ';

  double _previewScale = 0.6; // 결과 캔버스 표시 전용 축소
  bool _showGuide = true;

  // 케이스별 받침 박스 값. 슬라이더를 건드린 케이스만 들어 있다 (1번 화면과 같은 방식).
  final Map<int, FinalBoxParams> _caseFinal = {};

  int get _caseId => caseIdOf(_cho, _vowel);

  // 슬라이더로 바꾼 값 > 2번 규칙값(kVerticalFinalRuleParams) > 클래스 기본값
  FinalBoxParams get _fp =>
      _caseFinal[_caseId] ??
      finalRuleParamsOf(_cho, _vowel) ??
      const FinalBoxParams();

  // 2번 규칙값이 있고, 현재 값이 규칙값과 같은가
  bool get _finalRuleMatched {
    final rule = finalRuleParamsOf(_cho, _vowel);
    return rule != null && rule.toDisplayString() == _fp.toDisplayString();
  }

  NormalizedJamo? _choNorm;
  NormalizedJamo? _vowelNorm;
  NormalizedJamo? _jongNorm;

  // 초성과 종성이 같은 글자(예: 각의 ㄱ)면 한 번만 쓰고 종성은 초성 글씨를 그대로 쓴다.
  bool get _sameJamo => _cho == _jong;

  // 실제로 종성 박스에 넣을 자모
  NormalizedJamo? get _jongSource => _sameJamo ? _choNorm : _jongNorm;

  bool get _isReady =>
      _choNorm != null && _vowelNorm != null && _jongSource != null;

  // 초성+중성은 1번 화면에서 맞춘 규칙값 그대로 (없으면 세로형 시작값).
  SyllableParams get _upperParams =>
      ruleParamsOf(_cho, _vowel) ??
      SyllableParams.defaultsFor(VowelOrientation.vertical);

  // ---------------------------------------------------------------- 계산

  _FinalLayout _layout() {
    final total = _fp.upperHeight + _fp.gap + _fp.jongHeight;
    final top = (1 - total) / 2;
    final upper = ComposeBox(
      x: (1 - _fp.upperWidth) / 2,
      y: top,
      w: _fp.upperWidth,
      h: _fp.upperHeight,
    );
    final jong = ComposeBox(
      x: 0.5 + _fp.jongOffsetX - _fp.jongWidth / 2,
      y: top + _fp.upperHeight + _fp.gap,
      w: _fp.jongWidth,
      h: _fp.jongHeight,
    );
    return _FinalLayout(upper, jong);
  }

  // 0~1 공간의 획을 박스 안으로 선형 매핑
  List<StrokeData> _mapInto(List<StrokeData> src, ComposeBox box) {
    return src.map((s) {
      return StrokeData(
        points: s.points
            .map((p) => PointData(
                  x: box.x + p.x * box.w,
                  y: box.y + p.y * box.h,
                  pressure: p.pressure,
                ))
            .toList(),
      );
    }).toList();
  }

  List<StrokeData> _composeAll() {
    // 1번(받침 없음) 합성 결과: 0~1 한 칸 안에 자음/모음이 배치된 상태
    final upperCell = SyllableComposer.composeFit(
      consonant: _choNorm!,
      vowel: _vowelNorm!,
      params: _upperParams,
      orientation: VowelOrientation.vertical,
    );
    final lay = _layout();
    final upper = _mapInto(upperCell, lay.upper);
    final jong =
        SyllableComposer.remapFit(_jongSource!, lay.jong, _fp.jongAspectKeep);
    return [...upper, ...jong];
  }

  double _toCanvas(double v) => (0.5 + (v - 0.5) * _previewScale) * canvasSize;

  List<StrokeData> _toCanvasStrokes(List<StrokeData> strokes) {
    return strokes.map((s) {
      return StrokeData(
        points: s.points
            .map((p) => PointData(
                  x: _toCanvas(p.x),
                  y: _toCanvas(p.y),
                  pressure: p.pressure,
                ))
            .toList(),
      );
    }).toList();
  }

  void _redraw() {
    if (!_isReady) return;
    _resultKey.currentState?.loadStrokes(_toCanvasStrokes(_composeAll()));
  }

  void _combine() {
    final c = _choKey.currentState?.getValidPoints() ?? [];
    final v = _vowelKey.currentState?.getValidPoints() ?? [];
    // 같은 글자면 종성 캔버스가 없으므로 검사하지 않는다.
    final j = _sameJamo
        ? <StrokeData>[]
        : (_jongKey.currentState?.getValidPoints() ?? []);

    final missing = <String>[
      if (c.isEmpty) '초성($_cho)',
      if (v.isEmpty) '모음($_vowel)',
      if (!_sameJamo && j.isEmpty) '종성($_jong)',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${missing.join(', ')}을(를) 먼저 써주세요.')),
      );
      return;
    }

    setState(() {
      _choNorm = SyllableComposer.normalizeWithAspect(c);
      _vowelNorm = SyllableComposer.normalizeWithAspect(v);
      _jongNorm = _sameJamo ? null : SyllableComposer.normalizeWithAspect(j);
    });
    _redraw();
  }

  // 현재 케이스의 받침 박스 값을 바꾼다.
  void _updateFinal(FinalBoxParams p) {
    setState(() => _caseFinal[_caseId] = p);
    _redraw();
  }

  void _clearAll() {
    _choKey.currentState?.clearPoints();
    _vowelKey.currentState?.clearPoints();
    _jongKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _choNorm = null;
      _vowelNorm = null;
      _jongNorm = null;
    });
  }

  void _selectCho(String c) {
    if (c == _cho) return;
    _choKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      // 종성이 초성과 같았으면(같이 쓰던 중이면) 종성도 새 초성을 따라간다.
      // 종성을 따로 골라 둔 상태면 그대로 둔다.
      if (_sameJamo) {
        _jong = c;
        _jongNorm = null;
      }
      _cho = c;
      _choNorm = null;
    });
  }

  void _selectVowel(String v) {
    if (v == _vowel) return;
    _vowelKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _vowel = v;
      _vowelNorm = null;
    });
  }

  void _selectJong(String j) {
    if (j == _jong) return;
    _jongKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _jong = j;
      _jongNorm = null;
    });
  }

  Future<void> _copyParams() async {
    final text = '${caseLabelOf(_cho, _vowel)}  $_cho+$_vowel+$_jong\n'
        'preview=${_previewScale.toStringAsFixed(2)}\n'
        '[1번 규칙값] ${_upperParams.toDisplayString()}\n'
        '[2번 받침 박스] ${_fp.toDisplayString()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 파라미터를 복사했습니다.')),
    );
  }

  // 참고용 폰트 글자 (초성+중성+종성 완성형)
  String _referenceText() {
    final base = syllableOf(_cho, _vowel);
    final ji = _kJongseongOrder.indexOf(_jong);
    if (base == null || ji < 0) return '?';
    return String.fromCharCode(base.codeUnitAt(0) + ji);
  }

  // ---------------------------------------------------------------- UI 조각

  Widget _chips(List<String> items, String selected, ValueChanged<String> on) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: items
          .map((s) => ChoiceChip(
                label: Text(s, style: const TextStyle(fontSize: 16)),
                selected: s == selected,
                onSelected: (_) => on(s),
              ))
          .toList(),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(3)}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(3),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _canvasColumn(String title, Color color, Widget child) {
    return Column(
      children: [
        Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // 박스 가이드: 초성(파랑)·모음(빨강)은 1번 레이아웃을 위쪽 박스로 옮긴 것,
  // 종성(초록)은 아래 박스.
  Widget _resultCanvas() {
    final lay = _layout();
    final inner = SyllableComposer.computeLayout(
        _upperParams, VowelOrientation.vertical);

    ComposeBox toUpper(ComposeBox b) => ComposeBox(
          x: lay.upper.x + b.x * lay.upper.w,
          y: lay.upper.y + b.y * lay.upper.h,
          w: b.w * lay.upper.w,
          h: b.h * lay.upper.h,
        );

    return Stack(
      children: [
        DrawingCanvas(key: _resultKey, size: canvasSize, readOnly: true),
        if (_showGuide)
          Positioned(
            left: 2,
            top: 2,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(canvasSize, canvasSize),
                painter: _GuidePainter(
                  boxes: [
                    MapEntry(toUpper(inner.consonantBox), Colors.blue),
                    MapEntry(toUpper(inner.vowelBox), Colors.red),
                    MapEntry(lay.jong, Colors.green),
                  ],
                  canvasSize: canvasSize,
                  previewScale: _previewScale,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 종성 칸: 초성과 같은 글자면 캔버스 대신 안내만 보여준다.
  Widget _jongInput() {
    if (!_sameJamo) {
      return DrawingCanvas(key: _jongKey, size: canvasSize);
    }
    return Container(
      width: canvasSize,
      height: canvasSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 2),
        color: Colors.grey.withOpacity(0.08),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        '초성과 같은 글자($_jong)\n① 초성 글씨를 그대로 씁니다.\n'
        '(다른 종성을 쓰려면 종성 칩에서 다른 글자를 고르세요)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }

  Widget _referenceGlyph() {
    return Container(
      width: canvasSize,
      height: canvasSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 2),
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: Text(_referenceText(), style: const TextStyle(fontSize: 120)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = _upperParams;
    final matched = ruleParamsOf(_cho, _vowel) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('세로형 받침 있음 합성 테스트 (2번)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('초성 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _cho, _selectCho),
            const SizedBox(height: 14),
            const Text('모음 선택 (세로 모음만)',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(_kVerticalVowels, _vowel, _selectVowel),
            const SizedBox(height: 14),
            const Text('종성 선택 (초성과 같은 글자면 초성 글씨를 그대로 사용)',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _jong, _selectJong),
            const SizedBox(height: 14),

            // 1번 규칙 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '${caseLabelOf(_cho, _vowel)}   —   $_cho + $_vowel + $_jong'
                    '${matched ? '   ✓ 1번 규칙 적용' : '   (규칙 없음, 시작값)'}'
                    '${_finalRuleMatched ? '   ✓ 2번 규칙 그대로' : '   (2번 값 수정됨)'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1번 값: gap=${up.gap.toStringAsFixed(3)}, '
                    'aspectKeep=${up.aspectKeep.toStringAsFixed(2)}, '
                    'vowelShare=${up.vowelShare.toStringAsFixed(2)}, '
                    'consonantCross=${up.consonantCross.toStringAsFixed(2)}, '
                    'vowelCross=${up.vowelCross.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _canvasColumn('① 초성 $_cho 쓰기', Colors.black,
                    DrawingCanvas(key: _choKey, size: canvasSize)),
                _canvasColumn('② 모음 $_vowel 쓰기', Colors.black,
                    DrawingCanvas(key: _vowelKey, size: canvasSize)),
                _canvasColumn(
                    _sameJamo ? '③ 종성 $_jong (초성과 동일)' : '③ 종성 $_jong 쓰기',
                    Colors.black,
                    _jongInput()),
                _canvasColumn(
                  '④ 합성 결과 (파랑=초성, 빨강=모음, 초록=종성)',
                  Colors.blue,
                  _resultCanvas(),
                ),
                _canvasColumn('참고: 폰트 글자', Colors.grey, _referenceGlyph()),
              ],
            ),

            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _combine,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(120, 45),
                  ),
                  child: const Text('조합',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: _clearAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    minimumSize: const Size(100, 45),
                  ),
                  child: const Text('초기화',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                OutlinedButton(
                  // 현재 케이스의 2번 규칙값으로 되돌린다.
                  onPressed: () => _updateFinal(
                      finalRuleParamsOf(_cho, _vowel) ??
                          const FinalBoxParams()),
                  child: const Text('슬라이더 기본값'),
                ),
                OutlinedButton.icon(
                  onPressed: _copyParams,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('파라미터 복사'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _showGuide,
                      onChanged: (v) => setState(() => _showGuide = v),
                    ),
                    const Text('박스 가이드 표시'),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              _isReady
                  ? '조합 완료 — 슬라이더를 움직이면 바로 다시 그려집니다.'
                  : (_sameJamo
                      ? '①②에 글자를 쓰고 "조합"을 누르세요. (종성은 초성 글씨를 씁니다)'
                      : '①②③에 글자를 쓰고 "조합"을 누르세요.'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),

            const Divider(height: 36),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('위쪽 박스 (초성+모음, 1번 규칙 그대로 들어감)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '위쪽 높이',
                    value: _fp.upperHeight,
                    min: 0.3,
                    max: 0.9,
                    divisions: 60,
                    onChanged: (v) =>
                        _updateFinal(_fp.copyWith(upperHeight: v)),
                  ),
                  _slider(
                    label: '위쪽 폭',
                    value: _fp.upperWidth,
                    min: 0.6,
                    max: 1.1,
                    divisions: 50,
                    onChanged: (v) => _updateFinal(_fp.copyWith(upperWidth: v)),
                  ),
                  const Divider(height: 28),
                  const Text('아래쪽 박스 (종성)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '종성 높이',
                    value: _fp.jongHeight,
                    min: 0.15,
                    max: 0.6,
                    divisions: 45,
                    onChanged: (v) =>
                        _updateFinal(_fp.copyWith(jongHeight: v)),
                  ),
                  _slider(
                    label: '종성 폭',
                    value: _fp.jongWidth,
                    min: 0.3,
                    max: 1.1,
                    divisions: 80,
                    onChanged: (v) => _updateFinal(_fp.copyWith(jongWidth: v)),
                  ),
                  _slider(
                    label: '종성 좌우 위치',
                    value: _fp.jongOffsetX,
                    min: -0.3,
                    max: 0.3,
                    divisions: 60,
                    onChanged: (v) =>
                        _updateFinal(_fp.copyWith(jongOffsetX: v)),
                  ),
                  _slider(
                    label: '종성 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)',
                    value: _fp.jongAspectKeep,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) =>
                        _updateFinal(_fp.copyWith(jongAspectKeep: v)),
                  ),
                  const Divider(height: 28),
                  _slider(
                    label: '위/아래 박스 간격 (음수=겹침)',
                    value: _fp.gap,
                    min: -0.1,
                    max: 0.2,
                    divisions: 60,
                    onChanged: (v) => _updateFinal(_fp.copyWith(gap: v)),
                  ),
                  _slider(
                    label: '미리보기 축소 배율 (결과 캔버스 표시 전용)',
                    value: _previewScale,
                    min: 0.3,
                    max: 1.0,
                    divisions: 70,
                    onChanged: (v) {
                      setState(() => _previewScale = v);
                      _redraw();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 박스 여러 개를 결과 캔버스 위에 얇게 그린다.
/// 획과 같은 좌표 변환(중심 기준 previewScale 축소)을 적용한다.
class _GuidePainter extends CustomPainter {
  final List<MapEntry<ComposeBox, Color>> boxes;
  final double canvasSize;
  final double previewScale;

  _GuidePainter({
    required this.boxes,
    required this.canvasSize,
    required this.previewScale,
  });

  double _t(double v) => (0.5 + (v - 0.5) * previewScale) * canvasSize;

  Rect _rect(ComposeBox b) =>
      Rect.fromLTRB(_t(b.x), _t(b.y), _t(b.x + b.w), _t(b.y + b.h));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final e in boxes) {
      canvas.drawRect(_rect(e.key), paint..color = e.value);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => true;
}