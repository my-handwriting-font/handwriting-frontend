import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart' show ComposeBox;
import '../services/syllable_composer.dart';
import '../widgets/drawing_canvas.dart';

/// 혼합 모음(ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ) 합성 테스트 화면.
///
/// 가로 조각(ㅗ ㅜ ㅡ)과 세로 조각(ㅏ ㅐ ㅣ ㅓ ㅔ)을 각각 쓰고 "조합"을 누르면
/// 두 조각을 한 칸 안에 배치한 혼합 모음이 나온다. 자음은 넣지 않는다.
/// 여기서 정한 값은 syllable_composer.dart의 kCompoundVowelRuleParams에 적고,
/// 5번(혼합형) 화면에서는 이 값을 고정해서 자음만 맞춘다.
///
/// 슬라이더 값은 그룹마다 보관한다 (같은 그룹의 모음은 같은 값을 쓴다).
///   그룹 1 = ㅘ ㅙ ㅚ ㅟ ㅢ / 그룹 2 = ㅝ ㅞ
/// ㅝ ㅞ는 ㅓ·ㅔ의 왼쪽으로 튀어나온 획을 ㅜ 아래 획의 가운데로 자동으로 옮긴다.
/// 같은 조각을 쓰는 모음(예: ㅘ → ㅚ는 둘 다 ㅗ)으로 바꾸면 그 조각 글씨는 유지된다.
///
/// 서버 저장 없이 프론트에서만 계산한다.
class CompoundVowelTestScreen extends StatefulWidget {
  const CompoundVowelTestScreen({super.key});

  @override
  State<CompoundVowelTestScreen> createState() =>
      _CompoundVowelTestScreenState();
}

class _CompoundVowelTestScreenState extends State<CompoundVowelTestScreen> {
  final GlobalKey<DrawingCanvasState> _horzKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _vertKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _resultKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 240.0;

  String _vowel = 'ㅘ';

  double _previewScale = 0.6; // 결과 캔버스 표시 전용 축소
  bool _showGuide = true;

  // 그룹별 파라미터. 슬라이더를 건드린 그룹만 들어 있다.
  final Map<int, CompoundVowelParams> _groupParams = {};

  NormalizedJamo? _horzNorm;
  NormalizedJamo? _vertNorm;

  CompoundVowelPieces get _pieces => kCompoundVowelPieces[_vowel]!;

  int get _group => compoundVowelGroupOf(_vowel);

  bool get _stemAlign => kStemAlignVowels.contains(_vowel);

  bool get _isReady => _horzNorm != null && _vertNorm != null;

  // 슬라이더로 바꾼 값(그룹 기준) > 규칙값(kCompoundVowelRuleParams) > 시작값
  CompoundVowelParams _paramsFor(String v) =>
      _groupParams[compoundVowelGroupOf(v)] ??
      compoundVowelRuleParamsOf(v) ??
      const CompoundVowelParams();

  CompoundVowelParams get _params => _paramsFor(_vowel);

  // 규칙값이 있고, 현재 값이 규칙값과 같은가
  bool _ruleMatched(String v) {
    final rule = compoundVowelRuleParamsOf(v);
    return rule != null &&
        rule.toDisplayString() == _paramsFor(v).toDisplayString();
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
    final composed = composeCompoundVowel(
      vowel: _vowel,
      horizontal: _horzNorm!,
      vertical: _vertNorm!,
      params: _params,
    );
    _resultKey.currentState?.loadStrokes(_toCanvasStrokes(composed));
  }

