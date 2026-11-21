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
    ScanPoint(29, 197),
    ScanPoint(557, 197),
    ScanPoint(557, 815),
    ScanPoint(29, 815),
  ];

  imglib.Image blankSheet() => imglib.Image(width: 595, height: 842)
    ..clear(color: imglib.ColorRgb8(255, 255, 255));

  void shade(imglib.Image image, Exam exam, int question, int option) {
    final p = OmrSheetService.positionFor(exam, question, option);
    imglib.fillCircle(
      image,
      x: (p.x * 595).round(),
      y: (p.y * 842).round(),
      radius: 4,
      color: imglib.ColorRgb8(0, 0, 0),
    );
  }

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
    expect(result.blankQuestions, [2]);
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
    expect(result.ambiguousQuestions, [1]);
  });

  test('rejects corners supplied in the wrong order', () async {
    final image = blankSheet();
    expect(
      () => OmrScannerService().scan(
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
