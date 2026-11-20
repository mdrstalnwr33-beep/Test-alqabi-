import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';

class BubblePosition {
  const BubblePosition(this.x, this.y);
  final double x, y;
}

class OmrSheetService {
  static const pageWidth = 595.0, pageHeight = 842.0;
  static const _top = 250.0, _bottom = 790.0;
  static const _leftX = 34.0, _rightX = 305.0;
  static const _radius = 8.5;

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
      arabic = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    } catch (error) {
      throw StateError('تعذر تحميل خط اللغة العربية المضمن: $error');
    }
    final bold = arabic;
    // The existing exam header is placed on the right side of the sheet.
    final header = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _rtl('المدرسة: ${exam.schoolName.isEmpty ? '____________________' : exam.schoolName}', arabic, 12),
        pw.SizedBox(height: 5),
        _rtl('اسم الاختبار: ${exam.title}', arabic, 12),
        pw.SizedBox(height: 5),
        _rtl('المادة: ${exam.subject}', arabic, 10),
        pw.SizedBox(height: 4),
        _rtl('الفصل الدراسي: ${exam.termName.isEmpty ? '__________' : exam.termName}', arabic, 10),
        pw.SizedBox(height: 4),
        _rtl('المعلم: ${exam.teacherName.isEmpty ? '______________' : exam.teacherName}', arabic, 10),
        pw.SizedBox(height: 4),
        _rtl('اسم الطالب: ____________________', arabic, 10),
        pw.SizedBox(height: 4),
        _rtl('رقم الجلوس: __________', arabic, 10),
      ]),
    );
    // Student instructions are printed in a matching panel on the left.
    final instructions = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Center(child: _rtl('تعليمات مهمة للطلاب', bold, 12)),
        pw.Divider(color: PdfColors.grey500, thickness: 0.6),
        _rtl('١- ظلّل دائرة واحدة فقط لكل سؤال.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٢- املأ الدائرة بالكامل بقلم رصاص HB أو قلم داكن.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٣- لا تستخدم علامة صح أو تضع دائرة حول الحرف.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٤- امسح الإجابة الخاطئة جيداً قبل اختيار غيرها.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٥- يمنع استخدام الهاتف المحمول أو أي وسيلة اتصال.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٦- يسمح باستخدام الآلة الحاسبة إذا أذن المعلم.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٧- اكتب اسمك ورقم جلوسك بوضوح.', arabic, 9),
        pw.SizedBox(height: 3),
        _rtl('٨- لا تثنِ الورقة ولا تضع عليها علامات إضافية.', arabic, 9),
      ]),
    );
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [
      pw.Positioned(left: 28, right: 28, top: 18, child: pw.Center(child: _rtl('القاضي الذكي لتصحيح الاختبارات', arabic, 17))),
      pw.Positioned(left: 28, top: 48, width: 264, child: instructions),
      pw.Positioned(left: 303, top: 48, width: 264, child: header),
      _marker(22, 190), _marker(550, 190), _marker(22, 808), _marker(550, 808),
      ..._questionWidgets(exam, arabic),
      pw.Positioned(left: 28, top: 820, child: pw.Text('FORM ${exam.id.substring(exam.id.length > 6 ? exam.id.length - 6 : 0)}', style: const pw.TextStyle(fontSize: 7))),
    ])));
    return doc.save();
  }

  static pw.Widget _rtl(String text, pw.Font font, double size) => pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Text(ArabicReshaper.instance.reshape(text), textAlign: pw.TextAlign.right,
      style: pw.TextStyle(font: font, fontSize: size)),
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
          child: pw.Text(ArabicReshaper.instance.reshape(label), style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold))));
      }
    }
    return widgets;
  }
}