  void _combine() {
    final h = _horzKey.currentState?.getValidPoints() ?? [];
    final v = _vertKey.currentState?.getValidPoints() ?? [];

    final missing = <String>[
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
      _horzNorm = SyllableComposer.normalizeWithAspect(h);
      _vertNorm = SyllableComposer.normalizeWithAspect(v);
    });
    _redraw();
  }

  // 현재 모음이 속한 그룹의 파라미터를 바꾼다 (같은 그룹 모음 모두에 적용).
  void _updateParams(CompoundVowelParams p) {
    setState(() => _groupParams[_group] = p);
    _redraw();
  }

  void _clearAll() {
    _horzKey.currentState?.clearPoints();
    _vertKey.currentState?.clearPoints();
    _resultKey.currentState?.clearPoints();
    setState(() {
      _horzNorm = null;
      _vertNorm = null;
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
    final text = '혼합 모음 $_vowel '
        '(${_pieces.horizontal} + ${_pieces.vertical}) 그룹 $_group '
        'preview=${_previewScale.toStringAsFixed(2)}\n'
        '${_params.toDisplayString()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 현재 모음 파라미터를 복사했습니다.')),
    );
  }

  // 슬라이더를 건드린 모든 그룹의 값을 한 번에 복사 (그룹 순서대로)
  Future<void> _copyAllGroups() async {
    final groups = _groupParams.keys.toList()..sort();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 저장된 그룹이 없습니다.')),
      );
      return;
    }
    final text = groups
        .map((g) => '그룹 $g (${kCompoundVowelGroups[g]!.join(' ')})\n'
            '${_groupParams[g]!.toDisplayString()}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 그룹 ${groups.length}개 파라미터를 복사했습니다.')),
    );
  }

  // ---------------------------------------------------------------- UI 조각

  // checked가 true를 돌려주는 글자에는 ✓ 를 붙인다 (규칙값과 같은 모음).
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

  // 박스 가이드: 가로 조각(빨강), 세로 조각(주황).
  Widget _resultCanvas() {
    final p = _params;
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
                    MapEntry(p.horzBox, Colors.red),
                    MapEntry(p.vertBox, Colors.orange),
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
    return Container(
      width: canvasSize,
      height: canvasSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 2),
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: Text(_vowel, style: const TextStyle(fontSize: 120)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _params;
    final hasRule = compoundVowelRuleParamsOf(_vowel) != null;
    final matched = _ruleMatched(_vowel);
    // ㅝ ㅞ 자동 맞춤이 적용됐는지 (조합 후에만)
    final alignStatus = _isReady
        ? compoundVowelAlignStatus(
            vowel: _vowel,
            horizontal: _horzNorm!,
            vertical: _vertNorm!,
            params: p,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('혼합 모음 합성 테스트')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('혼합 모음 선택', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            _chips(kCompoundVowelChoices, _vowel, _selectVowel,
                checked: _ruleMatched),
            const SizedBox(height: 14),

            // 현재 모음 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_vowel = 가로 조각 ${_pieces.horizontal} + 세로 조각 ${_pieces.vertical}'
                '   —   그룹 $_group (${kCompoundVowelGroups[_group]!.join(' ')} 공유)'
                '${!hasRule ? '   (규칙 없음, 시작값)' : matched ? '   ✓ 규칙 그대로' : '   (값 수정됨)'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _canvasColumn('① 가로 조각 ${_pieces.horizontal} 쓰기',
                    Colors.black, DrawingCanvas(key: _horzKey, size: canvasSize)),
                _canvasColumn('② 세로 조각 ${_pieces.vertical} 쓰기',
                    Colors.black, DrawingCanvas(key: _vertKey, size: canvasSize)),
                _canvasColumn(
                  '③ 합성 결과 (빨강=가로 조각, 주황=세로 조각)',
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
                  // 현재 모음의 규칙값으로 되돌린다 (없으면 시작값).
                  onPressed: () => _updateParams(
                      compoundVowelRuleParamsOf(_vowel) ??
                          const CompoundVowelParams()),
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
                  onPressed: _copyAllGroups,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('전체 그룹 복사'),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              _isReady
                  ? '조합 완료 — 슬라이더를 움직이면 바로 다시 그려집니다.'
                  : '①②에 조각을 쓰고 "조합"을 누르세요.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (_stemAlign) ...[
              const SizedBox(height: 4),
              const Text(
                '💡 ㅝ·ㅞ는 튀어나온 획을 ㅜ 아래 획의 가운데로 자동으로 옮깁니다. '
                'ㅜ(가로획/아래 획)와 ㅓ·ㅔ(튀어나온 획/기둥)는 각각 떼서 써주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              if (alignStatus != null) ...[
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
            ],

            const Divider(height: 36),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('가로 조각 (${_pieces.horizontal})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '가로 조각 폭',
                    value: p.horzWidth,
                    min: 0.2,
                    max: 1.0,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(horzWidth: v)),
                  ),
                  _slider(
                    label: '가로 조각 높이',
                    value: p.horzHeight,
                    min: 0.1,
                    max: 0.7,
                    divisions: 60,
                    onChanged: (v) => _updateParams(p.copyWith(horzHeight: v)),
                  ),
                  _slider(
                    label: '가로 조각 좌우 위치 (가운데 x)',
                    value: p.horzX,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(horzX: v)),
                  ),
                  _slider(
                    label: '가로 조각 상하 위치 (가운데 y)',
                    value: p.horzY,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(horzY: v)),
                  ),
                  _slider(
                    label: '가로 조각 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)',
                    value: p.horzAspectKeep,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) =>
                        _updateParams(p.copyWith(horzAspectKeep: v)),
                  ),
                  const Divider(height: 28),
                  Text('세로 조각 (${_pieces.vertical})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  _slider(
                    label: '세로 조각 폭',
                    value: p.vertWidth,
                    min: 0.1,
                    max: 0.6,
                    divisions: 50,
                    onChanged: (v) => _updateParams(p.copyWith(vertWidth: v)),
                  ),
                  _slider(
                    label: '세로 조각 높이',
                    value: p.vertHeight,
                    min: 0.3,
                    max: 1.0,
                    divisions: 70,
                    onChanged: (v) => _updateParams(p.copyWith(vertHeight: v)),
                  ),
                  _slider(
                    label: '세로 조각 좌우 위치 (가운데 x)',
                    value: p.vertX,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(vertX: v)),
                  ),
                  _slider(
                    label: '세로 조각 상하 위치 (가운데 y)',
                    value: p.vertY,
                    min: 0.1,
                    max: 0.9,
                    divisions: 80,
                    onChanged: (v) => _updateParams(p.copyWith(vertY: v)),
                  ),
                  _slider(
                    label: '세로 조각 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)',
                    value: p.vertAspectKeep,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) =>
                        _updateParams(p.copyWith(vertAspectKeep: v)),
                  ),
                  if (_stemAlign)
                    _slider(
                      label: '튀어나온 획 상하 미세 조정 (0=ㅜ 가운데에서 살짝 아래, +아래 / -위)',
                      value: p.tickOffsetY,
                      min: -0.15,
                      max: 0.15,
                      divisions: 60,
                      onChanged: (v) =>
                          _updateParams(p.copyWith(tickOffsetY: v)),
                    ),
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