import 'dart:math' as math;

import '../models/handwriting_model.dart';
import 'double_jamo_composer.dart' show ComposeBox;

/// 모음이 자음의 오른쪽에 붙는지(ㅏ 계열), 아래에 붙는지(ㅗ 계열)
enum VowelOrientation {
  /// ㅏ ㅐ ㅑ ㅓ ㅔ ㅕ ㅣ : 자음 오른쪽에 붙음 (가, 나, 다 ...)
  vertical,

  /// ㅗ ㅛ ㅜ ㅠ ㅡ : 자음 아래에 붙음 (고, 구, 그 ...)
  horizontal,
}

const List<String> kChoseongChoices = [
  'ㄱ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

const List<String> kVowelChoices = [
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅣ', // 세로 모음
  'ㅗ', 'ㅛ', 'ㅜ', 'ㅠ', 'ㅡ', // 가로 모음
];

VowelOrientation orientationOf(String vowel) {
  const horizontal = ['ㅗ', 'ㅛ', 'ㅜ', 'ㅠ', 'ㅡ'];
  return horizontal.contains(vowel)
      ? VowelOrientation.horizontal
      : VowelOrientation.vertical;
}

// ------------------------------------------------------------ 그룹 / 케이스

/// 한 방향(세로형 또는 가로형)의 분류 리스트. 방향마다 따로 저장한다.
/// 그룹 번호를 직접 적고, 리스트에 없는 글자는 그 리스트의 첫 그룹으로 본다.
class SyllableRules {
  /// 자음 그룹 번호 → 글자
  final Map<int, List<String>> consonants;

  /// 모음 그룹 번호 → 글자
  final Map<int, List<String>> vowels;

  /// 모음과 겹치면 자동으로 오른쪽으로 미는 자음 (다리가 왼쪽 아래로 내려가는 자음)
  final List<String> shiftRight;

  /// 다리 각도 조정(avoidMode 2)을 적용할 자음
  final List<String> legAdjust;

  const SyllableRules({
    required this.consonants,
    required this.vowels,
    this.shiftRight = const [],
    this.legAdjust = const [],
  });
  static int? _find(Map<int, List<String>> m, String ch) {
    for (final e in m.entries) {
      if (e.value.contains(ch)) return e.key;
    }
    return null;
  }

  int consonantGroupOf(String c) =>
      _find(consonants, c) ?? consonants.keys.first;

  int vowelGroupOf(String v) => _find(vowels, v) ?? vowels.keys.first;

  /// 케이스 번호 계산용: 그룹이 몇 번째인지 (0부터)
  int consonantIndexOf(String c) =>
      consonants.keys.toList().indexOf(consonantGroupOf(c));

  int vowelIndexOf(String v) => vowels.keys.toList().indexOf(vowelGroupOf(v));
}

/// 1번: 세로형 (모음이 자음 오른쪽: ㅏ ㅐ ㅑ ㅓ ㅔ ㅕ ㅣ)
const SyllableRules kVerticalRules = SyllableRules(
  consonants: {
    1: ['ㄱ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅋ', 'ㅌ', 'ㅎ'],
    2: ['ㄴ', 'ㄷ', 'ㅈ', 'ㅊ', 'ㅍ'],
  },
  vowels: {
    3: ['ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅣ'],
    4: ['ㅓ', 'ㅔ', 'ㅕ', 'ㅖ'],
  },
);

/// 3번: 가로형 (모음이 자음 아래: ㅗ ㅛ ㅜ ㅠ ㅡ)
const SyllableRules kHorizontalRules = SyllableRules(
  consonants: {
    1: ['ㄱ', 'ㅅ', 'ㅋ', 'ㅈ', 'ㅊ'],
    2: ['ㄹ', 'ㅁ', 'ㅂ', 'ㅇ', 'ㅌ', 'ㅎ', 'ㄴ', 'ㄷ', 'ㅍ'],
  },
  vowels: {
    5: ['ㅗ', 'ㅛ'],
    6: ['ㅜ', 'ㅠ'],
    7: ['ㅡ'],
  },
  shiftRight: ['ㄱ', 'ㅋ'],
  legAdjust: ['ㄱ', 'ㅋ'],
);

/// 모음의 방향에 맞는 분류 리스트
SyllableRules rulesOf(VowelOrientation o) =>
    o == VowelOrientation.vertical ? kVerticalRules : kHorizontalRules;

int consonantGroupOf(String c, VowelOrientation o) =>
    rulesOf(o).consonantGroupOf(c);

int vowelGroupOf(String v) => rulesOf(orientationOf(v)).vowelGroupOf(v);

const List<String> _kCaseMarks = [
  '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩',
  '⑪', '⑫', '⑬', '⑭', '⑮', '⑯', '⑰', '⑱', '⑲', '⑳',
];

/// 케이스 번호 (받침 없음). 세로형 케이스가 먼저, 가로형이 그 뒤에 온다.
int caseIdOf(String c, String v) {
  final o = orientationOf(v);
  final r = rulesOf(o);
  final base = o == VowelOrientation.vertical
      ? 0
      : kVerticalRules.consonants.length * kVerticalRules.vowels.length;
  return base + r.consonantIndexOf(c) * r.vowels.length + r.vowelIndexOf(v);
}

String caseMarkOf(int id) =>
    id >= 0 && id < _kCaseMarks.length ? _kCaseMarks[id] : '#${id + 1}';

String caseLabelOf(String c, String v) {
  final o = orientationOf(v);
  return '케이스 ${caseMarkOf(caseIdOf(c, v))} '
      '(자음 ${consonantGroupOf(c, o)}그룹 × 모음 ${vowelGroupOf(v)}그룹)';
}

/// 세로형 규칙값. 키는 케이스 번호(0~3 = ①~④). 적지 않은 값은 세로형 기본값이다.
/// ① 자음1×모음3 / ② 자음1×모음4 / ③ 자음2×모음3 / ④ 자음2×모음4
/// 겹침 방지 여백은 끔(0).
const Map<int, SyllableParams> kVerticalRuleParams = {
  0: SyllableParams(gap: -0.045, aspectKeep: 0.6),
  1: SyllableParams(gap: -0.1, aspectKeep: 0.5),
  2: SyllableParams(gap: 0.0, aspectKeep: 0.5),
  3: SyllableParams(gap: -0.125, aspectKeep: 0.5),
};
/// 가로형 규칙값. 키는 케이스 번호(4~9 = ⑤~⑩). 적지 않은 값은 가로형 기본값이다.
/// ⑤ 자음1×모음5(ㅗㅛ) / ⑥ 자음1×모음6(ㅜㅠ) / ⑦ 자음1×모음7(ㅡ)
/// ⑧ 자음2×모음5 / ⑨ 자음2×모음6 / ⑩ 자음2×모음7
/// 위쪽 배율 = consonantScale, 아래쪽 배율 = vowelScale, 모음 가로 길이 = vowelCross.
/// 가로형 기본값(vowelShare 0.35, consonantCross 0.60, vowelCross 0.90)을 값마다 직접 적는다.
const Map<int, SyllableParams> kHorizontalRuleParams = {
  4: SyllableParams(
    gap: 0.025,
    consonantScale: 0.92,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.90,
    clearance: 0.12,
    avoidMode: 2,
    maxPush: 0.03,
    maxAngle: 70.0,
    minLegScale: 0.67,
  ),
  5: SyllableParams(
    gap: 0.055,
    consonantScale: 0.82,
    vowelScale: 1.0,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.90,
  ),
  6: SyllableParams(
    gap: -0.055,
    consonantScale: 0.88,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.73,
  ),
  7: SyllableParams(
    gap: 0.05,
    consonantScale: 0.9,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.90,
  ),
  8: SyllableParams(
    gap: 0.1,
    consonantScale: 0.8,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.90,
  ),
  9: SyllableParams(
    gap: -0.07,
    consonantScale: 0.88,
    vowelShare: 0.35,
    consonantCross: 0.60,
    vowelCross: 0.73,
  ),
};

/// 이 조합의 규칙값. 규칙이 정해지지 않은 조합은 null.
SyllableParams? ruleParamsOf(String c, String v) {
  final id = caseIdOf(c, v);
  return orientationOf(v) == VowelOrientation.vertical
      ? kVerticalRuleParams[id]
      : kHorizontalRuleParams[id];
}
/// 받침 있는 글자의 위(초성+모음)/아래(종성) 박스 파라미터. 0~1 정규화 공간.
/// 위쪽 박스에는 위의 케이스별 규칙값(kVerticalRuleParams 등)으로 합성한
/// 초성+모음이 통째로 들어가고, 종성은 아래 박스에 들어간다.
class FinalBoxParams {
  /// 위쪽 박스(초성+모음) 높이
  final double upperHeight;

  /// 위쪽 박스 폭
  final double upperWidth;

  /// 종성 박스 높이
  final double jongHeight;

  /// 종성 박스 폭
  final double jongWidth;

  /// 위/아래 박스 사이 간격 (음수면 겹침)
  final double gap;

  /// 종성 좌우 위치 이동 (+가 오른쪽)
  final double jongOffsetX;

  /// 종성 원본 비율 유지 정도 (0=박스 채우기, 1=비율 그대로)
  final double jongAspectKeep;

  const FinalBoxParams({
    this.upperHeight = 0.60,
    this.upperWidth = 1.0,
    this.jongHeight = 0.32,
    this.jongWidth = 0.75,
    this.gap = 0.03,
    this.jongOffsetX = 0.0,
    this.jongAspectKeep = 0.5,
  });

  FinalBoxParams copyWith({
    double? upperHeight,
    double? upperWidth,
    double? jongHeight,
    double? jongWidth,
    double? gap,
    double? jongOffsetX,
    double? jongAspectKeep,
  }) {
    return FinalBoxParams(
      upperHeight: upperHeight ?? this.upperHeight,
      upperWidth: upperWidth ?? this.upperWidth,
      jongHeight: jongHeight ?? this.jongHeight,
      jongWidth: jongWidth ?? this.jongWidth,
      gap: gap ?? this.gap,
      jongOffsetX: jongOffsetX ?? this.jongOffsetX,
      jongAspectKeep: jongAspectKeep ?? this.jongAspectKeep,
    );
  }

  String toDisplayString() {
    String f(double v) => v.toStringAsFixed(3);
    return 'upperHeight=${f(upperHeight)}, upperWidth=${f(upperWidth)}, '
        'jongHeight=${f(jongHeight)}, jongWidth=${f(jongWidth)}, '
        'gap=${f(gap)}, jongOffsetX=${f(jongOffsetX)}, '
        'jongAspectKeep=${f(jongAspectKeep)}';
  }
}

/// 2번: 세로형 받침 있음 규칙값. 키는 1번과 같은 케이스 번호(0~3 = ①~④).
/// 초성+모음 부분은 위의 kVerticalRuleParams(1번)를 그대로 쓰고,
/// 여기서는 위쪽 박스/종성 박스의 크기와 위치만 정한다.
/// ① 자음1×모음3 / ② 자음1×모음4 / ③ 자음2×모음3 / ④ 자음2×모음4
/// 지금은 네 케이스 모두 같은 값이다 (나눌 필요가 생기면 그 케이스만 바꾼다).
/// 값은 값마다 직접 적는다.
const Map<int, FinalBoxParams> kVerticalFinalRuleParams = {
  0: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.50,
    gap: -0.03,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  1: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.50,
    gap: -0.03,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  2: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.50,
    gap: -0.03,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  3: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.50,
    gap: -0.03,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
};

/// 4번: 가로형 받침 있음 규칙값. 키는 3번과 같은 케이스 번호(4~9 = ⑤~⑩).
/// 초성+모음 부분은 위의 kHorizontalRuleParams(3번)를 그대로 쓰고
/// (자동 오른쪽 밀기, 다리 각도 조정 포함), 여기서는 위쪽 박스/종성 박스만 정한다.
/// ⑤ 자음1×모음5(ㅗㅛ) / ⑥ 자음1×모음6(ㅜㅠ) / ⑦ 자음1×모음7(ㅡ)
/// ⑧ 자음2×모음5 / ⑨ 자음2×모음6 / ⑩ 자음2×모음7
/// 지금은 여섯 케이스 모두 같은 값이다 (나눌 필요가 생기면 그 케이스만 바꾼다).
/// 값은 값마다 직접 적는다.
const Map<int, FinalBoxParams> kHorizontalFinalRuleParams = {
  4: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  5: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  6: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  7: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  8: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  9: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.32,
    jongWidth: 0.40,
    gap: 0.145,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
};

/// 이 조합의 받침 있는 글자 규칙값. 규칙이 정해지지 않은 조합은 null.
FinalBoxParams? finalRuleParamsOf(String c, String v) =>
    orientationOf(v) == VowelOrientation.vertical
        ? kVerticalFinalRuleParams[caseIdOf(c, v)]
        : kHorizontalFinalRuleParams[caseIdOf(c, v)];

// ------------------------------------------------------------ 혼합 모음

/// 혼합 모음(ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ)을 이루는 두 조각.
class CompoundVowelPieces {
  /// 가로 조각 (ㅗ ㅜ ㅡ)
  final String horizontal;

  /// 세로 조각 (ㅏ ㅐ ㅣ ㅓ ㅔ)
  final String vertical;

  const CompoundVowelPieces(this.horizontal, this.vertical);
}

/// 혼합 모음 → 가로 조각 + 세로 조각
const Map<String, CompoundVowelPieces> kCompoundVowelPieces = {
  'ㅘ': CompoundVowelPieces('ㅗ', 'ㅏ'),
  'ㅙ': CompoundVowelPieces('ㅗ', 'ㅐ'),
  'ㅚ': CompoundVowelPieces('ㅗ', 'ㅣ'),
  'ㅝ': CompoundVowelPieces('ㅜ', 'ㅓ'),
  'ㅞ': CompoundVowelPieces('ㅜ', 'ㅔ'),
  'ㅟ': CompoundVowelPieces('ㅜ', 'ㅣ'),
  'ㅢ': CompoundVowelPieces('ㅡ', 'ㅣ'),
};

const List<String> kCompoundVowelChoices = [
  'ㅘ', 'ㅙ', 'ㅚ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅢ',
];

/// 혼합 모음 그룹. 같은 그룹은 같은 규칙값을 쓴다.
/// 1 = ㅘ ㅙ ㅚ ㅟ ㅢ / 2 = ㅝ ㅞ (ㅓ·ㅔ의 튀어나온 획을 ㅜ 줄기 가운데에 맞춤)
const Map<int, List<String>> kCompoundVowelGroups = {
  1: ['ㅘ', 'ㅙ', 'ㅚ', 'ㅟ', 'ㅢ'],
  2: ['ㅝ', 'ㅞ'],
};

/// 혼합 모음의 그룹 번호. 목록에 없으면 1.
int compoundVowelGroupOf(String v) {
  for (final e in kCompoundVowelGroups.entries) {
    if (e.value.contains(v)) return e.key;
  }
  return 1;
}

/// ㅓ·ㅔ의 왼쪽으로 튀어나온 획을 ㅜ 줄기(아래로 내려온 획)의
/// 세로 가운데 높이로 옮기는 모음.
const List<String> kStemAlignVowels = ['ㅝ', 'ㅞ'];

/// 혼합 모음 합성 파라미터. 0~1 정규화 공간(글자 한 칸 = 1x1) 기준.
/// 위치(X, Y)는 각 조각 박스의 가운데 좌표다.
/// 기본값은 측정값이 아니라 눈으로 맞추기 위한 출발점이다
/// (가로 조각은 왼쪽 아래, 세로 조각은 오른쪽에 길게).
class CompoundVowelParams {
  /// 가로 조각 박스 폭
  final double horzWidth;

  /// 가로 조각 박스 높이
  final double horzHeight;

  /// 가로 조각 박스 가운데 x
  final double horzX;

  /// 가로 조각 박스 가운데 y
  final double horzY;

  /// 가로 조각 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)
  final double horzAspectKeep;

  /// 세로 조각 박스 폭
  final double vertWidth;

  /// 세로 조각 박스 높이
  final double vertHeight;

  /// 세로 조각 박스 가운데 x
  final double vertX;

  /// 세로 조각 박스 가운데 y
  final double vertY;

  /// 세로 조각 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)
  final double vertAspectKeep;

  /// (ㅝ ㅞ 전용) 튀어나온 획 상하 미세 조정.
  /// 0이면 ㅜ 줄기의 세로 가운데, +면 아래쪽, -면 위쪽.
  final double tickOffsetY;

  const CompoundVowelParams({
    this.horzWidth = 0.60,
    this.horzHeight = 0.30,
    this.horzX = 0.38,
    this.horzY = 0.65,
    this.horzAspectKeep = 0.5,
    this.vertWidth = 0.22,
    this.vertHeight = 0.85,
    this.vertX = 0.78,
    this.vertY = 0.50,
    this.vertAspectKeep = 0.5,
    this.tickOffsetY = 0.0,
  });

  /// 가로 조각 박스
  ComposeBox get horzBox => ComposeBox(
        x: horzX - horzWidth / 2,
        y: horzY - horzHeight / 2,
        w: horzWidth,
        h: horzHeight,
      );

  /// 세로 조각 박스
  ComposeBox get vertBox => ComposeBox(
        x: vertX - vertWidth / 2,
        y: vertY - vertHeight / 2,
        w: vertWidth,
        h: vertHeight,
      );

  CompoundVowelParams copyWith({
    double? horzWidth,
    double? horzHeight,
    double? horzX,
    double? horzY,
    double? horzAspectKeep,
    double? vertWidth,
    double? vertHeight,
    double? vertX,
    double? vertY,
    double? vertAspectKeep,
    double? tickOffsetY,
  }) {
    return CompoundVowelParams(
      horzWidth: horzWidth ?? this.horzWidth,
      horzHeight: horzHeight ?? this.horzHeight,
      horzX: horzX ?? this.horzX,
      horzY: horzY ?? this.horzY,
      horzAspectKeep: horzAspectKeep ?? this.horzAspectKeep,
      vertWidth: vertWidth ?? this.vertWidth,
      vertHeight: vertHeight ?? this.vertHeight,
      vertX: vertX ?? this.vertX,
      vertY: vertY ?? this.vertY,
      vertAspectKeep: vertAspectKeep ?? this.vertAspectKeep,
      tickOffsetY: tickOffsetY ?? this.tickOffsetY,
    );
  }

  String toDisplayString() {
    String f(double v) => v.toStringAsFixed(3);
    return 'horzWidth=${f(horzWidth)}, horzHeight=${f(horzHeight)}, '
        'horzX=${f(horzX)}, horzY=${f(horzY)}, '
        'horzAspectKeep=${f(horzAspectKeep)}, '
        'vertWidth=${f(vertWidth)}, vertHeight=${f(vertHeight)}, '
        'vertX=${f(vertX)}, vertY=${f(vertY)}, '
        'vertAspectKeep=${f(vertAspectKeep)}, '
        'tickOffsetY=${f(tickOffsetY)}';
  }
}

/// 혼합 모음 규칙값. 키는 그룹 번호(1 = ㅘ ㅙ ㅚ ㅟ ㅢ, 2 = ㅝ ㅞ).
/// 테스트 화면에서 맞춘 값을 여기에 적는다. 값은 값마다 직접 적는다.
const Map<int, CompoundVowelParams> kCompoundVowelRuleParams = {
  // 그룹 1: ㅘ ㅙ ㅚ ㅟ ㅢ
  1: CompoundVowelParams(
    horzWidth: 0.50,
    horzHeight: 0.21,
    horzX: 0.43,
    horzY: 0.66,
    horzAspectKeep: 0.5,
    vertWidth: 0.18,
    vertHeight: 1.0,
    vertX: 0.76,
    vertY: 0.51,
    vertAspectKeep: 0.5,
    tickOffsetY: 0.0,
  ),
  // 그룹 2: ㅝ ㅞ
  2: CompoundVowelParams(
    horzWidth: 0.60,
    horzHeight: 0.30,
    horzX: 0.45,
    horzY: 0.65,
    horzAspectKeep: 0.5,
    vertWidth: 0.22,
    vertHeight: 0.85,
    vertX: 0.78,
    vertY: 0.50,
    vertAspectKeep: 0.5,
    tickOffsetY: 0.0,
  ),
};

/// 이 혼합 모음의 규칙값(그룹 기준). 규칙이 정해지지 않았으면 null.
CompoundVowelParams? compoundVowelRuleParamsOf(String v) =>
    kCompoundVowelRuleParams[compoundVowelGroupOf(v)];

/// 획 하나의 경계 상자
class _StrokeBounds {
  final double minX, maxX, minY, maxY;
  const _StrokeBounds(this.minX, this.maxX, this.minY, this.maxY);

  factory _StrokeBounds.of(StrokeData s) {
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final p in s.points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return _StrokeBounds(minX, maxX, minY, maxY);
  }

  double get w => maxX - minX;
  double get h => maxY - minY;
  double get centerY => (minY + maxY) / 2;
}

/// ㅝ ㅞ 자동 맞춤 결과 (옮긴 세로 조각 획 + 화면에 보여줄 상태 문구)
class _TickAlignResult {
  final List<StrokeData> vertical;
  final String status;
  const _TickAlignResult(this.vertical, this.status);
}

/// 한 획을 크게 꺾이는 지점(진행 방향이 turnDeg 넘게 바뀌는 곳)에서 나눈다.
/// 이어 쓴 ㅜ(가로획 → 되돌아옴 → 아래 획)나 ㅓ(짧은 획 → 위 → 아래)를
/// 조각으로 나눠서, 떼어 쓴 것과 똑같이 짧은 획·기둥을 찾을 수 있게 한다.
/// 꺾이는 곳이 없으면 원래 획 하나를 그대로 돌려준다.
List<StrokeData> _splitAtCorners(StrokeData s, {double turnDeg = 60.0}) {
  final pts = s.points;
  final n = pts.length;
  if (n < 5) return [s];

  // 시작점부터의 누적 길이
  final cum = <double>[0.0];
  for (var i = 1; i < n; i++) {
    final dx = pts[i].x - pts[i - 1].x;
    final dy = pts[i].y - pts[i - 1].y;
    cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
  }
  final total = cum.last;
  if (total < 1e-9) return [s];

  // 방향을 볼 때 앞뒤로 이만큼 떨어진 점을 쓴다 (손떨림 무시)
  final w = (total * 0.15).clamp(0.008, 0.03).toDouble();

  // 각 점에서 진행 방향이 꺾이는 각도 (도)
  final turns = List<double>.filled(n, 0.0);
  for (var i = 1; i < n - 1; i++) {
    var a = i;
    while (a > 0 && cum[i] - cum[a] < w) {
      a--;
    }
    var b = i;
    while (b < n - 1 && cum[b] - cum[i] < w) {
      b++;
    }
    if (cum[i] - cum[a] < w * 0.5 || cum[b] - cum[i] < w * 0.5) continue;
    final v1x = pts[i].x - pts[a].x, v1y = pts[i].y - pts[a].y;
    final v2x = pts[b].x - pts[i].x, v2y = pts[b].y - pts[i].y;
    final l1 = math.sqrt(v1x * v1x + v1y * v1y);
    final l2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (l1 < 1e-9 || l2 < 1e-9) continue;
    final c =
        ((v1x * v2x + v1y * v2y) / (l1 * l2)).clamp(-1.0, 1.0).toDouble();
    turns[i] = math.acos(c) * 180 / math.pi;
  }

  // 꺾임이 이어진 구간마다 가장 많이 꺾인 점 하나에서 자른다
  final cuts = <int>[];
  var i = 1;
  while (i < n - 1) {
    if (turns[i] > turnDeg) {
      var j = i;
      while (j + 1 < n - 1 && turns[j + 1] > turnDeg) {
        j++;
      }
      var k = i;
      for (var t = i; t <= j; t++) {
        if (turns[t] > turns[k]) k = t;
      }
      final last = cuts.isEmpty ? 0.0 : cum[cuts.last];
      if (cum[k] - last >= w && total - cum[k] >= w) cuts.add(k);
      i = j + 1;
    } else {
      i++;
    }
  }
  if (cuts.isEmpty) return [s];

  final out = <StrokeData>[];
  var start = 0;
  for (final k in cuts) {
    out.add(StrokeData(points: pts.sublist(start, k + 1)));
    start = k;
  }
  out.add(StrokeData(points: pts.sublist(start)));
  return out;
}

/// ㅝ ㅞ: ㅜ 전체 높이에서 이 비율 지점(위에서부터)을 아래 획의 가운데로 본다.
/// ㅜ는 가로획이 맨 위에 얇게 있으므로, 아래 획의 가운데는 ㅜ 전체 가운데보다
/// 아주 살짝 아래다 (0.5 = 정가운데).
const double kStemMidRatio = 0.53;

/// ㅝ ㅞ: ㅓ·ㅔ의 왼쪽으로 튀어나온 획을 ㅜ 아래 획의 가운데 높이로 옮긴다.
///
/// - ㅜ 쪽은 획을 찾지 않는다. ㅜ 전체(모든 획)의 위아래 범위에서
///   kStemMidRatio 지점을 아래 획의 가운데로 본다. 그래서 ㅜ를 떼어 쓰든
///   이어 쓰든 상관없다.
/// - ㅓ·ㅔ 쪽은 옮길 짧은 획을 골라야 하므로, 획을 크게 꺾이는 곳에서 잘라
///   조각으로 나눈 뒤 폭이 가장 넓은 조각을 짧은 획으로 본다(이어 써도 동작).
///   기둥 = 짧은 획을 뺀 나머지 중 높이가 가장 큰 조각.
/// - 짧은 획만 위아래로 옮기고(좌우는 그대로), 기둥 높이 안으로 제한한다.
/// - 짧은 획이 다른 획과 이어져 있었으면 그 획은 조각으로 나눠서 돌려준다
///   (옮긴 짧은 획과 나머지가 선으로 이어져 그려지지 않게).
_TickAlignResult _alignTickToStem(
  List<StrokeData> horz,
  List<StrokeData> vert,
  double offsetY,
) {
  // ㅜ 전체의 위아래 범위
  var uTop = double.infinity, uBottom = double.negativeInfinity;
  for (final s in horz) {
    for (final p in s.points) {
      if (p.y < uTop) uTop = p.y;
      if (p.y > uBottom) uBottom = p.y;
    }
  }
  if (uTop == double.infinity) {
    return _TickAlignResult(vert, '✗ 자동 맞춤 안 됨: ㅜ 획이 없음');
  }
  final stemMid = uTop + (uBottom - uTop) * kStemMidRatio;

  // ㅓ·ㅔ: 꺾이는 곳에서 잘라 조각으로 나눈다 (원래 획 번호, 조각)
  final vParts = <List<StrokeData>>[for (final s in vert) _splitAtCorners(s)];
  final vSegs = <MapEntry<int, StrokeData>>[
    for (var j = 0; j < vParts.length; j++)
      for (final seg in vParts[j]) MapEntry(j, seg),
  ];
  if (vSegs.length < 2) {
    return _TickAlignResult(
        vert, '✗ 자동 맞춤 안 됨: 세로 조각에서 튀어나온 획과 기둥을 나누지 못함 (꺾이는 곳이 없음)');
  }
  final vb = [for (final e in vSegs) _StrokeBounds.of(e.value)];

  // 튀어나온 획 = 폭이 가장 넓은 조각
  var tickIdx = 0;
  for (var i = 1; i < vb.length; i++) {
    if (vb[i].w > vb[tickIdx].w) tickIdx = i;
  }
  // 기둥 = 튀어나온 획을 뺀 나머지 중 높이가 가장 큰 조각
  var pillarIdx = -1;
  for (var i = 0; i < vb.length; i++) {
    if (i == tickIdx) continue;
    if (pillarIdx < 0 || vb[i].h > vb[pillarIdx].h) pillarIdx = i;
  }
  final tick = vb[tickIdx];
  final pillar = vb[pillarIdx];

  final wanted = stemMid + offsetY;
  final target = wanted.clamp(pillar.minY, pillar.maxY).toDouble();
  final dy = target - tick.centerY;

  StrokeData shifted(StrokeData s) => StrokeData(
        points: s.points
            .map((p) => PointData(x: p.x, y: p.y + dy, pressure: p.pressure))
            .toList(),
      );

  // 튀어나온 획이 들어 있던 원래 획만 조각으로 나눠서 내보내고, 나머지는 그대로
  final tickSeg = vSegs[tickIdx];
  final out = <StrokeData>[];
  for (var j = 0; j < vert.length; j++) {
    if (j != tickSeg.key) {
      out.add(vert[j]);
      continue;
    }
    for (final seg in vParts[j]) {
      out.add(identical(seg, tickSeg.value) ? shifted(seg) : seg);
    }
  }

  final clamped = (target - wanted).abs() > 1e-6;
  final status = clamped
      ? '△ 자동 맞춤 적용: 기둥 끝까지만 옮김 (목표 높이가 기둥 범위 밖)'
      : '✓ 자동 맞춤 적용: 튀어나온 획을 ㅜ 아래 획 가운데로 옮김'
          '${vSegs.length > vert.length ? ' (이어 쓴 획을 꺾인 곳에서 나눠서 찾음)' : ''}';

  return _TickAlignResult(out, status);
}

/// 가로 조각 + 세로 조각 → 혼합 모음 획 (0~1 한 칸 기준).
/// ㅝ ㅞ(kStemAlignVowels)는 튀어나온 획을 ㅜ 아래 획 가운데로 자동으로 옮긴다.
List<StrokeData> composeCompoundVowel({
  required String vowel,
  required NormalizedJamo horizontal,
  required NormalizedJamo vertical,
  required CompoundVowelParams params,
}) {
  final horz = SyllableComposer.remapFit(
      horizontal, params.horzBox, params.horzAspectKeep);
  final vert = SyllableComposer.remapFit(
      vertical, params.vertBox, params.vertAspectKeep);
  if (!kStemAlignVowels.contains(vowel)) return [...horz, ...vert];
  return [...horz, ..._alignTickToStem(horz, vert, params.tickOffsetY).vertical];
}

/// (테스트 화면 안내용) ㅝ ㅞ 자동 맞춤이 적용됐는지와 이유.
/// 자동 맞춤 대상이 아닌 모음이면 null.
String? compoundVowelAlignStatus({
  required String vowel,
  required NormalizedJamo horizontal,
  required NormalizedJamo vertical,
  required CompoundVowelParams params,
}) {
  if (!kStemAlignVowels.contains(vowel)) return null;
  final horz = SyllableComposer.remapFit(
      horizontal, params.horzBox, params.horzAspectKeep);
  final vert = SyllableComposer.remapFit(
      vertical, params.vertBox, params.vertAspectKeep);
  return _alignTickToStem(horz, vert, params.tickOffsetY).status;
}

// ------------------------------------------------------------ 5번: 혼합형 (받침 없음)

/// 5번(혼합형) 분류. 자음 그룹 × 모음 그룹으로 케이스를 나눈다.
/// 모음 그룹은 혼합 모음 규칙 그룹(kCompoundVowelGroups)과 다르다.
///   모음 1 = ㅗ가 들어간 모음 (위로 튀어나온 줄기가 자음 쪽으로 올라감)
///   모음 2 = ㅜ·ㅡ가 들어간 모음 (위가 평평한 가로획)
/// 자음 그룹은 아래가 뚫려 있는지 기준.
///   자음 3 = 아래가 뚫린 자음 / 자음 4 = 아래가 막힌 자음
const SyllableRules kMixedRules = SyllableRules(
  consonants: {
    3: ['ㄱ', 'ㅅ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅎ'],
    4: ['ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅇ', 'ㅌ', 'ㅍ'],
  },
  vowels: {
    1: ['ㅘ', 'ㅙ', 'ㅚ'],
    2: ['ㅝ', 'ㅞ', 'ㅟ', 'ㅢ'],
  },
  legAdjust: ['ㄱ', 'ㅋ'],
);

/// 5번 케이스 번호는 세로형(0~3), 가로형(4~9) 다음인 10부터 쓴다.
const int kMixedCaseBase = 10;

/// 5번 케이스 번호 (10~13 = ⑪~⑭)
/// ⑪ 자음3×모음1 / ⑫ 자음3×모음2 / ⑬ 자음4×모음1 / ⑭ 자음4×모음2
int mixedCaseIdOf(String c, String v) =>
    kMixedCaseBase +
    kMixedRules.consonantIndexOf(c) * kMixedRules.vowels.length +
    kMixedRules.vowelIndexOf(v);

String mixedCaseLabelOf(String c, String v) =>
    '케이스 ${caseMarkOf(mixedCaseIdOf(c, v))} '
    '(자음 ${kMixedRules.consonantGroupOf(c)}그룹 × '
    '모음 ${kMixedRules.vowelGroupOf(v)}그룹)';
/// 다리 각도 조정을 적용할 자음인가 (ㄱ ㅋ)
bool mixedLegAdjustOf(String c) => kMixedRules.legAdjust.contains(c);

/// 5번 합성 파라미터. 혼합 모음은 kCompoundVowelRuleParams 값으로 고정하고
/// 초성 박스만 정한다. 위치(X, Y)는 초성 박스의 가운데 좌표다.
class MixedSyllableParams {
  /// 초성 박스 폭
  final double consWidth;

  /// 초성 박스 높이
  final double consHeight;

  /// 초성 박스 가운데 x
  final double consX;

  /// 초성 박스 가운데 y
  final double consY;

  /// 초성 원본 비율 유지 (0=박스 채우기, 1=비율 그대로)
  final double consAspectKeep;

  /// (ㄱ ㅋ 전용) 다리 각도 조정 여백. 0이면 끈다.
  /// 가로 조각(ㅗ ㅜ ㅡ)을 기준으로 다리를 세운다. 모음은 움직이지 않는다.
  final double clearance;

  /// (ㄱ ㅋ 전용) 다리를 회전할 수 있는 최대 각도 (도)
  final double maxAngle;

  /// (ㄱ ㅋ 전용) 다리 길이를 줄일 수 있는 한계 (원래 길이 대비 최소 비율)
  final double minLegScale;

  const MixedSyllableParams({
    this.consWidth = 0.45,
    this.consHeight = 0.42,
    this.consX = 0.40,
    this.consY = 0.30,
    this.consAspectKeep = 0.5,
    this.clearance = 0.0,
    this.maxAngle = 40.0,
    this.minLegScale = 0.5,
  });

  /// 초성 박스
  ComposeBox get consBox => ComposeBox(
        x: consX - consWidth / 2,
        y: consY - consHeight / 2,
        w: consWidth,
        h: consHeight,
      );

  MixedSyllableParams copyWith({
    double? consWidth,
    double? consHeight,
    double? consX,
    double? consY,
    double? consAspectKeep,
    double? clearance,
    double? maxAngle,
    double? minLegScale,
  }) {
    return MixedSyllableParams(
      consWidth: consWidth ?? this.consWidth,
      consHeight: consHeight ?? this.consHeight,
      consX: consX ?? this.consX,
      consY: consY ?? this.consY,
      consAspectKeep: consAspectKeep ?? this.consAspectKeep,
      clearance: clearance ?? this.clearance,
      maxAngle: maxAngle ?? this.maxAngle,
      minLegScale: minLegScale ?? this.minLegScale,
    );
  }

  String toDisplayString() {
    String f(double v) => v.toStringAsFixed(3);
    return 'consWidth=${f(consWidth)}, consHeight=${f(consHeight)}, '
        'consX=${f(consX)}, consY=${f(consY)}, '
        'consAspectKeep=${f(consAspectKeep)}, '
        'clearance=${f(clearance)}, maxAngle=${f(maxAngle)}, '
        'minLegScale=${f(minLegScale)}';
  }
}

/// 5번 규칙값. 키는 케이스 번호(10~13 = ⑪~⑭).
/// 5번 테스트 화면에서 맞춘 값을 여기에 적는다. 값은 값마다 직접 적는다.
/// 다리 각도 조정(clearance)은 모두 꺼 둠(0).
const Map<int, MixedSyllableParams> kMixedRuleParams = {
  // ⑪ 자음3(뚫림) × 모음1(ㅘ ㅙ ㅚ)
  10: MixedSyllableParams(
    consWidth: 0.41,
    consHeight: 0.39,
    consX: 0.41,
    consY: 0.37,
    consAspectKeep: 0.5,
    clearance: 0.0,
    maxAngle: 40.0,
    minLegScale: 0.5,
  ),
  // ⑫ 자음3(뚫림) × 모음2(ㅝ ㅞ ㅟ ㅢ)
  11: MixedSyllableParams(
    consWidth: 0.45,
    consHeight: 0.31,
    consX: 0.45,
    consY: 0.30,
    consAspectKeep: 0.5,
    clearance: 0.0,
    maxAngle: 40.0,
    minLegScale: 0.5,
  ),
  // ⑬ 자음4(막힘) × 모음1(ㅘ ㅙ ㅚ)
  12: MixedSyllableParams(
    consWidth: 0.45,
    consHeight: 0.42,
    consX: 0.39,
    consY: 0.41,
    consAspectKeep: 0.5,
    clearance: 0.0,
    maxAngle: 40.0,
    minLegScale: 0.5,
  ),
  // ⑭ 자음4(막힘) × 모음2(ㅝ ㅞ ㅟ ㅢ)
  13: MixedSyllableParams(
    consWidth: 0.45,
    consHeight: 0.43,
    consX: 0.48,
    consY: 0.21,
    consAspectKeep: 0.5,
    clearance: 0.0,
    maxAngle: 40.0,
    minLegScale: 0.5,
  ),
};
/// 이 조합의 5번 규칙값. 정해지지 않았으면 null.
MixedSyllableParams? mixedRuleParamsOf(String c, String v) =>
    kMixedRuleParams[mixedCaseIdOf(c, v)];

    
/// 6번(혼합형 받침 있음) 분류. 종성과 맞닿는 모음 아래쪽 모양으로만 나눈다.
/// 초성은 맨 위라 종성과 닿지 않으므로 자음은 나누지 않는다.
///   A = 아래가 평평한 가로획 (ㅗ, ㅡ): ㅘ ㅙ ㅚ ㅢ
///   B = 아래로 내려오는 줄기 (ㅜ): ㅝ ㅞ ㅟ
/// 5번 그룹과 다르다 (ㅢ가 5번에서는 ㅝ 쪽, 6번에서는 ㅘ 쪽).
const Map<String, List<String>> kMixedFinalVowelGroups = {
  'A': ['ㅘ', 'ㅙ', 'ㅚ', 'ㅢ'],
  'B': ['ㅝ', 'ㅞ', 'ㅟ'],
};

/// 이 모음의 6번 그룹 이름 (A 또는 B). 목록에 없으면 A.
String mixedFinalGroupOf(String v) {
  for (final e in kMixedFinalVowelGroups.entries) {
    if (e.value.contains(v)) return e.key;
  }
  return 'A';
}

/// 6번 케이스 번호는 5번(10~13) 다음인 14부터 쓴다.
/// 14 = ⑮ A(ㅘ ㅙ ㅚ ㅢ) / 15 = ⑯ B(ㅝ ㅞ ㅟ)
const int kMixedFinalCaseBase = 14;

int mixedFinalCaseIdOf(String v) =>
    kMixedFinalCaseBase +
    kMixedFinalVowelGroups.keys.toList().indexOf(mixedFinalGroupOf(v));

String mixedFinalCaseLabelOf(String v) =>
    '6번 케이스 ${caseMarkOf(mixedFinalCaseIdOf(v))} '
    '(모음 ${mixedFinalGroupOf(v)}그룹: '
    '${kMixedFinalVowelGroups[mixedFinalGroupOf(v)]!.join(' ')})';

/// 6번: 혼합형 받침 있음 규칙값. 키는 6번 케이스 번호(14 = A, 15 = B).
/// 초성+혼합 모음 부분은 kMixedRuleParams(5번)를 그대로 쓰고,
/// 여기서는 위쪽 박스/종성 박스의 크기와 위치만 정한다 (2번·4번과 같은 방식).
/// 6번 테스트 화면에서 맞춘 값을 여기에 적는다. 값은 값마다 직접 적는다.
const Map<int, FinalBoxParams> kMixedFinalRuleParams = {
  // ⑮ A: ㅘ ㅙ ㅚ ㅢ
  14: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.23,
    jongWidth: 0.58,
    gap: -0.03,
    jongOffsetX: 0.0,
    jongAspectKeep: 0.5,
  ),
  // ⑯ B: ㅝ ㅞ ㅟ
  15: FinalBoxParams(
    upperHeight: 0.60,
    upperWidth: 1.0,
    jongHeight: 0.24,
    jongWidth: 0.50,
    gap: -0.10,
    jongOffsetX: 0.09,
    jongAspectKeep: 0.5,
  ),
};
/// 이 모음의 6번 규칙값. 정해지지 않았으면 null.
FinalBoxParams? mixedFinalRuleParamsOf(String v) =>
    kMixedFinalRuleParams[mixedFinalCaseIdOf(v)];
