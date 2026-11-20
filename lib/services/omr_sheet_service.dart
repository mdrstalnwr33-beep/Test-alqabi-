import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';

class BubblePosition {
  const BubblePosition(this.x, this.y);
  final double x, y;
}

class OmrSheetService {
  static const pageWidth = 595.0, pageHeight = 842.0;
  static const _top = 225.0, _bottom = 790.0;
  static const _leftX = 34.0, _rightX = 305.0;
  static const _radius = 7.0;

  static BubblePosition positionFor(Exam exam, int question, int option) {
    final rows = (exam.questionCount + 1) ~/ 2;
    final right = question >= rows;
    final row = right ? question - rows : question;
    final baseX = right ? _rightX : _leftX;
    final count = exam.optionsFor(question);
    final gap = count == 2 ? 42.0 : (count == 3 ? 35.0 : 30.0);
    final start = 76.0;
    return BubblePosition((baseX + start + option * gap) / pageWidth,
        (_top + row * (rows <= 1 ? 0 : (_bottom - _top) / (rows - 1))) / pageHeight);
  }

  static Future<Uint8List> buildPdf(Exam exam) async {
    final doc = pw.Document();
    late final pw.Font arabic;
    try {
      arabic = pw.Font.ttf(await rootBundle.load('packages/google_fonts/fonts/NotoSansArabic-Regular.ttf'));
    } catch (_) {
      arabic = pw.Font.helvetica();
    }
    final bold = arabic;
    final header = <pw.Widget>[
      _rtl(exam.schoolName.isEmpty ? 'اسم المدرسة: __________________________' : 'المدرسة: ${exam.schoolName}', arabic, 12),
      _rtl('اختبار: ${exam.title}', arabic, 12),
      _rtl('المادة: ${exam.subject}    الفصل الدراسي: ${exam.termName.isEmpty ? '____________' : exam.termName}', arabic, 10),
      _rtl('المعلم: ${exam.teacherName.isEmpty ? '________________' : exam.teacherName}', arabic, 10),
      _rtl('اسم الطالب: __________________________________    رقم الطالب: ______________', arabic, 10),
      _rtl('ظلّل دائرة واحدة لكل سؤال بقلم داكن، وحافظ على استواء الورقة عند التصوير.', arabic, 8),
    ];
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [
      pw.Positioned(left: 28, top: 20, child: pw.Text('القاضي الذكي لتصحيح الاختبارات', style: pw.TextStyle(font: bold, fontSize: 17, fontWeight: pw.FontWeight.bold))),
      pw.Positioned(left: 28, right: 28, top: 52, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: header)),
      _marker(22, 145), _marker(550, 145), _marker(22, 808), _marker(550, 808),
      ..._questionWidgets(exam, arabic),
      pw.Positioned(left: 28, top: 820, child: pw.Text('FORM ${exam.id.substring(exam.id.length > 6 ? exam.id.length - 6 : 0)}', style: const pw.TextStyle(fontSize: 7))),
    ])));
    return doc.save();
  }

  static pw.Widget _rtl(String text, pw.Font font, double size) => pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Text(text, textAlign: pw.TextAlign.right, style: pw.TextStyle(font: font, fontSize: size)),
  );

  static pw.Widget _marker(double x, double y) => pw.Positioned(left: x, top: y,
      child: pw.Container(width: 14, height: 14, color: PdfColors.black));

  static List<pw.Widget> _questionWidgets(Exam exam, pw.Font font) {
    final rows = (exam.questionCount + 1) ~/ 2;
    final pitch = rows <= 1 ? 0.0 : (_bottom - _top) / (rows - 1);
    final widgets = <pw.Widget>[];
    for (var q = 0; q < exam.questionCount; q++) {
      final right = q >= rows, row = right ? q - rows : q;
      final x = right ? _rightX : _leftX, y = _top + row * pitch;
      final number = (q + 1).toString().padLeft(2, '0');
      widgets.add(pw.Positioned(left: x, top: y - 7,
        child: pw.SizedBox(width: 31, child: pw.Text(number, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)))));
      final count = exam.optionsFor(q);
      final gap = count == 2 ? 42.0 : (count == 3 ? 35.0 : 30.0);
      for (var option = 0; option < count; option++) {
        final cx = x + 76 + option * gap;
        widgets.add(pw.Positioned(left: cx - _radius, top: y - _radius,
          child: pw.Container(width: _radius * 2, height: _radius * 2,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle,
              border: pw.Border.all(color: PdfColors.black, width: 1.25)))));
        final label = exam.questionTypes[q] == 'tf'
            ? (option == 0 ? 'ص' : 'خ')
            : String.fromCharCode(65 + option);
        widgets.add(pw.Positioned(left: cx - 4, top: y + 8,
          child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold))));
      }
    }
    return widgets;
  }
}
