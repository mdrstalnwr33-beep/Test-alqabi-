import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/exam.dart';
import '../services/app_store.dart';
import '../services/omr_sheet_service.dart';
import '../services/report_service.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final store = AppStore();
  final reports = ReportService();
  final List<Exam> exams = [];
  final List<ExamResult> results = [];
  int tab = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    final loadedExams = await store.loadExams();
    final loadedResults = await store.loadResults();
    if (!mounted) return;
    setState(() { exams..clear()..addAll(loadedExams); results..clear()..addAll(loadedResults); loading = false; });
  }
  Future<void> _persist() async {
    await store.saveExams(exams);
    await store.saveResults(results);
  }
  Future<void> newExam() async {
    final title = TextEditingController(), subject = TextEditingController();
    final school = TextEditingController(), teacher = TextEditingController();
    final tfCount = TextEditingController(text: '10'), mcqCount = TextEditingController(text: '10'), options = TextEditingController(text: '4');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إنشاء ورقة إجابة جديدة'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الاختبار')),
        const SizedBox(height: 10), TextField(controller: subject, decoration: const InputDecoration(labelText: 'المادة')),
        const SizedBox(height: 10), TextField(controller: school, decoration: const InputDecoration(labelText: 'اسم المدرسة')),
        const SizedBox(height: 10), TextField(controller: teacher, decoration: const InputDecoration(labelText: 'اسم المعلم')),
        const SizedBox(height: 10), TextField(controller: tfCount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أولاً: عدد فقرات الصح والخطأ')),
        const SizedBox(height: 10), TextField(controller: mcqCount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ثانياً: عدد فقرات الاختيار من متعدد')),
        const SizedBox(height: 6), const Text('حدد عدد الفقرات وأنواعها فقط؛ لا تحتاج إلى إدخال نصوص الأسئلة هنا.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 10), TextField(controller: options, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الخيارات (2–5)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إنشاء'))],
    ));
    if (ok != true) return;
    final mcq = int.tryParse(mcqCount.text) ?? 0, tf = int.tryParse(tfCount.text) ?? 0, n = mcq + tf, o = int.tryParse(options.text) ?? 0;
    if (title.text.trim().isEmpty || n < 1 || n > 40 || mcq < 0 || tf < 0 || o < 2 || o > 5) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تحقق من الاسم وعدد الأسئلة (حتى 40 في الورقة الواحدة) والخيارات.')));
      return;
    }
    setState(() => exams.insert(0, Exam(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), subject: subject.text.trim(), questionCount: n, optionCount: o, answerKey: List<int?>.filled(n, null), questionTypes: [...List<String>.filled(tf, 'tf'), ...List<String>.filled(mcq, 'mcq')], createdAt: DateTime.now(), schoolName: school.text.trim(), teacherName: teacher.text.trim())));
    await _persist();
  }
  Future<void> _deleteExam(Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الاختبار'),
        content: Text('هل تريد حذف اختبار «${exam.title}» ونماذجه ومفتاح إجابته؟\\n\\nسيتم الاحتفاظ بسجل النتائج السابقة ولن تُحذف درجات الطلاب.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف الاختبار'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => exams.removeWhere((item) => item.id == exam.id));
    await store.saveExams(exams);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الاختبار مع الاحتفاظ بالنتائج السابقة.')),
    );
  }

  void addResult(ExamResult result) async {
    setState(() => results.insert(0, result));
    await store.saveResults(results);
  }
  Future<void> openExam(Exam exam) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _ExamDetailScreen(exam: exam, onSave: (updated) async {
      final i = exams.indexWhere((e) => e.id == updated.id);
      if (i >= 0) exams[i] = updated;
      await store.saveExams(exams);
      if (mounted) setState(() {});
    })));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      ScanScreen(exams: exams, onResult: addResult),
      _resultsPage(),
      _settingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('القاضي الذكي'), actions: const [Padding(padding: EdgeInsetsDirectional.only(end: 16), child: Center(child: Text('OMR', style: TextStyle(fontWeight: FontWeight.bold))))]),
      body: loading ? const Center(child: CircularProgressIndicator()) : pages[tab],
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(onPressed: newExam, icon: const Icon(Icons.add), label: const Text('اختبار جديد')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.document_scanner_outlined), label: 'التصحيح'),
        NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'النتائج'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
      ]),
    );
  }
  Widget _dashboard() => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF142B4A), Color(0xFF176C78)]), borderRadius: BorderRadius.circular(22)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('أهلاً بك في القاضي الذكي', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
      SizedBox(height: 8), Text('أنشئ اختباراً، اطبع ورقة OMR، صوّر إجابات الطلاب، وراجع الدرجات.', style: TextStyle(color: Colors.white70, height: 1.6)),
    ])),
    const SizedBox(height: 18),
    Row(children: [_stat('الاختبارات', exams.length.toString(), Icons.assignment_outlined), const SizedBox(width: 10), _stat('أوراق مصححة', results.length.toString(), Icons.fact_check_outlined)]),
    const SizedBox(height: 22), const Text('اختباراتي', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
    if (exams.isEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: const Column(children: [Icon(Icons.note_add_outlined, size: 42, color: Color(0xFF12A89D)), SizedBox(height: 10), Text('لا توجد اختبارات بعد', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 5), Text('اضغط «اختبار جديد» للبدء.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))]))
    else ...exams.map((e) => Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
        title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(e.subject + ' • ' + e.questionCount.toString() + ' سؤال • ' + (e.hasAnswerKey ? 'مفتاح مكتمل' : 'مفتاح غير مكتمل')),
        trailing: PopupMenuButton<String>(
          tooltip: 'خيارات الاختبار',
          onSelected: (value) {
            if (value == 'open') openExam(e);
            if (value == 'delete') _deleteExam(e);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'open', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('فتح الاختبار'))),
            PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('حذف الاختبار'))),
          ],
        ),
        onTap: () => openExam(e),
      ),
    )),
  ]);
  Widget _stat(String label, String value, IconData icon) => Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF12A89D)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.black54))])));
  String _answerLabel(int? answer, String type) {
    if (answer == null) return 'فارغ';
    if (type == 'tf') return answer == 0 ? 'صح' : 'خطأ';
    return String.fromCharCode(65 + answer);
  }

  Future<void> _showResultDetails(ExamResult result) async {
    final hasKey = result.correctAnswers.length == result.responses.length;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تفاصيل التصحيح — ${result.studentName}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الاختبار: ${result.examTitle}'),
                Text('كود النموذج: ${result.variantCode.isEmpty ? 'BASE' : result.variantCode}'),
                Text('رقم الجلوس: ${result.seatNumber.isEmpty ? 'غير مقروء' : result.seatNumber}'),
                Text('الدرجة: ${result.correct}/${result.total}'),
                const Divider(),
                if (!hasKey)
                  const Text('هذه نتيجة قديمة؛ لم يكن التطبيق يحفظ مفتاح الإجابة المستخدم وقت التصحيح. لا يمكن عرض الإجابة الصحيحة لهذه النتيجة بأثر رجعي.', style: TextStyle(color: Colors.deepOrange))
                else
                  for (var i = 0; i < result.responses.length; i++)
                    Builder(builder: (context) {
                      final type = i < result.questionTypes.length ? result.questionTypes[i] : 'mcq';
                      final student = result.responses[i];
                      final key = result.correctAnswers[i];
                      final isCorrect = student != null && key != null && student == key;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: student == null ? Colors.orange.shade50 : (isCorrect ? Colors.green.shade50 : Colors.red.shade50),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(children: [
                            SizedBox(width: 34, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(child: Text('إجابة الطالب: ${_answerLabel(student, type)}')),
                            Expanded(child: Text('الصحيح: ${_answerLabel(key, type)}')),
                            Icon(student == null ? Icons.help_outline : (isCorrect ? Icons.check_circle : Icons.cancel), color: student == null ? Colors.orange : (isCorrect ? Colors.green : Colors.red), size: 20),
                          ]),
                        ),
                      );
                    }),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
      ),
    );
  }

  Widget _resultsPage() {
    if (results.isEmpty) return const Center(child: Text('لا توجد نتائج بعد. صحّح أول ورقة لتظهر النتائج هنا.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [const Expanded(child: Text('سجل النتائج', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))), IconButton(tooltip: 'تصدير PDF', onPressed: () async { final bytes = await reports.resultsPdf(results, 'All exams'); await Printing.sharePdf(bytes: bytes, filename: 'alqadi-results.pdf'); }, icon: const Icon(Icons.picture_as_pdf)), IconButton(tooltip: 'تصدير CSV لبرنامج Excel', onPressed: () async { final bytes = reports.resultsCsv(results); final dir = await getTemporaryDirectory(); final file = File('${dir.path}/alqadi-results.csv'); await file.writeAsBytes(bytes, flush: true); await Share.shareXFiles([XFile(file.path)], text: 'نتائج اختبارات القاضي الذكي'); }, icon: const Icon(Icons.table_view))]),
      ...results.map((r) => Card(child: ListTile(leading: CircleAvatar(child: Text(r.percentage.toStringAsFixed(0))), title: Text(r.studentName), subtitle: Text((r.seatNumber.isEmpty ? '' : 'رقم الجلوس: ' + r.seatNumber + ' • ') + r.examTitle + ' • ' + r.correct.toString() + '/' + r.total.toString() + ' • ' + r.scannedAt.toLocal().toString().substring(0, 16) + ' • النموذج: ' + (r.variantCode.isEmpty ? 'BASE' : r.variantCode)), trailing: Text(r.incorrect.toString() + ' خطأ'), onTap: () => _showResultDetails(r)))),
    ]);
  }
  Widget _settingsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const ListTile(leading: Icon(Icons.phone_android), title: Text('المعالجة على الجهاز'), subtitle: Text('التصوير والتحليل والحفظ المحلي لا تحتاج إلى حساب فوترة أو اتصال دائم بالإنترنت.')),
    Card(child: Column(children: [
      const ListTile(leading: Icon(Icons.backup_outlined), title: Text('نسخ احتياطي للبيانات'), subtitle: Text('احفظ الاختبارات ومفاتيحها والنماذج وسجل النتائج في ملف مستقل قبل تحديث التطبيق.')),
      ListTile(leading: const Icon(Icons.file_upload_outlined), title: const Text('تصدير نسخة احتياطية'), onTap: () async {
        try {
          final json = await store.exportBackup();
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/alqadi-backup-${DateTime.now().millisecondsSinceEpoch}.json');
          await file.writeAsString(json, flush: true);
          await Share.shareXFiles([XFile(file.path)], text: 'النسخة الاحتياطية لتطبيق القاضي الذكي');
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية: $e')));
        }
      }),
      ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('استعادة نسخة احتياطية'), onTap: () async {
        final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('استعادة البيانات'),
          content: const Text('ستستبدل هذه العملية الاختبارات والنتائج الحالية بمحتويات النسخة الاحتياطية. هل تريد المتابعة؟'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة'))],
        ));
        if (confirm != true) return;
        try {
          final count = await store.pickAndImportBackup();
          if (count == null) return;
          await _load();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت استعادة $count سجلّاً بنجاح.')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذرت استعادة النسخة: $e')));
        }
      }),
    ])),
    const ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('الخصوصية'), subtitle: Text('تُحفظ الاختبارات والنتائج على الجهاز. لا تُرفع صور الطلاب إلى خادم في هذا الإصدار.')),
    const ListTile(leading: Icon(Icons.info_outline), title: Text('نسخة تجريبية'), subtitle: Text('يجب مراجعة الإجابات المقروءة قبل اعتماد الدرجة، خصوصاً عند ظهور علامات غير واضحة.')),
  ]);
}

