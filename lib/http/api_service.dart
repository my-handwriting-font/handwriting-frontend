import 'dart:convert';
import 'dart:typed_data';
import 'package:handwriting_front/core/api_config.dart';
import 'package:http/http.dart' as http;
import '../core/session.dart';
import '../models/handwriting_model.dart';

class ApiService {
  static const String baseUrl = '${ApiConfig.springBaseUrl}/handwriting';

  static Future<bool> saveHandwriting(
    String charName,
    List<StrokeData> strokes,
  ) async {
    final url = Uri.parse('$baseUrl/save');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'charName': charName,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      }),
    );

    return response.statusCode == 200;
  }

  static Future<bool?> verifyRawCoordinates(
    String charName,
    List<StrokeData> strokes,
  ) async {
    final url = Uri.parse('$baseUrl/verify');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'charName': charName,
          'strokes': strokes.map((s) => s.toJson()).toList(),
          // 로그인한 사용자로 저장 (로그인 안 했으면 서버가 1번 사용자로 저장)
          if (Session.userId != null) 'userId': Session.userId,
        }),
      );

      if (response.statusCode == 200) {
        return response.body == 'true'; // Spring이 Boolean을 그대로 내려줌 ("true"/"false")
      } else {
        print('verify 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('verify 연결 실패: $e');
      return null;
    }
  }

  static Future<List<StrokeData>?> getLatestHandwriting() async {
    final url = Uri.parse('$baseUrl/latest');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> jsonData = jsonDecode(response.body);
      return jsonData.map((json) => StrokeData.fromJson(json)).toList();
    }

    return null;
  }

  static Future<Map<String, dynamic>?> checkBadWriting(
    String charName,
    List<StrokeData> strokes,
  ) async {
    final url = Uri.parse('${ApiConfig.fastApiBaseUrl}/predict');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'charName': charName,
          'strokes': strokes.map((s) => s.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('FastAPI 오류: ${response.statusCode}');
        print(response.body);
        return null;
      }
    } catch (e) {
      print('FastAPI 연결 실패: $e');
      return null;
    }
  }

  /// 폰트 만들기용: 검증을 통과해 DB에 저장된 자모의 원본 좌표 (글자 → 획).
  /// 서버에 연결하지 못하면 null.
  static Future<Map<String, List<StrokeData>>?> getSavedJamo() async {
    final url = Uri.parse(
        '$baseUrl/jamo${Session.userId != null ? '?userId=${Session.userId}' : ''}');
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        print('자모 불러오기 실패: ${response.statusCode}');
        return null;
      }
      // 키가 한글(ㄱ, ㅏ ...)이라 utf8로 직접 디코딩한다
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return decoded.map((jamo, strokes) => MapEntry(
            jamo,
            (strokes as List)
                .map((s) => StrokeData.fromJson(s as Map<String, dynamic>))
                .toList(),
          ));
    } catch (e) {
      print('자모 불러오기 연결 실패: $e');
      return null;
    }
  }
  /// 자모 26개를 한꺼번에 DB에 저장한다 (다 채웠을 때만 부른다).
  /// 성공하면 null, 실패하면 이유 문구.
  static Future<String?> saveAllJamo(Map<String, List<StrokeData>> jamo) async {
    if (Session.userId == null) return '로그인하지 않아 저장할 수 없습니다.';
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/jamo/save-all'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': Session.userId,
          'jamo': jamo.map((j, strokes) =>
              MapEntry(j, strokes.map((s) => s.toJson()).toList())),
        }),
      );
      if (response.statusCode == 200) return null;
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['message'] is String) return data['message'] as String;
      } catch (_) {}
      return '서버 오류 (${response.statusCode})';
    } catch (e) {
      return '서버에 연결하지 못했습니다.';
    }
  }
  /// 폰트 만들기: 합성한 글자 획을 FastAPI(/make-font)로 보내고 TTF 바이트를 받는다.
  /// glyphs 키는 유니코드 16진수(예: "AC00"), 값은 획마다 [x0, y0, x1, y1, ...] (0~1000).
  /// 실패하면 이유를 담은 Exception을 던진다.
  static Future<Uint8List> makeFont({
    required String fontName,
    required double strokeWidth,
    required Map<String, List<List<int>>> glyphs,
  }) async {
    final url = Uri.parse('${ApiConfig.fastApiBaseUrl}/make-font');

    final http.Response response;
    try {
      response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fontName': fontName,
          'strokeWidth': strokeWidth,
          'glyphs': glyphs,
        }),
      );
    } catch (e) {
      throw Exception('FastAPI 연결 실패: $e');
    }

    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('TTF 생성 실패 (${response.statusCode}): ${response.body}');
  }

  // ---------------------------------------------------------------- 내 폰트 (Spring /api/font)

  /// 만든 TTF를 Spring에 저장한다. 성공하면 fontId, 실패하면 Exception.
  static Future<int> saveFontToServer({
    required String fontName,
    required double strokeWidth,
    required int glyphCount,
    required Uint8List ttf,
  }) async {
    if (Session.userId == null) {
      throw Exception('로그인하지 않아 서버에 저장하지 않았습니다');
    }
    final url = Uri.parse('${ApiConfig.springBaseUrl}/font').replace(
      queryParameters: {
        'userId': '${Session.userId}',
        'fontName': fontName,
        'strokeWidth': '$strokeWidth',
        'glyphCount': '$glyphCount',
      },
    );

    final http.Response response;
    try {
      response = await http.post(
        url,
        headers: {'Content-Type': 'application/octet-stream'},
        body: ttf,
      );
    } catch (e) {
      throw Exception('Spring 연결 실패: $e');
    }

    if (response.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return (data['fontId'] as num).toInt();
    }
    throw Exception(
        '서버 저장 실패 (${response.statusCode}): ${utf8.decode(response.bodyBytes)}');
  }

    /// 서버에서 폰트 만들기: DB에 저장된 자모 26개로 서버가 배치 + TTF를 만들고 내 폰트에 저장한다.
  /// 성공하면 (fontId, glyphCount), 실패하면 이유를 담은 Exception.
  static Future<MadeFont> makeFontOnServer({
    required String fontName,
    required double strokeWidth,
  }) async {
    if (Session.userId == null) throw Exception('로그인하지 않았습니다');
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${ApiConfig.springBaseUrl}/font/make'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': Session.userId,
          'fontName': fontName,
          'strokeWidth': strokeWidth,
        }),
      );
    } catch (e) {
      throw Exception('Spring 연결 실패: $e');
    }
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final data = jsonDecode(text) as Map<String, dynamic>;
      return MadeFont(
        (data['fontId'] as num).toInt(),
        (data['glyphCount'] as num?)?.toInt(),
      );
    }
    try {
      final data = jsonDecode(text);
      if (data is Map && data['message'] is String) throw Exception(data['message']);
    } on FormatException catch (_) {}
    throw Exception('서버 오류 (${response.statusCode})');
  }

  /// 내 폰트 목록 (최근 것부터). 실패하면 null.
  static Future<List<FontInfo>?> getMyFonts() async {
    if (Session.userId == null) return [];
    try {
      final response = await http.get(
          Uri.parse('${ApiConfig.springBaseUrl}/font?userId=${Session.userId}'));
      if (response.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return list
          .map((e) => FontInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('폰트 목록 불러오기 실패: $e');
      return null;
    }
  }

  /// 서버에 저장된 TTF 받기. 실패하면 Exception.
  static Future<Uint8List> downloadFont(int fontId) async {
    final http.Response response;
    try {
      response = await http.get(Uri.parse(
          '${ApiConfig.springBaseUrl}/font/$fontId/file?userId=${Session.userId}'));
    } catch (e) {
      throw Exception('Spring 연결 실패: $e');
    }
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('다운로드 실패 (${response.statusCode})');
  }
}
/// 서버에서 만든 폰트 (fontId, 글자 수)
class MadeFont {
  final int fontId;
  final int? glyphCount;
  MadeFont(this.fontId, this.glyphCount);
}
/// 서버에 저장된 내 폰트 한 개
class FontInfo {
  final int fontId;
  final String fontName;
  final double? strokeWidth;
  final int? glyphCount;
  final DateTime? createdAt;

  FontInfo({
    required this.fontId,
    required this.fontName,
    this.strokeWidth,
    this.glyphCount,
    this.createdAt,
  });

  factory FontInfo.fromJson(Map<String, dynamic> json) => FontInfo(
        fontId: (json['fontId'] as num).toInt(),
        fontName: (json['fontName'] ?? '') as String,
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble(),
        glyphCount: (json['glyphCount'] as num?)?.toInt(),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'].toString()),
      );
}

//앤그록