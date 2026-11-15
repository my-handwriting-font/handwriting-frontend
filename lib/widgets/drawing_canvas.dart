import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/handwriting_model.dart'; // PointData, StrokeData

class DrawingCanvas extends StatefulWidget {
  final double size;

  // 읽기 전용 모드: 프리뷰 캔버스처럼 사용자가 직접 필기하면 안 되는 곳에서
  // true로 설정하면 터치/펜 입력을 받지 않는다.
  final bool readOnly;

  const DrawingCanvas({
    Key? key,
    required this.size,
    this.readOnly = false,
  }) : super(key: key);

  @override
  // InputScreen에서 GlobalKey로 접근해야 하므로 State 클래스는 public이어야 합니다.
  DrawingCanvasState createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  // 펜만 받을지 여부. 펜으로 아무것도 안 그려지면 false로 바꿔보세요.
  static const bool _stylusOnly = true;

  // 이 거리(픽셀)보다 가까운 점은 버려서 손 떨림과 중복 점을 줄인다.
  static const double _minPointDistance = 2.0;

  // 화면에 그려질 전체 획
  final List<StrokeData> _strokes = [];

  // 지금 펜이 닿아 있는 동안 기록되는 획의 점들
  List<PointData> _currentStrokePoints = [];

  // 지금 그리고 있는 포인터 하나만 받는다 (손바닥 등 다른 터치 무시)
  int? _activePointer;

  // --- 외부에서 호출하는 메서드 ---

  void clearPoints() {
    setState(() {
      _strokes.clear();
      _currentStrokePoints = [];
      _activePointer = null;
    });
  }

  List<StrokeData> getValidPoints() {
    // 펜을 떼지 않은 채 전송을 누르는 경우를 대비해 현재 획도 포함
    final List<StrokeData> allStrokes = List.from(_strokes);
    if (_currentStrokePoints.isNotEmpty) {
      allStrokes.add(StrokeData(points: List.from(_currentStrokePoints)));
    }
    return allStrokes;
  }

  void loadStrokes(List<StrokeData> fetchedStrokes) {
    setState(() {
      _strokes.clear();
      _currentStrokePoints = [];
      _activePointer = null;
      _strokes.addAll(fetchedStrokes);
    });
  }

  // --- 터치 및 펜 이벤트 ---

  bool _isAllowed(PointerEvent e) {
    if (!_stylusOnly) return true;
    return e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus ||
        e.kind == PointerDeviceKind.mouse; // 윈도우 마우스 테스트용
  }

  Offset _local(Offset global) =>
      (context.findRenderObject() as RenderBox).globalToLocal(global);

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || !_isAllowed(event)) return;
    _activePointer = event.pointer;

    final p = _local(event.position);
    setState(() {
      _currentStrokePoints = [
        PointData(x: p.dx, y: p.dy, pressure: event.pressure),
      ];
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    if (_currentStrokePoints.isEmpty) return;

    final p = _local(event.position);

    // 캔버스 영역 밖으로 나가는 점은 무시
    if (p.dx < 0 || p.dx > widget.size || p.dy < 0 || p.dy > widget.size) {
      return;
    }

    // 직전 점과 너무 가까우면 무시 (떨림/중복 제거)
    final last = _currentStrokePoints.last;
    if ((Offset(last.x, last.y) - p).distance < _minPointDistance) return;

    setState(() {
      _currentStrokePoints.add(
        PointData(x: p.dx, y: p.dy, pressure: event.pressure),
      );
    });
  }

  void _onPointerUp(PointerUpEvent event) => _finishStroke(event.pointer);

  void _onPointerCancel(PointerCancelEvent event) =>
      _finishStroke(event.pointer);

  void _finishStroke(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;

    setState(() {
      // 한 점짜리(살짝 닿은) 획은 버린다.
      if (_currentStrokePoints.length >= 2) {
        _strokes.add(StrokeData(points: List.from(_currentStrokePoints)));
      }
      _currentStrokePoints = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final canvas = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 2), // 정사각형 가이드라인
        color: Colors.white,
      ),
      // Listener를 써야 원시 필압(Pressure) 데이터를 그대로 받는다.
      // readOnly인 경우 콜백을 null로 넘겨 입력을 아예 받지 않는다.
      child: Listener(
        onPointerDown: widget.readOnly ? null : _onPointerDown,
        onPointerMove: widget.readOnly ? null : _onPointerMove,
        onPointerUp: widget.readOnly ? null : _onPointerUp,
        onPointerCancel: widget.readOnly ? null : _onPointerCancel,
        child: CustomPaint(
          painter: DrawingPainter(_strokes, _currentStrokePoints),
          size: Size(widget.size, widget.size),
        ),
      ),
    );

    // 읽기 전용(프리뷰) 캔버스는 스크롤을 막을 필요가 없다.
    if (widget.readOnly) return canvas;

    // 캔버스 위에서 시작한 터치는 부모 스크롤뷰에 넘기지 않고 캔버스가 가져간다.
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (EagerGestureRecognizer instance) {},
        ),
      },
      child: canvas,
    );
  }
}

