import 'dart:math' as math;

import '../models/handwriting_model.dart';
import 'double_jamo_composer.dart';
import 'syllable_composer.dart';

/// 폰트를 만들 때 사용자가 직접 쓰는 자모 26개 (CNN 클래스와 같다).
/// 나머지(쌍자음, 겹받침, ㅒ ㅖ, 혼합 모음)는 전부 이 26개로 만든다.
const List<String> kFontInputJamo = [
  'ㄱ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅗ', 'ㅛ', 'ㅜ', 'ㅠ', 'ㅡ', 'ㅣ',
];

/// 유니코드 완성형 순서
const List<String> kChoseongOrder = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];
const List<String> kJungseongOrder = [
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ',
  'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
];
const List<String> kJongseongOrder = [
  '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ',
  'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ',
  'ㅍ', 'ㅎ',
];

/// 쌍자음 → 홑자음 (규칙 그룹도 홑자음 기준으로 찾는다)
const Map<String, String> kDoubleToSingle = {
  'ㄲ': 'ㄱ',
  'ㄸ': 'ㄷ',
  'ㅃ': 'ㅂ',
  'ㅆ': 'ㅅ',
  'ㅉ': 'ㅈ',
};

/// 규칙값이 없을 때 쓰는 받침 박스 (2번 확정값과 같다)
const FinalBoxParams _kDefaultFinal = FinalBoxParams(
  upperHeight: 0.60,
  upperWidth: 1.0,
  jongHeight: 0.32,
  jongWidth: 0.50,
  gap: -0.03,
  jongOffsetX: 0.0,
  jongAspectKeep: 0.5,
);

/// 낱자모(ㄱ, ㅘ 등 한 글자) 글리프를 넣는 박스
const ComposeBox _kSingleJamoBox = ComposeBox(x: 0.15, y: 0.1, w: 0.7, h: 0.8);

/// 서버로 보낼 좌표 단위 (글자 한 칸 = 0~1000)
const int kGlyphUnits = 1000;

/// 획을 줄일 때 허용하는 오차 (0~1000 단위). 클수록 점이 줄고 각이 진다.
const double kSimplifyEpsilon = 2.5;

/// 글자 하나를 서버로 보낼 형식: 획마다 [x0, y0, x1, y1, ...]
typedef EncodedGlyph = List<List<int>>;

/// 26개 자모 → 11,172자 + 낱자모 51자의 획.
///
/// 글자마다 1~6번 틀 중 하나를 골라 syllable_composer.dart의 규칙값으로 합성한다.
///   - 세로 모음(ㅏ ㅐ ㅑ ㅒ ㅓ ㅔ ㅕ ㅖ ㅣ): 1번 / 받침 있으면 2번
///   - 가로 모음(ㅗ ㅛ ㅜ ㅠ ㅡ): 3번 / 받침 있으면 4번
///   - 혼합 모음(ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ): 5번 / 받침 있으면 6번
/// 쌍자음은 홑자음을 좌우로 복사하고(초성은 받침 유무에 따라 높이 프리셋이 다름),
/// 받침 ㄲ ㅆ과 겹받침은 받침 프리셋으로 두 자음을 나란히 놓는다.
/// ㅒ ㅖ는 ㅑ ㅕ 오른쪽에 ㅣ를 붙여 만든다.
class FontGlyphBuilder {
  final Map<String, NormalizedJamo> _written;

  final Map<String, NormalizedJamo> _choCache = {};
  final Map<String, NormalizedJamo> _jongCache = {};
  final Map<String, NormalizedJamo> _vowelCache = {};

  /// 실패한 글자 (글자, 이유). 실패한 글자는 빈 글리프로 들어간다.
  final List<String> failures = [];

  FontGlyphBuilder._(this._written);

  /// raw: 캔버스에 쓴 원본 좌표 (자모 → 획). 26개가 다 있어야 한다.
  factory FontGlyphBuilder.fromRaw(Map<String, List<StrokeData>> raw) {
    final missing = kFontInputJamo.where((j) => !raw.containsKey(j)).toList();
    if (missing.isNotEmpty) {
      throw ArgumentError('자모가 부족합니다: ${missing.join(' ')}');
    }
    final written = <String, NormalizedJamo>{};
    for (final j in kFontInputJamo) {
      final n = SyllableComposer.normalizeWithAspect(raw[j]!);
      if (n == null) throw ArgumentError('$j 획이 비어 있습니다.');
      written[j] = n;
    }
    return FontGlyphBuilder._(written);
  }

  // ---------------------------------------------------------------- 자모 준비

  NormalizedJamo _norm(List<StrokeData> strokes) =>
      SyllableComposer.normalizeWithAspect(strokes)!;