class _ExamDetailScreen extends StatefulWidget {
  const _ExamDetailScreen({required this.exam, required this.onSave});
  final Exam exam;
  final Future<void> Function(Exam) onSave;
  @override
  State<_ExamDetailScreen> createState() => _ExamDetailScreenState();
}
class _ExamDetailScreenState extends State<_ExamDetailScreen> {
  late List<int?> answers;
  late List<String> questionTypes;
  late List<ExamVariant> variants;
  final title = TextEditingController(), subject = TextEditingController();
  final school = TextEditingController(), teacher = TextEditingController();
  @override
  void initState() { super.initState(); answers = List<int?>.from(widget.exam.answerKey); questionTypes = List<String>.from(widget.exam.questionTypes); variants = List<ExamVariant>.from(widget.exam.variants);
    title.text = widget.exam.title; subject.text = widget.exam.subject; school.text = widget.exam.schoolName; teacher.text = widget.exam.teacherName; }

  Future<void> _editExamDetails() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('تعديل بيانات الاختبار'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الاختبار')),
        TextField(controller: subject, decoration: const InputDecoration(labelText: 'المادة')),
        TextField(controller: school, decoration: const InputDecoration(labelText: 'اسم المدرسة')),
        TextField(controller: teacher, decoration: const InputDecoration(labelText: 'اسم المعلم')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    if (ok == true) { await _save(allowIncomplete: true); if (mounted) setState(() {}); }
  }
  Future<void> _save({bool allowIncomplete = false}) async {
    if (!allowIncomplete && answers.any((v) => v == null)) return;
    // Keep every saved variant's own displayed key synchronized with the
    // teacher's source key. The question/option permutations remain unchanged.
    variants = variants.map((variant) => variant.withAnswerKey(answers)).toList();
    final updated = Exam(
      id: widget.exam.id, title: title.text.trim(), subject: subject.text.trim(),
      questionCount: widget.exam.questionCount, optionCount: widget.exam.optionCount,
      answerKey: List<int?>.from(answers), createdAt: widget.exam.createdAt,
      questionTypes: List<String>.from(questionTypes),
      schoolName: school.text.trim(), teacherName: teacher.text.trim(),
      variants: List<ExamVariant>.from(variants),
    );
    await widget.onSave(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ مفتاح الإجابة على الجهاز.')));
  }

  Future<void> _generateVariants() async {
    final countController = TextEditingController(text: '30');
    final count = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء نماذج متعددة'),
        content: TextField(
          controller: countController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد النماذج', helperText: 'من 1 إلى 100 نموذج مختلف'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(countController.text.trim());
              if (value == null || value < 1 || value > 100) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل عدداً صحيحاً من 1 إلى 100.')));
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    countController.dispose();
    if (count == null || !mounted) return;
    if (answers.length != widget.exam.questionCount || answers.any((answer) => answer == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكمل مفتاح الإجابة لجميع الفقرات أولاً، ثم أنشئ النماذج.')),
      );
      return;
    }
    try {
      final variants = ExamVariantFactory.generate(
        examId: widget.exam.id, questionTypes: questionTypes,
        optionCount: widget.exam.optionCount, answerKey: List<int?>.from(answers), count: count,
      );
      final updated = Exam(
        id: widget.exam.id, title: title.text.trim(), subject: subject.text.trim(),
        questionCount: widget.exam.questionCount, optionCount: widget.exam.optionCount,
        answerKey: List<int?>.from(answers), createdAt: widget.exam.createdAt,
        questionTypes: List<String>.from(questionTypes),
        schoolName: school.text.trim(), teacherName: teacher.text.trim(),
        variants: variants,
        );
      await widget.onSave(updated);
      this.variants = List<ExamVariant>.from(variants);
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء ${variants.length} نموذجاً وحفظ أكوادها.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء النماذج: $error')),
      );
    }
  }

  Future<void> _showVariantKeys() async {
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنشئ النماذج أولاً لعرض مفاتيحها.')),
      );
      return;
    }
    final report = variants.map((variant) {
      final key = variant.getAnswerKey(answers);
      final rows = <String>[];
      for (var displayedQ = 0; displayedQ < key.length; displayedQ++) {
        final originalQ = variant.questionOrder[displayedQ];
        final answer = key[displayedQ];
        final label = answer == null
            ? '—'
            : questionTypes[originalQ] == 'tf'
                ? (answer == 0 ? 'صح' : 'خطأ')
                : String.fromCharCode(65 + answer);
        rows.add('${displayedQ + 1}: $label');
      }
      return '${variant.code}\n${rows.join('   ')}';
    }).join('\n\n');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مفاتيح الإجابة لكل نموذج'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(report, textDirection: TextDirection.rtl),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _printNamedVariant() async {
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنشئ النماذج أولاً قبل توزيعها على الطلاب.')));
      return;
    }
    final namesController = TextEditingController();
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('أسماء الطلاب وتوزيع النماذج'),
      content: SizedBox(width: 420, child: TextField(
        controller: namesController, minLines: 5, maxLines: 10,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          labelText: 'أسماء الطلاب',
          hintText: 'اسم الطالب الأول\nاسم الطالب الثاني\nاسم الطالب الثالث',
          helperText: 'اسم ثلاثي واحد في كل سطر. يقبل القوائم المرقمة، ويُوزّع نموذجاً مختلفاً لكل طالب.',
          border: OutlineInputBorder(),
        ),
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () {
          final names = StudentNameParser.parse(namesController.text);
          if (names.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل أسماء الطلاب أولاً.')));
            return;
          }
          if (names.any((name) => !StudentNameParser.isAtLeastThreeParts(name))) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب كتابة الاسم الثلاثي لكل طالب، اسم واحد في كل سطر.')));
            return;
          }
          if (names.length > variants.length) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('عدد الطلاب ${names.length} أكبر من عدد النماذج ${variants.length}. أنشئ نماذج أكثر حتى يحصل كل طالب على نموذج مختلف.')));
            return;
          }
          Navigator.pop(context, true);
        }, child: const Text('إنشاء أوراق الطلاب')),
      ],
    ));
    if (accepted != true || !mounted) { namesController.dispose(); return; }
    final names = StudentNameParser.parse(namesController.text);
    namesController.dispose();
    try {
      if (answers.length != widget.exam.questionCount || answers.any((answer) => answer == null)) {
        throw StateError('حدد الإجابة الصحيحة لجميع الأسئلة قبل توزيع الاختبار.');
      }
      // Persist the latest key and question layout before exporting student sheets.
      // Otherwise the printed sheets could use unsaved answers while later scanning
      // reloads an older answer key from local storage.
      await _save();
      if (!mounted) return;
      final currentExam = Exam(
        id: widget.exam.id,
        title: title.text.trim(),
        subject: subject.text.trim(),
        questionCount: widget.exam.questionCount,
        optionCount: widget.exam.optionCount,
        answerKey: List<int?>.from(answers),
        createdAt: widget.exam.createdAt,
        questionTypes: List<String>.from(questionTypes),
        schoolName: school.text.trim(),
        teacherName: teacher.text.trim(),
        variants: List<ExamVariant>.from(variants),
      );
      final assignments = <AnswerSheetAssignment>[
        for (var i = 0; i < names.length; i++)
          AnswerSheetAssignment(
            variant: variants[i],
            studentName: names[i],
          ),
      ];
      await widget.onSave(currentExam);
      final bytes = await OmrSheetService.buildBatchPdf(currentExam, assignments: assignments);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('أوراق الإجابة بأسماء الطلاب')),
          body: PdfPreview(
            build: (_) async => bytes,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: 'أوراق_إجابات_الطلاب.pdf',
          ),
        ),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تجهيز أوراق الطلاب: $error')));
    }
  }

  Future<Uint8List> _createSheetPdf() async {
    final currentExam = Exam(
      id: widget.exam.id,
      title: title.text.trim(),
      subject: subject.text.trim(),
      questionCount: widget.exam.questionCount,
      optionCount: widget.exam.optionCount,
      answerKey: List<int?>.from(answers),
      createdAt: widget.exam.createdAt,
      questionTypes: List<String>.from(questionTypes),
      schoolName: school.text.trim(),
      teacherName: teacher.text.trim(),
      // PDF actions must not silently strip the variants already saved on the exam.
      variants: variants,
    );
    await widget.onSave(currentExam);
    return OmrSheetService.buildPdf(currentExam);
  }

  Future<void> _showPdfPreview() async {
    try {
      final bytes = await _createSheetPdf();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('معاينة ورقة الإجابة')),
          body: PdfPreview(
            build: (_) async => bytes,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: 'OMR-${title.text.trim()}.pdf',
          ),
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت معاينة ورقة الإجابة: $error')),
      );
    }
  }

  Future<void> _exportSheetPdf() async {
    try {
      final bytes = await _createSheetPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'OMR-${title.text.trim()}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تصدير ملف PDF: $error')),
      );
    }
  }

  Future<void> _printSheet() async {
    try {
      final bytes = await _createSheetPdf();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'OMR-${title.text.trim()}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت طباعة ورقة الإجابة: $error')),
      );
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title.text), actions: [IconButton(tooltip: 'تعديل بيانات الاختبار', onPressed: _editExamDetails, icon: const Icon(Icons.edit_note)), IconButton(tooltip: 'تصدير PDF', onPressed: _exportSheetPdf, icon: const Icon(Icons.picture_as_pdf)), IconButton(tooltip: 'معاينة ورقة الإجابة', onPressed: _showPdfPreview, icon: const Icon(Icons.preview)), IconButton(tooltip: 'طباعة ورقة الإجابة', onPressed: _printSheet, icon: const Icon(Icons.print))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(subject.text + ' • ' + widget.exam.questionCount.toString() + ' سؤال • اختيار: ' + questionTypes.where((t) => t == 'mcq').length.toString() + ' • صح/خطأ: ' + questionTypes.where((t) => t == 'tf').length.toString()),
        const SizedBox(height: 6), const Text('هذا التطبيق يصمم أوراق الإجابة فقط: حدّد نوع كل فقرة ومفتاحها، ثم أنشئ النماذج ووزّع ورقة باسم كل طالب.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          OutlinedButton.icon(onPressed: _showPdfPreview, icon: const Icon(Icons.preview), label: const Text('معاينة PDF')),
          OutlinedButton.icon(onPressed: _exportSheetPdf, icon: const Icon(Icons.download), label: const Text('تصدير PDF')),
          OutlinedButton.icon(onPressed: _printSheet, icon: const Icon(Icons.print), label: const Text('طباعة الورقة')),
          OutlinedButton.icon(onPressed: _generateVariants, icon: const Icon(Icons.copy_all), label: const Text('إنشاء نماذج متعددة')),
          OutlinedButton.icon(onPressed: _showVariantKeys, icon: const Icon(Icons.key), label: const Text('مفاتيح النماذج')),
          OutlinedButton.icon(onPressed: _printNamedVariant, icon: const Icon(Icons.person_add_alt_1), label: const Text('ورقة طالب باسمه')),
        ]),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('النماذج المحفوظة: ${variants.length} — ${variants.map((v) => v.code).take(6).join('، ')}${variants.length > 6 ? ' ...' : ''}',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.teal, fontSize: 12)),
        ],
      ])),
      Expanded(
        child: ListView.builder(
          itemCount: answers.length,
          itemBuilder: (context, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 15,
                      child: Text((i + 1).toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    const Text('نوع السؤال', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: questionTypes[i],
                        items: const [
                          DropdownMenuItem(value: 'mcq', child: Text('اختيار من متعدد')),
                          DropdownMenuItem(value: 'tf', child: Text('صح أو خطأ')),
                        ],
                        onChanged: (v) => setState(() {
                          questionTypes[i] = v!;
                                            variants.clear();
                          if (answers[i] != null && answers[i]! >= (v == 'tf' ? 2 : widget.exam.optionCount)) {
                            answers[i] = null;
                          }
                        }),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: List.generate(
                      questionTypes[i] == 'tf' ? 2 : widget.exam.optionCount,
                      (j) => ChoiceChip(
                        label: Text(
                          questionTypes[i] == 'tf'
                              ? (j == 0 ? 'صح' : 'خطأ')
                              : String.fromCharCode(65 + j),
                        ),
                        selected: answers[i] == j,
                        onSelected: (_) => setState(() => answers[i] = j),
                        avatar: answers[i] == j ? const Icon(Icons.check, size: 16) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: answers.every((v) => v != null) ? _save : null,
              child: const Text('حفظ مفتاح الإجابة'),
            ),
          ),
        ),
      ),
    ]),
  );
}
