import 'dart:math';

class ExamVariant {
  ExamVariant({required this.code, required this.questionOrder, required this.optionOrder, this.seed = 0});
  final String code;
  /// Original question indexes in the order printed on this variant.
  final List<int> questionOrder;
  /// For each original question, maps displayed option index to original option index.
  final List<List<int>> optionOrder;
  final int seed;

  int? originalQuestionForDisplayed(int displayedQuestion) {
    if (displayedQuestion < 0 || displayedQuestion >= questionOrder.length) return null;
    return questionOrder[displayedQuestion];
  }

  int? originalOptionForDisplayed(int displayedQuestion, int displayedOption) {
    final originalQuestion = originalQuestionForDisplayed(displayedQuestion);
    if (originalQuestion == null || originalQuestion < 0 || originalQuestion >= optionOrder.length) return null;
    final order = optionOrder[originalQuestion];
    if (displayedOption < 0 || displayedOption >= order.length) return null;
    return order[displayedOption];
  }

  int? getDisplayedAnswer(int displayedQuestion, List<int?> originalAnswerKey) {
    final originalQuestion = originalQuestionForDisplayed(displayedQuestion);
    if (originalQuestion == null || originalQuestion < 0 || originalQuestion >= originalAnswerKey.length) return null;
    final correct = originalAnswerKey[originalQuestion];
    if (correct == null || originalQuestion >= optionOrder.length) return null;
    final index = optionOrder[originalQuestion].indexOf(correct);
    return index < 0 ? null : index;
  }

  /// Converts answers read in the printed variant order back to the source exam order.
  List<int?> mapDisplayedAnswersToOriginal(List<int?> displayedAnswers) {
    if (displayedAnswers.length != questionOrder.length) {
      throw ArgumentError('عدد الإجابات لا يطابق عدد أسئلة النموذج.');
    }
    final original = List<int?>.filled(questionOrder.length, null);
    for (var displayedQ = 0; displayedQ < displayedAnswers.length; displayedQ++) {
      final originalQ = originalQuestionForDisplayed(displayedQ)!;
      final displayedOption = displayedAnswers[displayedQ];
      original[originalQ] = displayedOption == null
          ? null
          : originalOptionForDisplayed(displayedQ, displayedOption);
    }
    return original;
  }

  Map<String, dynamic> toJson() => {
    'code': code, 'questionOrder': questionOrder, 'optionOrder': optionOrder, 'seed': seed,
  };

  factory ExamVariant.fromJson(Map<String, dynamic> json) => ExamVariant(
    code: json['code'] as String,
    questionOrder: (json['questionOrder'] as List).map((v) => v as int).toList(),
    optionOrder: (json['optionOrder'] as List).map((row) => (row as List).map((v) => v as int).toList()).toList(),
    seed: (json['seed'] ?? 0) as int,
  );
}

class ExamVariantFactory {
  static List<ExamVariant> generate({
    required String examId,
    required List<String> questionTypes,
    required int optionCount,
    int count = 30,
    int seed = 20261125,
  }) {
    if (count < 1 || count > 100) throw ArgumentError.value(count, 'count', 'يجب أن يكون بين 1 و100');
    if (questionTypes.isEmpty || optionCount < 2 || optionCount > 5 ||
        questionTypes.any((type) => type != 'tf' && type != 'mcq')) {
      throw ArgumentError('بيانات الاختبار غير صالحة لإنشاء النماذج.');
    }

    final variants = <ExamVariant>[];
    final signatures = <String>{};
    final trueFalseQuestions = <int>[
      for (var i = 0; i < questionTypes.length; i++) if (questionTypes[i] == 'tf') i,
    ];
    final multipleChoiceQuestions = <int>[
      for (var i = 0; i < questionTypes.length; i++) if (questionTypes[i] == 'mcq') i,
    ];
    var attempt = 0;
    while (variants.length < count && attempt < count * 100) {
      final variantSeed = seed + attempt;
      final random = Random(variantSeed);
      final tfOrder = List<int>.from(trueFalseQuestions)..shuffle(random);
      final mcqOrder = List<int>.from(multipleChoiceQuestions)..shuffle(random);
      // Keep the printed sheet's required section order: true/false first, then MCQ.
      final questionOrder = [...tfOrder, ...mcqOrder];
      final optionOrder = List<List<int>>.generate(questionTypes.length, (q) {
        final n = questionTypes[q] == 'tf' ? 2 : optionCount;
        // Keep true/false semantics fixed so the printed labels remain correct.
        if (questionTypes[q] == 'tf') return List<int>.generate(n, (i) => i);
        return List<int>.generate(n, (i) => i)..shuffle(random);
      });
      final signature = questionOrder.join(',') + '|' + optionOrder.map((row) => row.join(',')).join(';');
      attempt++;
      if (!signatures.add(signature)) continue;
      final suffix = (variants.length + 1).toString().padLeft(2, '0');
      final cleanId = examId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final prefix = cleanId.length >= 4
          ? cleanId.substring(cleanId.length - 4).toUpperCase()
          : cleanId.toUpperCase().padLeft(4, '0');
      variants.add(ExamVariant(
        code: 'Q$prefix-$suffix',
        questionOrder: questionOrder,
        optionOrder: optionOrder,
        seed: variantSeed,
      ));
    }
    if (variants.length != count) {
      throw StateError('تعذر إنشاء العدد المطلوب من النماذج المختلفة. جرّب عدداً أقل.');
    }
    return variants;
  }
}

