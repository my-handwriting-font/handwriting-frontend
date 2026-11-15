import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart' show ComposeBox;
import '../services/syllable_composer.dart';
import '../widgets/drawing_canvas.dart';

/// 자음 + 모음 합성 테스트 화면 (받침 없는 글자: 가, 나, 다 ...).
///
/// 1번 캔버스에 자음, 2번 캔버스에 모음을 직접 쓰고 "조합" 버튼을 누르면
/// 3번 캔버스에 합쳐진 글자가 나온다. 조합 후에는 슬라이더를 움직이는 즉시
/// 결과가 다시 그려진다. 서버 저장 없이 프론트에서만 계산한다.
///
/// 슬라이더 값은 "케이스"(자음 그룹 × 모음 그룹)별로 따로 저장된다.
/// 같은 케이스 안에서 글자를 바꾸면 값이 유지되고, 다른 케이스로 가면 그 케이스의 값이 나온다.
/// 세로형 케이스는 정해진 규칙값으로 시작하고, 현재 값이 규칙값과 같으면 ✓ 로 표시한다.
/// 가로형에서 리스트의 자음(ㄱ, ㅋ)이 ㅗ·ㅛ와 겹치면 자음 좌우 위치를 자동으로 오른쪽으로 옮긴다.
class SyllableTestScreen extends StatefulWidget {
  const SyllableTestScreen({super.key});

  @override
  State<SyllableTestScreen> createState() => _SyllableTestScreenState();
}

class _SyllableTestScreenState extends State<SyllableTestScreen> {
  final GlobalKey<DrawingCanvasState> _consonantKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _vowelKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _resultKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 240.0;

  String _consonant = 'ㄱ';
  String _vowel = 'ㅏ';
  double _previewScale = 0.3; // 결과 캔버스 표시 전용 축소
  bool _showGuide = true;

  // 케이스별 파라미터. 슬라이더를 건드린 케이스만 들어 있다.
  final Map<int, SyllableParams> _caseParams = {};

  // 조합 버튼을 누를 때 정규화해서 보관. 이후 슬라이더 변경은 이걸로 재계산한다.
  NormalizedJamo? _consonantNorm;
  NormalizedJamo? _vowelNorm;

  VowelOrientation get _orientation => orientationOf(_vowel);
  bool get _isReady => _consonantNorm != null && _vowelNorm != null;

  int get _caseId => caseIdOf(_consonant, _vowel);

  // 글자 조합 (c, v)의 파라미터: 슬라이더로 바꾼 값 > 규칙값 > 방향별 시작값
  SyllableParams _paramsFor(String c, String v) =>
      _caseParams[caseIdOf(c, v)] ??
      ruleParamsOf(c, v) ??
      SyllableParams.defaultsFor(orientationOf(v));

  // 현재 케이스의 파라미터 (슬라이더에 보이는 값)
  SyllableParams get _params => _paramsFor(_consonant, _vowel);

  // 실제 합성·가이드에 쓰는 파라미터 (겹치면 자음 좌우 위치가 자동으로 바뀐 값)
  SyllableParams get _effectiveParams => _isReady
      ? SyllableComposer.resolveParams(
          consonant: _consonantNorm!,
          vowel: _vowelNorm!,
          params: _params,
          orientation: _orientation,
          autoShiftRight: autoShiftOf(_consonant, _vowel),
        )
      : _params;

  // 규칙값이 있는 조합이고, 현재 값이 규칙값과 같은가
  bool _ruleMatched(String c, String v) {
    final rule = ruleParamsOf(c, v);
    return rule != null && rule.sameAs(_paramsFor(c, v));
  }

  // ---------------------------------------------------------------- 계산/표시

