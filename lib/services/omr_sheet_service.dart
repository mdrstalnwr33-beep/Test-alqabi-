import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';
class BubblePosition {
  const BubblePosition(this.x, this.y);
  final double x, y;
}
class OmrSheetService {
  static const pageWidth = 595.0, pageHeight = 842.0;
  static const _leftX = 38.0, _rightX = 306.0, _top = 190.0, _bottom = 790.0;
  static const _optionStart = 82.0, _optionGap = 29.0, _radius = 4.8;
  static BubblePosition positionFor(Exam exam, int question, int option) {
    final rows = (exam.questionCount + 1) ~/ 2;
    final right = question >= rows;
    final row = right ? question - rows : question;
    final baseX = right ? _rightX : _leftX;
    final pitch = rows <= 1 ? 0.0 : (_bottom - _top) / (rows - 1);
    return BubblePosition((baseX + _optionStart + option * _optionGap) / pageWidth, (_top + row * pitch) / pageHeight);
  }
  static Future<Uint8List> buildPdf(Exam exam) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [
      pw.Positioned(left: 28, top: 24, child: pw.Text('AL QADI SMART OMR', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.Positioned(left: 28, top: 49, child: pw.Text('Exam: ' + exam.title + '    Subject: ' + exam.subject, style: const pw.TextStyle(fontSize: 9))),
      pw.Positioned(left: 28, top: 67, child: pw.Text('Student name: __________________________________________', style: const pw.TextStyle(fontSize: 10))),
      pw.Positioned(left: 28, top: 89, child: pw.Text('Student number: _________________________________________', style: const pw.TextStyle(fontSize: 10))),
      pw.Positioned(left: 28, top: 116, child: pw.Text('Fill ONE circle per question using a dark pen. Keep the page flat in the photo.', style: const pw.TextStyle(fontSize: 8))),
      _marker(22, 145), _marker(550, 145), _marker(22, 808), _marker(550, 808),
      ..._questionWidgets(exam),
      pw.Positioned(left: 28, top: 820, child: pw.Text('FORM ' + exam.id.substring(exam.id.length > 6 ? exam.id.length - 6 : 0), style: const pw.TextStyle(fontSize: 7))),
    ])));
    return doc.save();
  }
  static pw.Widget _marker(double x, double y) => pw.Positioned(left: x, top: y, child: pw.Container(width: 14, height: 14, color: PdfColors.black));
  static List<pw.Widget> _questionWidgets(Exam exam) {
    final rows = (exam.questionCount + 1) ~/ 2;
    final pitch = rows <= 1 ? 0.0 : (_bottom - _top) / (rows - 1);
    final widgets = <pw.Widget>[];
    for (var q = 0; q < exam.questionCount; q++) {
      final right = q >= rows, row = right ? q - rows : q, x = right ? _rightX : _leftX, y = _top + row * pitch;
      widgets.add(pw.Positioned(left: x, top: y - 5, child: pw.SizedBox(width: 29, child: pw.Text((q + 1).toString().padLeft(2, '0'), style: const pw.TextStyle(fontSize: 7)))));
      for (var option = 0; option < exam.optionCount; option++) {
        final cx = x + _optionStart + option * _optionGap;
        widgets.add(pw.Positioned(left: cx - _radius, top: y - _radius, child: pw.Container(width: _radius * 2, height: _radius * 2, decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: PdfColors.black, width: 0.8)))));
        widgets.add(pw.Positioned(left: cx - 2.2, top: y + 6, child: pw.Text(String.fromCharCode(65 + option), style: const pw.TextStyle(fontSize: 5))));
      }
    }
    return widgets;
  }
}
