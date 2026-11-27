import 'dart:typed_data';
import 'dart:convert';
import '../assets/alqadi_logo_data.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';

class BubblePosition {
  const BubblePosition(this.x, this.y);
  final double x, y;
}

class AnswerSheetAssignment {
  const AnswerSheetAssignment({required this.variant, required this.studentName, this.seatNumber = ''});
  final ExamVariant? variant;
  final String studentName;
  final String seatNumber;
}

class OmrSheetService {
  static const pageWidth = 595.0, pageHeight = 842.0;
  static const _top = 250.0, _bottom = 790.0;
  static const _leftX = 34.0, _rightX = 305.0;
  static const _radius = 8.5;

  static int _trueFalseCount(Exam exam) =>
      exam.questionTypes.take(exam.questionCount).where((type) => type == 'tf').length;

  static int _sectionIndex(Exam exam, int question) {
    final isTf = exam.questionTypes[question] == 'tf';
    var index = 0;
    for (var i = 0; i < question; i++) {
      if ((exam.questionTypes[i] == 'tf') == isTf) index++;
    }
    return index;
  }

  static int visualQuestionNumber(Exam exam, int question) {
    final index = _sectionIndex(exam, question);
    return exam.questionTypes[question] == 'tf'
        ? index + 1
        : _trueFalseCount(exam) + index + 1;
  }

  static BubblePosition positionFor(Exam exam, int question, int option) {
    final tfCount = _trueFalseCount(exam);
    final mcqCount = exam.questionCount - tfCount;
    final rows = tfCount > mcqCount ? tfCount : mcqCount;
    final isTf = exam.questionTypes[question] == 'tf';
    final row = _sectionIndex(exam, question);
    final baseX = isTf ? _rightX : _leftX;
    final count = exam.optionsFor(question);
    final gap = count == 2 ? 42.0 : (count == 3 ? 35.0 : 30.0);
    const start = 76.0;
    final pitch = rows <= 1 ? 0.0 : (_bottom - _top) / (rows - 1);
    return BubblePosition((baseX + start + option * gap) / pageWidth,
        (_top + row * pitch) / pageHeight);
  }

  static Future<Uint8List> buildPdf(Exam exam, {ExamVariant? variant, String studentName = '', String seatNumber = ''}) =>
      buildBatchPdf(exam, assignments: [
        AnswerSheetAssignment(variant: variant, studentName: studentName, seatNumber: seatNumber),
      ]);

