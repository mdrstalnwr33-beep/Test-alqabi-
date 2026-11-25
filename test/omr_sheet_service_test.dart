import 'package:flutter_test/flutter_test.dart';
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_sheet_service.dart';

void main() {
  test('student names are parsed from pasted numbered class lists', () {
    expect(
      StudentNameParser.parse('١- محمد أحمد علي\r\n2. خالد حسن صالح\n\n• سالم يحيى قاسم; فهد علي ناصر'),
      ['محمد أحمد علي', 'خالد حسن صالح', 'سالم يحيى قاسم', 'فهد علي ناصر'],
    );
    expect(StudentNameParser.isAtLeastThreeParts('محمد أحمد علي'), isTrue);
    expect(StudentNameParser.isAtLeastThreeParts('محمد أحمد'), isFalse);
  });

  test('all OMR bubble centers remain inside the A4 page', () {
    final exam = Exam(
      id: 'test-form-123456',
      title: 'اختبار تجريبي',
      subject: 'العلوم',
      questionCount: 40,
      optionCount: 5,
      answerKey: List<int?>.filled(40, null),
      questionTypes: List<String>.generate(40, (i) => i.isEven ? 'mcq' : 'tf'),
    );

    for (var question = 0; question < exam.questionCount; question++) {
      for (var option = 0; option < exam.optionsFor(question); option++) {
        final point = OmrSheetService.positionFor(exam, question, option);
        expect(point.x, greaterThan(0));
        expect(point.x, lessThan(1));
        expect(point.y, greaterThan(0));
        expect(point.y, lessThan(1));
      }
    }
  });

  test('true-false questions expose exactly two answer bubbles', () {
    final exam = Exam(
      id: 'test-form-123456',
      title: 'اختبار تجريبي',
      subject: 'العلوم',
      questionCount: 4,
      optionCount: 4,
      answerKey: List<int?>.filled(4, null),
      questionTypes: const ['tf', 'mcq', 'tf', 'mcq'],
    );

    expect(exam.optionsFor(0), 2);
    expect(exam.optionsFor(1), 4);
    expect(exam.optionsFor(2), 2);
    expect(exam.optionsFor(3), 4);
  });

  test('true-false questions appear first, followed by multiple choice', () {
    final exam = Exam(
      id: 'ordered-form-123',
      title: 'اختبار تجريبي',
      subject: 'العلوم',
      questionCount: 5,
      optionCount: 4,
      answerKey: List<int?>.filled(5, null),
      questionTypes: const ['tf', 'tf', 'mcq', 'mcq', 'mcq'],
    );

    expect(OmrSheetService.visualQuestionNumber(exam, 0), 1);
    expect(OmrSheetService.visualQuestionNumber(exam, 1), 2);
    expect(OmrSheetService.visualQuestionNumber(exam, 2), 3);
    expect(OmrSheetService.visualQuestionNumber(exam, 3), 4);
    expect(OmrSheetService.visualQuestionNumber(exam, 4), 5);

    final tf = OmrSheetService.positionFor(exam, 0, 0);
    final mcq = OmrSheetService.positionFor(exam, 2, 0);
    expect(tf.x, greaterThan(mcq.x));
    expect(tf.y, mcq.y);
  });

  test('generates 30 distinct reproducible variants and keeps the original key mapping', () {
    final types = <String>['tf', 'tf', 'mcq', 'mcq', 'mcq'];
    final first = ExamVariantFactory.generate(examId: 'exam-123456', questionTypes: types, optionCount: 4, count: 30);
    final second = ExamVariantFactory.generate(examId: 'exam-123456', questionTypes: types, optionCount: 4, count: 30);
    expect(first.length, 30);
    expect(first.map((v) => v.code).toSet().length, 30);
    expect(first.map((v) => v.questionOrder.join(',')).toSet().length, greaterThan(1));
    expect(first.map((v) => v.code).toList(), second.map((v) => v.code).toList());
    for (var i = 0; i < first.length; i++) {
      expect(first[i].questionOrder, second[i].questionOrder);
      expect(first[i].optionOrder, second[i].optionOrder);
    }
    final originalKey = <int?>[1, 0, 2, 3, 1];
    for (final variant in first) {
      for (var q = 0; q < types.length; q++) {
        if (types[q] == 'tf') expect(variant.optionOrder[q], [0, 1]);
      }
      for (var displayedQuestion = 0; displayedQuestion < types.length; displayedQuestion++) {
        final displayedCorrect = variant.getDisplayedAnswer(displayedQuestion, originalKey);
        final originalQuestion = variant.questionOrder[displayedQuestion];
        expect(variant.optionOrder[originalQuestion][displayedCorrect!], originalKey[originalQuestion]);
      }
    }
    expect(originalKey, <int?>[1, 0, 2, 3, 1]);
  });

  test('exam question text and choices survive JSON serialization', () {
    final exam = Exam(
      id: 'question-content-1', title: 'اختبار', subject: 'علوم',
      questionCount: 2, optionCount: 3, answerKey: const [1, 2],
      questionTypes: const ['tf', 'mcq'],
      questions: const [
        ExamQuestion(text: 'الماء يتكون من الهيدروجين والأكسجين', options: ['صح', 'خطأ']),
        ExamQuestion(text: 'ما وحدة قياس القوة؟', options: ['الجول', 'النيوتن', 'الواط']),
      ],
    );
    final restored = Exam.fromJson(exam.toJson());
    expect(restored.questions, hasLength(2));
    expect(restored.questions[0].text, 'الماء يتكون من الهيدروجين والأكسجين');
    expect(restored.questions[1].options, ['الجول', 'النيوتن', 'الواط']);
    final old = Exam.fromJson({
      'id': 'legacy-q', 'title': 'قديم', 'subject': '', 'questionCount': 1,
      'optionCount': 4, 'answerKey': [0], 'questionTypes': ['mcq'],
    });
    expect(old.questions, isEmpty);
  });

  test('exam variants survive local JSON serialization and old exam data remains readable', () {
    final exam = Exam(
      id: 'exam-123456', title: 'اختبار', subject: 'علوم', questionCount: 2,
      optionCount: 4, answerKey: const [1, 2], questionTypes: const ['tf', 'mcq'],
      variants: ExamVariantFactory.generate(examId: 'exam-123456', questionTypes: const ['tf', 'mcq'], optionCount: 4, count: 12),
    );
    final restored = Exam.fromJson(exam.toJson());
    expect(restored.variants.length, 12);
    expect(restored.variants.first.code, exam.variants.first.code);
    final legacy = Exam.fromJson({
      'id': 'old', 'title': 'قديم', 'subject': '', 'questionCount': 1,
      'optionCount': 4, 'answerKey': [0], 'questionTypes': ['mcq'],
    });
    expect(legacy.variants, isEmpty);
  });


  test('variant question order preserves TF-first layout and maps student answers to original key positions', () {
    const types = <String>['mcq', 'tf', 'mcq', 'tf'];
    const originalKey = <int?>[2, 1, 0, 0];
    final variants = ExamVariantFactory.generate(
      examId: 'mapping-test-1234',
      questionTypes: types,
      optionCount: 4,
      count: 12,
      seed: 77,
    );
    for (final variant in variants) {
      expect(variant.questionOrder.take(2).toSet(), <int>{1, 3});
      expect(variant.questionOrder.skip(2).toSet(), <int>{0, 2});
      final displayedCorrect = List<int?>.generate(
        types.length,
        (displayedQ) => variant.getDisplayedAnswer(displayedQ, originalKey),
      );
      final mappedBack = variant.mapDisplayedAnswersToOriginal(displayedCorrect);
      expect(mappedBack, originalKey);
    }
  });

}