// --- 캔버스에 선을 렌더링하는 클래스 ---
// --- 캔버스에 선을 렌더링하는 클래스 (필압 반영) ---
class DrawingPainter extends CustomPainter {
  final List<StrokeData> strokes;
  final List<PointData> currentStrokePoints;

  // 필압 0 → 최소 굵기, 필압 1 → 최대 굵기. 취향에 맞게 조절하세요.
  static const double _minWidth = 2.0;
  static const double _maxWidth = 7.0;

  // 굵기가 급격히 튀지 않게 이전 굵기를 얼마나 따라갈지 (0~1, 클수록 즉각 반응)
  static const double _smoothing = 0.35;

  DrawingPainter(this.strokes, this.currentStrokePoints);

  double _widthOf(double pressure) {
    // 필압 정보가 없는 점(0 이하)은 중간 굵기로 처리
    final p = pressure <= 0 ? 0.5 : pressure.clamp(0.0, 1.0);
    return _minWidth + (_maxWidth - _minWidth) * p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawPressureCurve(canvas, stroke.points, paint);
    }

    if (currentStrokePoints.isNotEmpty) {
      _drawPressureCurve(canvas, currentStrokePoints, paint);
    }
  }

  // 구간마다 굵기를 달리해 이어 그린다. 끝이 둥글어서 이음매가 티 나지 않는다.
  void _drawPressureCurve(Canvas canvas, List<PointData> pts, Paint paint) {
    if (pts.isEmpty) return;

    if (pts.length == 1) {
      paint.strokeWidth = _widthOf(pts.first.pressure);
      canvas.drawPoints(
        PointMode.points,
        [Offset(pts.first.x, pts.first.y)],
        paint,
      );
      return;
    }

    double width = _widthOf(pts.first.pressure);
    Offset start = Offset(pts.first.x, pts.first.y);

    for (int i = 0; i < pts.length - 1; i++) {
      final cur = pts[i];
      final next = pts[i + 1];

      final mid = Offset((cur.x + next.x) / 2, (cur.y + next.y) / 2);

      // 두 점의 평균 필압으로 목표 굵기를 구하고, 이전 굵기에서 부드럽게 이동
      final target = _widthOf((cur.pressure + next.pressure) / 2);
      width = width + (target - width) * _smoothing;
      paint.strokeWidth = width;

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(cur.x, cur.y, mid.dx, mid.dy);
      canvas.drawPath(path, paint);

      start = mid;
    }

    // 마지막 꼬리는 끝점까지 이어준다.
    final last = pts.last;
    paint.strokeWidth = width;
    canvas.drawLine(start, Offset(last.x, last.y), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}