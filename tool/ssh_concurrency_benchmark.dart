import 'dart:async';
import 'dart:io';

import 'package:seil_mobile/features/sessions/ssh_session_service.dart';

const _sessionCounts = [1, 4, 8, 16, 32];
const _rounds = 7;
const _simulatedMonitorLatency = Duration(milliseconds: 30);

Future<void> main() async {
  stdout.writeln('SEIL SSH concurrency benchmark');
  stdout.writeln(
    'Each session starts a ${_simulatedMonitorLatency.inMilliseconds} ms '
    'background tmux scan, then receives an interactive command.',
  );
  stdout
      .writeln('Legacy = one shared queue, current = isolated monitor queue.');
  stdout.writeln();
  stdout.writeln(
    'sessions | legacy p50 | legacy p95 | current p50 | current p95 | '
    'p95 wait reduction',
  );
  stdout.writeln(
    '---------|------------|------------|-------------|-------------|'
    '-------------------',
  );

  for (final sessionCount in _sessionCounts) {
    final legacySamples = <int>[];
    final currentSamples = <int>[];

    for (var round = 0; round < _rounds; round += 1) {
      legacySamples.addAll(
        await _runRound(
          sessionCount: sessionCount,
          isolateMonitorQueue: false,
        ),
      );
      currentSamples.addAll(
        await _runRound(
          sessionCount: sessionCount,
          isolateMonitorQueue: true,
        ),
      );
    }

    final legacyP50 = _percentile(legacySamples, 0.50);
    final legacyP95 = _percentile(legacySamples, 0.95);
    final currentP50 = _percentile(currentSamples, 0.50);
    final currentP95 = _percentile(currentSamples, 0.95);
    final reduction =
        legacyP95 == 0 ? 0.0 : (legacyP95 - currentP95) / legacyP95 * 100;

    stdout.writeln(
      '${sessionCount.toString().padLeft(8)} | '
      '${_milliseconds(legacyP50).padLeft(10)} | '
      '${_milliseconds(legacyP95).padLeft(10)} | '
      '${_milliseconds(currentP50).padLeft(11)} | '
      '${_milliseconds(currentP95).padLeft(11)} | '
      '${reduction.toStringAsFixed(1).padLeft(17)}%',
    );
  }

  stdout.writeln();
  stdout.writeln(
    'This isolates queueing delay only. Real SSH/server/network latency must be '
    'measured separately on the target Mac.',
  );
}

Future<List<int>> _runRound({
  required int sessionCount,
  required bool isolateMonitorQueue,
}) async {
  final sessions = List.generate(
    sessionCount,
    (_) => _BenchmarkQueues.create(
      isolateMonitorQueue: isolateMonitorQueue,
    ),
  );
  final monitorStarted = List.generate(
    sessionCount,
    (_) => Completer<void>(),
  );
  final monitorWork = <Future<String>>[];

  for (var index = 0; index < sessionCount; index += 1) {
    monitorWork.add(
      sessions[index].monitor.run(
        () async {
          monitorStarted[index].complete();
          await Future<void>.delayed(_simulatedMonitorLatency);
          return 'monitor';
        },
        priority: SshCommandPriority.background,
      ),
    );
  }

  await Future.wait(monitorStarted.map((started) => started.future));
  final interactiveLatencies = await Future.wait(
    sessions.map((session) async {
      final stopwatch = Stopwatch()..start();
      await session.interactive.run(
        () async => 'interactive',
        priority: SshCommandPriority.interactive,
      );
      stopwatch.stop();
      return stopwatch.elapsedMicroseconds;
    }),
  );
  await Future.wait(monitorWork);
  return interactiveLatencies;
}

int _percentile(List<int> samples, double percentile) {
  final sorted = [...samples]..sort();
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

String _milliseconds(int microseconds) =>
    '${(microseconds / 1000).toStringAsFixed(3)} ms';

class _BenchmarkQueues {
  const _BenchmarkQueues({
    required this.interactive,
    required this.monitor,
  });

  factory _BenchmarkQueues.create({required bool isolateMonitorQueue}) {
    final interactive = SshCommandQueue();
    return _BenchmarkQueues(
      interactive: interactive,
      monitor: isolateMonitorQueue ? SshCommandQueue() : interactive,
    );
  }

  final SshCommandQueue interactive;
  final SshCommandQueue monitor;
}
