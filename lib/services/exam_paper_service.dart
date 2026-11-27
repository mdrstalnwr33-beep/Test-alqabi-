import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';

class ExamPaperService {
  static Future<Uint8List> buildPdf(
    Exam exam, {
    ExamVariant? variant,
    String studentName = '',
  }) async {
    if (exam.questions.length != exam.questionCount ||
        exam.questions.any((q) => q.text.trim().isEmpty)) {
      throw StateError('أكمل نص جميع الأسئلة قبل إنشاء نسخة الاختبار.');
    }
    for (var i = 0; i < exam.questionCount; i++) {
      if (exam.questions[i].options.length != exam.optionsFor(i) ||
          exam.questions[i].options.any((v) => v.trim().isEmpty)) {
        throw StateError('أكمل جميع خيارات السؤال ${i + 1} قبل إنشاء نسخة الاختبار.');
      }
    }
    if (variant != null &&
        (variant.questionOrder.length != exam.questionCount ||
         variant.optionOrder.length != exam.questionCount)) {
      throw ArgumentError('ترتيب النموذج غير متوافق مع محتوى الاختبار.');
    }

    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final doc = pw.Document();
    final questionOrder = variant?.questionOrder ??
        List<int>.generate(exam.questionCount, (i) => i);
    final content = <pw.Widget>[];
    for (var displayed = 0; displayed < questionOrder.length; displayed++) {
      final original = questionOrder[displayed];
      final question = exam.questions[original];
      final optionOrder = variant?.optionOrder[original] ??
          List<int>.generate(question.options.length, (i) => i);
      final isTf = exam.questionTypes[original] == 'tf';
      content.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(
              ArabicReshaper.instance.reshape('${displayed + 1}- ${question.text}'),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: font, fontSize: 13),
            ),
          ),
          pw.SizedBox(height: 7),
          ...List.generate(optionOrder.length, (shownOption) {
            final originalOption = optionOrder[shownOption];
            final label = isTf
                ? (originalOption == 0 ? 'صح' : 'خطأ')
                : String.fromCharCode(65 + shownOption);
            final text = isTf ? label : '$label- ${question.options[originalOption]}';
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Text(
                  ArabicReshaper.instance.reshape(text),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
            );
          }),
        ]),
      ));
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 36, 38, 42),
      theme: pw.ThemeData.withFont(base: font),
      header: (_) => pw.Column(children: [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text(
            ArabicReshaper.instance.reshape(exam.schoolName.isEmpty ? 'اختبار' : exam.schoolName),
            style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text(
            ArabicReshaper.instance.reshape('${exam.title} — ${exam.subject}'),
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('CODE: ${variant?.code ?? 'BASE'}',
            style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(
              ArabicReshaper.instance.reshape('اسم الطالب: ${studentName.isEmpty ? '________________' : studentName}'),
              style: pw.TextStyle(
                font: font,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF8B0000),
              ),
            ),
          ),
        ]),
        pw.Divider(color: PdfColors.grey600),
      ]),
      build: (_) => content,
    ));
    return doc.save();
  }
}
