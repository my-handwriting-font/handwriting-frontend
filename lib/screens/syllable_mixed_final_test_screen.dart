import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart' show ComposeBox;
import '../services/syllable_composer.dart';
import '../widgets/drawing_canvas.dart';

/// 6번: 혼합형 받침 있음 (곽, 괜, 굉, 권, 궨, 귄, 긱 ...) 합성 테스트 화면.
///
/// 초성+혼합 모음은 5번(혼합형 받침 없음)의 케이스별 규칙값(kMixedRuleParams)과
/// 혼합 모음 규칙값(kCompoundVowelRuleParams)을 그대로 써서 합성하고,
/// 그 결과를 위쪽 박스에 넣는다. 종성은 아래 박스에 넣는다 (2번·4번과 같은 방식).
/// 5번 값과 혼합 모음 값은 여기서 바꾸지 않는다.
/// 이 화면의 슬라이더는 위/아래 박스의 크기와 위치, 종성 모양만 조절한다.
/// 받침 박스 값은 syllable_composer.dart의 kMixedFinalRuleParams(6번 규칙)에서
/// 케이스별로 가져오고, 슬라이더로 바꾼 값은 케이스별로 따로 보관한다.
/// 6번 케이스는 모음 아래쪽 모양으로만 나눈다.
///   ⑮ A = ㅘ ㅙ ㅚ ㅢ (아래가 평평) / ⑯ B = ㅝ ㅞ ㅟ (ㅜ 줄기가 아래로 내려옴)
///
/// 초성과 종성이 같은 글자(예: 곽의 ㄱ)면 한 번만 쓰고, 종성은 초성 글씨를 그대로 쓴다.
/// 같은 조각을 쓰는 모음으로 바꾸면 그 조각 글씨는 유지된다.
///
/// 서버 저장 없이 프론트에서만 계산한다.
class SyllableMixedFinalTestScreen extends StatefulWidget {
  const SyllableMixedFinalTestScreen({super.key});

  @override
  State<SyllableMixedFinalTestScreen> createState() =>
      _SyllableMixedFinalTestScreenState();
}

class _FinalLayout {
  final ComposeBox upper;
  final ComposeBox jong;
  const _FinalLayout(this.upper, this.jong);
}

/// 6번 규칙이 아직 없는 케이스의 시작값. 2번(세로형 받침 있음) 확정값과 같게 둔다.
const FinalBoxParams _kStartParams = FinalBoxParams(
  upperHeight: 0.60,
  upperWidth: 1.0,
  jongHeight: 0.32,
  jongWidth: 0.50,
  gap: -0.03,
  jongOffsetX: 0.0,
  jongAspectKeep: 0.5,
);

/// 완성형 글자의 종성 순서 (유니코드 한글 음절 계산용)
const List<String> _kJongseongOrder = [
  '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ',
  'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ',
  'ㅍ', 'ㅎ',
];

