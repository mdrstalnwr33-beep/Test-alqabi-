import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import '../services/omr_scanner_service.dart';

/// Live camera view. CameraX supplies analysis frames through the camera plugin;
/// capture is triggered only after the four fixed page markers remain stable.
class LiveAutoScanScreen extends StatefulWidget {
  const LiveAutoScanScreen({super.key});
  @override
  State<LiveAutoScanScreen> createState() => _LiveAutoScanScreenState();
}

class _LiveAutoScanScreenState extends State<LiveAutoScanScreen> {
  final OmrScannerService _scanner = OmrScannerService();
  CameraController? _controller;
  bool _starting = true, _capturing = false, _frameBusy = false;
  bool _cornersFound = false;
  int _stableFrames = 0, _frameNumber = 0;
  List<ScanPoint> _lastCorners = const [];
  String _message = 'وجّه الكاميرا نحو ورقة الإجابة كاملة';

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('لا توجد كاميرا متاحة.');
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_analyzeFrame);
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) setState(() {
        _starting = false;
        _message = 'تعذر تشغيل الكاميرا: $e';
      });
    }
  }

  Future<void> _analyzeFrame(CameraImage frame) async {
    if (_frameBusy || _capturing || ++_frameNumber % 3 != 0) return;
    _frameBusy = true;
    try {
      final bytes = _grayFrameAsJpeg(frame);
      final corners = await _scanner.detectCorners(bytes);
      final stable = _sameCorners(_lastCorners, corners, frame.width, frame.height);
      _stableFrames = stable ? _stableFrames + 1 : 1;
      _lastCorners = corners;
      if (mounted) setState(() {
        _cornersFound = true;
        _message = _stableFrames >= 4
            ? 'تم تثبيت المربعات الأربع — جارٍ الالتقاط والتصحيح'
            : 'تم التعرف على الزوايا؛ ثبّت الورقة قليلاً';
      });
      if (_stableFrames >= 4) await _captureAndReturn();
    } catch (_) {
      _stableFrames = 0;
      _lastCorners = const [];
      if (mounted && _cornersFound) setState(() {
        _cornersFound = false;
        _message = 'ضع الورقة كاملة داخل الإطار حتى تظهر المربعات الأربع';
      });
    } finally {
      _frameBusy = false;
    }
  }

  Uint8List _grayFrameAsJpeg(CameraImage frame) {
    final image = imglib.Image(width: frame.width, height: frame.height);
    final plane = frame.planes.first;
    final data = plane.bytes;
    for (var y = 0; y < frame.height; y++) {
      final row = y * plane.bytesPerRow;
      for (var x = 0; x < frame.width; x++) {
        final index = row + x * plane.bytesPerPixel!;
        final value = data[index];
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    var oriented = image;
    final rotation = _controller?.description.sensorOrientation ?? 0;
    if (rotation == 90 || rotation == 180 || rotation == 270) {
      oriented = imglib.copyRotate(image, angle: rotation);
    }
    return Uint8List.fromList(imglib.encodeJpg(oriented, quality: 65));
  }

  bool _sameCorners(List<ScanPoint> a, List<ScanPoint> b, int width, int height) {
    if (a.length != 4 || b.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      final dx = a[i].x - b[i].x;
      final dy = a[i].y - b[i].y;
      if ((dx * dx + dy * dy) > (width * width + height * height) * 0.0004) {
        return false;
      }
    }
    return true;
  }

  Future<void> _captureAndReturn() async {
    if (_capturing) return;
    _capturing = true;
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      await controller.stopImageStream();
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
      final photo = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop<XFile>(photo);
    } catch (e) {
      _capturing = false;
      if (mounted) setState(() => _message = 'تعذر التقاط الورقة؛ حاول تثبيتها مرة أخرى: $e');
      final controller = _controller;
      if (controller != null && controller.value.isInitialized && !controller.value.isStreamingImages) {
        await controller.startImageStream(_analyzeFrame);
      }
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().whenComplete(controller.dispose);
      } else {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('المسح التلقائي الفوري')),
      body: _starting
          ? const Center(child: CircularProgressIndicator())
          : controller == null || !controller.value.isInitialized
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_message, textAlign: TextAlign.center),
                ))
              : Stack(fit: StackFit.expand, children: [
                  CameraPreview(controller),
                  IgnorePointer(child: Container(
                    margin: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _cornersFound ? Colors.greenAccent : Colors.white,
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  )),
                  Positioned(
                    left: 18, right: 18, bottom: 28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.72),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
