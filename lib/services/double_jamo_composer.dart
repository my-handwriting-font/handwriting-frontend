import '../models/handwriting_model.dart';

/// 0~1 정규화 좌표 공간 위의 사각형 영역.
/// (x, y)는 좌상단 기준, w/h는 너비/높이.
class ComposeBox {
  final double x;
  final double y;
  final double w;
  final double h;

  const ComposeBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  @override
  String toString() =>
      'Box(x=${x.toStringAsFixed(3)}, y=${y.toStringAsFixed(3)}, '
      'w=${w.toStringAsFixed(3)}, h=${h.toStringAsFixed(3)})';
}

/// 쌍자음이 놓이는 위치. baseHeight(왼쪽 자음 높이 / 전체 폭) 프리셋에 쓴다.
/// 폰트 실측값 (Pretendard, Noto Sans KR, 나눔고딕, 나눔명조 레귤러).
enum DoubleJamoPosition {
  /// 초성, 받침 없음 (예: 까) — 실측 ≈1.03, 슬라이더 최댓값 1.0으로 제한
  choseongOpen('초성·받침없음', 1.0),

  /// 초성, 받침 있음 (예: 깐) — 실측 ≈0.74
  choseongClosed('초성·받침있음', 0.74),

  /// 받침 (예: 밖) — 실측 ≈0.52
  jongseong('받침', 0.52);

  final String label;
  final double baseHeight;

  const DoubleJamoPosition(this.label, this.baseHeight);
}

/// 자음별 gap 기본값 (초성 기준, 전체 폭 대비). 폰트 실측값.
/// ㄱ은 살짝 겹치고, ㅅ·ㅈ은 겹치므로 0으로 둔다 (실측은 0 이하).
/// 받침 ㄲ은 실측 ≈0.05.
const Map<String, double> kDoubleJamoGap = {
  'ㄱ': 0.0,
  'ㄷ': 0.05,
  'ㅂ': 0.09,
  'ㅅ': 0.0,
  'ㅈ': 0.0,
};

/// gap/scale/baseHeight 파라미터 묶음.
/// 화면의 슬라이더 값과 1:1로 대응됨.
///
/// 기본값은 폰트 실측 기준이다: 좌우 폭 비율 ≈1.0, 윗선 정렬.
/// (이전 기본값 scale=1.08 + 아래선 정렬은 실제 폰트와 반대로
/// 오른쪽이 위로 튀어나왔다.)
class DoubleJamoParams {
  final double gap;
  final double scale;
  final double baseHeight;

  const DoubleJamoParams({
    this.gap = 0.05,
    this.scale = 1.0,
    this.baseHeight = 1.0,
  });

  /// 자음과 위치에 맞는 실측 기본값.
  factory DoubleJamoParams.forJamo(
    String single, {
    DoubleJamoPosition position = DoubleJamoPosition.choseongOpen,
  }) {
    return DoubleJamoParams(
      gap: kDoubleJamoGap[single] ?? 0.05,
      scale: 1.0,
      baseHeight: position.baseHeight,
    );
  }

  DoubleJamoParams copyWith({
    double? gap,
    double? scale,
    double? baseHeight,
  }) {
    return DoubleJamoParams(
      gap: gap ?? this.gap,
      scale: scale ?? this.scale,
      baseHeight: baseHeight ?? this.baseHeight,
    );
  }
}

/// gap/scale/baseHeight → leftBox/rightBox 계산 결과.
/// 왼쪽은 기본 크기, 오른쪽은 scale배로 배치한다 (윗선 정렬).
class DoubleJamoLayout {
  final ComposeBox leftBox;
  final ComposeBox rightBox;

  const DoubleJamoLayout({required this.leftBox, required this.rightBox});
}

/// 쌍자음(ㄲ, ㄸ, ㅃ, ㅆ, ㅉ) 합성 로직.
///
/// 단자음(ㄱ, ㄷ, ㅂ, ㅅ, ㅈ 등)의 0~1 정규화 좌표를 그대로 복사해서
/// 좌우로 배치한다. 폰트 실측에서 좌우 폭·높이 비율이 ≈1.0이고 윗선이
/// 맞으므로 기본 scale은 1.0이다 (ㄲ만 오른쪽이 6~18% 더 길고, ㄸ은 폭 ≈1.12).
///
/// 자음 종류에 의존하지 않는 순수 함수이므로 ㄱ/ㄷ/ㅂ/ㅅ/ㅈ 어디에든
/// 동일하게 적용 가능하다.
class DoubleJamoComposer {
  /// gap, scale, baseHeight로부터 leftBox/rightBox를 계산한다.
  static DoubleJamoLayout computeLayout(DoubleJamoParams params) {
    final gap = params.gap;
    final scale = params.scale;
    final baseHeight = params.baseHeight;

    final leftW = (1 - gap) / (1 + scale);
    final rightW = leftW * scale;

    // 윗선 정렬: 두 박스의 y를 같게 둔다 (실측 top 차이 ≈0).
    // 왼쪽 박스의 아랫선은 이전과 같이 1에 고정된다.
    final top = 1 - baseHeight;

    final leftBox = ComposeBox(
      x: 0,
      y: top,
      w: leftW,
      h: baseHeight,
    );

    final rightBox = ComposeBox(
      x: leftW + gap,
      y: top,
      w: rightW,
      h: baseHeight * scale,
    );

    return DoubleJamoLayout(leftBox: leftBox, rightBox: rightBox);
  }