/// 5번: 초성 + 혼합 모음 (받침 없음, 0~1 한 칸 기준).
/// 혼합 모음은 vowelParams(없으면 kCompoundVowelRuleParams 규칙값)로 고정해서 합성하고,
/// 초성은 params의 초성 박스에 넣는다.
/// legAdjust(ㄱ ㅋ)이고 clearance > 0이면 초성 다리를 가로 조각 기준으로 세운다.
List<StrokeData> composeMixedSyllable({
  required NormalizedJamo consonant,
  required String vowel,
  required NormalizedJamo horizontal,
  required NormalizedJamo vertical,
  required MixedSyllableParams params,
  CompoundVowelParams? vowelParams,
  bool legAdjust = false,
}) {
  final vp = vowelParams ??
      compoundVowelRuleParamsOf(vowel) ??
      const CompoundVowelParams();
  final vowelStrokes = composeCompoundVowel(
    vowel: vowel,
    horizontal: horizontal,
    vertical: vertical,
    params: vp,
  );
  var cons = SyllableComposer.remapFit(
      consonant, params.consBox, params.consAspectKeep);
  if (legAdjust && params.clearance > 0) {
    final horz = SyllableComposer.remapFit(
        horizontal, vp.horzBox, vp.horzAspectKeep);
    cons = SyllableComposer.adjustLegAgainst(
      cons,
      horz,
      clearance: params.clearance,
      maxAngle: params.maxAngle,
      minLegScale: params.minLegScale,
    );
  }
  return [...cons, ...vowelStrokes];
}