  /// 초성. 쌍자음은 받침 유무에 따라 높이 프리셋을 다르게 쓴다.
  NormalizedJamo _choseong(String c, bool hasJong) {
    final single = kDoubleToSingle[c];
    if (single == null) return _written[c]!;
    final key = '$c|$hasJong';
    return _choCache.putIfAbsent(key, () {
      final params = DoubleJamoParams.forJamo(
        single,
        position: hasJong
            ? DoubleJamoPosition.choseongClosed
            : DoubleJamoPosition.choseongOpen,
      );
      return _norm(DoubleJamoComposer.compose(_written[single]!.strokes, params));
    });
  }

  /// 종성. 홑자음은 쓴 글씨, 쌍자음·겹받침은 받침 프리셋으로 두 자음을 나란히.
  NormalizedJamo _jongseong(String j) {
    final w = _written[j];
    if (w != null) return w;
    return _jongCache.putIfAbsent(j, () {
      final single = kDoubleToSingle[j];
      if (single != null) {
        return _norm(DoubleJamoComposer.compose(
            _written[single]!.strokes, finalPairParams(single)));
      }
      final pair = kCompoundFinals[j]!;
      return _norm(DoubleJamoComposer.composePair(
        _written[pair[0]]!.strokes,
        _written[pair[1]]!.strokes,
        finalPairParams(pair[0]),
      ));
    });
  }

  /// 세로/가로 모음 (ㅒ ㅖ는 ㅑ ㅕ + ㅣ로 만든다)
  NormalizedJamo _simpleVowel(String v) {
    final w = _written[v];
    if (w != null) return w;
    return _vowelCache.putIfAbsent(v, () => derivedVowelOf(v, _written)!);
  }

  // ---------------------------------------------------------------- 합성

  /// 0~1 공간의 획을 박스 안으로 선형 매핑
  static List<StrokeData> _mapInto(List<StrokeData> src, ComposeBox box) {
    return src
        .map((s) => StrokeData(
              points: s.points
                  .map((p) => PointData(
                        x: box.x + p.x * box.w,
                        y: box.y + p.y * box.h,
                        pressure: p.pressure,
                      ))
                  .toList(),
            ))
        .toList();
  }

  /// 받침 있는 글자: 위쪽(초성+모음) 한 칸을 위 박스에, 종성을 아래 박스에 (2·4·6번 공통)
  static List<StrokeData> _withFinal(
    List<StrokeData> upperCell,
    NormalizedJamo jong,
    FinalBoxParams fp,
  ) {
    final total = fp.upperHeight + fp.gap + fp.jongHeight;
    final top = (1 - total) / 2;
    final upper = ComposeBox(
      x: (1 - fp.upperWidth) / 2,
      y: top,
      w: fp.upperWidth,
      h: fp.upperHeight,
    );
    final jongBox = ComposeBox(
      x: 0.5 + fp.jongOffsetX - fp.jongWidth / 2,
      y: top + fp.upperHeight + fp.gap,
      w: fp.jongWidth,
      h: fp.jongHeight,
    );
    return [
      ..._mapInto(upperCell, upper),
      ...SyllableComposer.remapFit(jong, jongBox, fp.jongAspectKeep),
    ];
  }

  /// 완성형 글자 하나 (0~1 한 칸 기준 획)
  List<StrokeData> syllable(String cho, String jung, String jong) {
    final hasJong = jong.isNotEmpty;
    final ruleC = kDoubleToSingle[cho] ?? cho; // 규칙 그룹은 홑자음 기준
    final c = _choseong(cho, hasJong);
    final pieces = kCompoundVowelPieces[jung];

    List<StrokeData> upperCell;
    FinalBoxParams? fp;

    if (pieces != null) {
      // 5번 / 6번: 혼합 모음
      upperCell = composeMixedSyllable(
        consonant: c,
        vowel: jung,
        horizontal: _written[pieces.horizontal]!,
        vertical: _written[pieces.vertical]!,
        params: mixedRuleParamsOf(ruleC, jung) ?? const MixedSyllableParams(),
        legAdjust: mixedLegAdjustOf(ruleC),
      );
      if (hasJong) fp = mixedFinalRuleParamsOf(jung) ?? _kDefaultFinal;
    } else {
      // 1~4번: 세로 / 가로 모음
      final o = orientationOf(jung);
      upperCell = SyllableComposer.composeFit(
        consonant: c,
        vowel: _simpleVowel(jung),
        params: ruleParamsOf(ruleC, jung) ?? SyllableParams.defaultsFor(o),
        orientation: o,
        autoShiftRight: autoShiftOf(ruleC, jung),
        legAdjust: autoLegOf(ruleC, jung),
      );
      if (hasJong) fp = finalRuleParamsOf(ruleC, jung) ?? _kDefaultFinal;
    }

    if (!hasJong) return upperCell;
    return _withFinal(upperCell, _jongseong(jong), fp!);
  }

