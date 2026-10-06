import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/widgets/app_dialog.dart';

void main() {
  testWidgets(
    'окно без касания (например, по push) не возвращает фокус в поле',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: TextField()),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      final closed = showAppDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Окно')),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await closed;

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );
}
