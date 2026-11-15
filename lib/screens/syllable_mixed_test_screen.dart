import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart' show ComposeBox;
import '../services/syllable_composer.dart';
import '../widgets/drawing_canvas.dart';

/// 5번: 혼합형 받침 없음 (과, 괘, 괴, 궈, 궤, 귀, 긔 ...) 합성 테스트 화면.
///
/// 초성, 가로 조각(ㅗ ㅜ ㅡ), 세로 조각(ㅏ ㅐ ㅣ ㅓ ㅔ)을 쓰고 "조합"을 누른다.
/// 혼합 모음은 kCompoundVowelRuleParams(혼합 모음 화면에서 정한 값)로 고정하고,
/// 여기서는 초성 박스만 슬라이더로 맞춘다.
/// 여기서 정한 값은 syllable_composer.dart의 kMixedRuleParams에 적는다.
///
/// 슬라이더 값은 케이스(⑪~⑭)마다 보관한다.
///   ⑪ 자음1×혼합1 / ⑫ 자음1×혼합2 / ⑬ 자음2×혼합1 / ⑭ 자음2×혼합2
/// ㄱ·ㅋ은 다리 각도 조정 슬라이더가 추가로 나온다 (여백 0 = 끔).
/// 같은 조각을 쓰는 모음으로 바꾸면 그 조각 글씨는 유지된다.
///
/// 서버 저장 없이 프론트에서만 계산한다.
class SyllableMixedTestScreen extends StatefulWidget {
  const SyllableMixedTestScreen({super.key});

  @override
  State<SyllableMixedTestScreen> createState() =>
      _SyllableMixedTestScreenState();
}

class _SyllableMixedTestScreenState extends State<SyllableMixedTestScreen> {
  final GlobalKey<DrawingCanvasState> _consKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _horzKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _vertKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _resultKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 240.0;

  String _consonant = 'ㄱ';
  String _vowel = 'ㅘ';

  double _previewScale = 0.6; // 결과 캔버스 표시 전용 축소
  bool _showGuide = true;

  // 케이스별 파라미터. 슬라이더를 건드린 케이스만 들어 있다.
  final Map<int, MixedSyllableParams> _caseParams = {};

  NormalizedJamo? _consNorm;
  NormalizedJamo? _horzNorm;
  NormalizedJamo? _vertNorm;

  CompoundVowelPieces get _pieces => kCompoundVowelPieces[_vowel]!;

  int get _caseId => mixedCaseIdOf(_consonant, _vowel);

  bool get _legAdjust => mixedLegAdjustOf(_consonant);

  bool get _stemAlign => kStemAlignVowels.contains(_vowel);

  bool get _isReady =>
      _consNorm != null && _horzNorm != null && _vertNorm != null;

  // 혼합 모음은 규칙값으로 고정 (규칙이 없으면 시작값)
  CompoundVowelParams get _vowelParams =>
      compoundVowelRuleParamsOf(_vowel) ?? const CompoundVowelParams();

  // 슬라이더로 바꾼 값(케이스 기준) > 규칙값(kMixedRuleParams) > 시작값
  MixedSyllableParams _paramsFor(String c, String v) =>
      _caseParams[mixedCaseIdOf(c, v)] ??
      mixedRuleParamsOf(c, v) ??
      const MixedSyllableParams();

  MixedSyllableParams get _params => _paramsFor(_consonant, _vowel);

  // 규칙값이 있고, 현재 값이 규칙값과 같은가
  bool _ruleMatched(String c, String v) {
    final rule = mixedRuleParamsOf(c, v);
    return rule != null &&
        rule.toDisplayString() == _paramsFor(c, v).toDisplayString();
  }