// ------------------------------------------------------------ 파생 모음 (ㅒ ㅖ)

/// 직접 쓰지 않고 만드는 모음. 쓴 모음(base) 오른쪽에 ㅣ를 일정 간격으로 붙인다.
/// gap은 모음 높이(=1) 대비 간격이다.
///   ㅒ = ㅑ + ㅣ : ㅑ 오른쪽 끝은 짧은 획 끝이라 간격을 좁게
///   ㅖ = ㅕ + ㅣ : ㅕ 오른쪽 끝은 기둥이라 간격을 넓게 (ㅔ의 두 기둥 사이 정도)
class DerivedVowel {
  final String base;
  final double gap;
  const DerivedVowel(this.base, this.gap);
}

const Map<String, DerivedVowel> kDerivedVowels = {
  'ㅒ': DerivedVowel('ㅑ', 0.08),
  'ㅖ': DerivedVowel('ㅕ', 0.20),
};

/// base(ㅑ 또는 ㅕ) 오른쪽에 stem(ㅣ)을 gap만큼 띄워 붙인 새 모음.
/// 둘 다 높이 1로 맞춰서 위아래를 같게 두고, 원래 비율(aspect)을 살린 뒤 다시 정규화한다.
NormalizedJamo? deriveVowelWithStem(
  NormalizedJamo base,
  NormalizedJamo stem,
  double gap,
) {
  final bw = base.aspect; // 높이 1일 때의 폭
  final sw = stem.aspect;
  final raw = <StrokeData>[
    ...base.strokes.map((s) => StrokeData(
          points: s.points
              .map((p) => PointData(x: p.x * bw, y: p.y, pressure: p.pressure))
              .toList(),
        )),
    ...stem.strokes.map((s) => StrokeData(
          points: s.points
              .map((p) => PointData(
                    x: bw + gap + p.x * sw,
                    y: p.y,
                    pressure: p.pressure,
                  ))
              .toList(),
        )),
  ];
  return SyllableComposer.normalizeWithAspect(raw);
}

