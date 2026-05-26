import 'package:flutter_test/flutter_test.dart';

import 'package:smart_album/main.dart';

void main() {
  testWidgets('App should render gallery screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SmartAlbumApp());
    expect(find.text('随搜相册'), findsOneWidget);
  });
}