class _SyllableMixedFinalTestScreenState
    extends State<SyllableMixedFinalTestScreen> {
  final GlobalKey<DrawingCanvasState> _choKey = GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _horzKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _vertKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _jongKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _resultKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 240.0;

  String _cho = 'ㄱ';
  String _vowel = 'ㅘ';
  String _jong = 'ㄱ';

  double _previewScale = 0.6; // 결과 캔버스 표시 전용 축소
  bool _showGuide = true;

  // 케이스별 받침 박스 값. 슬라이더를 건드린 케이스만 들어 있다.
  final Map<int, FinalBoxParams> _caseFinal = {};

  CompoundVowelPieces get _pieces => kCompoundVowelPieces[_vowel]!;

  // 6번 케이스는 모음 아래쪽 모양으로만 나눈다 (A = ㅘ ㅙ ㅚ ㅢ / B = ㅝ ㅞ ㅟ)
  int get _caseId => mixedFinalCaseIdOf(_vowel);

  // 슬라이더로 바꾼 값 > 6번 규칙값(kMixedFinalRuleParams) > 시작값
  FinalBoxParams get _fp =>
      _caseFinal[_caseId] ?? mixedFinalRuleParamsOf(_vowel) ?? _kStartParams;

  // 6번 규칙값이 있고, 현재 값이 규칙값과 같은가
  bool get _finalRuleMatched {
    final rule = mixedFinalRuleParamsOf(_vowel);
    return rule != null && rule.toDisplayString() == _fp.toDisplayString();
  }

  NormalizedJamo? _choNorm;
  NormalizedJamo? _horzNorm;
  NormalizedJamo? _vertNorm;
  NormalizedJamo? _jongNorm;

  // 초성과 종성이 같은 글자면 한 번만 쓰고 종성은 초성 글씨를 그대로 쓴다.
  bool get _sameJamo => _cho == _jong;

  // 실제로 종성 박스에 넣을 자모
  NormalizedJamo? get _jongSource => _sameJamo ? _choNorm : _jongNorm;

  bool get _isReady =>
      _choNorm != null &&
      _horzNorm != null &&
      _vertNorm != null &&
      _jongSource != null;

  // 혼합 모음은 혼합 모음 규칙값 그대로 (없으면 시작값)
  CompoundVowelParams get _vowelParams =>
      compoundVowelRuleParamsOf(_vowel) ?? const CompoundVowelParams();

  // 초성 배치는 5번 규칙값 그대로 (없으면 시작값)
  MixedSyllableParams get _upperParams =>
      mixedRuleParamsOf(_cho, _vowel) ?? const MixedSyllableParams();

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
    // 5번(받침 없음) 합성 결과: 0~1 한 칸 안에 초성 + 혼합 모음이 배치된 상태
    final upperCell = composeMixedSyllable(
      consonant: _choNorm!,
      vowel: _vowel,
      horizontal: _horzNorm!,
      vertical: _vertNorm!,
      params: _upperParams,
      vowelParams: _vowelParams,
      legAdjust: mixedLegAdjustOf(_cho),
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
    final h = _horzKey.currentState?.getValidPoints() ?? [];
    final v = _vertKey.currentState?.getValidPoints() ?? [];
    // 같은 글자면 종성 캔버스가 없으므로 검사하지 않는다.
    final j = _sameJamo
        ? <StrokeData>[]
        : (_jongKey.currentState?.getValidPoints() ?? []);

    final missing = <String>[
      if (c.isEmpty) '초성($_cho)',
      if (h.isEmpty) '가로 조각(${_pieces.horizontal})',
      if (v.isEmpty) '세로 조각(${_pieces.vertical})',
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
      _horzNorm = SyllableComposer.normalizeWithAspect(h);
      _vertNorm = SyllableComposer.normalizeWithAspect(v);
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
    _horzKey.currentState?.clearPoints();
    _vertKey.currentState?.clearPoints();
    _jongKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _choNorm = null;
      _horzNorm = null;
      _vertNorm = null;
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

  // 모음을 바꾸면, 조각 글자가 달라진 쪽만 비운다 (같은 조각이면 글씨 유지).
  void _selectVowel(String v) {
    if (v == _vowel) return;
    final oldPieces = _pieces;
    final newPieces = kCompoundVowelPieces[v]!;
    final horzChanged = oldPieces.horizontal != newPieces.horizontal;
    final vertChanged = oldPieces.vertical != newPieces.vertical;

    if (horzChanged) _horzKey.currentState?.clearPoints();
    if (vertChanged) _vertKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();

    setState(() {
      _vowel = v;
      if (horzChanged) _horzNorm = null;
      if (vertChanged) _vertNorm = null;
    });
    _redraw();
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
    final text = '${mixedFinalCaseLabelOf(_vowel)}  $_cho+$_vowel+$_jong\n'
        'preview=${_previewScale.toStringAsFixed(2)}\n'
        '[5번 규칙값] ${_upperParams.toDisplayString()}\n'
        '[6번 받침 박스] ${_fp.toDisplayString()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 파라미터를 복사했습니다.')),
    );
  }

  // 슬라이더를 건드린 모든 케이스의 받침 박스 값을 한 번에 복사
  Future<void> _copyAllCases() async {
    final ids = _caseFinal.keys.toList()..sort();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 저장된 케이스가 없습니다.')),
      );
      return;
    }
    final text = ids
        .map((id) => '6번 케이스 ${caseMarkOf(id)} (키 $id)\n'
            '[6번 받침 박스] ${_caseFinal[id]!.toDisplayString()}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 케이스 ${ids.length}개 파라미터를 복사했습니다.')),
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

  // 박스 가이드: 초성(파랑)·가로 조각(빨강)·세로 조각(주황)은 5번 배치를
  // 위쪽 박스로 옮긴 것, 종성(초록)은 아래 박스.
  Widget _resultCanvas() {
    final lay = _layout();
    final up = _upperParams;
    final vp = _vowelParams;

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
                    MapEntry(toUpper(up.consBox), Colors.blue),
                    MapEntry(toUpper(vp.horzBox), Colors.red),
                    MapEntry(toUpper(vp.vertBox), Colors.orange),
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
    final has5Rule = mixedRuleParamsOf(_cho, _vowel) != null;
    final hasVowelRule = compoundVowelRuleParamsOf(_vowel) != null;
    final hasFinalRule = mixedFinalRuleParamsOf(_vowel) != null;

    return Scaffold(
      appBar: AppBar(title: const Text('혼합형 받침 있음 합성 테스트 (6번)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('초성 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _cho, _selectCho),
            const SizedBox(height: 14),
            const Text('혼합 모음 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kCompoundVowelChoices, _vowel, _selectVowel),
            const SizedBox(height: 14),
            const Text('종성 선택 (초성과 같은 글자면 초성 글씨를 그대로 사용)',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _jong, _selectJong),
            const SizedBox(height: 14),

            // 5번 / 6번 규칙 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '${mixedFinalCaseLabelOf(_vowel)}   —   $_cho + $_vowel + $_jong'
                    '${has5Rule ? '   ✓ 5번 규칙 적용' : '   (5번 규칙 없음, 시작값)'}'
                    '${!hasFinalRule ? '   (6번 규칙 없음, 시작값)' : _finalRuleMatched ? '   ✓ 6번 규칙 그대로' : '   (6번 값 수정됨)'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '5번 ${mixedCaseLabelOf(_cho, _vowel)}, '
                    '모음 $_vowel = ${_pieces.horizontal} + ${_pieces.vertical}, '
                    '혼합 모음 그룹 ${compoundVowelGroupOf(_vowel)} 규칙'
                    '${hasVowelRule ? ' 고정' : ' 없음 (시작값 사용)'}'
                    '${mixedLegAdjustOf(_cho) && _upperParams.clearance > 0 ? ', 다리 조정' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasVowelRule ? Colors.black54 : Colors.red,
                    ),
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
                _canvasColumn('② 가로 조각 ${_pieces.horizontal} 쓰기',
                    Colors.black, DrawingCanvas(key: _horzKey, size: canvasSize)),
                _canvasColumn('③ 세로 조각 ${_pieces.vertical} 쓰기',
                    Colors.black, DrawingCanvas(key: _vertKey, size: canvasSize)),
                _canvasColumn(
                    _sameJamo ? '④ 종성 $_jong (초성과 동일)' : '④ 종성 $_jong 쓰기',
                    Colors.black,
                    _jongInput()),
                _canvasColumn(
                  '⑤ 합성 결과 (파랑=초성, 빨강·주황=모음, 초록=종성)',
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
                  // 현재 케이스의 6번 규칙값으로 되돌린다 (없으면 시작값).
                  onPressed: () => _updateFinal(
                      mixedFinalRuleParamsOf(_vowel) ?? _kStartParams),
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
                OutlinedButton.icon(
                  onPressed: _copyAllCases,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('전체 케이스 복사'),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              _isReady
                  ? '조합 완료 — 슬라이더를 움직이면 바로 다시 그려집니다.'
                  : (_sameJamo
                      ? '①②③에 글자를 쓰고 "조합"을 누르세요. (종성은 초성 글씨를 씁니다)'
                      : '①②③④에 글자를 쓰고 "조합"을 누르세요.'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),

            const Divider(height: 36),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('위쪽 박스 (초성+혼합 모음, 5번 규칙 그대로 들어감)',
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