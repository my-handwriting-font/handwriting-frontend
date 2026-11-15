import 'package:flutter/material.dart';

import '../http/api_service.dart';
import '../models/handwriting_model.dart';
import '../services/double_jamo_composer.dart';
import '../services/normalization_service.dart';
import '../widgets/drawing_canvas.dart';

/// 쌍자음(ㄲ, ㄸ, ㅃ, ㅆ, ㅉ) 합성 공식을 실시간으로 튜닝해보는 테스트 화면.
///
/// - ㄱ은 DB에 이미 저장돼 있으므로 /latest로 불러온다.
/// - ㄷ/ㅂ/ㅅ/ㅈ은 DB에 없으므로, 왼쪽 캔버스에 사용자가 직접 그려서
///   그 획을 정규화한 뒤 합성 원본으로 사용한다.
/// - 어느 쪽이든 gap / scale / baseHeight 슬라이더로 좌우 비대칭 배치를
///   조절하고, 결과를 오른쪽 캔버스에 그려서 눈으로 확인한다.
///
/// 서버에 저장하지 않고 프론트에서만 계산하는 순수 미리보기 화면이다.
/// (기존 /double/save, /double 엔드포인트와는 별개)
class DoubleJamoTestScreen extends StatefulWidget {
  const DoubleJamoTestScreen({super.key});

  @override
  State<DoubleJamoTestScreen> createState() => _DoubleJamoTestScreenState();
}

class _DoubleJamoTestScreenState extends State<DoubleJamoTestScreen> {
  final GlobalKey<DrawingCanvasState> _baseCanvasKey =
      GlobalKey<DrawingCanvasState>();
  final GlobalKey<DrawingCanvasState> _composedCanvasKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 260.0;

  JamoPair _selectedPair = kDoubleJamoPairs.first;
  DoubleJamoParams _params = const DoubleJamoParams();

  // 합성 결과를 캔버스에 "표시"할 때만 적용하는 축소 배율.
  // 공식 계산 결과(0~1 좌표) 자체는 건드리지 않고, 화면에 그릴 때만
  // 중심(0.5, 0.5) 기준으로 축소해서 캔버스 안에 여백을 두고 작게 보여준다.
  // → 나중에 실제 저장/서버 반영 시에는 이 축소를 빼고 원본 계산값을 써야 함.
  double _previewScale = 0.6;

  // 정규화된(0~1) 원본 자음 좌표. ㄱ은 DB에서, 나머지는 캔버스에서 그려서 채운다.
  List<StrokeData>? _baseStrokes;
  List<StrokeData>? _lastComposed;
  bool _isLoading = false;

  // ㄱ만 DB 연동, 나머지(ㄷ/ㅂ/ㅅ/ㅈ)는 사용자가 왼쪽 캔버스에 직접 그린다.
  bool get _isDbBacked => _selectedPair.single == 'ㄱ';

  bool get _isBaseLoaded => _baseStrokes != null && _baseStrokes!.isNotEmpty;

  // 0~1 정규화 좌표를 캔버스 픽셀 좌표로 그대로(1:1) 매핑한다.
  // DB에서 불러온 ㄱ 미리보기는 글자 하나뿐이라 꽉 차게 보여줘도
  // 판별에 문제가 없어서 그대로 둔다.
  List<StrokeData> _denormalizeToCanvas(List<StrokeData> strokes) {
    return strokes.map((stroke) {
      return StrokeData(
        points: stroke.points.map((p) {
          return PointData(
            x: p.x * canvasSize,
            y: p.y * canvasSize,
            pressure: p.pressure,
          );
        }).toList(),
      );
    }).toList();
  }

