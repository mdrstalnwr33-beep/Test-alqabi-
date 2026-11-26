import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import '../models/exam.dart';
import '../services/omr_scanner_service.dart';
import '../services/omr_sheet_service.dart';

class LiveScanCapture {
  const LiveScanCapture({required this.photo, required this.readout});
  final XFile photo;
  final OmrReadout readout;
}

class LiveAutoScanScreen extends StatefulWidget {
  const LiveAutoScanScreen({super.key, required this.exam});
  final Exam exam;
  @override
  State<LiveAutoScanScreen> createState() => _LiveAutoScanScreenState();
}

class _LiveAutoScanScreenState extends State<LiveAutoScanScreen> {
  final OmrScannerService _scanner = OmrScannerService();
  CameraController? _controller;
  bool _starting = true, _capturing = false, _frameBusy = false, _cornersFound = false;
  int _stableFrames = 0, _frameNumber = 0;
  List<ScanPoint> _lastCorners = const [];
  String _message = 'وجّه الكاميرا نحو ورقة الإجابة كاملة';
  XFile? _photo;
  OmrReadout? _readout;

  @override
  void initState() { super.initState(); _startCamera(); }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('لا توجد كاميرا متاحة.');
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      _controller = controller;
      await controller.startImageStream(_analyzeFrame);
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) setState(() { _starting = false; _message = 'تعذر تشغيل الكاميرا: $e'; });
    }
  }

  Future<void> _analyzeFrame(CameraImage frame) async {
    if (_frameBusy || _capturing || ++_frameNumber % 3 != 0) return;
    _frameBusy = true;
    try {
      final corners = await _scanner.detectCorners(_grayFrameAsJpeg(frame));
      final stable = _sameCorners(_lastCorners, corners, frame.width, frame.height);
      _stableFrames = stable ? _stableFrames + 1 : 1;
      _lastCorners = corners;
      if (mounted) setState(() {
        _cornersFound = true;
        _message = _stableFrames >= 4 ? 'ثبتت المربعات الأربع — جارٍ الالتقاط وقراءة الإجابات' : 'تم التعرف على الزوايا؛ ثبّت الورقة قليلاً';
      });
      if (_stableFrames >= 4) await _captureAndAnalyze();
    } catch (_) {
      _stableFrames = 0; _lastCorners = const [];
      if (mounted && _cornersFound) setState(() { _cornersFound = false; _message = 'أظهر الورقة كاملة حتى تظهر المربعات الأربع'; });
    } finally { _frameBusy = false; }
  }

  Uint8List _grayFrameAsJpeg(CameraImage frame) {
    final image = imglib.Image(width: frame.width, height: frame.height);
    final plane = frame.planes.first, data = plane.bytes;
    for (var y = 0; y < frame.height; y++) {
      final row = y * plane.bytesPerRow;
      for (var x = 0; x < frame.width; x++) {
        final value = data[row + x * (plane.bytesPerPixel ?? 1)];
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    var oriented = image;
    final rotation = _controller?.description.sensorOrientation ?? 0;
    if (rotation == 90 || rotation == 180 || rotation == 270) oriented = imglib.copyRotate(image, angle: rotation);
    return Uint8List.fromList(imglib.encodeJpg(oriented, quality: 65));
  }

  bool _sameCorners(List<ScanPoint> a, List<ScanPoint> b, int width, int height) {
    if (a.length != 4 || b.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      final dx = a[i].x - b[i].x, dy = a[i].y - b[i].y;
      if (dx * dx + dy * dy > (width * width + height * height) * 0.0004) return false;
    }
    return true;
  }

  Future<void> _captureAndAnalyze() async {
    if (_capturing) return;
    _capturing = true;
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      await controller.stopImageStream();
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
      final photo = await controller.takePicture();
      final readout = await _scanner.scan(imageBytes: await photo.readAsBytes(), exam: widget.exam);
      if (!mounted) return;
      setState(() { _photo = photo; _readout = readout; _message = 'اكتملت القراءة — الأخضر صحيح والأحمر خاطئ'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _message = 'تعذرت قراءة الورقة: $e'; _capturing = false; });
      final controller = _controller;
      if (controller != null && controller.value.isInitialized && !controller.value.isStreamingImages) await controller.startImageStream(_analyzeFrame);
    }
  }

  List<_BubbleMark> _marks(OmrReadout r) {
    final v = widget.exam.variants.where((x) => x.code == r.variantCode).firstOrNull;
    final layout = v == null ? widget.exam : Exam(
      id: widget.exam.id, title: widget.exam.title, subject: widget.exam.subject,
      questionCount: widget.exam.questionCount, optionCount: widget.exam.optionCount,
      answerKey: widget.exam.answerKey,
      questionTypes: v.questionOrder.map((q) => widget.exam.questionTypes[q]).toList(),
    );
    final result = <_BubbleMark>[];
    for (var q = 0; q < r.displayedMarkedOptions.length; q++) {
      final selected = r.displayedMarkedOptions[q];
      final key = q < r.variantAnswerKey.length ? r.variantAnswerKey[q] : null;
      for (final option in selected) {
        final p = OmrSheetService.positionFor(layout, q, option);
        result.add(_BubbleMark(p.x, p.y, selected.length == 1 && option == key ? Colors.green : Colors.red));
      }
    }
    return result;
  }

  Future<void> _retry() async {
    setState(() { _photo = null; _readout = null; _capturing = false; _stableFrames = 0; _lastCorners = const []; _message = 'وجّه الكاميرا نحو ورقة الإجابة كاملة'; });
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isStreamingImages) await c.startImageStream(_analyzeFrame);
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      if (c.value.isStreamingImages) { c.stopImageStream().whenComplete(c.dispose); } else { c.dispose(); }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller, r = _readout;
    return Scaffold(
      appBar: AppBar(title: const Text('المسح والتصحيح المباشر')),
      body: _starting ? const Center(child: CircularProgressIndicator())
        : r != null ? _resultView(r)
        : c == null || !c.value.isInitialized
          ? Center(child: Text(_message, textAlign: TextAlign.center))
          : Stack(fit: StackFit.expand, children: [
              CameraPreview(c),
              IgnorePointer(child: Container(margin: const EdgeInsets.all(22), decoration: BoxDecoration(border: Border.all(color: _cornersFound ? Colors.greenAccent : Colors.white, width: 4), borderRadius: BorderRadius.circular(18)))),
              Positioned(left: 18, right: 18, bottom: 28, child: Container(
                padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black.withOpacity(.72), borderRadius: BorderRadius.circular(14)),
                child: Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              )),
            ]),
    );
  }

  Widget _resultView(OmrReadout r) {
    final correct = List<int>.generate(r.displayedMarkedOptions.length, (q) => q)
      .where((q) => r.displayedMarkedOptions[q].length == 1 && q < r.variantAnswerKey.length && r.displayedMarkedOptions[q].first == r.variantAnswerKey[q]).length;
    return Column(children: [
      Expanded(child: Center(child: AspectRatio(aspectRatio: OmrSheetService.pageWidth / OmrSheetService.pageHeight,
        child: Stack(fit: StackFit.expand, children: [
          Image.memory(r.warpedImageBytes, fit: BoxFit.fill),
          CustomPaint(painter: _BubbleMarkPainter(_marks(r))),
        ]),
      ))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: Text(
        'الطالب: \${r.studentName.isEmpty ? "غير مقروء" : r.studentName}  |  النموذج: \${r.variantCode}\\nالصحيح: $correct من \${widget.exam.questionCount}  |  الفارغ: \${r.blankQuestions.length}  |  المكرر: \${r.ambiguousQuestions.length}',
        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('إعادة التصوير'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.icon(onPressed: () => Navigator.of(context).pop<LiveScanCapture>(LiveScanCapture(photo: _photo!, readout: r)), icon: const Icon(Icons.check), label: const Text('حفظ النتيجة'))),
      ])),
    ]);
  }
}

class _BubbleMark {
  const _BubbleMark(this.x, this.y, this.color);
  final double x, y;
  final Color color;
}
class _BubbleMarkPainter extends CustomPainter {
  _BubbleMarkPainter(this.marks);
  final List<_BubbleMark> marks;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = 8.5 * size.width / OmrSheetService.pageWidth;
    for (final m in marks) {
      final center = Offset(m.x * size.width, m.y * size.height);
      canvas.drawCircle(center, radius, Paint()..color = m.color.withOpacity(.28));
      canvas.drawCircle(center, radius, Paint()..color = m.color..style = PaintingStyle.stroke..strokeWidth = 3);
    }
  }
  @override
  bool shouldRepaint(covariant _BubbleMarkPainter oldDelegate) => true;
}
