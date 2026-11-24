import 'dart:convert';
import 'dart:typed_data';
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
  List<int> resultsCsv(List<ExamResult> results) {
    final rows = <String>['Student,SeatNumber,Exam,Total,Correct,Incorrect,Unanswered,Ambiguous,Percentage'];
    for (final r in results) {
      String cell(String value) => '"' + value.replaceAll('"', '""') + '"';
      rows.add([cell(r.studentName), cell(r.seatNumber), cell(r.examTitle), r.total, r.correct, r.incorrect, r.unanswered, r.ambiguous, r.percentage.toStringAsFixed(1)].join(','));
    }
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(rows.join(String.fromCharCodes([13, 10])))];
  }
}