/// ㅒ ㅖ를 만든다. 파생 모음이 아니면 null.
/// written: 사용자가 쓴 모음 (ㅑ ㅕ ㅣ가 들어 있어야 한다)
NormalizedJamo? derivedVowelOf(String v, Map<String, NormalizedJamo> written) {
  final d = kDerivedVowels[v];
  if (d == null) return null;
  final base = written[d.base];
  final stem = written['ㅣ'];
  if (base == null || stem == null) return null;
  return deriveVowelWithStem(base, stem, d.gap);
}

/// 이 조합이 "겹치면 자음 오른쪽으로 밀기" 대상인가
bool autoShiftOf(String c, String v) =>
    rulesOf(orientationOf(v)).shiftRight.contains(c);

bool autoLegOf(String c, String v) =>
    rulesOf(orientationOf(v)).legAdjust.contains(c);
// ------------------------------------------------------------ 글자 조합

/// 초성 + 중성 → 완성형 글자 (받침 없음). 참고용 폰트 글자 표시에 쓴다.
String? syllableOf(String choseong, String jungseong) {
  const cho = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];
  const jung = [
    'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ',
    'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
  ];
  final ci = cho.indexOf(choseong);
  final vi = jung.indexOf(jungseong);
  if (ci < 0 || vi < 0) return null;
  return String.fromCharCode(0xAC00 + (ci * 21 + vi) * 28);
}