  /// 원본(0~1) StrokeData 리스트를 지정된 box 범위로 리스케일(remap)한다.
  /// 원본 좌표가 이미 0~1 범위라고 가정하고, 그 범위를 box 안으로 선형 매핑한다.
  static List<StrokeData> _remapStrokes(
    List<StrokeData> original,
    ComposeBox box,
  ) {
    return original.map((stroke) {
      final remappedPoints = stroke.points.map((p) {
        return PointData(
          x: box.x + p.x * box.w,
          y: box.y + p.y * box.h,
          pressure: p.pressure,
        );
      }).toList();

      return StrokeData(points: remappedPoints);
    }).toList();
  }

  /// 단자음 원본 좌표(0~1) 하나로부터 쌍자음 좌표 리스트를 합성한다.
  /// 왼쪽/오른쪽 모두 같은 원본을 복사해서 각자의 box로 리맵한 뒤 합친다.
  static List<StrokeData> compose(
    List<StrokeData> baseStrokes,
    DoubleJamoParams params,
  ) {
    if (baseStrokes.isEmpty) return [];

    final layout = computeLayout(params);

    final leftStrokes = _remapStrokes(baseStrokes, layout.leftBox);
    final rightStrokes = _remapStrokes(baseStrokes, layout.rightBox);

    return [...leftStrokes, ...rightStrokes];
  }

  /// 서로 다른 두 자음(겹받침 ㄳ ㄵ ...)을 왼쪽/오른쪽에 넣는다.
  /// 배치 공식은 compose(쌍자음)와 똑같다. 왼쪽과 오른쪽 원본만 다르다.
  static List<StrokeData> composePair(
    List<StrokeData> leftStrokes,
    List<StrokeData> rightStrokes,
    DoubleJamoParams params,
  ) {
    if (leftStrokes.isEmpty || rightStrokes.isEmpty) return [];

    final layout = computeLayout(params);

    return [
      ..._remapStrokes(leftStrokes, layout.leftBox),
      ..._remapStrokes(rightStrokes, layout.rightBox),
    ];
  }
}

/// 겹받침 → [왼쪽 자음, 오른쪽 자음].
/// 쌍자음 받침(ㄲ ㅆ)과 같은 규칙으로 합성한다 (finalPairParams).
const Map<String, List<String>> kCompoundFinals = {
  'ㄳ': ['ㄱ', 'ㅅ'],
  'ㄵ': ['ㄴ', 'ㅈ'],
  'ㄶ': ['ㄴ', 'ㅎ'],
  'ㄺ': ['ㄹ', 'ㄱ'],
  'ㄻ': ['ㄹ', 'ㅁ'],
  'ㄼ': ['ㄹ', 'ㅂ'],
  'ㄽ': ['ㄹ', 'ㅅ'],
  'ㄾ': ['ㄹ', 'ㅌ'],
  'ㄿ': ['ㄹ', 'ㅍ'],
  'ㅀ': ['ㄹ', 'ㅎ'],
  'ㅄ': ['ㅂ', 'ㅅ'],
};

/// 받침 자리에 두 자음을 나란히 넣을 때의 파라미터.
/// 쌍자음 받침(ㄲ ㅆ)과 겹받침(ㄳ ㄵ ...)이 모두 이 값을 쓴다:
/// 받침 프리셋(baseHeight 0.52), 좌우 비율 1.0, 간격은 왼쪽 자음 기준(kDoubleJamoGap, 없으면 0.05).
DoubleJamoParams finalPairParams(String leftConsonant) =>
    DoubleJamoParams.forJamo(
      leftConsonant,
      position: DoubleJamoPosition.jongseong,
    );

/// 단자음 → 쌍자음 매핑. 지금은 ㄱ→ㄲ만 DB 연동이 되지만,
/// 합성 공식 자체는 자음 종류에 무관하므로 구조만 미리 확장해둔다.
class JamoPair {
  final String single;
  final String double;

  const JamoPair(this.single, this.double);
}

const List<JamoPair> kDoubleJamoPairs = [
  JamoPair('ㄱ', 'ㄲ'),
  JamoPair('ㄷ', 'ㄸ'),
  JamoPair('ㅂ', 'ㅃ'),
  JamoPair('ㅅ', 'ㅆ'),
  JamoPair('ㅈ', 'ㅉ'),
];