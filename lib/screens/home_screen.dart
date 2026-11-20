import 'package:flutter/material.dart';
import '../models/exam.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final List<Exam> exams = [];
  int tab = 0;

  Future<void> newExam() async {
    final title = TextEditingController();
    final subject = TextEditingController();
    final count = TextEditingController(text: '20');
    final options = TextEditingController(text: '4');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إنشاء اختبار جديد'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الاختبار')),
        const SizedBox(height: 10),
        TextField(controller: subject, decoration: const InputDecoration(labelText: 'المادة')),
        const SizedBox(height: 10),
        TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الأسئلة')),
        const SizedBox(height: 10),
        TextField(controller: options, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الخيارات (2 إلى 5)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إنشاء')),
      ],
    ));
    if (ok != true) return;
    final n = int.tryParse(count.text) ?? 0;
    final o = int.tryParse(options.text) ?? 0;
    if (title.text.trim().isEmpty || n < 1 || n > 200 || o < 2 || o > 5) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تحقق من الاسم وعدد الأسئلة والخيارات')));
      return;
    }
    setState(() => exams.insert(0, Exam(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), subject: subject.text.trim(), questionCount: n, optionCount: o, answerKey: List<int?>.filled(n, null))));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashboard(), const ScanScreen(), _notice(Icons.analytics_outlined, 'النتائج', 'ستظهر نتائج الطلاب بعد اكتمال محرك التصحيح.'), _notice(Icons.settings_outlined, 'الإعدادات', 'إعدادات التطبيق ستضاف في الإصدارات القادمة.')];
    return Scaffold(
      appBar: AppBar(title: const Text('القاضي الذكي'), actions: const [Padding(padding: EdgeInsetsDirectional.only(end: 16), child: Center(child: Text('OMR', style: TextStyle(fontWeight: FontWeight.bold))))]),
      body: pages[tab],
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
      SizedBox(height: 8), Text('أنشئ اختبارك، جهّز مفتاح الإجابة، ثم صحّح أوراق الطلاب بالكاميرا.', style: TextStyle(color: Colors.white70, height: 1.6)),
    ])),
    const SizedBox(height: 20),
    Row(children: [
      _stat('الاختبارات', exams.length.toString(), Icons.assignment_outlined),
      const SizedBox(width: 10), _stat('نمط التصحيح', 'OMR', Icons.center_focus_strong),
    ]),
    const SizedBox(height: 22), const Text('اختباراتي', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    if (exams.isEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: const Column(children: [
      Icon(Icons.note_add_outlined, size: 42, color: Color(0xFF12A89D)), SizedBox(height: 10),
      Text('لا توجد اختبارات بعد', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 5), Text('اضغط «اختبار جديد» للبدء في إعداد أول اختبار.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
    ])) else ...exams.map((exam) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
      title: Text(exam.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(exam.subject + ' • ' + exam.questionCount.toString() + ' سؤال • ' + exam.optionCount.toString() + ' خيارات'),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnswerKeyScreen(exam: exam))),
    ))),
  ]);

  Widget _stat(String label, String value, IconData icon) => Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: const Color(0xFF12A89D)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.black54)),
  ])));
  Widget _notice(IconData icon, String title, String message) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 54, color: const Color(0xFF12A89D)), const SizedBox(height: 14), Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
  ])));
}

class AnswerKeyScreen extends StatefulWidget {
  const AnswerKeyScreen({super.key, required this.exam});
  final Exam exam;
  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}
class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  late List<int?> answers;
  @override
  void initState() { super.initState(); answers = List<int?>.from(widget.exam.answerKey); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.exam.title)),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(14), child: Text('مفتاح الإجابة • اختر الإجابة الصحيحة لكل سؤال', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Expanded(child: ListView.builder(itemCount: answers.length, itemBuilder: (context, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
        SizedBox(width: 38, child: Text((i + 1).toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        ...List.generate(widget.exam.optionCount, (j) => Expanded(child: RadioListTile<int>(contentPadding: EdgeInsets.zero, dense: true, visualDensity: VisualDensity.compact, title: Text(String.fromCharCode(65 + j)), value: j, groupValue: answers[i], onChanged: (v) => setState(() => answers[i] = v)))),
      ])))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton(
        onPressed: answers.every((v) => v != null) ? () { widget.exam.answerKey.setAll(0, answers); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظ المفتاح في الذاكرة الحالية فقط؛ الحفظ الدائم قيد التطوير.'))); Navigator.pop(context); } : null,
        child: const Text('حفظ مفتاح الإجابة'),
      )))),
    ]),
  );
}