/// 자음 + 모음 합성 파라미터.
///
/// 모든 값은 0~1 정규화 공간(글자 한 칸 = 1x1) 기준이다.
/// "주축" = 자음과 모음이 나란히 놓이는 방향(세로 모음이면 가로, 가로 모음이면 세로),
/// "교차축" = 그에 수직인 방향.
class SyllableParams {
  /// 자음과 모음 사이 간격 (주축 방향, 전체 길이 대비)
  final double gap;

  /// 자음 박스 전체 크기 배율 (주축·교차축 모두)
  final double consonantScale;

  /// 모음 박스 전체 크기 배율 (주축·교차축 모두)
  final double vowelScale;

  /// 주축 방향에서 모음이 차지하는 몫 (0.3이면 자음 0.7 : 모음 0.3)
  final double vowelShare;

  /// 자음 교차축 길이 (세로 모음이면 자음의 세로 길이)
  final double consonantCross;

  /// 모음 교차축 길이 (세로 모음이면 모음의 세로 길이)
  final double vowelCross;

  /// 자음의 교차축 위치 이동 (세로 모음이면 +가 아래쪽, 가로 모음이면 +가 오른쪽)
  final double consonantOffset;

  /// 모음의 교차축 위치 이동
  final double vowelOffset;

  /// 원본 비율 유지 정도. 0 = 박스를 꽉 채움(비율 왜곡), 1 = 원본 가로세로 비율 유지.
  final double aspectKeep;

  /// 겹침 방지 최소 여백 (0~1 공간). 0이면 이 기능을 끈다.
  final double clearance;

  /// 겹침 방지 기준.
  /// 2 = 다리 각도 조정: (가로 모음 전용) 자음의 맨 아래 점(다리 끝)이 모음의
  ///     튀어나온 획(ㅛ면 오른쪽 줄기)보다 왼쪽에 있을 때 동작한다.
  ///     ㅗ·ㅛ는 겹치지 않아도, ㅜ·ㅠ·ㅡ는 겹칠 때만 동작한다.
  ///     자음 획의 모서리를 축으로 그 뒤쪽 다리만 회전해 다리 끝이 줄기보다
  ///     clearance만큼 오른쪽에 오게 하고, 끝이 모음 끝 위에 오도록 다리 길이를 줄인다.
  ///     위쪽 가로획과 모음은 그대로다. 조건이 안 맞거나 한계(maxAngle, minLegScale)로
  ///     부족하면 남은 만큼 끝점 기준으로 모음을 민다(maxPush).
  /// 1 = 끝점 기준: 자음에서 모음 쪽으로 가장 튀어나온 점(가로 모음이면 맨 아래 점,
  ///     세로 모음이면 맨 오른쪽 점)과 모음에서 자음 쪽으로 가장 튀어나온 끝(맨 위 /
  ///     맨 왼쪽 점)의 거리를 주축 방향으로만 비교한다. 가로 위치가 달라도 적용된다.
  ///     자음은 건드리지 않고 모음만 밀어낸다.
  /// 0 = 가까운 거리 기준: 두 획 사이의 가장 가까운 거리가 여백보다 작으면
  ///     (가로 모음이면) 자음 아래쪽을 오른쪽으로 휘고, 그래도 부족하면 모음을 민다.
  final int avoidMode;

  /// 가로 모음(자음 아래에 모음)일 때, 자음의 아래쪽 획을 오른쪽으로 비킬 수 있는 최대량
  /// (자음 폭 대비 비율). 위 획은 그대로 두고 아래로 갈수록 더 많이 움직인다.
  final double maxBend;

  /// 비키는 것만으로 부족할 때 모음을 자음에서 멀리 밀어낼 수 있는 최대량 (0~1 공간).
  final double maxPush;

  /// avoidMode 2: 다리를 회전할 수 있는 최대 각도 (도).
  final double maxAngle;

  /// avoidMode 2: 다리 길이를 줄일 수 있는 한계 (원래 길이 대비 최소 비율, 0.1~1).
  final double minLegScale;

  const SyllableParams({
    this.gap = 0.06,
    this.consonantScale = 1.0,
    this.vowelScale = 1.0,
    this.vowelShare = 0.30,
    this.consonantCross = 0.65,
    this.vowelCross = 0.92,
    this.consonantOffset = 0.0,
    this.vowelOffset = 0.0,
    this.aspectKeep = 1.0,
    this.clearance = 0.0,
    this.avoidMode = 1,
    this.maxBend = 0.50,
    this.maxPush = 0.15,
    this.maxAngle = 40.0,
    this.minLegScale = 0.50,
  });

  /// 방향별 시작값. 측정값이 아니라 눈으로 맞추기 위한 출발점이다.
  factory SyllableParams.defaultsFor(VowelOrientation o) {
    if (o == VowelOrientation.vertical) {
      return const SyllableParams();
    }
    return const SyllableParams(
      gap: 0.05,
      vowelShare: 0.35,
      consonantCross: 0.60,
      vowelCross: 0.90,
    );
  }

  SyllableParams copyWith({
    double? gap,
    double? consonantScale,
    double? vowelScale,
    double? vowelShare,
    double? consonantCross,
    double? vowelCross,
    double? consonantOffset,
    double? vowelOffset,
    double? aspectKeep,
    double? clearance,
    int? avoidMode,
    double? maxBend,
    double? maxPush,
    double? maxAngle,
    double? minLegScale,
  }) {
    return SyllableParams(
      gap: gap ?? this.gap,
      consonantScale: consonantScale ?? this.consonantScale,
      vowelScale: vowelScale ?? this.vowelScale,
      vowelShare: vowelShare ?? this.vowelShare,
      consonantCross: consonantCross ?? this.consonantCross,
      vowelCross: vowelCross ?? this.vowelCross,
      consonantOffset: consonantOffset ?? this.consonantOffset,
      vowelOffset: vowelOffset ?? this.vowelOffset,
      aspectKeep: aspectKeep ?? this.aspectKeep,
      clearance: clearance ?? this.clearance,
      avoidMode: avoidMode ?? this.avoidMode,
      maxBend: maxBend ?? this.maxBend,
      maxPush: maxPush ?? this.maxPush,
      maxAngle: maxAngle ?? this.maxAngle,
      minLegScale: minLegScale ?? this.minLegScale,
    );
  }

  /// 좋은 값을 찾았을 때 복사해서 기록하기 위한 문자열
  String toDisplayString() {
    String f(double v) => v.toStringAsFixed(3);
    return 'gap=${f(gap)}, consonantScale=${f(consonantScale)}, '
        'vowelScale=${f(vowelScale)}, vowelShare=${f(vowelShare)}, '
        'consonantCross=${f(consonantCross)}, vowelCross=${f(vowelCross)}, '
        'consonantOffset=${f(consonantOffset)}, vowelOffset=${f(vowelOffset)}, '
        'aspectKeep=${f(aspectKeep)}, clearance=${f(clearance)}, '
        'avoidMode=$avoidMode, maxBend=${f(maxBend)}, maxPush=${f(maxPush)}, '
        'maxAngle=${f(maxAngle)}, minLegScale=${f(minLegScale)}';
  }

