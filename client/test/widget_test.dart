import 'package:flutter_test/flutter_test.dart';
import 'package:barricade/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const BarricadeApp());
    expect(find.text('Barricade'), findsOneWidget);
  });
}