class ExamQuestion {
  const ExamQuestion({required this.text, List<String>? options})
      : options = options ?? <String>[];
  final String text;
  final List<String> options;
  Map<String, dynamic> toJson() => {'text': text, 'options': options};
  factory ExamQuestion.fromJson(Map<String, dynamic> json) => ExamQuestion(
    text: (json['text'] ?? '') as String,
    options: (json['options'] as List?)?.map((v) => v.toString()).toList() ?? const <String>[],
  );
}

class Exam {
  Exam({required this.id, required this.title, required this.subject, required this.questionCount, required this.optionCount, required this.answerKey, this.createdAt, List<String>? questionTypes, this.schoolName = '', this.teacherName = '', this.termName = '', List<ExamVariant>? variants, List<ExamQuestion>? questions})
      : questionTypes = questionTypes ?? List<String>.filled(questionCount, 'mcq'), variants = variants ?? [], questions = questions ?? [];
  final String id, title, subject;
  final int questionCount, optionCount;
  final List<int?> answerKey;
  final DateTime? createdAt;
  final List<String> questionTypes;
  final String schoolName, teacherName, termName;
  final List<ExamVariant> variants;
  final List<ExamQuestion> questions;
  int optionsFor(int index) => index < questionTypes.length && questionTypes[index] == 'tf' ? 2 : optionCount;
  bool get hasAnswerKey => answerKey.length == questionCount && answerKey.every((v) => v != null);
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'subject': subject, 'questionCount': questionCount, 'optionCount': optionCount,
    'answerKey': answerKey, 'questionTypes': questionTypes, 'schoolName': schoolName, 'teacherName': teacherName,
    'termName': termName, 'variants': variants.map((v) => v.toJson()).toList(),
    'questions': questions.map((q) => q.toJson()).toList(),
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };
  factory Exam.fromJson(Map<String, dynamic> json) {
    final count = json['questionCount'] as int;
    return Exam(
      id: json['id'] as String, title: json['title'] as String, subject: (json['subject'] ?? '') as String,
      questionCount: count, optionCount: json['optionCount'] as int,
      answerKey: (json['answerKey'] as List).map((v) => v == null ? null : v as int).toList(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
      questionTypes: (json['questionTypes'] as List?)?.map((v) => v.toString()).toList(),
      schoolName: (json['schoolName'] ?? '') as String, teacherName: (json['teacherName'] ?? '') as String,
      termName: (json['termName'] ?? '') as String,
      variants: (json['variants'] as List?)?.map((v) => ExamVariant.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
      questions: (json['questions'] as List?)?.map((v) => ExamQuestion.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
    );
  }
}

class ExamResult {
  ExamResult({required this.id, required this.examId, required this.examTitle, required this.studentName, required this.responses, required this.correct, required this.incorrect, required this.unanswered, required this.ambiguous, required this.scannedAt, this.seatNumber = '', this.variantCode = ''});
  final String id, examId, examTitle, studentName, seatNumber, variantCode;
  final List<int?> responses;
  final int correct, incorrect, unanswered, ambiguous;
  final DateTime scannedAt;
  int get total => responses.length;
  double get percentage => total == 0 ? 0 : correct * 100 / total;
  Map<String, dynamic> toJson() => {'id': id, 'examId': examId, 'examTitle': examTitle, 'studentName': studentName, 'seatNumber': seatNumber, 'variantCode': variantCode, 'responses': responses, 'correct': correct, 'incorrect': incorrect, 'unanswered': unanswered, 'ambiguous': ambiguous, 'scannedAt': scannedAt.toIso8601String()};
  factory ExamResult.fromJson(Map<String, dynamic> json) => ExamResult(
    id: json['id'] as String, examId: json['examId'] as String, examTitle: json['examTitle'] as String,
    studentName: json['studentName'] as String, seatNumber: (json['seatNumber'] ?? '') as String,
    variantCode: (json['variantCode'] ?? '') as String,
    responses: (json['responses'] as List).map((v) => v == null ? null : v as int).toList(),
    correct: json['correct'] as int, incorrect: json['incorrect'] as int, unanswered: json['unanswered'] as int,
    ambiguous: json['ambiguous'] as int, scannedAt: DateTime.parse(json['scannedAt'] as String));
}
