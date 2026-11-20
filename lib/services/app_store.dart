import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam.dart';
class AppStore {
  static const _examsKey = 'alqadi_exams_v1';
  static const _resultsKey = 'alqadi_results_v1';
  Future<List<Exam>> loadExams() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_examsKey);
    if (raw == null || raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).map((e) => Exam.fromJson(Map<String, dynamic>.from(e as Map))).toList(); } catch (_) { return []; }
  }
  Future<void> saveExams(List<Exam> exams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_examsKey, jsonEncode(exams.map((e) => e.toJson()).toList()));
  }
  Future<List<ExamResult>> loadResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_resultsKey);
    if (raw == null || raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).map((e) => ExamResult.fromJson(Map<String, dynamic>.from(e as Map))).toList(); } catch (_) { return []; }
  }
  Future<void> saveResults(List<ExamResult> results) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resultsKey, jsonEncode(results.map((e) => e.toJson()).toList()));
  }
}
