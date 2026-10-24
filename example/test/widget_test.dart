import 'package:easy_monitoring/easy_monitoring.dart';
import 'package:easy_monitoring_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MonitoringDashboardPage renders live metrics from Rust',
      (WidgetTester tester) async {
    final monitor = EasyMonitoring(
      defaultInterval: const Duration(milliseconds: 250),
    );
    addTearDown(monitor.dispose);

    await tester.pumpWidget(EasyMonitoringExampleApp(monitoring: monitor));
    expect(find.text('easy_monitoring'), findsOneWidget);
  });
}
