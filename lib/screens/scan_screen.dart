import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}
class _ScanScreenState extends State<ScanScreen> {
  final picker = ImagePicker();
  XFile? image;
  bool busy = false;
  Future<void> choose(ImageSource source) async {
    setState(() => busy = true);
    try {
      final result = await picker.pickImage(source: source, imageQuality: 95);
      if (result != null && mounted) setState(() => image = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح الصورة: ' + e.toString())));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('تصوير ورقة الإجابة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('التقط صورة واضحة لورقة OMR أو اختر صورة محفوظة. احرص على ظهور الورقة كاملة وإضاءة جيدة.', style: TextStyle(color: Colors.black54, height: 1.6)),
    const SizedBox(height: 18),
    Container(height: 300, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDCE3EA))),
      child: image == null ? const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.document_scanner_outlined, size: 68, color: Color(0xFF12A89D)), SizedBox(height: 12), Text('لم يتم اختيار ورقة بعد')]) : ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(File(image!.path), fit: BoxFit.contain, width: double.infinity, height: 300))),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: busy ? null : () => choose(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('التقاط صورة بالكاميرا')),
    const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: busy ? null : () => choose(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('اختيار صورة من الجهاز')),
    if (busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
    if (image != null) const Padding(padding: EdgeInsets.only(top: 12), child: Text('تم استيراد الصورة. تحليل علامات OMR واحتساب الدرجات لم يُفعّلا بعد؛ لن تظهر درجة تلقائية في هذه المرحلة.', style: TextStyle(color: Colors.deepOrange, height: 1.5))),
  ]);
}
