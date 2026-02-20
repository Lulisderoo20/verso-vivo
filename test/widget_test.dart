import 'package:flutter_test/flutter_test.dart';
import 'package:verso_vivo/main.dart';

void main() {
  testWidgets('renderiza la pregunta principal', (tester) async {
    await tester.pumpWidget(const VersoVivoApp());

    expect(
      find.text('Sobre que quieres que trate el versiculo de hoy?'),
      findsOneWidget,
    );
    expect(find.text('VersoVivo'), findsOneWidget);
  });
}

