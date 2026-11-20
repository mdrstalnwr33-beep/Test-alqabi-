class Exam {
  Exam({required this.id, required this.title, required this.subject, required this.questionCount, required this.optionCount, required this.answerKey, this.createdAt});
  final String id, title, subject;
  final int questionCount, optionCount;
  final List<int?> answerKey;
  final DateTime? createdAt;
  bool get hasAnswerKey => answerKey.length == questionCount && answerKey.every((v) => v != null);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'subject': subject, 'questionCount': questionCount, 'optionCount': optionCount, 'answerKey': answerKey, 'createdAt': (createdAt ?? DateTime.now()).toIso8601String()};
  factory Exam.fromJson(Map<String, dynamic> json) => Exam(id: json['id'] as String, title: json['title'] as String, subject: (json['subject'] ?? '') as String, questionCount: json['questionCount'] as int, optionCount: json['optionCount'] as int, answerKey: (json['answerKey'] as List).map((v) => v == null ? null : v as int).toList(), createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String));
}
class ExamResult {
  ExamResult({required this.id, required this.examId, required this.examTitle, required this.studentName, required this.responses, required this.correct, required this.incorrect, required this.unanswered, required this.ambiguous, required this.scannedAt});
  final String id, examId, examTitle, studentName;
  final List<int?> responses;
  final int correct, incorrect, unanswered, ambiguous;
  final DateTime scannedAt;
  int get total => responses.length;
  double get percentage => total == 0 ? 0 : correct * 100 / total;
  Map<String, dynamic> toJson() => {'id': id, 'examId': examId, 'examTitle': examTitle, 'studentName': studentName, 'responses': responses, 'correct': correct, 'incorrect': incorrect, 'unanswered': unanswered, 'ambiguous': ambiguous, 'scannedAt': scannedAt.toIso8601String()};
  factory ExamResult.fromJson(Map<String, dynamic> json) => ExamResult(id: json['id'] as String, examId: json['examId'] as String, examTitle: json['examTitle'] as String, studentName: json['studentName'] as String, responses: (json['responses'] as List).map((v) => v == null ? null : v as int).toList(), correct: json['correct'] as int, incorrect: json['incorrect'] as int, unanswered: json['unanswered'] as int, ambiguous: json['ambiguous'] as int, scannedAt: DateTime.parse(json['scannedAt'] as String));
}