  /// 슬라이더로 만들 수 있는 값이 모두 같은가 (부동소수 오차는 무시)
  bool sameAs(SyllableParams o) {
    bool eq(double a, double b) => (a - b).abs() < 1e-4;
    return eq(gap, o.gap) &&
        eq(consonantScale, o.consonantScale) &&
        eq(vowelScale, o.vowelScale) &&
        eq(vowelShare, o.vowelShare) &&
        eq(consonantCross, o.consonantCross) &&
        eq(vowelCross, o.vowelCross) &&
        eq(consonantOffset, o.consonantOffset) &&
        eq(vowelOffset, o.vowelOffset) &&
        eq(aspectKeep, o.aspectKeep) &&
        eq(clearance, o.clearance) &&
        avoidMode == o.avoidMode &&
        eq(maxBend, o.maxBend) &&
        eq(maxPush, o.maxPush) &&
        eq(maxAngle, o.maxAngle) &&
        eq(minLegScale, o.minLegScale);
  }
}

/// 정규화된 자모 + 원본 가로세로 비율(가로 ÷ 세로).
class NormalizedJamo {
  final List<StrokeData> strokes; // 각 축을 0~1로 늘린 획
  final double aspect;
  const NormalizedJamo(this.strokes, this.aspect);
}

class SyllableLayout {
  final ComposeBox consonantBox;
  final ComposeBox vowelBox;

  const SyllableLayout({required this.consonantBox, required this.vowelBox});
}

/// 겹침 방지까지 끝난 자음/모음 획.
class ComposedParts {
  final List<StrokeData> consonant;
  final List<StrokeData> vowel;
  const ComposedParts(this.consonant, this.vowel);
}

class _Pt {
  final double x;
  final double y;
  const _Pt(this.x, this.y);
}

/// 초성(자음) + 중성(모음) 합성 (받침 없는 글자 전용).
class SyllableComposer {
  /// 박스 크기를 정하는 기준 간격. gap 슬라이더와는 무관한 상수다.
  /// gap 기본값(0.06)과 같게 두면 기본 상태의 모습이 예전과 같다.
  static const double kRefGap = 0.06;

  /// avoidMode 2 / 자동 오른쪽 밀기: 모음 "맨 위 끝" 근처로 보는 띠의 두께 (0~1 공간).
  static const double _kTipBand = 0.04;

  /// 자동 오른쪽 밀기: 겹칠 때 자음 좌우 위치(consonantOffset)를 이 값으로 바꾼다.
  static const double kAutoShiftOffset = 0.15;

  /// 자동 오른쪽 밀기 판정: 자음 맨 아래 점이 줄기 + 이 값보다 왼쪽이면 겹친 것으로 본다.
  static const double _kAutoShiftMargin = 0.02;

  /// 모음 맨 위 끝 띠의 가로 폭이 이보다 넓으면 가로 막대(ㅜ ㅠ ㅡ),
  /// 좁으면 줄기(ㅗ ㅛ)로 본다.
  static const double _kMaxTipWidth = 0.3;

  /// 파라미터 → 자음/모음 박스.
  ///
  /// 박스 크기는 vowelShare·배율·교차축 길이로만 정해지고 gap에는 영향받지 않는다.
  /// gap은 두 박스 사이의 거리만 바꾼다. 묶음 전체를 칸 가운데로 맞추므로
  /// gap을 키우면 자음은 왼쪽(가로 모음이면 위쪽)으로, 모음은 오른쪽(아래쪽)으로
  /// 같은 거리만큼 벌어진다.
  static SyllableLayout computeLayout(
    SyllableParams p,
    VowelOrientation orientation,
  ) {
    // 박스 크기: gap이 아니라 고정 기준 간격(kRefGap)으로 계산
    final mainC = (1 - kRefGap) * (1 - p.vowelShare) * p.consonantScale;
    final mainV = (1 - kRefGap) * p.vowelShare * p.vowelScale;

    // 위치: 실제 gap으로 배치하고 묶음 전체를 가운데로
    final total = mainC + p.gap + mainV;
    final start = (1 - total) / 2;

    final crossC = p.consonantCross * p.consonantScale;
    final crossV = p.vowelCross * p.vowelScale;
    final cStart = 0.5 + p.consonantOffset - crossC / 2;
    final vStart = 0.5 + p.vowelOffset - crossV / 2;

    if (orientation == VowelOrientation.vertical) {
      return SyllableLayout(
        consonantBox: ComposeBox(x: start, y: cStart, w: mainC, h: crossC),
        vowelBox: ComposeBox(
            x: start + mainC + p.gap, y: vStart, w: mainV, h: crossV),
      );
    }
    return SyllableLayout(
      consonantBox: ComposeBox(x: cStart, y: start, w: crossC, h: mainC),
      vowelBox: ComposeBox(
          x: vStart, y: start + mainC + p.gap, w: crossV, h: mainV),
    );
  }

  /// 캔버스 픽셀 좌표 → 0~1 정규화.
  ///
  /// NormalizationService와 같지만 한 가지가 다르다. ㅣ나 ㅡ처럼 한 축으로
  /// 거의 길이가 없는 글자(반대 축 길이의 12% 미만)는 손떨림이 박스 전체로
  /// 늘어나 지그재그가 되므로, 그 축은 0.5(가운데)로 모은다.
  static List<StrokeData> normalize(List<StrokeData> strokes) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      for (final p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (minX == double.infinity) return [];

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    final collapseX = rangeX < rangeY * 0.12;
    final collapseY = rangeY < rangeX * 0.12;

    return strokes.map((s) {
      return StrokeData(
        points: s.points.map((p) {
          return PointData(
            x: collapseX || rangeX == 0 ? 0.5 : (p.x - minX) / rangeX,
            y: collapseY || rangeY == 0 ? 0.5 : (p.y - minY) / rangeY,
            pressure: p.pressure,
          );
        }).toList(),
      );
    }).toList();
  }