  /// 낱자모 한 글자 (ㄱ ㄲ ㄳ ... ㅏ ... ㅘ ... ㅣ)
  List<StrokeData>? singleJamo(String ch) {
    NormalizedJamo? j;
    if (_written.containsKey(ch)) {
      j = _written[ch];
    } else if (kDoubleToSingle.containsKey(ch)) {
      j = _choseong(ch, false);
    } else if (kCompoundFinals.containsKey(ch)) {
      final pair = kCompoundFinals[ch]!;
      j = _norm(DoubleJamoComposer.composePair(
        _written[pair[0]]!.strokes,
        _written[pair[1]]!.strokes,
        DoubleJamoParams.forJamo(pair[0]),
      ));
    } else if (kDerivedVowels.containsKey(ch)) {
      j = _simpleVowel(ch);
    } else if (kCompoundVowelPieces.containsKey(ch)) {
      final pieces = kCompoundVowelPieces[ch]!;
      j = _norm(composeCompoundVowel(
        vowel: ch,
        horizontal: _written[pieces.horizontal]!,
        vertical: _written[pieces.vertical]!,
        params: compoundVowelRuleParamsOf(ch) ?? const CompoundVowelParams(),
      ));
    }
    if (j == null) return null;
    return SyllableComposer.remapFit(j, _kSingleJamoBox, 1.0);
  }

  // ---------------------------------------------------------------- 전체 만들기

  /// 11,172자 + 낱자모 51자를 만든다. 키는 유니코드 16진수 (예: "AC00").
  /// onProgress(done, total)로 진행 상황을 알려 주고, 중간중간 화면이 멈추지 않게 쉰다.
  Future<Map<String, EncodedGlyph>> buildAll({
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <String, EncodedGlyph>{};
    failures.clear();

    const jamoStart = 0x3131, jamoEnd = 0x3163;
    final total = 11172 + (jamoEnd - jamoStart + 1);
    var done = 0;

    Future<void> tick() async {
      done++;
      if (done % 200 == 0 || done == total) {
        onProgress?.call(done, total);
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 낱자모
    for (var code = jamoStart; code <= jamoEnd; code++) {
      final ch = String.fromCharCode(code);
      try {
        final strokes = singleJamo(ch);
        if (strokes != null) out[_hex(code)] = encode(strokes);
      } catch (e) {
        failures.add('$ch: $e');
      }
      await tick();
    }

    // 완성형 11,172자
    for (var ci = 0; ci < kChoseongOrder.length; ci++) {
      for (var vi = 0; vi < kJungseongOrder.length; vi++) {
        for (var ji = 0; ji < kJongseongOrder.length; ji++) {
          final code = 0xAC00 + (ci * 21 + vi) * 28 + ji;
          try {
            final strokes = syllable(
                kChoseongOrder[ci], kJungseongOrder[vi], kJongseongOrder[ji]);
            out[_hex(code)] = encode(strokes);
          } catch (e) {
            failures.add('${String.fromCharCode(code)}: $e');
          }
          await tick();
        }
      }
    }
    return out;
  }

  static String _hex(int code) => code.toRadixString(16).toUpperCase();

  // ---------------------------------------------------------------- 전송 형식

  /// 0~1 획 → 0~1000 정수 좌표, 점 줄이기(RDP).
  static EncodedGlyph encode(List<StrokeData> strokes) {
    final out = <List<int>>[];
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final pts = s.points
          .map((p) => math.Point<double>(p.x * kGlyphUnits, p.y * kGlyphUnits))
          .toList();
      final simple = _rdp(pts, kSimplifyEpsilon);
      final flat = <int>[];
      int? lx, ly;
      for (final p in simple) {
        final x = p.x.round(), y = p.y.round();
        if (x == lx && y == ly) continue;
        flat..add(x)..add(y);
        lx = x;
        ly = y;
      }
      if (flat.isNotEmpty) out.add(flat);
    }
    return out;
  }

  /// Ramer–Douglas–Peucker 선 단순화
  static List<math.Point<double>> _rdp(List<math.Point<double>> pts, double eps) {
    if (pts.length < 3) return pts;
    final keep = List<bool>.filled(pts.length, false);
    keep[0] = true;
    keep[pts.length - 1] = true;
    final stack = <List<int>>[
      [0, pts.length - 1]
    ];
    while (stack.isNotEmpty) {
      final range = stack.removeLast();
      final a = range[0], b = range[1];
      if (b - a < 2) continue;
      final pa = pts[a], pb = pts[b];
      final dx = pb.x - pa.x, dy = pb.y - pa.y;
      final len = math.sqrt(dx * dx + dy * dy);
      var best = -1.0;
      var idx = -1;
      for (var i = a + 1; i < b; i++) {
        final p = pts[i];
        final d = len < 1e-9
            ? math.sqrt((p.x - pa.x) * (p.x - pa.x) + (p.y - pa.y) * (p.y - pa.y))
            : ((p.x - pa.x) * dy - (p.y - pa.y) * dx).abs() / len;
        if (d > best) {
          best = d;
          idx = i;
        }
      }
      if (best > eps) {
        keep[idx] = true;
        stack
          ..add([a, idx])
          ..add([idx, b]);
      }
    }
    return [
      for (var i = 0; i < pts.length; i++)
        if (keep[i]) pts[i]
    ];
  }
}