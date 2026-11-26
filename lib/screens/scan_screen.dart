import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';
import '../models/exam.dart';
import '../services/omr_scanner_service.dart';
import '../services/omr_grading_service.dart';
import 'live_auto_scan_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.exams, required this.onResult});
  final List<Exam> exams;
  final ValueChanged<ExamResult> onResult;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}
class _ScanScreenState extends State<ScanScreen> {
  final picker = ImagePicker();
  final scanner = OmrScannerService();
  Exam? selectedExam;
  XFile? image;
  List<ScanPoint> corners = [];
  bool busy = false;
  String stageMessage = 'اختر الاختبار ثم صوّر ورقة الإجابة المطبوعة.';

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectedExam != null) {
      final matches = widget.exams.where((e) => e.id == selectedExam!.id);
      selectedExam = matches.isEmpty ? null : matches.first;
    }
  }

  Future<void> openLiveAutoScan() async {
    final exam = selectedExam;
    if (exam == null) return;
    final capture = await Navigator.push<LiveScanCapture>(
      context,
      MaterialPageRoute(builder: (_) => LiveAutoScanScreen(exam: exam)),
    );
    if (capture == null || !mounted) return;
    setState(() {
      image = capture.photo;
      corners = [];
      stageMessage = 'تمت القراءة تلقائياً وعرض الإجابات الصحيحة والخاطئة.';
    });
    await scanNow(suppliedReadout: capture.readout);
  }

  Future<void> choose(ImageSource source) async {
    try {
      final picked = await picker.pickImage(source: source, imageQuality: 95, maxWidth: 2400);
      if (picked != null && mounted) setState(() { image = picked; corners = []; stageMessage = 'سيكتشف التطبيق زوايا الورقة تلقائياً عند بدء التحليل. تأكد من ظهور الورقة كاملة.'; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح الصورة: ' + e.toString())));
    }
  }

  Future<void> scanNow({OmrReadout? suppliedReadout}) async {
    final exam = selectedExam;
    final photo = image;
    if (exam == null || photo == null) return;
    if (!exam.hasAnswerKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل مفتاح الإجابة أولاً من صفحة الاختبار.')));
      return;
    }
    setState(() => busy = true);
    try {
      final readout = suppliedReadout ?? await scanner.scan(imageBytes: await photo.readAsBytes(), exam: exam);
      if (!mounted) return;
      final review = suppliedReadout == null
          ? await Navigator.push<_ReviewSubmission>(context, MaterialPageRoute(builder: (_) => _ReviewAnswersScreen(exam: exam, readout: readout)))
          : _ReviewSubmission(answers: readout.answers, studentName: readout.studentName, seatNumber: readout.seatNumber);
      if (review == null || !mounted) return;
      final reviewed = review.answers;
      final grade = OmrGradingService.grade(
        originalAnswers: reviewed,
        questionOrder: readout.questionOrder,
        optionDisplayIndex: readout.optionDisplayIndex,
        displayedAnswerKey: readout.variantAnswerKey,
        questionTypes: exam.questionTypes,
        optionCount: exam.optionCount,
      );
      final correct = grade.correct;
      final incorrect = grade.incorrect;
      final unanswered = grade.unanswered;
      // A completely untouched sheet is an absence; an individual blank or
      // double-marked question remains worth zero without marking attendance absent.
      final isAbsent = reviewed.every((answer) => answer == null) &&
          readout.ambiguousQuestions.isEmpty;
      final savedCorrectAnswers = List<int?>.filled(exam.questionCount, null);
      if (readout.variantCode == 'BASE') {
        for (var q = 0; q < exam.questionCount; q++) { savedCorrectAnswers[q] = exam.answerKey[q]; }
      } else {
        final savedVariant = exam.variants.firstWhere((v) => v.code == readout.variantCode);
        for (var displayedQ = 0; displayedQ < savedVariant.questionOrder.length; displayedQ++) {
          final originalQ = savedVariant.questionOrder[displayedQ];
          final displayedCorrect = readout.variantAnswerKey[displayedQ];
          if (displayedCorrect != null && displayedCorrect >= 0 && displayedCorrect < savedVariant.optionOrder[originalQ].length) {
            savedCorrectAnswers[originalQ] = savedVariant.optionOrder[originalQ][displayedCorrect];
          }
        }
      }
      final appDir = await getApplicationDocumentsDirectory();
      final savedPaper = await File(photo.path).copy('${appDir.path}/student-paper-${DateTime.now().microsecondsSinceEpoch}.jpg');
      final result = ExamResult(
        id: DateTime.now().microsecondsSinceEpoch.toString(), examId: exam.id, examTitle: exam.title,
        studentName: review.studentName.isEmpty ? 'غير مقروء' : review.studentName,
        seatNumber: review.seatNumber,
        variantCode: readout.variantCode,
        sourceImagePath: savedPaper.path,
        responses: reviewed, correctAnswers: savedCorrectAnswers,
        questionTypes: List<String>.from(exam.questionTypes),
        correct: correct, incorrect: incorrect, unanswered: unanswered,
        ambiguous: readout.ambiguousQuestions.length, isAbsent: isAbsent, scannedAt: DateTime.now(),
      );
      widget.onResult(result);
      setState(() { image = null; corners = []; stageMessage = 'تم تصحيح الورقة وحفظ النتيجة.'; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAbsent ? 'تم تسجيل الطالب غائباً لعدم تظليل أي فقرة.' : 'تم التصحيح: ' + correct.toString() + ' من ' + exam.questionCount.toString())));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحليل الورقة: ' + e.toString())));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('تصحيح ورقة OMR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('اطبع نموذج الإجابة من الاختبار نفسه. أثناء التصوير التقط الورقة كاملة من أعلى، وسيتعرف التطبيق تلقائياً على المربعات السوداء الأربع لتصحيح الميل والمنظور.', style: TextStyle(color: Colors.black54, height: 1.5)),
    const SizedBox(height: 16),
    DropdownButtonFormField<Exam>(
      value: selectedExam != null && widget.exams.any((e) => e.id == selectedExam!.id) ? widget.exams.firstWhere((e) => e.id == selectedExam!.id) : null,
      decoration: const InputDecoration(labelText: 'اختر الاختبار'),
      items: widget.exams.map((e) => DropdownMenuItem(value: e, child: Text(e.title))).toList(),
      onChanged: (e) => setState(() => selectedExam = e),
    ),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: () => choose(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('الكاميرا'))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(onPressed: () => choose(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('المعرض'))),
    ]),
    const SizedBox(height: 12),
    if (image != null) _imagePreview() else Container(height: 190, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.document_scanner_outlined, size: 54, color: Color(0xFF12A89D)), Text('لم يتم اختيار صورة') ])),
    const SizedBox(height: 10),
    Text(stageMessage, style: const TextStyle(color: Colors.black54)),
    
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: busy || selectedExam == null || image == null ? null : scanNow, icon: const Icon(Icons.fact_check_outlined), label: Text(busy ? 'جارٍ تحليل الورقة...' : 'تحليل الورقة وتصحيحها')),
    if (busy) const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator())),
  ]);

  Widget _imagePreview() => SizedBox(height: 410, child: LayoutBuilder(builder: (context, constraints) {
    final file = File(image!.path);
    return FutureBuilder<imglib.Image>(
      future: _loadPreview(file),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('تعذر عرض الصورة المختارة.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final img = snapshot.data!;
        final scale = _fitScale(img.width.toDouble(), img.height.toDouble(), constraints.maxWidth, constraints.maxHeight);
        return Stack(alignment: Alignment.center, children: [
            Image.file(file, fit: BoxFit.contain, width: constraints.maxWidth, height: constraints.maxHeight),
            Positioned(top: 8, right: 8, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(.65), borderRadius: BorderRadius.circular(8)), child: const Padding(padding: EdgeInsets.all(7), child: Text('اكتشاف تلقائي للزوايا', style: TextStyle(color: Colors.white))))),
          ]);
      },
    );
  }));

  Future<imglib.Image> _loadPreview(File file) async {
    final decoded = imglib.decodeImage(await file.readAsBytes());
    if (decoded == null) throw StateError('تعذر قراءة الصورة.');
    return decoded;
  }
  double _fitScale(double iw, double ih, double w, double h) => (w / iw < h / ih) ? w / iw : h / ih;
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.points, this.scale, this.dx, this.dy);
  final List<ScanPoint> points;
  final double scale, dx, dy;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.red..strokeWidth = 3..style = PaintingStyle.stroke;
    final fill = Paint()..color = Colors.yellow;
    final positions = points.map((e) => Offset(dx + e.x * scale, dy + e.y * scale)).toList();
    if (positions.length >= 2) { final path = Path()..moveTo(positions.first.dx, positions.first.dy); for (final v in positions.skip(1)) { path.lineTo(v.dx, v.dy); } canvas.drawPath(path, p); }
    for (var i = 0; i < positions.length; i++) {
      canvas.drawCircle(positions[i], 9, fill);
      final tp = TextPainter(text: TextSpan(text: (i + 1).toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, positions[i] + const Offset(-4, -7));
    }
  }
  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => true;
}

