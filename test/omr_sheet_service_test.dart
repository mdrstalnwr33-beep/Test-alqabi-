import 'package:flutter_test/flutter_test.dart';
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_sheet_service.dart';

void main() {
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
      questionTypes: const ['mcq', 'tf', 'mcq', 'tf'],
    );

    expect(exam.optionsFor(0), 4);
    expect(exam.optionsFor(1), 2);
    expect(exam.optionsFor(2), 4);
    expect(exam.optionsFor(3), 2);
  });
}
