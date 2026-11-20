class Exam {
  Exam({required this.id, required this.title, required this.subject, required this.questionCount, required this.optionCount, required this.answerKey});
  final String id;
  final String title;
  final String subject;
  final int questionCount;
  final int optionCount;
  final List<int?> answerKey;
}