  // 결과 캔버스 표시용 변환: 중심(0.5, 0.5) 기준으로 previewScale만큼 축소.
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
    final composed = SyllableComposer.composeFit(
      consonant: _consonantNorm!,
      vowel: _vowelNorm!,
      params: _params,
      orientation: _orientation,
      autoShiftRight: autoShiftOf(_consonant, _vowel),
      // 다리 각도 조정(avoidMode 2)은 리스트의 자음(ㄱ, ㅋ)에만 적용
      legAdjust: autoLegOf(_consonant, _vowel),
    );
    _resultKey.currentState?.loadStrokes(_toCanvasStrokes(composed));
  }

  void _combine() {
    final c = _consonantKey.currentState?.getValidPoints() ?? [];
    final v = _vowelKey.currentState?.getValidPoints() ?? [];

    if (c.isEmpty || v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(c.isEmpty && v.isEmpty
              ? '자음과 모음을 모두 써주세요.'
              : c.isEmpty
                  ? '자음($_consonant)을 먼저 써주세요.'
                  : '모음($_vowel)을 먼저 써주세요.'),
        ),
      );
      return;
    }

    setState(() {
      _consonantNorm = SyllableComposer.normalizeWithAspect(c);
      _vowelNorm = SyllableComposer.normalizeWithAspect(v);
    });
    _redraw();
  }

  // 현재 케이스의 파라미터를 바꾼다.
  void _updateParams(SyllableParams p) {
    setState(() => _caseParams[_caseId] = p);
    _redraw();
  }

  void _clearAll() {
    _consonantKey.currentState?.clearPoints();
    _vowelKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _consonantNorm = null;
      _vowelNorm = null;
    });
  }

  void _selectConsonant(String c) {
    if (c == _consonant) return;
    _consonantKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _consonant = c;
      _consonantNorm = null;
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

  Future<void> _copyParams() async {
    final text = '${caseLabelOf(_consonant, _vowel)}\n'
        '$_consonant+$_vowel (${_orientation.name}) '
        'preview=${_previewScale.toStringAsFixed(2)}\n'
        '${_params.toDisplayString()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 현재 케이스 파라미터를 복사했습니다.')),
    );
  }

  // 슬라이더를 건드린 모든 케이스의 값을 한 번에 복사
  Future<void> _copyAllCases() async {
    final ids = _caseParams.keys.toList()..sort();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 저장된 케이스가 없습니다.')),
      );
      return;
    }
    final text = ids
        .map((id) => '케이스 ${caseMarkOf(id)} '
            'preview=${_previewScale.toStringAsFixed(2)}\n'
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

  // 결과 캔버스 위에 자음(파랑)/모음(빨강) 박스를 겹쳐 그리는 가이드.
  // 캔버스 내부 좌표계가 테두리(2px) 안쪽에서 시작하므로 2px 안쪽으로 맞춘다.
  // 자동 오른쪽 밀기가 적용되면 옮겨진 자음 박스를 그린다.
  Widget _resultCanvas() {
    final layout =
        SyllableComposer.computeLayout(_effectiveParams, _orientation);
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
                  consonantBox: layout.consonantBox,
                  vowelBox: layout.vowelBox,
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
    final glyph = syllableOf(_consonant, _vowel) ?? '?';
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
    final vertical = _orientation == VowelOrientation.vertical;
    final params = _params;
    final matched = _ruleMatched(_consonant, _vowel);

    return Scaffold(
      appBar: AppBar(title: const Text('자음+모음 합성 테스트')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('자음 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kChoseongChoices, _consonant, _selectConsonant,
                checked: (c) => _ruleMatched(c, _vowel)),
            const SizedBox(height: 14),
            const Text('모음 선택 (ㅏ 계열은 오른쪽, ㅗ 계열은 아래에 붙음)',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kVowelChoices, _vowel, _selectVowel,
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
                '${caseLabelOf(_consonant, _vowel)}   —   '
                '$_consonant + $_vowel'
                '${matched ? '   ✓ 규칙 적용' : ''}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
            const SizedBox(height: 20),

            // 화면 1 / 2 / 3
            Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _canvasColumn(
                  '① 자음 $_consonant 쓰기',
                  Colors.black,
                  DrawingCanvas(key: _consonantKey, size: canvasSize),
                ),
                _canvasColumn(
                  '② 모음 $_vowel 쓰기',
                  Colors.black,
                  DrawingCanvas(key: _vowelKey, size: canvasSize),
                ),
                _canvasColumn(
                  '③ 합성 결과 (파랑=자음 박스, 빨강=모음 박스)',
                  Colors.blue,
                  _resultCanvas(),
                ),
                _canvasColumn(
                  '참고: 폰트 글자',
                  Colors.grey,
                  _referenceGlyph(),
                ),
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
                // 해당 케이스의 규칙값으로 되돌린다 (규칙이 없으면 방향별 시작값).
                OutlinedButton(
                  onPressed: () => _updateParams(
                      ruleParamsOf(_consonant, _vowel) ??
                          SyllableParams.defaultsFor(_orientation)),
                  child: const Text('슬라이더 기본값'),
                ),
                OutlinedButton.icon(
                  onPressed: _copyParams,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('파라미터 복사'),
                ),
                // 파라미터 복사 오른쪽: 박스 가이드 표시 스위치
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
                  : '① ②에 글자를 쓰고 "조합"을 누르세요.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),

            const Divider(height: 36),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('기본 조절',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '간격 (gap)',
                    value: params.gap,
                    min: -0.2,
                    max: 0.3,
                    divisions: 100,
                    onChanged: (v) => _updateParams(params.copyWith(gap: v)),
                  ),
                  _slider(
                    label: vertical ? '왼쪽 배율 (자음)' : '위쪽 배율 (자음)',
                    value: params.consonantScale,
                    min: 0.5,
                    max: 1.5,
                    divisions: 50,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(consonantScale: v)),
                  ),
                  _slider(
                    label: vertical ? '오른쪽 배율 (모음)' : '아래쪽 배율 (모음)',
                    value: params.vowelScale,
                    min: 0.5,
                    max: 1.5,
                    divisions: 50,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(vowelScale: v)),
                  ),
                  _slider(
                    label: '원본 비율 유지 (0=박스 채우기, 1=비율 그대로)',
                    value: params.aspectKeep,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(aspectKeep: v)),
                  ),
                  const SizedBox(height: 6),
                  const Text('겹침 방지 기준',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(vertical
                            ? '끝점 기준 (자음 맨 오른쪽 ↔ 모음 맨 왼쪽)'
                            : '끝점 기준 (자음 맨 아래 ↔ 모음 맨 위)'),
                        selected: params.avoidMode == 1,
                        onSelected: (_) =>
                            _updateParams(params.copyWith(avoidMode: 1)),
                      ),
                      ChoiceChip(
                        label: const Text('가까운 거리 기준 (자음 휘기 포함)'),
                        selected: params.avoidMode == 0,
                        onSelected: (_) =>
                            _updateParams(params.copyWith(avoidMode: 0)),
                      ),
                      ChoiceChip(
                        label: const Text('다리 각도 조정 (모서리 기준 회전, 가로 모음 전용)'),
                        selected: params.avoidMode == 2,
                        onSelected: (_) =>
                            _updateParams(params.copyWith(avoidMode: 2)),
                      ),
                    ],
                  ),
                  _slider(
                    label: '겹침 방지 여백 (0=끔)',
                    value: params.clearance,
                    min: 0.0,
                    max: 0.12,
                    divisions: 24,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(clearance: v)),
                  ),
                  if (params.avoidMode == 0)
                    _slider(
                      label: '자음 비킴 최대량 (가로 모음 전용)',
                      value: params.maxBend,
                      min: 0.0,
                      max: 0.8,
                      divisions: 32,
                      onChanged: (v) =>
                          _updateParams(params.copyWith(maxBend: v)),
                    ),
                  if (params.avoidMode == 2) ...[
                    _slider(
                      label: '다리 최대 회전 각도 (도)',
                      value: params.maxAngle,
                      min: 0.0,
                      max: 70.0,
                      divisions: 70,
                      onChanged: (v) =>
                          _updateParams(params.copyWith(maxAngle: v)),
                    ),
                    _slider(
                      label: '다리 최소 길이 비율 (원래 길이 대비)',
                      value: params.minLegScale,
                      min: 0.3,
                      max: 1.0,
                      divisions: 70,
                      onChanged: (v) =>
                          _updateParams(params.copyWith(minLegScale: v)),
                    ),
                  ],
                  _slider(
                    label: '모음 밀어내기 최대량 (0=모음은 안 밈)',
                    value: params.maxPush,
                    min: 0.0,
                    max: 0.3,
                    divisions: 30,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(maxPush: v)),
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
                  const Divider(height: 32),
                  const Text('추가 조절',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: vertical ? '모음 폭 비중' : '모음 높이 비중',
                    value: params.vowelShare,
                    min: 0.1,
                    max: 0.6,
                    divisions: 50,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(vowelShare: v)),
                  ),
                  _slider(
                    label: vertical ? '자음 세로 길이' : '자음 가로 길이',
                    value: params.consonantCross,
                    min: 0.3,
                    // 인쇄체 실측은 최대 ≈1.0 (ㅗ 0.99)이지만 여유를 둔다
                    max: 1.3,
                    divisions: 100,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(consonantCross: v)),
                  ),
                  _slider(
                    label: vertical ? '모음 세로 길이' : '모음 가로 길이',
                    value: params.vowelCross,
                    min: 0.3,
                    // 인쇄체 실측은 ㅓ·ㅣ·ㅡ에서 1.26~1.28까지 나온다
                    max: 1.3,
                    divisions: 100,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(vowelCross: v)),
                  ),
                  _slider(
                    label: vertical ? '자음 상하 위치' : '자음 좌우 위치',
                    value: params.consonantOffset,
                    min: -0.3,
                    max: 0.3,
                    divisions: 60,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(consonantOffset: v)),
                  ),
                  _slider(
                    label: vertical ? '모음 상하 위치' : '모음 좌우 위치',
                    value: params.vowelOffset,
                    min: -0.3,
                    max: 0.3,
                    divisions: 60,
                    onChanged: (v) =>
                        _updateParams(params.copyWith(vowelOffset: v)),
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

/// 자음 박스(파랑)와 모음 박스(빨강)를 결과 캔버스 위에 얇게 그린다.
/// 획과 같은 좌표 변환(중심 기준 previewScale 축소)을 적용한다.
class _GuidePainter extends CustomPainter {
  final ComposeBox consonantBox;
  final ComposeBox vowelBox;
  final double canvasSize;
  final double previewScale;

  _GuidePainter({
    required this.consonantBox,
    required this.vowelBox,
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
    canvas.drawRect(_rect(consonantBox), paint..color = Colors.blue);
    canvas.drawRect(_rect(vowelBox), paint..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => true;
}