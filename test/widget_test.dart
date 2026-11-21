import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alqadi_smart_exam_checker/main.dart';

void main() {
  testWidgets('Arabic home screen opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AlQadiApp());
    await tester.pumpAndSettle();
    expect(find.text('القاضي الذكي'), findsOneWidget);
    expect(find.text('اختبار جديد'), findsOneWidget);
  });
}