  /// Builds one printable PDF containing one personalized page per student.
  static Future<Uint8List> buildBatchPdf(
    Exam exam, {
    required List<AnswerSheetAssignment> assignments,
  }) async {
    if (assignments.isEmpty) throw ArgumentError('أضف طالباً واحداً على الأقل.');
    final doc = pw.Document();
    late final pw.Font arabic;
    try {
      arabic = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    } catch (error) {
      throw StateError('تعذر تحميل خط اللغة العربية المضمن: $error');
    }
    final bold = arabic;
    // Normalize the embedded JPEG logo to PNG. The PDF image decoder can
    // reject some otherwise valid JPEG encodings; PNG avoids that failure.
    final logoImage = img.decodeImage(base64Decode(alqadiLogoJpegBase64));
    if (logoImage == null) {
      throw StateError('تعذر قراءة شعار الأستاذ محمد القاضي.');
    }
    final logoPngBytes = Uint8List.fromList(img.encodePng(logoImage));
    final assignedCodes = assignments
        .map((assignment) => assignment.variant?.code)
        .whereType<String>()
        .toList();
    if (assignedCodes.toSet().length != assignedCodes.length) {
      throw ArgumentError('لا يمكن توزيع النموذج نفسه على أكثر من طالب في الدفعة الواحدة.');
    }
    for (final assignment in assignments) {
      final variant = assignment.variant;
      final studentName = assignment.studentName;
      final seatNumber = assignment.seatNumber;
      final layoutExam = variant == null ? exam : Exam(
        id: exam.id, title: exam.title, subject: exam.subject,
        questionCount: exam.questionCount, optionCount: exam.optionCount,
        answerKey: exam.answerKey,
        questionTypes: variant.questionOrder.map((i) => exam.questionTypes[i]).toList(),
        schoolName: exam.schoolName, teacherName: exam.teacherName,
      );
      if (variant != null) {
        if (!exam.variants.any((saved) => saved.code == variant.code)) {
          throw ArgumentError('كود النموذج غير محفوظ ضمن هذا الاختبار: ${variant.code}');
        }
        if (studentName.trim().isEmpty) {
          throw ArgumentError('اسم الطالب مطلوب لكل ورقة نموذج مخصصة.');
        }
        if (variant.questionOrder.length != exam.questionCount ||
            variant.optionOrder.length != exam.questionCount ||
            variant.questionOrder.toSet().length != exam.questionCount ||
            variant.questionOrder.any((q) => q < 0 || q >= exam.questionCount)) {
          throw ArgumentError('ترتيب أسئلة النموذج غير متوافق مع الاختبار.');
        }
        for (var q = 0; q < exam.questionCount; q++) {
          final expected = exam.optionsFor(q);
          final order = variant.optionOrder[q];
          if (order.length != expected ||
              order.toSet().length != expected ||
              order.any((option) => option < 0 || option >= expected)) {
            throw ArgumentError('ترتيب خيارات النموذج رقم ${q + 1} غير صالح.');
          }
        }
      }
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
        _rtl('الصف: ${exam.grade.trim().isEmpty ? '____________________' : exam.grade.trim()}', arabic, 10),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFEAF2FF),
            border: pw.Border.all(color: PdfColor.fromInt(0xFF3975C6), width: 0.8),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: _rtl(
            'اسم الطالب: ${studentName.isEmpty ? '________________________________' : studentName}',
            bold, 15, color: PdfColor.fromInt(0xFF1557B0),
          ),
        ),
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
        _rtl('٢- استخدم قلماً أسود جافاً واملأ الدائرة بالكامل.', arabic, 9),
        pw.SizedBox(height: 4),
        _rtl('٣- لا تضع علامة صح؛ ظلّل الدائرة بالكامل.', arabic, 9),
        pw.SizedBox(height: 4),
        _rtl('٤- اكتب اسمك بخط واضح في المكان المخصص.', arabic, 9),
        pw.SizedBox(height: 4),
        _rtl('٥- لا تثنِ الورقة أو تكتب داخل دوائر الإجابة.', arabic, 9),
      ]),
    );
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [
      pw.Positioned(left: 210, right: 210, top: 4, child: pw.Center(child: pw.Image(
        pw.MemoryImage(logoPngBytes),
        width: 175, height: 68, fit: pw.BoxFit.contain,
      ))),
      pw.Positioned(left: 28, top: 76, child: pw.SizedBox(width: 264, child: instructions)),
      pw.Positioned(left: 303, top: 76, child: pw.SizedBox(width: 264, child: header)),
      // Section legend is kept in the clear band above the answer grid.
      pw.Positioned(left: 40, top: 214, child: _sectionLegend(
        'حل فقرات الاختيار من متعدد', false, arabic)),
      pw.Positioned(left: 315, top: 214, child: _sectionLegend(
        'حل فقرات الصح والخطأ', true, arabic)),
      // Fixed calibration markers: same four page-corner positions as the printed reference form.
      _marker(15, 17), _marker(566, 17), _marker(566, 796), _marker(15, 796),
      ..._questionWidgets(layoutExam, arabic, variant: variant),
      if (exam.teacherName.trim().isNotEmpty)
        pw.Positioned(
          left: 90, right: 90, top: 801,
          child: pw.Center(
            child: pw.Text(
              ArabicReshaper.instance.reshape('الأستاذ/ ${exam.teacherName.trim()}'),
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: bold,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF243B53),
              ),
            ),
          ),
        ),
      pw.Positioned(left: 28, top: 816, child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 1)),
        child: pw.Text('CODE: ${variant?.code ?? 'BASE'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      )),
    ])));
    }
    return doc.save();
  }

  static String _arabicDigits(String value) => value.replaceAllMapped(
    RegExp(r'[0-9]'),
    (match) => '٠١٢٣٤٥٦٧٨٩'[int.parse(match.group(0)!)],
  );

  static pw.Widget _rtl(String text, pw.Font font, double size, {PdfColor? color}) => pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Text(ArabicReshaper.instance.reshape(text), textAlign: pw.TextAlign.right,
      style: pw.TextStyle(font: font, fontSize: size, color: color)),
  );

  static pw.Widget _sectionLegend(String title, bool isTf, pw.Font font) =>
      pw.Container(
        width: 235, height: 24,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5),
        decoration: pw.BoxDecoration(
          color: isTf ? PdfColor.fromInt(0xFFE5F4EF) : PdfColor.fromInt(0xFFE8EFFB),
          border: pw.Border.all(
            color: isTf ? PdfColor.fromInt(0xFF4C9B83) : PdfColor.fromInt(0xFF5879B8),
            width: 0.8,
          ),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: _rtl(title, font, 8),
      );

  static pw.Widget _marker(double x, double y) => pw.Positioned(left: x, top: y,
      child: pw.Container(width: 14, height: 14, color: PdfColors.black));

  static List<pw.Widget> _questionWidgets(Exam exam, pw.Font font, {ExamVariant? variant}) {
    final tfCount = _trueFalseCount(exam);
    final mcqCount = exam.questionCount - tfCount;
    final rows = tfCount > mcqCount ? tfCount : mcqCount;
    final pitch = rows <= 1 ? 0.0 : (_bottom - _top) / (rows - 1);
    final widgets = <pw.Widget>[];
    for (var q = 0; q < exam.questionCount; q++) {
      final isTf = exam.questionTypes[q] == 'tf';
      final row = _sectionIndex(exam, q);
      // In Arabic reading order, true/false is the first section on the right;
      // multiple-choice follows in the left column.
      final x = isTf ? _rightX : _leftX, y = _top + row * pitch;
      widgets.add(pw.Positioned(
        left: x + 34, top: y - 8,
        child: pw.Container(
          width: 28, height: 16,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 0),
          decoration: pw.BoxDecoration(
            color: isTf ? PdfColor.fromInt(0xFFE5F4EF) : PdfColor.fromInt(0xFFE8EFFB),
            border: pw.Border.all(
              color: isTf ? PdfColor.fromInt(0xFF4C9B83) : PdfColor.fromInt(0xFF5879B8),
              width: 0.65,
            ),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: _rtl(isTf ? 'صح/خطأ' : 'اختيار', font, 6.5),
        ),
      ));
      // Question numbers use Arabic-Indic digits and sit at the far right
      // of each question row, following Arabic reading direction.
      final number = _arabicDigits(visualQuestionNumber(exam, q).toString().padLeft(2, '0'));
      final count = exam.optionsFor(q);
      final gap = count == 2 ? 42.0 : (count == 3 ? 35.0 : 30.0);
      // Keep the question number close to the last answer bubble. This is
      // calculated per question type so TF (2 bubbles) does not leave a wide gap.
      final lastBubbleCenter = 76.0 + (count - 1) * gap;
      widgets.add(pw.Positioned(left: x + lastBubbleCenter + 17, top: y - 7,
        child: pw.SizedBox(width: 24, child: pw.Text(number,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)))));
      for (var option = 0; option < count; option++) {
        final cx = x + 76 + option * gap;
        widgets.add(pw.Positioned(left: cx - _radius, top: y - _radius,
          child: pw.Container(width: _radius * 2, height: _radius * 2,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle,
              border: pw.Border.all(color: PdfColors.black, width: 1.25)))));
        final originalQuestion = variant == null ? q : variant.questionOrder[q];
        final displayedToOriginal = variant == null
            ? List<int>.generate(count, (i) => i)
            : variant.optionOrder[originalQuestion];
        final label = exam.questionTypes[q] == 'tf'
            ? (displayedToOriginal[option] == 0 ? 'ص' : 'خ')
            : String.fromCharCode(65 + option);
        widgets.add(pw.Positioned(left: cx - 4, top: y + 8,
          child: pw.Text(ArabicReshaper.instance.reshape(label), style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold))));
      }
    }
    return widgets;
  }
}