  /// normalize + 원본 비율 계산. ㅣ, ㅡ처럼 한 축이 거의 없는 글자도 안전하게 처리한다.
  static NormalizedJamo? normalizeWithAspect(List<StrokeData> strokes) {
    final norm = normalize(strokes);
    if (norm.isEmpty) return null;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      for (final p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    final w = (maxX - minX) < 1e-6 ? 1e-6 : (maxX - minX);
    final h = (maxY - minY) < 1e-6 ? 1e-6 : (maxY - minY);
    return NormalizedJamo(norm, (w / h).clamp(0.02, 50.0).toDouble());
  }

  static List<StrokeData> _remap(List<StrokeData> src, ComposeBox box) {
    return src.map((s) {
      return StrokeData(
        points: s.points.map((p) {
          return PointData(
            x: box.x + p.x * box.w,
            y: box.y + p.y * box.h,
            pressure: p.pressure,
          );
        }).toList(),
      );
    }).toList();
  }

  /// 박스 안에 자모를 넣는다. keep=0이면 박스를 꽉 채우고(왜곡),
  /// keep=1이면 원본 비율을 유지한 채 박스 안에 들어가는 최대 크기로 넣는다.
  /// 박스 안에서는 가운데 정렬한다.
  static List<StrokeData> _remapFit(
    NormalizedJamo j,
    ComposeBox box,
    double keep,
  ) {
    final double containW;
    final double containH;
    if (j.aspect >= box.w / box.h) {
      containW = box.w;
      containH = box.w / j.aspect;
    } else {
      containH = box.h;
      containW = box.h * j.aspect;
    }

    final fw = box.w + (containW - box.w) * keep;
    final fh = box.h + (containH - box.h) * keep;

    final fitted = ComposeBox(
      x: box.x + (box.w - fw) / 2,
      y: box.y + (box.h - fh) / 2,
      w: fw,
      h: fh,
    );
    return _remap(j.strokes, fitted);
  }

  /// _remapFit의 공개 버전. 받침 있는 글자 테스트 화면처럼
  /// 다른 파일에서 자모 하나를 박스에 맞춰 넣을 때 쓴다.
  static List<StrokeData> remapFit(
    NormalizedJamo j,
    ComposeBox box,
    double keep,
  ) =>
      _remapFit(j, box, keep);

  // ------------------------------------------------------------ 자동 오른쪽 밀기

  /// 자동 오른쪽 밀기가 필요한 만큼 겹쳤는가를 거리로 돌려준다. 겹치지 않으면 0.
  ///
  /// 자음 맨 아래 점이 모음 맨 위보다 아래로 내려왔고(겹침), 그 점이 모음 줄기
  /// (ㅛ면 오른쪽 줄기) + _kAutoShiftMargin보다 왼쪽에 있으면 그 차이를 돌려준다.
  /// 모음 맨 위가 가로 막대(ㅜ ㅠ ㅡ)면 옆으로 밀어도 소용없으므로 0.
  static double _autoShiftNeed(List<StrokeData> cons, List<StrokeData> vow) {
    var ex = 0.0;
    var ey = double.negativeInfinity;
    for (final s in cons) {
      for (final pt in s.points) {
        if (pt.y > ey) {
          ey = pt.y;
          ex = pt.x;
        }
      }
    }
    var vowTop = double.infinity;
    for (final s in vow) {
      for (final pt in s.points) {
        if (pt.y < vowTop) vowTop = pt.y;
      }
    }
    if (ey == double.negativeInfinity || vowTop == double.infinity) return 0;
    if (ey <= vowTop) return 0; // 겹치지 않음

    var tipLeft = double.infinity;
    var tipRight = double.negativeInfinity;
    for (final s in vow) {
      for (final pt in s.points) {
        if (pt.y <= vowTop + _kTipBand) {
          if (pt.x < tipLeft) tipLeft = pt.x;
          if (pt.x > tipRight) tipRight = pt.x;
        }
      }
    }
    if (tipRight - tipLeft > _kMaxTipWidth) return 0; // 가로 막대

    final need = tipRight + _kAutoShiftMargin - ex;
    return need > 0 ? need : 0;
  }

  // ------------------------------------------------------------ 겹침 방지

  /// 획 위의 점들을 step 간격으로 촘촘하게 만든다 (거리 계산용).
  static List<_Pt> _densify(List<StrokeData> strokes, double step) {
    final out = <_Pt>[];
    for (final s in strokes) {
      final pts = s.points;
      for (var i = 0; i < pts.length; i++) {
        out.add(_Pt(pts[i].x, pts[i].y));
        if (i + 1 < pts.length) {
          final dx = pts[i + 1].x - pts[i].x;
          final dy = pts[i + 1].y - pts[i].y;
          final len = math.sqrt(dx * dx + dy * dy);
          final n = (len / step).floor();
          for (var j = 1; j <= n; j++) {
            final t = j / (n + 1);
            out.add(_Pt(pts[i].x + dx * t, pts[i].y + dy * t));
          }
        }
      }
    }
    return out;
  }

  /// 자음 점들(오른쪽으로 k*depth만큼 이동)과 모음 점들(vdx, vdy만큼 이동) 사이의 최소 거리.
  static double _minDist(
    List<_Pt> cons,
    List<double> depth,
    double k,
    List<_Pt> vow,
    double vdx,
    double vdy,
  ) {
    var best = double.infinity;
    for (var i = 0; i < cons.length; i++) {
      final cx = cons[i].x + k * depth[i];
      final cy = cons[i].y;
      for (var j = 0; j < vow.length; j++) {
        final dx = cx - (vow[j].x + vdx);
        final dy = cy - (vow[j].y + vdy);
        final d = dx * dx + dy * dy;
        if (d < best) best = d;
      }
    }
    return math.sqrt(best);
  }

  /// 점 좌표를 (dx, dy)만큼 옮긴 새 획 목록.
  static List<StrokeData> _shift(List<StrokeData> src, double dx, double dy) {
    return src.map((s) {
      return StrokeData(
        points: s.points
            .map((pt) => PointData(
                  x: pt.x + dx,
                  y: pt.y + dy,
                  pressure: pt.pressure,
                ))
            .toList(),
      );
    }).toList();
  }

  /// 다리 각도 조정 (avoidMode = 2). 가로 모음 전용.
  ///
  /// 동작 조건:
  ///  1) 모음 맨 위가 줄기(ㅗ, ㅛ)면: 겹치지 않아도 된다.
  ///     모음 맨 위가 가로 막대(ㅜ, ㅠ, ㅡ)면: 겹쳐야 한다
  ///     (자음 맨 아래 점 + clearance > 모음 맨 위 끝).
  ///  2) 자음의 맨 아래 점(다리 끝)이 모음의 튀어나온 획(ㅛ면 오른쪽 줄기) 끝보다 왼쪽
  ///
  /// 동작: 맨 아래 점이 속한 획에서 모서리를 찾아, 모서리 뒤쪽(다리)을
  /// 모서리를 축으로 회전(+균일 축소)한다. 곡선 모양은 그대로 유지된다.
  /// 모서리 = 획의 시작점과 맨 아래 점을 잇는 직선에서 가장 멀리 떨어진 점
  /// (맨 아래 점보다 앞쪽만 본다. 끝을 올려 쓴 획이나 배율에 영향받지 않는다).
  ///  - 목표: 다리 끝 x가 (줄기 끝 x + clearance) 이상, 다리 끝 y가 (모음 끝 y - clearance) 이하
  ///  - 회전은 maxAngle까지, 축소는 minLegScale까지만 한다.
  ///  - 모서리 앞(위쪽 가로획)과 모음은 움직이지 않는다.
  ///
  /// 조건이 안 맞거나(모서리를 못 찾음 등) 한계로 부족하면 남은 만큼
  /// 끝점 기준(_avoidByExtent)으로 모음을 민다. 겹치지 않았으면 밀지 않는다.
  static ComposedParts _avoidByLeg(
    List<StrokeData> cons,
    List<StrokeData> vow,
    SyllableParams p,
    VowelOrientation orientation,
  ) {
    if (orientation != VowelOrientation.horizontal) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    // 자음의 맨 아래 점(다리 끝)과 그 점이 속한 획
    var ex = 0.0;
    var ey = double.negativeInfinity;
    var strokeIdx = -1;
    var pointIdx = -1;
    for (var a = 0; a < cons.length; a++) {
      final pts = cons[a].points;
      for (var b = 0; b < pts.length; b++) {
        if (pts[b].y > ey) {
          ey = pts[b].y;
          ex = pts[b].x;
          strokeIdx = a;
          pointIdx = b;
        }
      }
    }

    // 모음의 맨 위 끝
    var vowTop = double.infinity;
    for (final s in vow) {
      for (final pt in s.points) {
        if (pt.y < vowTop) vowTop = pt.y;
      }
    }
    if (strokeIdx < 0 || vowTop == double.infinity) {
      return ComposedParts(cons, vow);
    }

    // 모음 맨 위 끝 근처(띠)의 가로 범위. 폭이 좁으면 줄기(ㅗ ㅛ), 넓으면 가로 막대(ㅜ ㅠ ㅡ).
    var tipLeft = double.infinity;
    var tipRight = double.negativeInfinity;
    for (final s in vow) {
      for (final pt in s.points) {
        if (pt.y <= vowTop + _kTipBand) {
          if (pt.x < tipLeft) tipLeft = pt.x;
          if (pt.x > tipRight) tipRight = pt.x;
        }
      }
    }
    final stemTop = tipRight - tipLeft <= _kMaxTipWidth;

    // 조건 1: 줄기(ㅗ ㅛ)는 겹치지 않아도 진행, 가로 막대(ㅜ ㅠ ㅡ)는 겹칠 때만
    final overlapping = ey + p.clearance - vowTop > 0;
    if (!overlapping && !stemTop) {
      return ComposedParts(cons, vow);
    }

    // 조건 2: 다리 끝이 모음의 튀어나온 획(ㅛ면 오른쪽 줄기)보다 왼쪽
    if (ex >= tipRight) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    // ---- 모서리 찾기
    final pts = cons[strokeIdx].points;
    if (pts.length < 4) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    final cum = <double>[0.0];
    for (var i = 1; i < pts.length; i++) {
      final dx = pts[i].x - pts[i - 1].x;
      final dy = pts[i].y - pts[i - 1].y;
      cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    }

    // 모서리 = 시작점~맨 아래 점을 잇는 직선에서 가장 멀리 떨어진 점 (맨 아래 점보다 앞쪽만)
    final sx = pts.first.x;
    final sy = pts.first.y;
    final cx = ex - sx;
    final cy = ey - sy;
    final chord = math.sqrt(cx * cx + cy * cy);
    if (pointIdx < 2 || chord < 1e-6) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    var bestDist = -1.0;
    var cornerIdx = -1;
    for (var i = 1; i < pointIdx; i++) {
      final d = ((pts[i].x - sx) * cy - (pts[i].y - sy) * cx).abs() / chord;
      if (d > bestDist) {
        bestDist = d;
        cornerIdx = i;
      }
    }
    // 거의 일직선이면(꺾임 없음) 이 방식은 쓰지 않는다
    if (cornerIdx < 0 || bestDist < chord * 0.15) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    final cornerS = cum[cornerIdx];
    final corner = _Pt(pts[cornerIdx].x, pts[cornerIdx].y);

    // 다리 벡터 (모서리 → 다리 끝). 왼쪽 아래로 내려가는 다리만 대상으로 한다.
    final lx = ex - corner.x;
    final ly = ey - corner.y;
    final len = math.sqrt(lx * lx + ly * ly);
    if (lx >= 0 || ly <= 0 || len < 0.05) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    // ---- 목표 각도: 다리 끝 x를 (줄기 끝 + clearance)까지. 수직(0)보다 더 눕히진 않는다.
    final xTarget = tipRight + p.clearance;
    final dxT = math.min(xTarget - corner.x, 0.0);
    final dyT = math.sqrt(math.max(len * len - dxT * dxT, 0.0));
    var phi = math.atan2(dyT, dxT) - math.atan2(ly, lx);
    final maxRad = p.maxAngle.clamp(0.0, 80.0).toDouble() * math.pi / 180.0;
    phi = phi.clamp(-maxRad, maxRad).toDouble();
    final cosP = math.cos(phi);
    final sinP = math.sin(phi);

    // 회전 후 다리 끝의 세로 오프셋 → 끝이 (모음 끝 - clearance) 위에 오도록 길이 축소.
    // 다리를 세우면 아래로 길어지므로, 원래 안 겹쳤어도 여기서 줄어들 수 있다.
    final rotY = lx * sinP + ly * cosP;
    final minScale = p.minLegScale.clamp(0.1, 1.0).toDouble();
    var scale = 1.0;
    final avail = (vowTop - p.clearance) - corner.y;
    if (rotY > 1e-6 && avail < rotY) {
      scale = avail <= 0 ? minScale : avail / rotY;
    }
    scale = scale.clamp(minScale, 1.0).toDouble();

    // 바뀐 게 없으면 다음 방식으로
    if (phi.abs() < 1e-6 && (1.0 - scale).abs() < 1e-6) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    // ---- 변환: 모서리 앞은 그대로, 모서리 점을 끼워 넣고, 뒤쪽은 회전+축소
    PointData xform(PointData q) {
      final dx = q.x - corner.x;
      final dy = q.y - corner.y;
      return PointData(
        x: corner.x + scale * (dx * cosP - dy * sinP),
        y: corner.y + scale * (dx * sinP + dy * cosP),
        pressure: q.pressure,
      );
    }

    final newPts = <PointData>[];
    var inserted = false;
    for (var i = 0; i < pts.length; i++) {
      if (cum[i] <= cornerS) {
        newPts.add(pts[i]);
      } else {
        if (!inserted) {
          newPts.add(PointData(
            x: corner.x,
            y: corner.y,
            pressure: pts[i > 0 ? i - 1 : 0].pressure,
          ));
          inserted = true;
        }
        newPts.add(xform(pts[i]));
      }
    }

    final newCons = List<StrokeData>.of(cons);
    newCons[strokeIdx] = StrokeData(points: newPts);

    // 한계로 겹침이 남았으면 남은 만큼만 모음을 민다 (이미 해결됐으면 아무것도 안 함)
    return _avoidByExtent(newCons, vow, p, orientation);
  }

  /// 끝점 기준 겹침 방지 (avoidMode = 1).
  ///
  /// 가로 모음(모음이 자음 아래): 자음의 맨 아래 점과 모음의 맨 위 끝점의 높이만 비교한다.
  /// 세로 모음(모음이 자음 오른쪽): 자음의 맨 오른쪽 점과 모음의 맨 왼쪽 점의 x만 비교한다.
  /// 두 점이 주축 방향으로 clearance 이상 떨어지도록 모음을 밀어낸다. 반대쪽 위치(가로/세로)는
  /// 보지 않으므로, 자음의 끝이 모음의 튀어나온 획보다 옆으로 많이 떨어져 있어도 적용된다.
  /// 자음은 움직이지 않고, 모음은 최대 maxPush까지(칸 밖으로는 나가지 않게) 민다.
  static ComposedParts _avoidByExtent(
    List<StrokeData> cons,
    List<StrokeData> vow,
    SyllableParams p,
    VowelOrientation orientation,
  ) {
    final horizontal = orientation == VowelOrientation.horizontal;

    var consEdge = double.negativeInfinity; // 자음에서 모음 쪽으로 가장 튀어나온 값
    var vowEdge = double.infinity; // 모음에서 자음 쪽으로 가장 튀어나온 값
    var vowFar = double.negativeInfinity; // 모음의 반대쪽 끝 (칸 밖 판정용)

    for (final s in cons) {
      for (final pt in s.points) {
        final v = horizontal ? pt.y : pt.x;
        if (v > consEdge) consEdge = v;
      }
    }
    for (final s in vow) {
      for (final pt in s.points) {
        final v = horizontal ? pt.y : pt.x;
        if (v < vowEdge) vowEdge = v;
        if (v > vowFar) vowFar = v;
      }
    }
    if (consEdge == double.negativeInfinity || vowEdge == double.infinity) {
      return ComposedParts(cons, vow);
    }

    final need = consEdge + p.clearance - vowEdge;
    if (need <= 0) return ComposedParts(cons, vow);

    final cap = math.min(p.maxPush, math.max(0.0, 1.0 - vowFar));
    final push = math.min(need, cap);
    if (push <= 0) return ComposedParts(cons, vow);

    return ComposedParts(
      cons,
      _shift(vow, horizontal ? 0.0 : push, horizontal ? push : 0.0),
    );
  }

  /// 자음과 모음이 겹치거나 너무 가까우면 비켜 준다 (avoidMode = 0: 가까운 거리 기준).
  ///
  /// 1) 가로 모음(모음이 자음 아래): 자음의 위 획은 그대로 두고, 아래로 갈수록 더 많이
  ///    오른쪽으로 옮긴다(최대 params.maxBend). 모음은 움직이지 않는다.
  /// 2) 그래도 params.clearance만큼 떨어지지 않으면 모음을 자음에서 멀리 밀어낸다
  ///    (최대 params.maxPush, 칸 밖으로는 나가지 않게 제한).
  ///    세로 모음(모음이 자음 오른쪽)은 1)은 건너뛰고 2)만 한다.
  ///
  /// params.clearance가 0이면 아무것도 하지 않는다.
  static ComposedParts _avoidOverlap(
    List<StrokeData> cons,
    List<StrokeData> vow,
    SyllableParams p,
    VowelOrientation orientation, {
    bool legAdjust = false,
  }) {
    if (p.clearance <= 0) return ComposedParts(cons, vow);
    if (p.avoidMode == 2) {
      // 다리 각도 조정은 리스트에 있는 자음(ㄱ)만. 나머지는 건드리지 않는다.
      if (!legAdjust) return ComposedParts(cons, vow);
      return _avoidByLeg(cons, vow, p, orientation);
    }
        if (p.avoidMode == 1) {
      return _avoidByExtent(cons, vow, p, orientation);
    }

    const step = 0.015;
    final cd = _densify(cons, step);
    final vd = _densify(vow, step);
    if (cd.isEmpty || vd.isEmpty) return ComposedParts(cons, vow);

    final horizontal = orientation == VowelOrientation.horizontal;

    // 이동 전 거리. 이미 충분히 떨어져 있으면 그대로 둔다.
    final zeros = List<double>.filled(cd.length, 0.0);
    if (_minDist(cd, zeros, 0, vd, 0, 0) >= p.clearance) {
      return ComposedParts(cons, vow);
    }

    // ---- 1) 자음 아래쪽 획을 오른쪽으로 비키기 (가로 모음만)
    var outCons = cons;
    var depth = zeros;
    var k = 0.0;
    if (horizontal) {
      var top = double.infinity, bottom = double.negativeInfinity;
      var minX = double.infinity, maxX = double.negativeInfinity;
      for (final q in cd) {
        if (q.y < top) top = q.y;
        if (q.y > bottom) bottom = q.y;
        if (q.x < minX) minX = q.x;
        if (q.x > maxX) maxX = q.x;
      }
      final span = bottom - top;
      if (span > 1e-6) {
        double depthOf(double y) => ((y - top) / span).clamp(0.0, 1.0).toDouble();
        depth = cd.map((q) => depthOf(q.y)).toList();

        // 최대 이동량: maxBend(자음 폭 대비)와 "칸 밖으로 안 나감" 중 작은 값
        var maxK = p.maxBend * (maxX - minX);
        for (var i = 0; i < cd.length; i++) {
          if (depth[i] > 1e-6) {
            final room = (1.0 - cd[i].x) / depth[i];
            if (room < maxK) maxK = room;
          }
        }
        if (maxK < 0) maxK = 0;

        // 여백이 확보되는 가장 작은 이동량을 찾는다. 없으면 가장 멀어지는 값.
        var bestD = _minDist(cd, depth, 0, vd, 0, 0);
        var bestK = 0.0;
        const steps = 24;
        for (var i = 1; i <= steps; i++) {
          final kk = maxK * i / steps;
          final d = _minDist(cd, depth, kk, vd, 0, 0);
          if (d >= p.clearance) {
            bestK = kk;
            bestD = d;
            break;
          }
          if (d > bestD) {
            bestD = d;
            bestK = kk;
          }
        }
        k = bestK;

        if (k > 0) {
          outCons = cons.map((s) {
            return StrokeData(
              points: s.points.map((pt) {
                return PointData(
                  x: pt.x + k * depthOf(pt.y),
                  y: pt.y,
                  pressure: pt.pressure,
                );
              }).toList(),
            );
          }).toList();
        }
      }
    }

    // ---- 2) 모음 밀어내기
    var vowMax = double.negativeInfinity;
    for (final q in vd) {
      final v = horizontal ? q.y : q.x;
      if (v > vowMax) vowMax = v;
    }
    final cap = math.min(p.maxPush, math.max(0.0, 1.0 - vowMax));

    var push = 0.0;
    for (var iter = 0; iter < 8 && push < cap; iter++) {
      final d = _minDist(cd, depth, k, vd, horizontal ? 0.0 : push,
          horizontal ? push : 0.0);
      if (d >= p.clearance) break;
      push = math.min(cap, push + (p.clearance - d));
    }

    var outVow = vow;
    if (push > 0) {
      final dx = horizontal ? 0.0 : push;
      final dy = horizontal ? push : 0.0;
      outVow = vow.map((s) {
        return StrokeData(
          points: s.points.map((pt) {
            return PointData(x: pt.x + dx, y: pt.y + dy, pressure: pt.pressure);
          }).toList(),
        );
      }).toList();
    }

    return ComposedParts(outCons, outVow);
  }

  // ------------------------------------------------------------ 합성

  /// 정규화된 자음/모음 → 합성된 글자 획 (0~1 공간). 박스를 꽉 채우는 이전 방식.
  static List<StrokeData> compose({
    required List<StrokeData> consonant,
    required List<StrokeData> vowel,
    required SyllableParams params,
    required VowelOrientation orientation,
  }) {
    if (consonant.isEmpty || vowel.isEmpty) return [];
    final layout = computeLayout(params, orientation);
    final parts = _avoidOverlap(
      _remap(consonant, layout.consonantBox),
      _remap(vowel, layout.vowelBox),
      params,
      orientation,
    );
    return [...parts.consonant, ...parts.vowel];
  }

  /// 실제 합성에 쓸 파라미터.
  /// autoShiftRight가 true(리스트의 ㄱ, ㅋ)이고 가로 모음과 겹치면
  /// 자음 좌우 위치를 kAutoShiftOffset으로 바꾼 값을, 아니면 그대로 돌려준다.
  /// 화면의 박스 가이드도 이 값으로 그리면 실제 배치와 맞는다.
  static SyllableParams resolveParams({
    required NormalizedJamo consonant,
    required NormalizedJamo vowel,
    required SyllableParams params,
    required VowelOrientation orientation,
    bool autoShiftRight = false,
  }) {
    if (!autoShiftRight || orientation != VowelOrientation.horizontal) {
      return params;
    }
    final layout = computeLayout(params, orientation);
    final cons = _remapFit(consonant, layout.consonantBox, params.aspectKeep);
    final vow = _remapFit(vowel, layout.vowelBox, params.aspectKeep);
    if (_autoShiftNeed(cons, vow) <= 0) return params;
    return params.copyWith(consonantOffset: kAutoShiftOffset);
  }

  /// 원본 비율을 반영한 합성 (aspectKeep 사용) + 겹침 방지(clearance 사용).
  /// autoShiftRight가 true면 겹칠 때 자음 좌우 위치를 kAutoShiftOffset으로 바꿔 배치한다.
   static List<StrokeData> composeFit({
    required NormalizedJamo consonant,
    required NormalizedJamo vowel,
    required SyllableParams params,
    required VowelOrientation orientation,
    bool autoShiftRight = false,
    bool legAdjust = false,
  }) {
    final p = resolveParams(
      consonant: consonant,
      vowel: vowel,
      params: params,
      orientation: orientation,
      autoShiftRight: autoShiftRight,
    );
    final layout = computeLayout(p, orientation);
    final parts = _avoidOverlap(
      _remapFit(consonant, layout.consonantBox, p.aspectKeep),
      _remapFit(vowel, layout.vowelBox, p.aspectKeep),
      p,
      orientation,
      legAdjust: legAdjust,
    );
    return [...parts.consonant, ...parts.vowel];
  }

  /// 다리 각도 조정(avoidMode 2)만 따로 쓴다.
  /// 5번(혼합형)에서 ㄱ·ㅋ 다리를 가로 조각(ㅗ ㅜ ㅡ) 기준으로 세울 때 쓴다.
  /// 모음은 움직이지 않는다(maxPush 0). clearance가 0이면 그대로 돌려준다.
  static List<StrokeData> adjustLegAgainst(
    List<StrokeData> cons,
    List<StrokeData> horzPiece, {
    required double clearance,
    double maxAngle = 40.0,
    double minLegScale = 0.5,
  }) {
    if (clearance <= 0) return cons;
    final p = SyllableParams(
      clearance: clearance,
      avoidMode: 2,
      maxPush: 0.0,
      maxAngle: maxAngle,
      minLegScale: minLegScale,
    );
    return _avoidByLeg(cons, horzPiece, p, VowelOrientation.horizontal)
        .consonant;
  }
}