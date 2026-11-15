import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:handwriting_front/http/api_service.dart';
import '../widgets/drawing_canvas.dart';
import '../models/handwriting_model.dart';
import '../services/normalization_service.dart';
import 'bad_writing_test_screen.dart';
import 'compound_vowel_test_screen.dart';
import 'double_jamo_test_screen.dart';
import 'syllable_final_horizontal_test_screen.dart';
import 'syllable_final_test_screen.dart';
import 'syllable_mixed_test_screen.dart';
import 'syllable_test_screen.dart';
import 'syllable_mixed_final_test_screen.dart';
import 'font_maker_screen.dart';

/// 개발자 테스트 화면 (홈 맨 아래 링크로 들어온다).
/// 원본/정규화 좌표 확인, 1~6번 합성 테스트 화면으로 이동.
class InputScreen extends StatefulWidget {
  const InputScreen({Key? key}) : super(key: key);

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final GlobalKey<DrawingCanvasState> _originalCanvasKey =
      GlobalKey<DrawingCanvasState>();

  final GlobalKey<DrawingCanvasState> _serverCanvasKey =
      GlobalKey<DrawingCanvasState>();

  final double canvasSize = 250.0;

  void _showJsonDialog(String title, String jsonString) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 600,
            height: 500,
            child: SingleChildScrollView(
              child: SelectableText(jsonString),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  void _showRawData() {
    final strokes = _originalCanvasKey.currentState?.getValidPoints();

    if (strokes != null && strokes.isNotEmpty) {
      final request = HandwritingRequest(
        charName: "ㄱ",
        strokes: strokes,
      );

      const encoder = JsonEncoder.withIndent('  ');
      final rawJson = encoder.convert(request.toJson());

      _showJsonDialog('원본 JSON 데이터', rawJson);
    } else {
      _showEmptyWarning();
    }
  }

  void _showNormalizedData() {
    final strokes = _originalCanvasKey.currentState?.getValidPoints();

    if (strokes != null && strokes.isNotEmpty) {
      final normalizedStrokes =
          NormalizationService.normalizeStrokes(strokes);

      final request = HandwritingRequest(
        charName: "ㄱ",
        strokes: normalizedStrokes,
      );

      const encoder = JsonEncoder.withIndent('  ');
      final normalizedJson = encoder.convert(request.toJson());

      _showJsonDialog('정규화 JSON 데이터 테스트용', normalizedJson);
    } else {
      _showEmptyWarning();
    }
  }

  void _saveToServer() async {
    final strokes = _originalCanvasKey.currentState?.getValidPoints();

    if (strokes != null && strokes.isNotEmpty) {
      final isSuccess = await ApiService.saveHandwriting("ㄱ", strokes);

      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 원본 좌표가 서버로 전송되었습니다!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 저장 실패... 서버 상태를 확인해주세요.')),
        );
      }
    } else {
      _showEmptyWarning();
    }
  }

  void _loadFromServer() async {
    final fetchedStrokes = await ApiService.getLatestHandwriting();

    if (fetchedStrokes != null && fetchedStrokes.isNotEmpty) {
      _drawNormalizedStrokesOnServerCanvas(fetchedStrokes);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📥 서버 데이터 불러오기 완료')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ 불러올 데이터가 없거나 실패했습니다.')),
      );
    }
  }

  void _drawNormalizedStrokesOnServerCanvas(List<StrokeData> strokes) {
    final double targetScale = canvasSize * 0.5;
    final double offset = (canvasSize - targetScale) / 2;

    final denormalized = strokes.map((stroke) {
      return StrokeData(
        points: stroke.points.map((p) {
          return PointData(
            x: (p.x * targetScale) + offset,
            y: (p.y * targetScale) + offset,
            pressure: p.pressure,
          );
        }).toList(),
      );
    }).toList();

    _serverCanvasKey.currentState?.loadStrokes(denormalized);
  }

  void _showEmptyWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('먼저 왼쪽 캔버스에 글자를 입력해주세요.')),
    );
  }

  /// 테스트 화면으로 가는 버튼 (색, 글자, 이동할 화면)
  Widget _navButton(String text, Color color, Widget screen) {
    return ElevatedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(100, 45),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('개발자 테스트'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    const Text(
                      "[ 원본 ]",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DrawingCanvas(
                      key: _originalCanvasKey,
                      size: canvasSize,
                    ),
                  ],
                ),
                const SizedBox(width: 30),
                Column(
                  children: [
                    const Text(
                      "[ 서버 데이터 ]",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DrawingCanvas(
                      key: _serverCanvasKey,
                      size: canvasSize,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showRawData,
                  icon: const Icon(Icons.code),
                  label: const Text('원본 JSON'),
                ),
                const SizedBox(width: 15),
                OutlinedButton.icon(
                  onPressed: _showNormalizedData,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('정규화 JSON 테스트'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    _originalCanvasKey.currentState?.clearPoints();
                    _serverCanvasKey.currentState?.clearPoints();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    minimumSize: const Size(100, 45),
                  ),
                  child: const Text(
                    '둘 다 초기화',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _saveToServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(100, 45),
                  ),
                  child: const Text(
                    'ㄱ 저장',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _loadFromServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(100, 45),
                  ),
                  child: const Text(
                    'ㄱ 불러오기',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _navButton('악필 검증 테스트', Colors.red,
                    const BadWritingTestScreen()),
                _navButton('쌍자음 합성 테스트', Colors.teal,
                    const DoubleJamoTestScreen()),
                _navButton('자음+모음 합성 테스트', Colors.indigo,
                    const SyllableTestScreen()),
                _navButton('받침 있음 합성 테스트 (2번)', Colors.deepPurple,
                    const SyllableFinalTestScreen()),
                _navButton('가로형 받침 있음 합성 테스트 (4번)', Colors.brown,
                    const SyllableFinalHorizontalTestScreen()),
                _navButton('혼합 모음 합성 테스트', Colors.pink,
                    const CompoundVowelTestScreen()),
                _navButton('혼합형 받침 없음 합성 테스트 (5번)', Colors.cyan,
                    const SyllableMixedTestScreen()),
                _navButton('혼합형 받침 있음 합성 테스트 (6번)', Colors.deepOrange,
                    const SyllableMixedFinalTestScreen()),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FontMakerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.font_download, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(100, 45),
                  ),
                  label: const Text(
                    '폰트 만들기 (TTF)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}