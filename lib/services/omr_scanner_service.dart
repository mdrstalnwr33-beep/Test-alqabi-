import 'dart:typed_data';
import 'dart:io';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:image/image.dart' as imglib;
import '../models/exam.dart';
import 'omr_sheet_service.dart';
class ScanPoint { const ScanPoint(this.x, this.y); final double x, y; }
class OmrReadout {
  const OmrReadout({required this.answers, required this.ambiguousQuestions, required this.blankQuestions, this.studentName = '', this.seatNumber = '', this.variantCode = ''});
  final List<int?> answers;
  final List<int> ambiguousQuestions, blankQuestions;
  final String studentName, seatNumber, variantCode;
}
class OmrScannerService {
  OmrScannerService({
    Future<String> Function(imglib.Image)? variantCodeReader,
    Future<(String, String)> Function(imglib.Image)? identityReader,
  }) : _variantCodeReader = variantCodeReader,
       _identityReader = identityReader;

  final Future<String> Function(imglib.Image)? _variantCodeReader;
  final Future<(String, String)> Function(imglib.Image)? _identityReader;

  static const outputWidth = 1190, outputHeight = 1684;
  Future<List<ScanPoint>> detectCorners(Uint8List imageBytes) async {
    final decoded = imglib.decodeImage(imageBytes);
    if (decoded == null) throw StateError('تعذر قراءة الصورة.');
    final scale = decoded.width > 1200 ? 1200 / decoded.width : 1.0;
    final small = scale < 1 ? imglib.copyResize(decoded, width: 1200) : decoded;
    final w = small.width, h = small.height;
    final seen = Uint8List(w * h);
    final queue = <int>[];
    final candidates = <ScanPoint>[];
    final sizes = <List<int>>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final start = y * w + x;
        if (seen[start] != 0) continue;
        final p = small.getPixel(x, y);
        final gray = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (gray > 65) { seen[start] = 1; continue; }
        queue
          ..clear()
          ..add(start);
        seen[start] = 1;
        var head = 0, minX = x, maxX = x, minY = y, maxY = y;
        while (head < queue.length) {
          final index = queue[head++], px = index % w, py = index ~/ w;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = px + dx, ny = py + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              final ni = ny * w + nx;
              if (seen[ni] != 0) continue;
              seen[ni] = 1;
              final np = small.getPixel(nx, ny);
              final ng = 0.299 * np.r + 0.587 * np.g + 0.114 * np.b;
              if (ng <= 65) queue.add(ni);
            }
          }
        }
        final bw = maxX - minX + 1, bh = maxY - minY + 1;
        final ratio = bw / bh;
        final area = bw * bh;
        if (bw >= 7 && bh >= 7 && bw <= w * 0.045 && bh <= w * 0.045 &&
            ratio >= 0.68 && ratio <= 1.45 && queue.length >= area * 0.48) {
          candidates.add(ScanPoint((minX + maxX) / 2, (minY + maxY) / 2));
          sizes.add([bw, bh]);
        }
      }
    }
    if (candidates.length < 4) {
      throw StateError('لم أتمكن من اكتشاف المربعات السوداء الأربعة. صوّر الورقة كاملة بإضاءة جيدة ومن دون قص الأطراف.');
    }
    // The generated sheet uses four fixed markers close to the physical
    // page corners. These normalized coordinates match the PDF marker centers.
    final targets = <ScanPoint>[
      ScanPoint(w * 22 / 595, h * 24 / 842),
      ScanPoint(w * 573 / 595, h * 24 / 842),
      ScanPoint(w * 573 / 595, h * 803 / 842),
      ScanPoint(w * 22 / 595, h * 803 / 842),
    ];
    final selected = <ScanPoint>[];
    final used = <int>{};
    for (final target in targets) {
      var best = -1, bestScore = double.infinity;
      for (var i = 0; i < candidates.length; i++) {
        if (used.contains(i)) continue;
        final p = candidates[i];
        // Keep each marker in its own page-corner zone so a dark bubble,
        // logo detail, or text cannot be mistaken for a missing corner.
        final inExpectedCorner = switch (selected.length) {
          0 => p.x < w * 0.25 && p.y < h * 0.22,
          1 => p.x > w * 0.75 && p.y < h * 0.22,
          2 => p.x > w * 0.75 && p.y > h * 0.78,
          _ => p.x < w * 0.25 && p.y > h * 0.78,
        };
        if (!inExpectedCorner) continue;
        final dx = (p.x - target.x) / w, dy = (p.y - target.y) / h;
        final score = dx * dx + dy * dy;
        if (score < bestScore) { bestScore = score; best = i; }
      }
      if (best < 0 || bestScore > 0.035) {
        throw StateError('تعذر تحديد أحد مربعات المعايرة. تأكد من ظهور الورقة كاملة داخل الصورة.');
      }
      used.add(best);
      selected.add(ScanPoint(candidates[best].x / scale, candidates[best].y / scale));
    }
    return selected;
  }

  Future<OmrReadout> scan({required List<int> imageBytes, List<ScanPoint>? corners, required Exam exam}) async {
    final bytes = Uint8List.fromList(imageBytes);
    final source = imglib.decodeImage(bytes);
    if (source == null) throw StateError('تعذر قراءة الصورة.');
    final detectedCorners = corners ?? await detectCorners(bytes);
    if (detectedCorners.length != 4) throw ArgumentError('تعذر تحديد زوايا الورقة تلقائياً.');
    _validateCorners(detectedCorners, source.width, source.height);
    final warped = _warp(source, detectedCorners);
    final identity = await (_identityReader?.call(warped) ?? _readStudentIdentity(warped));
    final variantCode = await (_variantCodeReader?.call(warped) ?? _readVariantCode(warped));
    ExamVariant? variant;
    if (exam.variants.isNotEmpty) {
      if (variantCode.isEmpty) throw StateError('تعذر قراءة كود النموذج؛ أعد تصوير الورقة بوضوح. لم يتم التصحيح.');
      for (final candidate in exam.variants) {
        if (candidate.code == variantCode) { variant = candidate; break; }
      }
      // OCR sometimes appends one extra trailing digit to a two-digit code
      // (for example, reading Q1234-01 as Q1234-017). Retry only that case.
      if (variant == null && variantCode.length > 1) {
        final shortened = variantCode.substring(0, variantCode.length - 1);
        for (final candidate in exam.variants) {
          if (candidate.code == shortened) { variant = candidate; break; }
        }
      }
      if (variant == null) throw StateError('كود النموذج غير مسجل في هذا الاختبار: $variantCode. أوقف التصحيح لحماية النتيجة.');
    } else if (variantCode.isNotEmpty && variantCode != 'BASE') {
      throw StateError('كود الورقة لا يطابق الاختبار المحدد.');
    }
    final layoutExam = variant == null ? exam : Exam(
      id: exam.id, title: exam.title, subject: exam.subject,
      questionCount: exam.questionCount, optionCount: exam.optionCount,
      answerKey: exam.answerKey,
      questionTypes: variant.questionOrder.map((i) => exam.questionTypes[i]).toList(),
      schoolName: exam.schoolName, teacherName: exam.teacherName,
    );
    final displayedAnswers = <int?>[], ambiguous = <int>[], blanks = <int>[];
    for (var q = 0; q < layoutExam.questionCount; q++) {
      final scores = <double>[];
      for (var option = 0; option < layoutExam.optionsFor(q); option++) {
        final p = OmrSheetService.positionFor(layoutExam, q, option);
        scores.add(_darkRatio(warped, (p.x * outputWidth).round(), (p.y * outputHeight).round()));
      }
      final ranked = List<int>.generate(scores.length, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
      final best = scores[ranked.first], second = ranked.length > 1 ? scores[ranked[1]] : 0.0;
      if (best < 0.22) { displayedAnswers.add(null); blanks.add(OmrSheetService.visualQuestionNumber(layoutExam, q)); }
      else if (best < 0.48 || best - second < 0.14) { displayedAnswers.add(null); ambiguous.add(OmrSheetService.visualQuestionNumber(layoutExam, q)); }
      else { displayedAnswers.add(ranked.first); }
    }
    final answers = variant == null ? displayedAnswers : variant.mapDisplayedAnswersToOriginal(displayedAnswers);
    return OmrReadout(answers: answers, ambiguousQuestions: ambiguous, blankQuestions: blanks,
      studentName: identity.$1, seatNumber: identity.$2, variantCode: variantCode);
  }

  Future<String> _readVariantCode(imglib.Image warped) async {
    const left = 48, top = 1620, width = 500, height = 52;
    if (warped.width < left + width || warped.height < top + height) return '';
    final crop = imglib.copyCrop(warped, x: left, y: top, width: width, height: height);
    final cleaned = imglib.grayscale(crop);
    imglib.contrast(cleaned, contrast: 150);
    final enlarged = imglib.copyResize(cleaned, width: width * 3, height: height * 3,
      interpolation: imglib.Interpolation.cubic);
    final dir = await Directory.systemTemp.createTemp('alqadi_variant_');
    final file = File('${dir.path}/variant_code.png');
    try {
      await file.writeAsBytes(imglib.encodePng(enlarged), flush: true);
      final raw = await TesseractOcr.extractText(file.path, config: OCRConfig(
        language: 'eng', engine: OCREngine.tesseract,
        options: {'tessedit_pageseg_mode': '7', 'tessedit_char_whitelist': 'QABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-:'},
      ));
      final normalized = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '');
      if (normalized.contains('BASE')) return 'BASE';
      final match = RegExp(r'Q[A-Z0-9]{4}-[0-9]{2,3}').firstMatch(normalized);
      return match?.group(0) ?? '';
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<(String, String)> _readStudentIdentity(imglib.Image warped) async {
    Future<String> recognize({required int top, required String fileName}) async {
      // The warped page is rendered at 2x PDF coordinates. The name and
      // seat-number lines are in the lower part of the right-hand header,
      // not near the top of the warped image.
      const left = 606, width = 528, height = 48;
      final safeTop = top.clamp(0, warped.height - height).toInt();
      final crop = imglib.copyCrop(warped, x: left, y: safeTop, width: width, height: height);
      final cleaned = imglib.grayscale(crop);
      imglib.contrast(cleaned, contrast: 125);
      final enlarged = imglib.copyResize(cleaned, width: width * 4, height: height * 4,
          interpolation: imglib.Interpolation.cubic);
      final dir = await Directory.systemTemp.createTemp('alqadi_identity_');
      final file = File('${dir.path}/$fileName.png');
      try {
        await file.writeAsBytes(imglib.encodePng(enlarged), flush: true);
        return await TesseractOcr.extractText(file.path, config: OCRConfig(
          language: 'ara+eng',
          engine: OCREngine.tesseract,
          options: {'tessedit_pageseg_mode': '7', 'preserve_interword_spaces': '1'},
        ));
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
    try {
      // The identity fields are inside the header near the top of the page.
      // The previous 674/704px crops were far below the header and therefore
      // read blank paper instead of the printed student name and seat number.
      final rawName = await recognize(top: 304, fileName: 'student_name');
      final rawSeat = await recognize(top: 336, fileName: 'seat_number');
      final name = rawName
          .replaceAll(RegExp(r'اسم\s*الطالب|اسم الطالب|الطالب|[_ـ:：]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ').trim();
      final digits = rawSeat.replaceAll('٠','0').replaceAll('١','1')
          .replaceAll('٢','2').replaceAll('٣','3').replaceAll('٤','4')
          .replaceAll('٥','5').replaceAll('٦','6').replaceAll('٧','7')
          .replaceAll('٨','8').replaceAll('٩','9');
      return (name, RegExp(r'\d+').firstMatch(digits)?.group(0) ?? '');
    } catch (_) {
      return ('', '');
    }
  }

  imglib.Image _warp(imglib.Image source, List<ScanPoint> corners) {
    // Warp back to the exact centers of the four markers printed on the PDF.
    final dst = <ScanPoint>[
      ScanPoint(22 / OmrSheetService.pageWidth * outputWidth, 24 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(573 / OmrSheetService.pageWidth * outputWidth, 24 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(573 / OmrSheetService.pageWidth * outputWidth, 803 / OmrSheetService.pageHeight * outputHeight),
      ScanPoint(22 / OmrSheetService.pageWidth * outputWidth, 803 / OmrSheetService.pageHeight * outputHeight),
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
    // Search a small neighborhood for the filled center of the bubble.
    // This compensates for minor perspective/registration errors after warping,
    // while avoiding the printed outer ring of an unfilled bubble.
    const radius = 5;
    var bestRatio = 0.0;
    for (var oy = -8; oy <= 8; oy += 2) {
      for (var ox = -8; ox <= 8; ox += 2) {
        var dark = 0, total = 0;
        for (var y = -radius; y <= radius; y++) {
          for (var x = -radius; x <= radius; x++) {
            if (x*x + y*y > radius*radius) continue;
            final pxX = cx + ox + x, pxY = cy + oy + y;
            if (pxX < 0 || pxY < 0 || pxX >= image.width || pxY >= image.height) continue;
            final px = image.getPixel(pxX, pxY);
            final gray = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
            if (gray < 130) dark++;
            total++;
          }
        }
        if (total > 0) {
          final ratio = dark / total;
          if (ratio > bestRatio) bestRatio = ratio;
        }
      }
    }
    return bestRatio;
  }}
