import 'dart:typed_data';
import 'package:image/image.dart' as imglib;
import '../models/exam.dart';
import 'omr_sheet_service.dart';
class ScanPoint { const ScanPoint(this.x, this.y); final double x, y; }
class OmrReadout {
  const OmrReadout({required this.answers, required this.ambiguousQuestions, required this.blankQuestions});
  final List<int?> answers;
  final List<int> ambiguousQuestions, blankQuestions;
}
class OmrScannerService {
  static const outputWidth = 1190, outputHeight = 1684;
  Future<OmrReadout> scan({required List<int> imageBytes, required List<ScanPoint> corners, required Exam exam}) async {
    if (corners.length != 4) throw ArgumentError('حدد زوايا الورقة الأربع.');
    final source = imglib.decodeImage(Uint8List.fromList(imageBytes));
    if (source == null) throw StateError('تعذر قراءة الصورة.');
    _validateCorners(corners, source.width, source.height);
    final warped = _warp(source, corners);
    final answers = <int?>[], ambiguous = <int>[], blanks = <int>[];
    for (var q = 0; q < exam.questionCount; q++) {
      final scores = <double>[];
      for (var option = 0; option < exam.optionsFor(q); option++) {
        final p = OmrSheetService.positionFor(exam, q, option);
        scores.add(_darkRatio(warped, (p.x * outputWidth).round(), (p.y * outputHeight).round()));
      }
      final ranked = List<int>.generate(scores.length, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
      final best = scores[ranked.first], second = ranked.length > 1 ? scores[ranked[1]] : 0.0;
      if (best < 0.22) { answers.add(null); blanks.add(OmrSheetService.visualQuestionNumber(exam, q)); }
      else if (best < 0.48 || best - second < 0.14) { answers.add(null); ambiguous.add(OmrSheetService.visualQuestionNumber(exam, q)); }
      else { answers.add(ranked.first); }
    }
    return OmrReadout(answers: answers, ambiguousQuestions: ambiguous, blankQuestions: blanks);
  }
  imglib.Image _warp(imglib.Image source, List<ScanPoint> corners) {
    final dst = <ScanPoint>[
      ScanPoint(29 / OmrSheetService.pageWidth * outputWidth, 197 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(557 / OmrSheetService.pageWidth * outputWidth, 197 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(557 / OmrSheetService.pageWidth * outputWidth, 815 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(29 / OmrSheetService.pageWidth * outputWidth, 815 / OmrSheetService.pageHeight * outputHeight),
    ];
    final h = _homography(dst, corners);
    final out = imglib.Image(width: outputWidth, height: outputHeight, numChannels: 3);
    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        final den = h[6] * x + h[7] * y + 1;
        if (den.abs() < 1e-10) {
          out.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        final sx = (h[0] * x + h[1] * y + h[2]) / den, sy = (h[3] * x + h[4] * y + h[5]) / den;
        if (sx >= 0 && sy >= 0 && sx < source.width - 1 && sy < source.height - 1) {
          final px = source.getPixel(sx.round(), sy.round());
          out.setPixelRgb(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt());
        } else { out.setPixelRgb(x, y, 255, 255, 255); }
      }
    }
    return out;
  }
  void _validateCorners(List<ScanPoint> points, int width, int height) {
    for (final p in points) {
      if (!p.x.isFinite || !p.y.isFinite || p.x < 0 || p.y < 0 || p.x >= width || p.y >= height) {
        throw ArgumentError('إحدى الزوايا خارج حدود الصورة. أعد تحديد مراكز المربعات السوداء.');
      }
    }
    // The four points must follow the printed marker order: TL, TR, BR, BL.
    var sign = 0;
    var twiceArea = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1) throw ArgumentError('الزوايا متقاربة أو على خط واحد. أعد تحديدها بالترتيب.');
      final currentSign = cross > 0 ? 1 : -1;
      if (sign != 0 && currentSign != sign) {
        throw ArgumentError('ترتيب الزوايا غير صحيح. ابدأ بأعلى اليسار ثم أعلى اليمين ثم أسفل اليمين ثم أسفل اليسار.');
      }
      sign = currentSign;
      twiceArea += a.x * b.y - b.x * a.y;
    }
    if (twiceArea.abs() < 2000) {
      throw ArgumentError('المساحة المحددة صغيرة جداً. تأكد من تحديد المربعات الأربعة حول الورقة.');
    }
  }

  List<double> _homography(List<ScanPoint> from, List<ScanPoint> to) {
    final m = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      final x = from[i].x, y = from[i].y, u = to[i].x, v = to[i].y;
      m.add([x, y, 1, 0, 0, 0, -u*x, -u*y, u]);
      m.add([0, 0, 0, x, y, 1, -v*x, -v*y, v]);
    }
    for (var c = 0; c < 8; c++) {
      var pivot = c;
      for (var r = c + 1; r < 8; r++) { if (m[r][c].abs() > m[pivot][c].abs()) pivot = r; }
      final temp = m[c]; m[c] = m[pivot]; m[pivot] = temp;
      final divisor = m[c][c];
      if (divisor.abs() < 1e-10) throw StateError('تعذر ضبط منظور الصورة. أعد تحديد الزوايا.');
      for (var j = c; j < 9; j++) { m[c][j] /= divisor; }
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final factor = m[r][c];
        for (var j = c; j < 9; j++) { m[r][j] -= factor * m[c][j]; }
      }
    }
    return List<double>.generate(8, (i) => m[i][8]);
  }
  double _darkRatio(imglib.Image image, int cx, int cy) {
    const radius = 6;
    var dark = 0, total = 0;
    for (var y = -radius; y <= radius; y++) {
      for (var x = -radius; x <= radius; x++) {
        if (x*x + y*y > radius*radius) continue;
        final pxX = cx + x, pxY = cy + y;
        if (pxX < 0 || pxY < 0 || pxX >= image.width || pxY >= image.height) continue;
        final px = image.getPixel(pxX, pxY);
        final gray = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
        if (gray < 105) dark++;
        total++;
      }
    }
    return total == 0 ? 0 : dark / total;
  }
}