  // 합성 결과 전용: 중심(0.5, 0.5)을 기준으로 previewScale만큼 축소한 뒤
  // 캔버스 픽셀 좌표로 변환한다. 예를 들어 previewScale=0.6이면 글자가
  // 캔버스 가운데 60% 영역 안에 작게 모여서 그려지고, 나머지 40%는 여백이 된다.
  // gap/scale/baseHeight 값이 커서 0~1 범위를 살짝 벗어나는 경우에도
  // 여백 덕분에 캔버스 밖으로 잘려나가지 않고 보이는 효과도 있다.
  List<StrokeData> _denormalizeComposedToCanvas(List<StrokeData> strokes) {
    return strokes.map((stroke) {
      return StrokeData(
        points: stroke.points.map((p) {
          final centeredX = 0.5 + (p.x - 0.5) * _previewScale;
          final centeredY = 0.5 + (p.y - 0.5) * _previewScale;
          return PointData(
            x: centeredX * canvasSize,
            y: centeredY * canvasSize,
            pressure: p.pressure,
          );
        }).toList(),
      );
    }).toList();
  }

  Future<void> _loadBaseFromServer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final fetched = await ApiService.getLatestHandwriting();

      if (fetched != null && fetched.isNotEmpty) {
        setState(() {
          _baseStrokes = fetched;
        });

        _baseCanvasKey.currentState
            ?.loadStrokes(_denormalizeToCanvas(fetched));
        _composedCanvasKey.currentState?.clearPoints();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📥 DB에서 불러왔습니다 (⚠️ /latest는 charName을 구분하지 않고 '
                'DB에 가장 최근 저장된 글자를 반환합니다)',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 불러올 데이터가 없거나 실패했습니다.')),
          );
        }
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _runCompose() {
    List<StrokeData>? baseForCompose;

    if (_isDbBacked) {
      // ㄱ: DB에서 이미 불러와 정규화된 _baseStrokes를 그대로 사용.
      if (!_isBaseLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('먼저 "DB에서 불러오기"로 원본 글자를 불러와주세요.')),
        );
        return;
      }
      baseForCompose = _baseStrokes;
    } else {
      // ㄷ/ㅂ/ㅅ/ㅈ: 왼쪽 캔버스에 사용자가 직접 그린 원본 픽셀 좌표를 가져와서
      // 정규화(0~1)한 뒤 합성 원본으로 사용한다.
      final rawStrokes = _baseCanvasKey.currentState?.getValidPoints();

      if (rawStrokes == null || rawStrokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('먼저 왼쪽 캔버스에 ${_selectedPair.single}을(를) 직접 그려주세요.'),
          ),
        );
        return;
      }

      final normalized = NormalizationService.normalizeStrokes(rawStrokes);
      _baseStrokes = normalized;
      baseForCompose = normalized;
    }

    final composed = DoubleJamoComposer.compose(baseForCompose!, _params);
    _lastComposed = composed;
    _composedCanvasKey.currentState
        ?.loadStrokes(_denormalizeComposedToCanvas(composed));
  }

  // 미리보기 배율 슬라이더 전용: gap/scale/baseHeight는 그대로 두고
  // 이미 계산된 마지막 합성 결과를 새 배율로 다시 그리기만 한다.
  // (공식을 다시 계산할 필요가 없어 즉시 반영된다.)
  void _redrawComposedPreview() {
    if (_lastComposed == null) return;
    _composedCanvasKey.currentState
        ?.loadStrokes(_denormalizeComposedToCanvas(_lastComposed!));
  }

  void _clearAll() {
    setState(() {
      _baseStrokes = null;
      _lastComposed = null;
    });
    _baseCanvasKey.currentState?.clearPoints();
    _composedCanvasKey.currentState?.clearPoints();
  }

  void _onSelectPair(JamoPair pair) {
    if (_selectedPair.single == pair.single) return;
    setState(() {
      _selectedPair = pair;
      _baseStrokes = null;
      _lastComposed = null;
    });
    // 다른 자음으로 바꾸면 이전 자음의 그림/합성 결과는 의미가 없으므로 비운다.
    _baseCanvasKey.currentState?.clearPoints();
    _composedCanvasKey.currentState?.clearPoints();
  }

  Widget _buildPairSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: kDoubleJamoPairs.map((pair) {
        final bool isSelected = _selectedPair.single == pair.single;
        return ElevatedButton(
          onPressed: () => _onSelectPair(pair),
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? Colors.black : Colors.grey.shade300,
            foregroundColor: isSelected ? Colors.white : Colors.black,
            minimumSize: const Size(64, 42),
          ),
          child: Text(
            '${pair.single} → ${pair.double}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSlider({
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
        Text(
          '$label: ${value.toStringAsFixed(3)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(3),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildCanvasColumn({
    required String title,
    required GlobalKey<DrawingCanvasState> canvasKey,
    required Color titleColor,
    required bool readOnly,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
        ),
        const SizedBox(height: 10),
        DrawingCanvas(
          key: canvasKey,
          size: canvasSize,
          readOnly: readOnly,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('쌍자음 합성 테스트'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              _isDbBacked
                  ? '자음 선택 (${_selectedPair.single}은(는) DB에서 불러와서 확인)'
                  : '자음 선택 (${_selectedPair.single}은(는) DB에 없어 왼쪽 캔버스에 직접 그려서 확인)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _buildPairSelector(),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCanvasColumn(
                  title: _isDbBacked
                      ? '[ 원본 ${_selectedPair.single} (DB) ]'
                      : '[ 원본 ${_selectedPair.single} (직접 그리기) ]',
                  canvasKey: _baseCanvasKey,
                  titleColor: Colors.black,
                  // ㄱ은 DB에서 불러온 걸 보여주기만 하는 읽기 전용 프리뷰,
                  // 나머지는 사용자가 직접 그려야 하므로 필기 가능하게 둔다.
                  readOnly: _isDbBacked,
                ),
                const SizedBox(width: 30),
                _buildCanvasColumn(
                  title: '[ 합성 ${_selectedPair.double} ]',
                  canvasKey: _composedCanvasKey,
                  titleColor: Colors.blue,
                  readOnly: true,
                ),
              ],
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildSlider(
                    label: 'gap (간격)',
                    value: _params.gap,
                    min: 0.0,
                    max: 0.3,
                    divisions: 60,
                    onChanged: (v) {
                      setState(() {
                        _params = _params.copyWith(gap: v);
                      });
                    },
                  ),
                  _buildSlider(
                    label: 'scale (오른쪽 배율)',
                    value: _params.scale,
                    min: 0.5,
                    max: 2.0,
                    divisions: 60,
                    onChanged: (v) {
                      setState(() {
                        _params = _params.copyWith(scale: v);
                      });
                    },
                  ),
                  _buildSlider(
                    label: 'baseHeight (세로 비율)',
                    value: _params.baseHeight,
                    min: 0.3,
                    max: 1.0,
                    divisions: 70,
                    onChanged: (v) {
                      setState(() {
                        _params = _params.copyWith(baseHeight: v);
                      });
                    },
                  ),
                  const Divider(height: 32),
                  _buildSlider(
                    label: '미리보기 축소 배율 (캔버스 표시 전용)',
                    value: _previewScale,
                    min: 0.3,
                    max: 1.0,
                    divisions: 70,
                    onChanged: (v) {
                      setState(() {
                        _previewScale = v;
                      });
                      _redrawComposedPreview();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                // ㄱ일 때만 DB 불러오기 버튼을 보여준다.
                // 나머지 자음은 왼쪽 캔버스에 바로 그리면 되므로 이 버튼이 필요 없다.
                if (_isDbBacked)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _loadBaseFromServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size(120, 45),
                    ),
                    child: Text(
                      _isLoading
                          ? '불러오는 중...'
                          : 'DB에서 ${_selectedPair.single} 불러오기',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ElevatedButton(
                  onPressed: _runCompose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(120, 45),
                  ),
                  child: const Text(
                    '합성 실행',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _clearAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    minimumSize: const Size(100, 45),
                  ),
                  child: const Text(
                    '초기화',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (!_isDbBacked) ...[
              const SizedBox(height: 12),
              Text(
                '💡 왼쪽 캔버스에 ${_selectedPair.single}을(를) 쓴 뒤 "합성 실행"을 누르면 '
                '그 글씨를 정규화해서 합성에 사용합니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}