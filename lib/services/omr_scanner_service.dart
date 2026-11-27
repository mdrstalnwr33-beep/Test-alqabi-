import 'dart:typed_data';
import 'dart:io';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:image/image.dart' as imglib;
import '../models/exam.dart';
import 'omr_sheet_service.dart';
class ScanPoint { const ScanPoint(this.x, this.y); final double x, y; }
class OmrReadout {
  const OmrReadout({
    required this.answers,
    required this.ambiguousQuestions,
    required this.blankQuestions,
    this.studentName = '',
    this.seatNumber = '',
    this.variantCode = '',
    this.questionNumbers = const [],
    this.optionDisplayIndex = const [],
    this.questionOrder = const [],
    this.variantAnswerKey = const [],
    this.warpedImageBytes,
    this.displayedMarkedOptions = const [],
  });
  /// Answers are stored in the original exam/key order.
  final List<int?> answers;
  /// These question numbers are the numbers printed on the scanned variant.
  final List<int> ambiguousQuestions, blankQuestions;
  final String studentName, seatNumber, variantCode;
  /// For each original question index, its displayed number on this paper.
  final List<int> questionNumbers;
  /// For each original question and original option, its displayed A/B/C/D position.
  final List<List<int>> optionDisplayIndex;
  /// Maps displayed question positions to original exam question indexes.
  final List<int> questionOrder;
  /// Correct option indexes in this exact variant's printed question/option order.
  final List<int?> variantAnswerKey;
  /// Perspective-corrected page image used for accurate on-page live feedback.
  final Uint8List? warpedImageBytes;
  /// Marked displayed option indexes for each displayed question (including duplicates).
  final List<List<int>> displayedMarkedOptions;

  /// A paper is absent only when every question is blank and none is ambiguous
  /// (a double-marked question is not treated as an untouched paper).
  bool get isAbsent => answers.every((answer) => answer == null) && ambiguousQuestions.isEmpty;
}
class OmrScannerService {
  OmrScannerService({
    Future<String> Function(imglib.Image)? variantCodeReader,
    Future<(String, String)> Function(imglib.Image)? identityReader,
  }) : _variantCodeReader = variantCodeReader,
       _identityReader = identityReader;

  final Future<String> Function(imglib.Image)? _variantCodeReader;
  final Future<(String, String)> Function(imglib.Image)? _identityReader;

