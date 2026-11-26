import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';
class ReportService {
  Future<Uint8List> resultsPdf(List<ExamResult> results, String title) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (_) => [
      pw.Text('AL QADI SMART - RESULTS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8), pw.Text(title, style: const pw.TextStyle(fontSize: 12)), pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(headers: ['Student', 'Seat No.', 'Score', 'Correct', 'Wrong', 'Blank', '%'], data: results.map((r) => [r.studentName, r.seatNumber, '${r.correct}/${r.total}', r.correct.toString(), r.incorrect.toString(), r.unanswered.toString(), r.percentage.toStringAsFixed(1)]).toList(), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), cellStyle: const pw.TextStyle(fontSize: 8)),
    ]));
    return doc.save();
  }

  Future<Uint8List> studentResultCardPdf(ExamResult result, {Uint8List? paperImage}) async {
    final doc = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final arabicFont = pw.Font.ttf(fontData);
    final paper = paperImage == null ? null : pw.MemoryImage(paperImage);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFont),
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Container(
          padding: const pw.EdgeInsets.all(22),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.teal700, width: 2),
            borderRadius: pw.BorderRadius.circular(14),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(child: pw.Text('بطاقة نتيجة الطالب', style: pw.TextStyle(font: arabicFont, fontSize: 25, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900))),
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text(result.examTitle, style: pw.TextStyle(font: arabicFont, fontSize: 17))),
              pw.Divider(color: PdfColors.teal700),
              pw.SizedBox(height: 12),
              pw.Text('اسم الطالب: ${result.studentName}', style: pw.TextStyle(font: arabicFont, fontSize: 19)),
              pw.SizedBox(height: 7),
              pw.Text('رقم الجلوس: ${result.seatNumber.isEmpty ? 'غير مسجل' : result.seatNumber}', style: pw.TextStyle(font: arabicFont, fontSize: 15)),
              pw.SizedBox(height: 7),
              pw.Text('النموذج: ${result.variantCode.isEmpty ? 'BASE' : result.variantCode}', style: pw.TextStyle(font: arabicFont, fontSize: 14)),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 15),
                decoration: pw.BoxDecoration(color: PdfColors.teal50, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(children: [
                  pw.Text(result.isAbsent ? 'الحالة' : 'الدرجة', style: pw.TextStyle(font: arabicFont, fontSize: 16)),
                  pw.Text(result.isAbsent ? 'غائب' : '${result.correct} / ${result.total}', style: pw.TextStyle(font: arabicFont, fontSize: 32, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                  if (!result.isAbsent) pw.Text('${result.percentage.toStringAsFixed(1)}٪', style: pw.TextStyle(font: arabicFont, fontSize: 19)),
                ]),
              ),
              pw.SizedBox(height: 14),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                pw.Text('صحيح: ${result.correct}', style: pw.TextStyle(font: arabicFont, fontSize: 13)),
                pw.Text('خطأ: ${result.incorrect}', style: pw.TextStyle(font: arabicFont, fontSize: 13)),
                pw.Text('فارغ: ${result.unanswered}', style: pw.TextStyle(font: arabicFont, fontSize: 13)),
              ]),
              if (paper != null) ...[
                pw.SizedBox(height: 18),
                pw.Text('صورة ورقة الإجابة المصححة', style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Expanded(child: pw.Center(child: pw.Image(paper, fit: pw.BoxFit.contain))),
              ],
              pw.Spacer(),
              pw.Divider(),
              pw.Center(child: pw.Text('القاضي الذكي لتصحيح الاختبارات', style: pw.TextStyle(font: arabicFont, fontSize: 12, color: PdfColors.grey700))),
            ],
          ),
        ),
      ),
    ));
    return doc.save();
  }

  List<int> resultsCsv(List<ExamResult> results) {
    final rows = <String>['Student,SeatNumber,Exam,Total,Correct,Incorrect,Unanswered,Ambiguous,Percentage'];
    for (final r in results) {
      String cell(String value) => '"' + value.replaceAll('"', '""') + '"';
      rows.add([cell(r.studentName), cell(r.seatNumber), cell(r.examTitle), r.total, r.correct, r.incorrect, r.unanswered, r.ambiguous, r.percentage.toStringAsFixed(1)].join(','));
    }
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(rows.join(String.fromCharCodes([13, 10])))];
  }
}
