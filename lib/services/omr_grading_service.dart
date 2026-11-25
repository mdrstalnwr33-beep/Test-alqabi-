class OmrGradeSummary {
  const OmrGradeSummary({
    required this.correct,
    required this.incorrect,
    required this.unanswered,
  });

  final int correct;
  final int incorrect;
  final int unanswered;

  int get total => correct + incorrect + unanswered;
}

/// Scores a reviewed answer sheet against the answer key for the exact
/// detected model. Both question order and option order are reversed only
/// for comparison; saved student responses remain in the source exam order.
class OmrGradingService {
  static OmrGradeSummary grade({
    required List<int?> originalAnswers,
    required List<int> questionOrder,
    required List<List<int>> optionDisplayIndex,
    required List<int?> displayedAnswerKey,
    required List<String> questionTypes,
    required int optionCount,
  }) {
    final count = originalAnswers.length;
    if (questionOrder.length != count ||
        optionDisplayIndex.length != count ||
        displayedAnswerKey.length != count ||
        questionTypes.length != count) {
      throw StateError('بيانات التصحيح لا تتطابق مع عدد أسئلة الاختبار.');
    }

    final seen = <int>{};
    for (final originalQuestion in questionOrder) {
      if (originalQuestion < 0 || originalQuestion >= count ||
          !seen.add(originalQuestion)) {
        throw StateError('ترتيب أسئلة النموذج غير صالح.');
      }
    }
    if (seen.length != count) {
      throw StateError('ترتيب أسئلة النموذج غير مكتمل.');
    }

    var correct = 0;
    var incorrect = 0;
    var unanswered = 0;
    for (var displayedQuestion = 0; displayedQuestion < count; displayedQuestion++) {
      final originalQuestion = questionOrder[displayedQuestion];
      final correctDisplayed = displayedAnswerKey[displayedQuestion];
      if (correctDisplayed == null) {
        throw StateError('مفتاح الإجابة للنموذج غير مكتمل؛ لم يتم اعتماد الدرجة.');
      }
      final originalAnswer = originalAnswers[originalQuestion];
      if (originalAnswer == null) {
        unanswered++;
        continue;
      }

      final optionMap = optionDisplayIndex[originalQuestion];
      if (originalAnswer < 0 || originalAnswer >= optionMap.length) {
        throw StateError('إجابة الطالب خارج نطاق خيارات السؤال.');
      }
      final displayedAnswer = optionMap[originalAnswer];
      final maximumOptions = questionTypes[originalQuestion] == 'tf' ? 2 : optionCount;
      if (displayedAnswer < 0 || displayedAnswer >= maximumOptions ||
          correctDisplayed < 0 || correctDisplayed >= maximumOptions) {
        throw StateError('ترتيب خيارات النموذج غير صالح؛ لم يتم اعتماد الدرجة.');
      }

      if (displayedAnswer == correctDisplayed) {
        correct++;
      } else {
        incorrect++;
      }
    }

    return OmrGradeSummary(
      correct: correct,
      incorrect: incorrect,
      unanswered: unanswered,
    );
  }
}
