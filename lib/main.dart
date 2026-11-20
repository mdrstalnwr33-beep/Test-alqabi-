import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlQadiApp());
}

class AlQadiApp extends StatelessWidget {
  const AlQadiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'القاضي الذكي لتصحيح الاختبارات',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF12A89D), primary: const Color(0xFF142B4A)),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF142B4A), foregroundColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: HomeScreen()),
  );
}