class _ReviewSubmission {
  const _ReviewSubmission({required this.answers, required this.studentName, required this.seatNumber});
  final List<int?> answers;
  final String studentName, seatNumber;
}

class _ReviewAnswersScreen extends StatefulWidget {
  const _ReviewAnswersScreen({required this.exam, required this.readout});
  final Exam exam;
  final OmrReadout readout;
  @override
  State<_ReviewAnswersScreen> createState() => _ReviewAnswersScreenState();
}
class _ReviewAnswersScreenState extends State<_ReviewAnswersScreen> {
  late List<int?> answers;
  late final List<int> order;
  late final TextEditingController studentNameController, seatNumberController;

  @override
  void initState() {
    super.initState();
    answers = List<int?>.from(widget.readout.answers);
    order = List<int>.generate(answers.length, (i) => i)
      ..sort((a, b) => _number(a).compareTo(_number(b)));
    studentNameController = TextEditingController(text: widget.readout.studentName);
    seatNumberController = TextEditingController(text: widget.readout.seatNumber);
  }

  @override
  void dispose() {
    studentNameController.dispose();
    seatNumberController.dispose();
    super.dispose();
  }

  int _number(int question) =>
      question < widget.readout.questionNumbers.length
          ? widget.readout.questionNumbers[question]
          : question + 1;