  /// Removes the printed field caption from OCR output without deleting a
  /// legitimate word that happens to occur inside a student's name.
  static String cleanStudentName(String raw) {
    var value = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    value = value.replaceFirst(
      RegExp(r'^(?:اسم\s*(?:الطالب|التلميذ)|رقم\s*الجلوس|الجلوس)\s*[:：\-]?\s*'),
      '',
    );
    return value
        .replaceAll(RegExp(r'[^\u0621-\u064A\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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
    var variantCode = await (_variantCodeReader?.call(warped) ?? _readVariantCode(warped));
    ExamVariant? variant;
    // A plain BASE sheet remains valid even after shuffled variants are created.
    if (variantCode == 'BASE') {
      variant = null;
    } else if (exam.variants.isNotEmpty) {
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
      // Store and display the canonical registered code, not the noisy OCR text.
      variantCode = variant.code;
    } else if (variantCode.isNotEmpty) {
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
    final displayedMarkedOptions = <List<int>>[];
    // Normalize local illumination once per page before measuring bubbles.
    // This reduces false blanks caused by phone shadows and uneven lighting.
    final normalizedGray = _normalizeForLighting(warped);
    for (var q = 0; q < layoutExam.questionCount; q++) {
      final scores = <double>[];
      for (var option = 0; option < layoutExam.optionsFor(q); option++) {
        final p = OmrSheetService.positionFor(layoutExam, q, option);
        scores.add(_darkRatio(normalizedGray, warped.width, warped.height,
            (p.x * outputWidth).round(), (p.y * outputHeight).round()));
      }
      final ranked = List<int>.generate(scores.length, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
      final best = scores[ranked.first], second = ranked.length > 1 ? scores[ranked[1]] : 0.0;
      // Count distinct bubble centers that contain a meaningful dark fill.
      // Any two marked options make the whole question invalid (zero points),
      // even if one mark is darker than the other.
      final markedIndexes = <int>[for (var i = 0; i < scores.length; i++) if (scores[i] >= 0.22) i];
      displayedMarkedOptions.add(markedIndexes);
      final markedOptions = markedIndexes.length;
      if (markedOptions == 0) {
        displayedAnswers.add(null);
        blanks.add(OmrSheetService.visualQuestionNumber(layoutExam, q));
      } else if (markedOptions > 1 || best < 0.48 || best - second < 0.14) {
        displayedAnswers.add(null);
        ambiguous.add(OmrSheetService.visualQuestionNumber(layoutExam, q));
      } else {
        displayedAnswers.add(ranked.first);
      }
    }
    final answers = variant == null ? displayedAnswers : variant.mapDisplayedAnswersToOriginal(displayedAnswers);

    // Keep the answer data in original key order, but also retain the printed
    // question/option positions so the review screen mirrors the student's form.
    final questionNumbers = List<int>.generate(exam.questionCount, (q) =>
        variant == null
            ? OmrSheetService.visualQuestionNumber(exam, q)
            : variant.questionOrder.indexOf(q) + 1);
    final optionDisplayIndex = List<List<int>>.generate(exam.questionCount, (q) {
      final optionCount = exam.optionsFor(q);
      if (variant == null) return List<int>.generate(optionCount, (j) => j);
      final displayedOrder = variant.optionOrder[q];
      return List<int>.generate(optionCount, (j) => displayedOrder.indexOf(j));
    });

    return OmrReadout(
      answers: answers,
      ambiguousQuestions: ambiguous,
      blankQuestions: blanks,
      studentName: identity.$1,
      seatNumber: identity.$2,
      variantCode: variantCode,
      questionNumbers: questionNumbers,
      optionDisplayIndex: optionDisplayIndex,
      questionOrder: variant == null
          ? List<int>.generate(exam.questionCount, (q) => q)
          : List<int>.from(variant.questionOrder),
      variantAnswerKey: variant == null
          ? List<int?>.from(exam.answerKey)
          : variant.getAnswerKey(exam.answerKey),
      warpedImageBytes: Uint8List.fromList(imglib.encodeJpg(warped, quality: 92)),
      displayedMarkedOptions: displayedMarkedOptions,
    );
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
    Future<String> recognize({
      required int top,
      required String fileName,
      required String language,
      bool isName = false,
    }) async {
      // The student's name is the final, enlarged row in the right header.
      // Keep the full line, including Arabic dots and descenders, in the OCR crop.
      const left = 606, width = 528, height = 84;
      final safeTop = top.clamp(0, warped.height - height).toInt();
      final crop = imglib.copyCrop(warped, x: left, y: safeTop, width: width, height: height);
      final gray = imglib.grayscale(crop);
      imglib.contrast(gray, contrast: 190);
      final enlarged = imglib.copyResize(
        gray,
        width: width * 6,
        height: height * 6,
        interpolation: imglib.Interpolation.cubic,
      );
      final binary = imglib.Image(width: enlarged.width, height: enlarged.height, numChannels: 3);
      for (var y = 0; y < enlarged.height; y++) {
        for (var x = 0; x < enlarged.width; x++) {
          final pixel = enlarged.getPixel(x, y);
          final value = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) < 165 ? 0 : 255;
          binary.setPixelRgb(x, y, value, value, value);
        }
      }

      final dir = await Directory.systemTemp.createTemp('alqadi_identity_');
      final file = File('${dir.path}/$fileName.png');
      try {
        final candidates = <String>[];
        for (final image in [enlarged, binary]) {
          await file.writeAsBytes(imglib.encodePng(image), flush: true);
          for (final pageMode in ['7', '6', '11']) {
            final raw = await TesseractOcr.extractText(file.path, config: OCRConfig(
              language: language,
              engine: OCREngine.tesseract,
              options: {
                'tessedit_pageseg_mode': pageMode,
                'preserve_interword_spaces': '1',
                if (isName) 'user_defined_dpi': '300',
              },
            ));
            candidates.add(raw.trim());
          }
        }

        if (isName) {
          candidates.sort((a, b) {
            final cleanA = cleanStudentName(a), cleanB = cleanStudentName(b);
            final lettersA = RegExp(r'[\u0621-\u064A]').allMatches(cleanA).length;
            final lettersB = RegExp(r'[\u0621-\u064A]').allMatches(cleanB).length;
            final wordsA = cleanA.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
            final wordsB = cleanB.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
            final scoreA = lettersA +
                (wordsA >= 3 && wordsA <= 5 ? 35 : wordsA == 2 ? 8 : 0) -
                (wordsA > 6 ? 25 : 0);
            final scoreB = lettersB +
                (wordsB >= 3 && wordsB <= 5 ? 35 : wordsB == 2 ? 8 : 0) -
                (wordsB > 6 ? 25 : 0);
            return scoreB.compareTo(scoreA);
          });
        } else {
          candidates.sort((a, b) => RegExp(r'\d').allMatches(b).length
              .compareTo(RegExp(r'\d').allMatches(a).length));
        }
        return candidates.isEmpty ? '' : candidates.first;
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }

    try {
      // Arabic-only recognition improves names; mixed Arabic/English remains
      // useful for seat numbers that may be printed with either digit style.
      final rawName = await recognize(
        top: 300,
        fileName: 'student_name',
        language: 'ara',
        isName: true,
      );
      final rawSeat = await recognize(
        top: 334,
        fileName: 'seat_number',
        language: 'ara+eng',
      );
      final name = cleanStudentName(rawName);
      final arabicLetters = RegExp(r'[\u0621-\u064A]').allMatches(name).length;
      final normalizedDigits = rawSeat
          .replaceAll('٠', '0').replaceAll('١', '1')
          .replaceAll('٢', '2').replaceAll('٣', '3')
          .replaceAll('٤', '4').replaceAll('٥', '5')
          .replaceAll('٦', '6').replaceAll('٧', '7')
          .replaceAll('٨', '8').replaceAll('٩', '9');
      // Never mistake a printed field label such as "رقم الجلوس" for a name.
      return (
        arabicLetters >= 4 ? name : '',
        RegExp(r'\d+').firstMatch(normalizedDigits)?.group(0) ?? '',
      );
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
  /// Estimates and removes slow-changing page illumination (shadows) using
  /// a box-background integral image. The printed bubble geometry is untouched.
  Uint8List _normalizeForLighting(imglib.Image image) {
    final width = image.width, height = image.height;
    final stride = width + 1;
    final integral = Int64List((width + 1) * (height + 1));
    final gray = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final value = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round().clamp(0, 255).toInt();
        gray[y * width + x] = value;
        rowSum += value;
        integral[(y + 1) * stride + x + 1] =
            integral[y * stride + x + 1] + rowSum;
      }
    }

    const backgroundRadius = 20;
    final normalized = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final y0 = (y - backgroundRadius).clamp(0, height - 1).toInt();
      final y1 = (y + backgroundRadius + 1).clamp(0, height).toInt();
      for (var x = 0; x < width; x++) {
        final x0 = (x - backgroundRadius).clamp(0, width - 1).toInt();
        final x1 = (x + backgroundRadius + 1).clamp(0, width).toInt();
        final sum = integral[y1 * stride + x1] -
            integral[y0 * stride + x1] -
            integral[y1 * stride + x0] +
            integral[y0 * stride + x0];
        final area = (x1 - x0) * (y1 - y0);
        final background = area == 0 ? 255.0 : sum / area;
        // White paper under a shadow becomes near-white; dark ink remains dark.
        final value = (gray[y * width + x] * 255.0 /
                (background < 1 ? 1 : background))
            .round().clamp(0, 255).toInt();
        normalized[y * width + x] = value;
      }
    }
    return normalized;
  }

  double _darkRatio(Uint8List gray, int width, int height, int cx, int cy) {
    // Search a small neighborhood for the filled center of the bubble.
    // The center disc excludes the printed outer ring of an empty bubble.
    const radius = 5;
    var bestRatio = 0.0;
    for (var oy = -8; oy <= 8; oy += 2) {
      for (var ox = -8; ox <= 8; ox += 2) {
        var dark = 0, total = 0;
        for (var y = -radius; y <= radius; y++) {
          for (var x = -radius; x <= radius; x++) {
            if (x * x + y * y > radius * radius) continue;
            final pxX = cx + ox + x, pxY = cy + oy + y;
            if (pxX < 0 || pxY < 0 || pxX >= width || pxY >= height) continue;
            if (gray[pxY * width + pxX] < 185) dark++;
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
  }
}
