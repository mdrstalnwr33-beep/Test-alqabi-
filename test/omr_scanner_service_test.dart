import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_scanner_service.dart';
import 'package:alqadi_smart_exam_checker/services/omr_sheet_service.dart';

void main() {
  Exam makeExam() => Exam(
    id: 'scanner-test-123456',
    title: 'اختبار تجريبي',
    subject: 'العلوم',
    questionCount: 2,
    optionCount: 4,
    answerKey: const [2, 0],
    questionTypes: const ['mcq', 'tf'],
  );

  List<ScanPoint> corners() => const [
    ScanPoint(22, 24),
    ScanPoint(573, 24),
    ScanPoint(573, 803),
    ScanPoint(22, 803),
  ];

  imglib.Image blankSheet() {
    final image = imglib.Image(width: 595, height: 842);
    imglib.fill(image, color: imglib.ColorRgb8(255, 255, 255));
    return image;
  }

  imglib.Image sheetWithCornerMarkers() {
    final image = blankSheet();
    final black = imglib.ColorRgb8(0, 0, 0);
    imglib.fillRect(image, x1: 15, y1: 17, x2: 28, y2: 30, color: black);
    imglib.fillRect(image, x1: 566, y1: 17, x2: 579, y2: 30, color: black);
    imglib.fillRect(image, x1: 566, y1: 796, x2: 579, y2: 809, color: black);
    imglib.fillRect(image, x1: 15, y1: 796, x2: 28, y2: 809, color: black);
    return image;
  }

  void shade(imglib.Image image, Exam exam, int question, int option) {
    final p = OmrSheetService.positionFor(exam, question, option);
    imglib.fillCircle(
      image,
      x: (p.x * 595).round(),
      y: (p.y * 842).round(),
      radius: 7,
      color: imglib.ColorRgb8(0, 0, 0),
    );
  }


  test('automatically detects the four fixed page-corner markers', () async {
    final image = sheetWithCornerMarkers();
    final detected = await OmrScannerService().detectCorners(imglib.encodePng(image));
    expect(detected, hasLength(4));
    expect(detected[0].x, closeTo(22, 1));
    expect(detected[0].y, closeTo(24, 1));
    expect(detected[1].x, closeTo(573, 1));
    expect(detected[1].y, closeTo(24, 1));
    expect(detected[2].x, closeTo(573, 1));
    expect(detected[2].y, closeTo(803, 1));
    expect(detected[3].x, closeTo(22, 1));
    expect(detected[3].y, closeTo(803, 1));
  });

  test('reads a black-pen mark and preserves a blank answer', () async {
    final exam = makeExam();
    final image = blankSheet();
    shade(image, exam, 0, 2);

    final result = await OmrScannerService().scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers[0], 2);
    expect(result.answers[1], isNull);
    expect(result.blankQuestions, [1]);
    expect(result.ambiguousQuestions, isEmpty);
  });

  test('flags two equally shaded choices as ambiguous', () async {
    final exam = makeExam();
    final image = blankSheet();
    shade(image, exam, 0, 0);
    shade(image, exam, 0, 1);

    final result = await OmrScannerService().scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers[0], isNull);
    expect(result.ambiguousQuestions, [2]);
  });

  test('rejects corners supplied in the wrong order', () async {
    final image = blankSheet();
    await expectLater(
      OmrScannerService().scan(
        imageBytes: imglib.encodePng(image),
        corners: const [
          ScanPoint(29, 197),
          ScanPoint(557, 815),
          ScanPoint(557, 197),
          ScanPoint(29, 815),
        ],
        exam: makeExam(),
      ),
      throwsArgumentError,
    );
  });
}
