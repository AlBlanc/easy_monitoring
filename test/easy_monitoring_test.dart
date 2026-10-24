import 'dart:io';

import 'package:easy_monitoring/easy_monitoring.dart';
import 'package:test/test.dart';

void main() {
  group('EasyMonitoring', () {
    late EasyMonitoring monitor;

    setUp(() {
      monitor = EasyMonitoring(
        defaultInterval: const Duration(milliseconds: 250),
      );
    });

    tearDown(() async {
      await monitor.dispose();
    });

    test('returns native Rust library version', () {
      expect(monitor.nativeVersion, equals('0.1.1-1'));
    });

    test(
        'fetches one-shot SystemMetrics with valid CPU, RAM, GPU, and current process values',
        () async {
      final metrics = await monitor.getSystemMetrics();

      // CPU checks
      expect(metrics.cpu.brand, isNotEmpty);
      expect(metrics.cpu.logicalCores, greaterThan(0));
      expect(metrics.cpu.physicalCores, greaterThan(0));
      expect(metrics.cpu.usagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.cpu.cores.length, equals(metrics.cpu.logicalCores));

      // Memory (RAM & Swap) checks (percentage + absolute values)
      expect(metrics.memory.totalMemoryBytes, greaterThan(0));
      expect(metrics.memory.usedMemoryBytes, greaterThan(0));
      expect(
        metrics.memory.usedMemoryBytes,
        lessThanOrEqualTo(metrics.memory.totalMemoryBytes),
      );
      expect(metrics.memory.usagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.memory.totalMemoryGb, greaterThan(0.0));
      expect(metrics.memory.formattedUsage, contains('/'));

      // GPU checks
      expect(metrics.gpu.vendor, isNotEmpty);
      expect(metrics.gpu.model, isNotEmpty);
      expect(metrics.gpu.usagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.gpu.vramUsagePercent, inInclusiveRange(0.0, 100.0));

      // Current process checks
      expect(metrics.currentProcess.pid, equals(pid));
      expect(metrics.currentProcess.name, isNotEmpty);
      expect(metrics.currentProcess.memoryBytes, greaterThan(0));
      expect(metrics.currentProcess.memoryUsagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.currentProcess.cpuUsagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.currentProcess.gpuUsagePercent, inInclusiveRange(0.0, 100.0));
      expect(metrics.currentProcess.gpuVramUsagePercent, inInclusiveRange(0.0, 100.0));
    });

    test('fetches current process metrics directly and via currentProcessStream',
        () async {
      final proc = await monitor.getCurrentProcessMetrics();
      expect(proc.pid, equals(pid));
      expect(proc.memoryBytes, greaterThan(0));
      expect(proc.formattedMemoryUsage, contains('/'));

      final streamSamples = await monitor
          .currentProcessStream(interval: const Duration(milliseconds: 200))
          .take(2)
          .toList();
      expect(streamSamples.length, equals(2));
      for (final sample in streamSamples) {
        expect(sample.pid, equals(pid));
        expect(sample.memoryBytes, greaterThan(0));
      }
    });

    test('streams live CPU, Memory, GPU, and Process metrics over time',
        () async {
      final samples = await monitor
          .metricsStream(interval: const Duration(milliseconds: 200))
          .take(3)
          .toList();

      expect(samples.length, equals(3));
      for (final sample in samples) {
        expect(sample.cpu.usagePercent, inInclusiveRange(0.0, 100.0));
        expect(sample.memory.totalMemoryBytes, greaterThan(0));
        expect(sample.gpu.vramUsagePercent, inInclusiveRange(0.0, 100.0));
        expect(sample.currentProcess.pid, equals(pid));
      }
    });
  });
}
