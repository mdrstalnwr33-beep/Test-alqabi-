import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_scanner_service.dart';
import 'package:alqadi_smart_exam_checker/services/omr_sheet_service.dart';

void main() {
  test('cleans only an OCR field caption from an Arabic student name', () {
    expect(
      OmrScannerService.cleanStudentName('اسم الطالب: عبد الطالب محمد'),
      'عبد الطالب محمد',
    );
    expect(
      OmrScannerService.cleanStudentName('رقم الجلوس: ٧٦'),
      '',
    );
  });

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

  OmrScannerService scanner() => OmrScannerService(
    identityReader: (_) async => ('', ''),
    variantCodeReader: (_) async => '',
  );

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

    final result = await scanner().scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers[0], 2);
    expect(result.answers[1], isNull);
    expect(result.blankQuestions, [1]);
    expect(result.ambiguousQuestions, isEmpty);
    expect(result.isAbsent, isFalse);
  });

  test('flags two equally shaded choices as ambiguous', () async {
    final exam = makeExam();
    final image = blankSheet();
    shade(image, exam, 0, 0);
    shade(image, exam, 0, 1);

    final result = await scanner().scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers[0], isNull);
    expect(result.ambiguousQuestions, [2]);
    expect(result.isAbsent, isFalse);
  });

  test('marks a completely unshaded paper as absent', () async {
    final exam = makeExam();
    final result = await scanner().scan(
      imageBytes: imglib.encodePng(blankSheet()),
      corners: corners(),
      exam: exam,
    );
    expect(result.answers, [null, null]);
    expect(result.blankQuestions, [2, 1]);
    expect(result.ambiguousQuestions, isEmpty);
    expect(result.isAbsent, isTrue);
  });

  test('still scans the original BASE sheet after variants have been generated', () async {
    final base = makeExam();
    final variant = ExamVariantFactory.generate(
      examId: base.id,
      questionTypes: base.questionTypes,
      optionCount: base.optionCount,
      answerKey: base.answerKey,
      count: 1,
    ).single;
    final exam = base.copyWith(variants: [variant]);
    final image = blankSheet();
    shade(image, exam, 0, 2);
    shade(image, exam, 1, 0);
    final baseScanner = OmrScannerService(
      identityReader: (_) async => ('', ''),
      variantCodeReader: (_) async => 'BASE',
    );

    final result = await baseScanner.scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers, exam.answerKey);
    expect(result.variantCode, 'BASE');
  });

  test('maps a shuffled variant correctly when OCR appends one extra code digit', () async {
    final base = makeExam();
    final variant = ExamVariantFactory.generate(
      examId: base.id,
      questionTypes: base.questionTypes,
      optionCount: base.optionCount,
      answerKey: base.answerKey,
      count: 1,
    ).single;
    final exam = base.copyWith(variants: [variant]);
    final layoutExam = exam.copyWith(
      questionTypes: variant.questionOrder.map((i) => exam.questionTypes[i]).toList(),
    );
    final image = blankSheet();
    for (var displayedQuestion = 0; displayedQuestion < exam.questionCount; displayedQuestion++) {
      final displayedAnswer = variant.getDisplayedAnswer(displayedQuestion, exam.answerKey);
      shade(image, layoutExam, displayedQuestion, displayedAnswer!);
    }
    final codeWithOcrNoise = '${variant.code}7';
    final variantScanner = OmrScannerService(
      identityReader: (_) async => ('', ''),
      variantCodeReader: (_) async => codeWithOcrNoise,
    );

    final result = await variantScanner.scan(
      imageBytes: imglib.encodePng(image),
      corners: corners(),
      exam: exam,
    );

    expect(result.answers, exam.answerKey);
    expect(result.variantCode, variant.code);
    expect(result.questionOrder, variant.questionOrder);
    expect(result.variantAnswerKey, variant.getAnswerKey(exam.answerKey));
    for (var originalQuestion = 0; originalQuestion < exam.questionCount; originalQuestion++) {
      expect(
        result.questionNumbers[originalQuestion],
        variant.questionOrder.indexOf(originalQuestion) + 1,
      );
      expect(
        result.optionDisplayIndex[originalQuestion],
        List<int>.generate(
          exam.optionsFor(originalQuestion),
          (option) => variant.optionOrder[originalQuestion].indexOf(option),
        ),
      );
    }
  });

  test('stores a distinct transformed answer key for each generated variant', () {
    final base = makeExam();
    final variants = ExamVariantFactory.generate(
      examId: base.id,
      questionTypes: base.questionTypes,
      optionCount: base.optionCount,
      answerKey: base.answerKey,
      count: 2,
    );

    expect(variants, hasLength(2));
    for (final variant in variants) {
      expect(variant.displayedAnswerKey, hasLength(base.questionCount));
      expect(variant.displayedAnswerKey, variant.buildDisplayedAnswerKey(base.answerKey));
      final restored = variant.mapDisplayedAnswersToOriginal(variant.displayedAnswerKey);
      expect(restored, base.answerKey);
      final saved = ExamVariant.fromJson(variant.toJson());
      expect(saved.displayedAnswerKey, variant.displayedAnswerKey);
    }
    expect(variants.map((v) => v.code).toSet(), hasLength(2));
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
