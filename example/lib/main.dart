import 'dart:async';
import 'dart:math' as math;

import 'package:easy_monitoring/easy_monitoring.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const EasyMonitoringExampleApp());
}

class EasyMonitoringExampleApp extends StatelessWidget {
  const EasyMonitoringExampleApp({
    super.key,
    this.monitoring,
  });

  final EasyMonitoring? monitoring;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Monitoring — Live CPU, RAM, GPU & Process',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
          surface: const Color(0xFF161B22),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF161B22),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF30363D)),
          ),
        ),
      ),
      home: MonitoringDashboardPage(
        monitoring: monitoring ?? EasyMonitoring.instance,
      ),
    );
  }
}

class MonitoringDashboardPage extends StatefulWidget {
  const MonitoringDashboardPage({
    super.key,
    required this.monitoring,
  });

  final EasyMonitoring monitoring;

  @override
  State<MonitoringDashboardPage> createState() =>
      _MonitoringDashboardPageState();
}

class _MonitoringDashboardPageState extends State<MonitoringDashboardPage> {
  static const int _maxHistoryLength = 60;

  Duration _interval = const Duration(seconds: 1);
  bool _isPaused = false;
  bool _showAllCores = false;

  StreamSubscription<SystemMetrics>? _subscription;
  SystemMetrics? _latest;
  Object? _error;
  String _nativeVersion = '...';

  final List<double> _cpuHistory = [];
  final List<double> _ramHistory = [];
  final List<double> _gpuLoadHistory = [];
  final List<double> _gpuVramHistory = [];
  final List<double> _procCpuHistory = [];
  final List<double> _procRamHistory = [];
  final List<double> _procGpuHistory = [];

  @override
  void initState() {
    super.initState();
    _initVersion();
    _subscribeStream();
  }

  void _initVersion() {
    try {
      _nativeVersion = widget.monitoring.nativeVersion;
    } catch (_) {
      _nativeVersion = 'unavailable';
    }
  }

  void _recordSnapshot(SystemMetrics metrics) {
    _error = null;
    _latest = metrics;
    _pushHistory(_cpuHistory, metrics.cpu.usagePercent);
    _pushHistory(_ramHistory, metrics.memory.usagePercent);
    _pushHistory(_gpuLoadHistory, metrics.gpu.usagePercent);
    _pushHistory(_gpuVramHistory, metrics.gpu.vramUsagePercent);
    _pushHistory(_procCpuHistory, metrics.currentProcess.cpuUsagePercent);
    _pushHistory(_procRamHistory, metrics.currentProcess.memoryUsagePercent);
    _pushHistory(_procGpuHistory, metrics.currentProcess.gpuUsagePercent);
  }

  void _subscribeStream() {
    _subscription?.cancel();
    if (_isPaused) return;

    _subscription = widget.monitoring
        .metricsStream(interval: _interval)
        .listen(
      (metrics) {
        if (!mounted) return;
        setState(() {
          _recordSnapshot(metrics);
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _error = err;
        });
      },
    );
  }

  void _pushHistory(List<double> list, double value) {
    list.add(value.clamp(0.0, 100.0));
    if (list.length > _maxHistoryLength) {
      list.removeAt(0);
    }
  }

  Future<void> _refreshOnce() async {
    try {
      final snapshot = await widget.monitoring.getSystemMetrics();
      if (!mounted) return;
      setState(() {
        _recordSnapshot(snapshot);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
      });
    }
  }

