import 'package:flutter_test/flutter_test.dart';
import 'package:alqadi_smart_exam_checker/models/exam.dart';
import 'package:alqadi_smart_exam_checker/services/omr_sheet_service.dart';

void main() {
  test('exam data survives JSON round trip', () {
    final exam = Exam(id: '123', title: 'Physics', subject: 'Science', questionCount: 3, optionCount: 4, answerKey: [0, 2, 1], createdAt: DateTime.utc(2026, 1, 1));
    final decoded = Exam.fromJson(exam.toJson());
    expect(decoded.title, 'Physics');
    expect(decoded.answerKey, [0, 2, 1]);
    expect(decoded.hasAnswerKey, isTrue);
  });

  test('all OMR bubble coordinates stay within A4 page', () {
    final exam = Exam(id: '1234567', title: 'Test', subject: '', questionCount: 100, optionCount: 5, answerKey: List<int?>.filled(100, 0));
    for (var q = 0; q < exam.questionCount; q++) {
      for (var a = 0; a < exam.optionCount; a++) {
        final p = OmrSheetService.positionFor(exam, q, a);
        expect(p.x, greaterThan(0));
        expect(p.x, lessThan(1));
        expect(p.y, greaterThan(0));
        expect(p.y, lessThan(1));
      }
    }
  });
}
