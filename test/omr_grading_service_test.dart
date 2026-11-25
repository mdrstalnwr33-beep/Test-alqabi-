import 'package:flutter_test/flutter_test.dart';
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_grading_service.dart';

void main() {
  test('grades every generated model against its own shuffled answer key', () {
    final exam = Exam(
      id: 'Q3108',
      title: 'اختبار تجريبي',
      subject: 'العلوم',
      questionCount: 12,
      optionCount: 4,
      questionTypes: const [
        'tf', 'tf', 'tf', 'tf',
        'mcq', 'mcq', 'mcq', 'mcq', 'mcq', 'mcq', 'mcq', 'mcq',
      ],
      answerKey: const [0, 1, 0, 1, 2, 0, 3, 1, 2, 3, 0, 1],
    );
    final variants = ExamVariantFactory.generate(
      examId: exam.id,
      questionTypes: exam.questionTypes,
      optionCount: exam.optionCount,
      answerKey: exam.answerKey,
      count: 30,
    );

    expect(variants.map((variant) => variant.code).toSet(), hasLength(30));
    for (final variant in variants) {
      final key = variant.getAnswerKey(exam.answerKey);
      final optionDisplayIndex = List<List<int>>.generate(
        exam.questionCount,
        (question) => List<int>.generate(
          exam.optionsFor(question),
          (option) => variant.optionOrder[question].indexOf(option),
        ),
      );

      final allCorrectAnswers = variant.mapDisplayedAnswersToOriginal(key);
      final fullScore = OmrGradingService.grade(
        originalAnswers: allCorrectAnswers,
        questionOrder: variant.questionOrder,
        optionDisplayIndex: optionDisplayIndex,
        displayedAnswerKey: key,
        questionTypes: exam.questionTypes,
        optionCount: exam.optionCount,
      );
      expect(fullScore.correct, exam.questionCount, reason: variant.code);
      expect(fullScore.incorrect, 0, reason: variant.code);
      expect(fullScore.unanswered, 0, reason: variant.code);

      final deliberatelyWrongDisplayed = List<int?>.from(key);
      deliberatelyWrongDisplayed[0] = (deliberatelyWrongDisplayed[0]! + 1) %
          exam.optionsFor(variant.questionOrder[0]);
      final oneWrongAnswer = variant.mapDisplayedAnswersToOriginal(deliberatelyWrongDisplayed);
      final partialScore = OmrGradingService.grade(
        originalAnswers: oneWrongAnswer,
        questionOrder: variant.questionOrder,
        optionDisplayIndex: optionDisplayIndex,
        displayedAnswerKey: key,
        questionTypes: exam.questionTypes,
        optionCount: exam.optionCount,
      );
      expect(partialScore.correct, exam.questionCount - 1, reason: variant.code);
      expect(partialScore.incorrect, 1, reason: variant.code);
    }
  });

  test('does not award a score when the model key is incomplete', () {
    expect(
      () => OmrGradingService.grade(
        originalAnswers: const [0],
        questionOrder: const [0],
        optionDisplayIndex: const [[0, 1]],
        displayedAnswerKey: const [null],
        questionTypes: const ['tf'],
        optionCount: 4,
      ),
      throwsStateError,
    );
  });
}