  void _changeInterval(Duration newInterval) {
    setState(() {
      _interval = newInterval;
    });
    _subscribeStream();
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    if (_isPaused) {
      _subscription?.cancel();
      _subscription = null;
    } else {
      _subscribeStream();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _latest;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monitor_heart_rounded, color: Color(0xFF38BDF8)),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'easy_monitoring',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Text(
                  'Rust v$_nativeVersion (sysinfo + gfxinfo)',
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          _IntervalDropdown(
            currentInterval: _interval,
            onChanged: _changeInterval,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _isPaused ? 'Resume stream' : 'Pause stream',
            onPressed: _togglePause,
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: _isPaused
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFFACC15),
            ),
          ),
          IconButton(
            tooltip: 'One-shot snapshot',
            onPressed: _refreshOnce,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _buildBody(metrics),
    );
  }

  Widget _buildBody(SystemMetrics? metrics) {
    if (_error != null && metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                'Native monitoring error:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refreshOnce,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (metrics == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing Rust probes (sysinfo & gfxinfo)...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCurrentProcessCard(metrics.currentProcess),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              if (isWide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildCpuCard(metrics.cpu)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMemoryCard(metrics.memory)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildGpuCard(metrics.gpu)),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  _buildCpuCard(metrics.cpu),
                  const SizedBox(height: 16),
                  _buildMemoryCard(metrics.memory),
                  const SizedBox(height: 16),
                  _buildGpuCard(metrics.gpu),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _buildCpuCoresSection(metrics.cpu),
        ],
      ),
    );
  }

  Widget _buildCurrentProcessCard(ProcessMetrics proc) {
    const accent = Color(0xFFF97316);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.terminal_rounded,
              title: 'Current Process (${proc.name} • PID ${proc.pid})',
              subtitle:
                  'Status: ${proc.status} • Uptime: ${proc.runTimeSeconds}s',
              accentColor: accent,
              badgeText: 'RAM ${proc.formattedMemory}',
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 820;
                final children = [
                  _buildProcessSubPanel(
                    title: 'Process CPU',
                    percentText: '${proc.cpuUsagePercent.toStringAsFixed(2)}%',
                    progressValue: proc.cpuUsagePercent / 100.0,
                    color: const Color(0xFF38BDF8),
                    history: _procCpuHistory,
                    rows: [
                      _MetricRow(
                        label: 'Normalized CPU share',
                        value: '${proc.cpuUsagePercent.toStringAsFixed(2)} %',
                      ),
                      _MetricRow(
                        label: 'Raw core load (100% = 1 core)',
                        value:
                            '${proc.rawCpuUsagePercent.toStringAsFixed(1)} %',
                      ),
                    ],
                  ),
                  _buildProcessSubPanel(
                    title: 'Process RAM',
                    percentText:
                        '${proc.memoryUsagePercent.toStringAsFixed(2)}%',
                    progressValue: proc.memoryUsagePercent / 100.0,
                    color: const Color(0xFFA855F7),
                    history: _procRamHistory,
                    rows: [
                      _MetricRow(
                        label: 'Physical RAM used / total',
                        value: proc.formattedMemoryUsage,
                      ),
                      _MetricRow(
                        label: 'Allocated virtual memory',
                        value: ByteFormatter.format(proc.virtualMemoryBytes),
                      ),
                    ],
                  ),
                  _buildProcessSubPanel(
                    title: 'Process GPU',
                    percentText: '${proc.gpuUsagePercent.toStringAsFixed(1)}%',
                    progressValue: proc.gpuUsagePercent / 100.0,
                    color: const Color(0xFF10B981),
                    history: _procGpuHistory,
                    rows: [
                      _MetricRow(
                        label: 'Process GPU load',
                        value: '${proc.gpuUsagePercent.toStringAsFixed(1)} %',
                      ),
                      _MetricRow(
                        label: 'Process VRAM / total',
                        value:
                            '${proc.formattedGpuVramUsage} (${proc.gpuVramUsagePercent.toStringAsFixed(2)}%)',
                      ),
                    ],
                  ),
                ];

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: 12),
                      Expanded(child: children[1]),
                      const SizedBox(width: 12),
                      Expanded(child: children[2]),
                    ],
                  );
                }
                return Column(
                  children: [
                    children[0],
                    const SizedBox(height: 12),
                    children[1],
                    const SizedBox(height: 12),
                    children[2],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessSubPanel({
    required String title,
    required String percentText,
    required double progressValue,
    required Color color,
    required List<double> history,
    required List<Widget> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                percentText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFF21262D),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: _SparklineChart(
              values: history,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF30363D), height: 1),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildCpuCard(CpuMetrics cpu) {
    const accent = Color(0xFF38BDF8);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.memory_rounded,
              title: 'System Processor (CPU)',
              subtitle: cpu.brand,
              accentColor: accent,
              badgeText: '${cpu.usagePercent.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (cpu.usagePercent / 100.0).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFF21262D),
                valueColor: const AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: _SparklineChart(
                values: _cpuHistory,
                color: accent,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF30363D), height: 1),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'Global utilization (%)',
              value: '${cpu.usagePercent.toStringAsFixed(2)} %',
            ),
            _MetricRow(
              label: 'Cores (Physical / Logical)',
              value: '${cpu.physicalCores} P / ${cpu.logicalCores} L',
            ),
            _MetricRow(
              label: 'Average frequency (absolute)',
              value: cpu.averageFrequencyMhz > 0
                  ? '${cpu.averageFrequencyMhz} MHz (${cpu.averageFrequencyGhz.toStringAsFixed(2)} GHz)'
                  : 'N/A',
            ),
            _MetricRow(
              label: 'Peak frequency (absolute)',
              value: cpu.maxFrequencyMhz > 0
                  ? '${cpu.maxFrequencyMhz} MHz (${cpu.maxFrequencyGhz.toStringAsFixed(2)} GHz)'
                  : 'N/A',
            ),
            _MetricRow(
              label: 'Vendor',
              value: cpu.vendorId,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(MemoryMetrics mem) {
    const accent = Color(0xFFA855F7);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.storage_rounded,
              title: 'System Memory (RAM & Swap)',
              subtitle: mem.formattedUsage,
              accentColor: accent,
              badgeText: '${mem.usagePercent.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (mem.usagePercent / 100.0).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFF21262D),
                valueColor: const AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: _SparklineChart(
                values: _ramHistory,
                color: accent,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF30363D), height: 1),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'Used / total RAM (GB)',
              value: mem.formattedUsage,
            ),
            _MetricRow(
              label: 'Used / total RAM (MB)',
              value:
                  '${mem.usedMemoryMb.toStringAsFixed(0)} MB / ${mem.totalMemoryMb.toStringAsFixed(0)} MB',
            ),
            _MetricRow(
              label: 'Available RAM (absolute)',
              value: ByteFormatter.format(mem.availableMemoryBytes),
            ),
            _MetricRow(
              label: 'Free RAM (absolute)',
              value: ByteFormatter.format(mem.freeMemoryBytes),
            ),
            _MetricRow(
              label: 'Used / total Swap',
              value: mem.totalSwapBytes > 0
                  ? '${mem.formattedSwapUsage} (${mem.swapUsagePercent.toStringAsFixed(1)}%)'
                  : '0 B / 0 B (0.0%)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpuCard(GpuMetrics gpu) {
    const accent = Color(0xFF10B981);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.developer_board_rounded,
              title: 'System Graphics Card (GPU)',
              subtitle:
                  gpu.available ? '${gpu.vendor} • ${gpu.model}' : gpu.model,
              accentColor: accent,
              badgeText: '${gpu.usagePercent.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GPU Load: ${gpu.usagePercent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8B949E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (gpu.usagePercent / 100.0).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: const Color(0xFF21262D),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VRAM: ${gpu.vramUsagePercent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8B949E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (gpu.vramUsagePercent / 100.0).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: const Color(0xFF21262D),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF34D399),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: _SparklineChart(
                values: _gpuLoadHistory,
                secondaryValues: _gpuVramHistory,
                color: accent,
                secondaryColor: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF30363D), height: 1),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'GPU core load (%)',
              value: '${gpu.usagePercent.toStringAsFixed(1)} %',
            ),
            _MetricRow(
              label: 'Used / total VRAM (GB)',
              value: gpu.formattedVramUsage,
            ),
            _MetricRow(
              label: 'Used / total VRAM (MB)',
              value:
                  '${gpu.usedVramMb.toStringAsFixed(0)} MB / ${gpu.totalVramMb.toStringAsFixed(0)} MB (${gpu.vramUsagePercent.toStringAsFixed(1)}%)',
            ),
            _MetricRow(
              label: 'GPU temperature',
              value: gpu.temperatureCelsius != null
                  ? '${gpu.temperatureCelsius!.toStringAsFixed(1)} °C'
                  : 'N/A (not reported by OS)',
            ),
            _MetricRow(
              label: 'Family / Architecture',
              value: gpu.family,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCpuCoresSection(CpuMetrics cpu) {
    final visibleCores =
        _showAllCores ? cpu.cores : cpu.cores.take(12).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Per-Logical-Core Breakdown (${cpu.cores.length} cores)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cpu.cores.length > 12)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllCores = !_showAllCores;
                      });
                    },
                    icon: Icon(
                      _showAllCores
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _showAllCores
                          ? 'Collapse'
                          : 'Show all ${cpu.cores.length} cores',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 64,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: visibleCores.length,
              itemBuilder: (context, index) {
                final core = visibleCores[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Core #${core.index + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${core.usagePercent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (core.usagePercent / 100.0).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: const Color(0xFF21262D),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.badgeText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B949E),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accentColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8B949E),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE6EDF3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntervalDropdown extends StatelessWidget {
  const _IntervalDropdown({
    required this.currentInterval,
    required this.onChanged,
  });

  final Duration currentInterval;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ];

    return DropdownButtonHideUnderline(
      child: DropdownButton<Duration>(
        value: currentInterval,
        borderRadius: BorderRadius.circular(8),
        dropdownColor: const Color(0xFF21262D),
        items: options.map((duration) {
          final label = duration.inMilliseconds < 1000
              ? '${duration.inMilliseconds} ms'
              : '${duration.inSeconds} s';
          return DropdownMenuItem<Duration>(
            value: duration,
            child: Text(
              'Refresh: $label',
              style: const TextStyle(fontSize: 13),
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) onChanged(val);
        },
      ),
    );
  }
}

class _SparklineChart extends StatelessWidget {
  const _SparklineChart({
    required this.values,
    required this.color,
    this.secondaryValues,
    this.secondaryColor,
  });

  final List<double> values;
  final Color color;
  final List<double>? secondaryValues;
  final Color? secondaryColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _SparklinePainter(
        values: values,
        color: color,
        secondaryValues: secondaryValues,
        secondaryColor: secondaryColor,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    this.secondaryValues,
    this.secondaryColor,
  });

  final List<double> values;
  final Color color;
  final List<double>? secondaryValues;
  final Color? secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF21262D)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSeries(canvas, size, values, color, fill: true);
    if (secondaryValues != null && secondaryColor != null) {
      _drawSeries(
        canvas,
        size,
        secondaryValues!,
        secondaryColor!,
        fill: false,
      );
    }
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<double> data,
    Color seriesColor, {
    required bool fill,
  }) {
    if (data.isEmpty) return;

    final path = Path();
    final count = math.max(data.length, 2);
    final stepX = size.width / (count - 1);

    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalized = (data[i].clamp(0.0, 100.0)) / 100.0;
      final y = size.height - (normalized * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (data.length == 1) {
      final normalized = (data.first.clamp(0.0, 100.0)) / 100.0;
      final y = size.height - (normalized * size.height);
      path.lineTo(size.width, y);
    }

    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(
          data.length == 1 ? size.width : (data.length - 1) * stepX,
          size.height,
        )
        ..lineTo(0, size.height)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            seriesColor.withValues(alpha: 0.30),
            seriesColor.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size);

      canvas.drawPath(fillPath, fillPaint);
    }

    final strokePaint = Paint()
      ..color = seriesColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}
