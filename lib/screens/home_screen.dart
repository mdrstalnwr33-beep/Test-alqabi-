import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'dart:io';
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
    final count = TextEditingController(text: '20'), options = TextEditingController(text: '4');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إنشاء اختبار جديد'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الاختبار')),
        const SizedBox(height: 10), TextField(controller: subject, decoration: const InputDecoration(labelText: 'المادة')),
        const SizedBox(height: 10), TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الأسئلة (1–100)')),
        const SizedBox(height: 10), TextField(controller: options, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الخيارات (2–5)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إنشاء'))],
    ));
    if (ok != true) return;
    final n = int.tryParse(count.text) ?? 0, o = int.tryParse(options.text) ?? 0;
    if (title.text.trim().isEmpty || n < 1 || n > 100 || o < 2 || o > 5) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تحقق من الاسم وعدد الأسئلة والخيارات.')));
      return;
    }
    setState(() => exams.insert(0, Exam(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), subject: subject.text.trim(), questionCount: n, optionCount: o, answerKey: List<int?>.filled(n, null), createdAt: DateTime.now())));
    await _persist();
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
    else ...exams.map((e) => Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)), title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(e.subject + ' • ' + e.questionCount.toString() + ' سؤال • ' + (e.hasAnswerKey ? 'مفتاح مكتمل' : 'مفتاح غير مكتمل')), trailing: const Icon(Icons.chevron_left), onTap: () => openExam(e)))),
  ]);
  Widget _stat(String label, String value, IconData icon) => Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF12A89D)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.black54))])));
  Widget _resultsPage() {
    if (results.isEmpty) return const Center(child: Text('لا توجد نتائج بعد. صحّح أول ورقة لتظهر النتائج هنا.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [const Expanded(child: Text('سجل النتائج', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))), IconButton(tooltip: 'تصدير PDF', onPressed: () async { final bytes = await reports.resultsPdf(results, 'All exams'); await Printing.sharePdf(bytes: bytes, filename: 'alqadi-results.pdf'); }, icon: const Icon(Icons.picture_as_pdf)), IconButton(tooltip: 'تصدير CSV لبرنامج Excel', onPressed: () async { final bytes = reports.resultsCsv(results); final dir = await getTemporaryDirectory(); final file = File('${dir.path}/alqadi-results.csv'); await file.writeAsBytes(bytes, flush: true); await Share.shareXFiles([XFile(file.path)], text: 'نتائج اختبارات القاضي الذكي'); }, icon: const Icon(Icons.table_view))]),
      ...results.map((r) => Card(child: ListTile(leading: CircleAvatar(child: Text(r.percentage.toStringAsFixed(0))), title: Text(r.studentName), subtitle: Text(r.examTitle + ' • ' + r.correct.toString() + '/' + r.total.toString() + ' • ' + r.scannedAt.toLocal().toString().substring(0, 16)), trailing: Text(r.incorrect.toString() + ' خطأ')))),
    ]);
  }
  Widget _settingsPage() => ListView(padding: const EdgeInsets.all(18), children: const [
    ListTile(leading: Icon(Icons.phone_android), title: Text('المعالجة على الجهاز'), subtitle: Text('التصوير والتحليل والحفظ المحلي لا تحتاج إلى حساب فوترة أو اتصال دائم بالإنترنت.')),
    ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('الخصوصية'), subtitle: Text('تُحفظ الاختبارات والنتائج على الجهاز. لا تُرفع صور الطلاب إلى خادم في هذا الإصدار.')),
    ListTile(leading: Icon(Icons.info_outline), title: Text('نسخة تجريبية'), subtitle: Text('يجب مراجعة الإجابات المقروءة قبل اعتماد الدرجة، خصوصاً عند ظهور علامات غير واضحة.')),
  ]);
}

class _ExamDetailScreen extends StatefulWidget {
  const _ExamDetailScreen({required this.exam, required this.onSave});
  final Exam exam;
  final ValueChanged<Exam> onSave;
  @override
  State<_ExamDetailScreen> createState() => _ExamDetailScreenState();
}
class _ExamDetailScreenState extends State<_ExamDetailScreen> {
  late List<int?> answers;
  @override
  void initState() { super.initState(); answers = List<int?>.from(widget.exam.answerKey); }
  Future<void> _save() async {
    if (answers.any((v) => v == null)) return;
    final updated = Exam(id: widget.exam.id, title: widget.exam.title, subject: widget.exam.subject, questionCount: widget.exam.questionCount, optionCount: widget.exam.optionCount, answerKey: answers, createdAt: widget.exam.createdAt);
    widget.onSave(updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ مفتاح الإجابة على الجهاز.')));
  }
  Future<void> _printSheet() async {
    if (answers.any((v) => v == null)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل مفتاح الإجابة قبل طباعة الورقة.'))); return; }
    await _save();
    final bytes = await OmrSheetService.buildPdf(widget.exam);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'OMR-${widget.exam.title}.pdf');
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.exam.title), actions: [IconButton(tooltip: 'طباعة ورقة الإجابة', onPressed: _printSheet, icon: const Icon(Icons.print))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(widget.exam.subject + ' • ' + widget.exam.questionCount.toString() + ' سؤال • ' + widget.exam.optionCount.toString() + ' خيارات'),
        const SizedBox(height: 6), const Text('حدد الإجابة الصحيحة لكل سؤال، ثم احفظ المفتاح واطبع ورقة OMR.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 8), OutlinedButton.icon(onPressed: _printSheet, icon: const Icon(Icons.picture_as_pdf), label: const Text('معاينة وطباعة ورقة الإجابة')),
      ])),
      Expanded(child: ListView.builder(itemCount: answers.length, itemBuilder: (context, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(children: [
        SizedBox(width: 34, child: Text((i + 1).toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        ...List.generate(widget.exam.optionCount, (j) => Expanded(child: RadioListTile<int>(contentPadding: EdgeInsets.zero, dense: true, visualDensity: VisualDensity.compact, title: Text(String.fromCharCode(65 + j)), value: j, groupValue: answers[i], onChanged: (v) => setState(() => answers[i] = v)))),
      ])))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: answers.every((v) => v != null) ? _save : null, child: const Text('حفظ مفتاح الإجابة'))))),
    ]),
  );
}