  // ---------------------------------------------------------------- 계산/표시

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
    final composed = composeMixedSyllable(
      consonant: _consNorm!,
      vowel: _vowel,
      horizontal: _horzNorm!,
      vertical: _vertNorm!,
      params: _params,
      vowelParams: _vowelParams,
      legAdjust: _legAdjust,
    );
    _resultKey.currentState?.loadStrokes(_toCanvasStrokes(composed));
  }

  void _combine() {
    final c = _consKey.currentState?.getValidPoints() ?? [];
    final h = _horzKey.currentState?.getValidPoints() ?? [];
    final v = _vertKey.currentState?.getValidPoints() ?? [];

    final missing = <String>[
      if (c.isEmpty) '초성($_consonant)',
      if (h.isEmpty) '가로 조각(${_pieces.horizontal})',
      if (v.isEmpty) '세로 조각(${_pieces.vertical})',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${missing.join(', ')}을(를) 먼저 써주세요.')),
      );
      return;
    }

    setState(() {
      _consNorm = SyllableComposer.normalizeWithAspect(c);
      _horzNorm = SyllableComposer.normalizeWithAspect(h);
      _vertNorm = SyllableComposer.normalizeWithAspect(v);
    });
    _redraw();
  }

  // 현재 케이스의 파라미터를 바꾼다 (같은 케이스 조합 모두에 적용).
  void _updateParams(MixedSyllableParams p) {
    setState(() => _caseParams[_caseId] = p);
    _redraw();
  }

  void _clearAll() {
    _consKey.currentState?.clearPoints();
    _horzKey.currentState?.clearPoints();
    _vertKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _consNorm = null;
      _horzNorm = null;
      _vertNorm = null;
    });
  }

  void _selectConsonant(String c) {
    if (c == _consonant) return;
    _consKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _consonant = c;
      _consNorm = null;
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

  Future<void> _copyParams() async {
    final text = '5번 $_consonant + $_vowel '
        '${mixedCaseLabelOf(_consonant, _vowel)} '
        'preview=${_previewScale.toStringAsFixed(2)}\n'
        '${_params.toDisplayString()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 현재 케이스 파라미터를 복사했습니다.')),
    );
  }

  // 슬라이더를 건드린 모든 케이스의 값을 한 번에 복사 (케이스 순서대로)
  Future<void> _copyAllCases() async {
    final ids = _caseParams.keys.toList()..sort();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 저장된 케이스가 없습니다.')),
      );
      return;
    }
    final text = ids
        .map((id) => '케이스 ${caseMarkOf(id)} (키 $id)\n'
            '${_caseParams[id]!.toDisplayString()}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 케이스 ${ids.length}개 파라미터를 복사했습니다.')),
    );
  }

  // ---------------------------------------------------------------- UI 조각

  // checked가 true를 돌려주는 글자에는 ✓ 를 붙인다 (규칙값과 같은 조합).
  Widget _chips(
    List<String> items,
    String selected,
    ValueChanged<String> onSelect, {
    bool Function(String)? checked,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: items
          .map((s) => ChoiceChip(
                label: Text(checked != null && checked(s) ? '$s ✓' : s,
                    style: const TextStyle(fontSize: 16)),
                selected: s == selected,
                onSelected: (_) => onSelect(s),
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

  // 박스 가이드: 초성(초록), 가로 조각(빨강), 세로 조각(주황).
  Widget _resultCanvas() {
    final p = _params;
    final vp = _vowelParams;
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
                    MapEntry(p.consBox, Colors.green),
                    MapEntry(vp.horzBox, Colors.red),
                    MapEntry(vp.vertBox, Colors.orange),
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

  Widget _referenceGlyph() {
    final glyph = syllableOf(_consonant, _vowel) ?? '';
    return Container(
      width: canvasSize,
      height: canvasSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 2),
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: Text(glyph, style: const TextStyle(fontSize: 120)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _params;
    final hasRule = mixedRuleParamsOf(_consonant, _vowel) != null;
    final matched = _ruleMatched(_consonant, _vowel);
    final vowelGroup = compoundVowelGroupOf(_vowel);
    final hasVowelRule = compoundVowelRuleParamsOf(_vowel) != null;
    // ㅝ ㅞ 자동 맞춤이 적용됐는지 (조합 후에만)
    final alignStatus = _isReady
        ? compoundVowelAlignStatus(
            vowel: _vowel,
            horizontal: _horzNorm!,
            vertical: _vertNorm!,
            params: _vowelParams,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('혼합형 받침 없음 합성 테스트 (5번)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('초성 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _consonant, _selectConsonant,
                checked: (c) => _ruleMatched(c, _vowel)),
            const SizedBox(height: 14),
            const Text('혼합 모음 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kCompoundVowelChoices, _vowel, _selectVowel,
                checked: (v) => _ruleMatched(_consonant, v)),
            const SizedBox(height: 14),

            // 현재 케이스 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${syllableOf(_consonant, _vowel) ?? ''}  —  '
                '${mixedCaseLabelOf(_consonant, _vowel)}'
                '${!hasRule ? '   (규칙 없음, 시작값)' : matched ? '   ✓ 규칙 그대로' : '   (값 수정됨)'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '모음 $_vowel = ${_pieces.horizontal} + ${_pieces.vertical}, '
              '혼합 모음 그룹 $vowelGroup 규칙'
              '${hasVowelRule ? ' 고정' : ' 없음 (시작값 사용)'}',
              style: TextStyle(
                fontSize: 13,
                color: hasVowelRule ? Colors.black54 : Colors.red,
              ),
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _canvasColumn('① 초성 $_consonant 쓰기', Colors.black,
                    DrawingCanvas(key: _consKey, size: canvasSize)),
                _canvasColumn('② 가로 조각 ${_pieces.horizontal} 쓰기',
                    Colors.black, DrawingCanvas(key: _horzKey, size: canvasSize)),
                _canvasColumn('③ 세로 조각 ${_pieces.vertical} 쓰기',
                    Colors.black, DrawingCanvas(key: _vertKey, size: canvasSize)),
                _canvasColumn(
                  '④ 합성 결과 (초록=초성, 빨강=가로, 주황=세로)',
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
                  // 현재 케이스의 규칙값으로 되돌린다 (없으면 시작값).
                  onPressed: () => _updateParams(
                      mixedRuleParamsOf(_consonant, _vowel) ??
                          const MixedSyllableParams()),
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
                  : '①②③을 쓰고 "조합"을 누르세요.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (_stemAlign && alignStatus != null) ...[
              const SizedBox(height: 4),
              Text(
                alignStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: alignStatus.startsWith('✓')
                      ? Colors.green
                      : alignStatus.startsWith('△')
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
            ],

            const Divider(height: 36),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('초성 ($_consonant)',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '초성 박스 폭',
                    value: p.consWidth,
                    min: 0.2,
                    max: 0.8,
                    divisions: 60,
                    onChanged: (v) => _updateParams(p.copyWith(consWidth: v)),
                  ),
                  _slider(
                    label: '초성 박스 높이',
                    value: p.consHeight,
                    min: 0.2,
                    max: 0.8,
                    divisions: 60,
                    onChanged: (v) => _updateParams(p.copyWith(consHeight: v)),
                  ),
                  _slider(
                    label: '초성 좌우 위치 (가운데 x)',
                    value: p.consX,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(consX: v)),
                  ),
                  _slider(
                    label: '초성 상하 위치 (가운데 y)',
                    value: p.consY,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(consY: v)),
                  ),
                  _slider(
                    label: '초성 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)',
                    value: p.consAspectKeep,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) =>
                        _updateParams(p.copyWith(consAspectKeep: v)),
                  ),
                  if (_legAdjust) ...[
                    const Divider(height: 28),
                    const Text('다리 각도 조정 (ㄱ ㅋ, 가로 조각 기준)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    _slider(
                      label: '여백 (0=끔)',
                      value: p.clearance,
                      min: 0.0,
                      max: 0.2,
                      divisions: 40,
                      onChanged: (v) => _updateParams(p.copyWith(clearance: v)),
                    ),
                    _slider(
                      label: '최대 회전 각도 (도)',
                      value: p.maxAngle,
                      min: 0.0,
                      max: 80.0,
                      divisions: 80,
                      onChanged: (v) => _updateParams(p.copyWith(maxAngle: v)),
                    ),
                    _slider(
                      label: '다리 길이 최소 비율',
                      value: p.minLegScale,
                      min: 0.1,
                      max: 1.0,
                      divisions: 90,
                      onChanged: (v) =>
                          _updateParams(p.copyWith(minLegScale: v)),
                    ),
                  ],
                  const Divider(height: 28),
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