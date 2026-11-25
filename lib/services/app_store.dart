import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../models/exam.dart';

class AppStore {
  static const _examsKey = 'alqadi_exams_v1';
  static const _resultsKey = 'alqadi_results_v1';

  /// Reads each record independently. A damaged record no longer hides every
  /// other exam/result, and the original raw value is backed up before save.
  Future<List<T>> _load<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    final items = <T>[];
    var failed = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        failed = true;
      } else {
        for (final entry in decoded) {
          try {
            items.add(parse(Map<String, dynamic>.from(entry as Map)));
          } catch (_) {
            failed = true;
          }
        }
      }
    } catch (_) {
      failed = true;
    }

    if (failed) {
      await prefs.setString('${key}_corrupt_backup', raw);
    }
    return items;
  }

  Future<List<Exam>> loadExams() => _load(_examsKey, Exam.fromJson);

  Future<void> saveExams(List<Exam> exams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _examsKey,
      jsonEncode(exams.map((exam) => exam.toJson()).toList()),
    );
  }

  Future<List<ExamResult>> loadResults() => _load(_resultsKey, ExamResult.fromJson);

  Future<void> saveResults(List<ExamResult> results) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _resultsKey,
      jsonEncode(results.map((result) => result.toJson()).toList()),
    );
  }

  Future<String> exportBackup() async {
    final exams = await loadExams();
    final results = await loadResults();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'alqadi-smart-exam-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'exams': exams.map((e) => e.toJson()).toList(),
      'results': results.map((r) => r.toJson()).toList(),
    });
  }

  Future<int> importBackup(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map || decoded['format'] != 'alqadi-smart-exam-backup') {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح.');
    }
    final exams = (decoded['exams'] as List)
        .map((v) => Exam.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    final results = (decoded['results'] as List)
        .map((v) => ExamResult.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    await saveExams(exams);
    await saveResults(results);
    return exams.length + results.length;
  }

  Future<int?> pickAndImportBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], withData: false);
    final path = picked?.files.single.path;
    if (path == null) return null;
    return importBackup(path);
  }
}