  int _displayIndex(int question, int option) {
    final mapping = widget.readout.optionDisplayIndex;
    return question < mapping.length && option < mapping[question].length
        ? mapping[question][option]
        : option;
  }

  List<int> _optionsInPrintedOrder(int question) =>
      List<int>.generate(widget.exam.optionsFor(question), (i) => i)
        ..sort((a, b) => _displayIndex(question, a).compareTo(_displayIndex(question, b)));

  String _optionLabel(int question, int option) =>
      widget.exam.questionTypes[question] == 'tf'
          ? (option == 0 ? 'صح' : 'خطأ')
          : String.fromCharCode(65 + _displayIndex(question, option));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مراجعة الإجابات')),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(children: [
          TextField(
            controller: studentNameController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'اسم الطالب - قراءة تلقائية',
              helperText: widget.readout.studentName.isEmpty
                  ? 'لم يُقرأ الاسم بوضوح؛ يمكنك تصحيحه اختيارياً.'
                  : 'تم استخراج الاسم من الورقة.',
              prefixIcon: const Icon(Icons.person_outline),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: seatNumberController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'رقم الجلوس / الكود - قراءة تلقائية',
              helperText: widget.readout.seatNumber.isEmpty
                  ? 'لم يُقرأ الرقم بوضوح.'
                  : 'تم استخراج الرقم من الورقة.',
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'راجع القراءة قبل اعتماد الدرجة. كود النموذج: ${widget.readout.variantCode} — التظليل المكرر/غير الواضح: ${widget.readout.ambiguousQuestions.length}، الفقرات غير المظللة: ${widget.readout.blankQuestions.length}. كل فقرة فارغة أو مزدوجة التظليل درجتها صفر، وإذا لم تُظلّل أي فقرة تسجل الورقة غائباً.',
          style: const TextStyle(height: 1.5),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: order.length,
          itemBuilder: (context, index) {
            final question = order[index];
            final printedNumber = _number(question);
            final unclear = widget.readout.ambiguousQuestions.contains(printedNumber);
            return Card(
              color: unclear ? Colors.orange.shade50 : null,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      printedNumber.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Wrap(spacing: 2, children: [
                      for (final option in _optionsInPrintedOrder(question))
                        ChoiceChip(
                          label: Text(_optionLabel(question, option)),
                          selected: answers[question] == option,
                          onSelected: (_) => setState(() => answers[question] = option),
                        ),
                      ChoiceChip(
                        label: const Text('فارغ'),
                        selected: answers[question] == null,
                        onSelected: (_) => setState(() => answers[question] = null),
                      ),
                      if (unclear)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(start: 6),
                          child: Text(
                            'غير واضح',
                            style: TextStyle(color: Colors.deepOrange, fontSize: 12),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _ReviewSubmission(
                    answers: List<int?>.from(answers),
                    studentName: studentNameController.text.trim(),
                    seatNumber: seatNumberController.text.trim(),
                  ),
                );
              },
              child: const Text('اعتماد التصحيح وحفظ النتيجة'),
            ),
          ),
        ),
      ),
    ]),
  );
}
