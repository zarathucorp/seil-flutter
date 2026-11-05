import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/features/sessions/ssh_session_service.dart';
import 'package:seil_mobile/features/sessions/workspace_screen.dart';

void main() {
  test('tmux status refresh captures only ten lines per inactive terminal', () {
    final command = buildTmuxSessionStatusCommand();

    expect(command, contains('tmux list-sessions'));
    expect(command, contains('tmux list-windows'));
    expect(command, contains('tmux list-panes'));
    expect(command, contains('#{pane_id}'));
    expect(command, contains('capture-pane'));
    expect(command, contains('-S -10'));
    expect(command, isNot(contains('-S -30')));
    expect(command, contains('while IFS="|" read -r'));
    expect(command, isNot(contains(' cut ')));
  });

  test('tmux tab width follows the current label length', () {
    final shortWidth = tmuxTabWidthForLabel('흥');
    final expandedWidth = tmuxTabWidthForLabel('흥칫뿡');
    final mediumWidth = tmuxTabWidthForLabel('안녕하세요');
    final longWidth = tmuxTabWidthForLabel('래래래래래래래래래래래래');

    expect(shortWidth, lessThan(expandedWidth));
    expect(expandedWidth, lessThan(mediumWidth));
    expect(shortWidth, lessThan(mediumWidth));
    expect(mediumWidth, lessThan(longWidth));
    expect(tmuxTabWidthForLabel('흥'), shortWidth);
    expect(longWidth, lessThanOrEqualTo(168));
  });

  test('background tmux status refresh remains fixed at two seconds', () {
    expect(
      tmuxBackgroundRefreshInterval,
      const Duration(seconds: 2),
    );
  });

  test('interactive commands jump ahead of queued background work', () async {
    final queue = SshCommandQueue();
    final blocker = Completer<void>();
    final order = <String>[];

    final runningBackground = queue.run(
      () async {
        order.add('running-background');
        await blocker.future;
        return 'running-background';
      },
      priority: SshCommandPriority.background,
    );
    final queuedBackground = queue.run(
      () async {
        order.add('queued-background');
        return 'queued-background';
      },
      priority: SshCommandPriority.background,
    );
    final queuedForeground = queue.run(
      () async {
        order.add('queued-foreground');
        return 'queued-foreground';
      },
    );
    final queuedInteractive = queue.run(
      () async {
        order.add('queued-interactive');
        return 'queued-interactive';
      },
      priority: SshCommandPriority.interactive,
    );

    blocker.complete();
    await Future.wait([
      runningBackground,
      queuedBackground,
      queuedForeground,
      queuedInteractive,
    ]);

    expect(order, [
      'running-background',
      'queued-interactive',
      'queued-foreground',
      'queued-background',
    ]);
  });

  test('monitor work cannot block interactive commands', () async {
    final interactiveQueue = SshCommandQueue();
    final monitorQueue = SshCommandQueue();
    final monitorStarted = Completer<void>();
    final releaseMonitor = Completer<void>();
    var monitorFinished = false;

    final monitorWork = monitorQueue.run(
      () async {
        monitorStarted.complete();
        await releaseMonitor.future;
        monitorFinished = true;
        return 'monitor';
      },
      priority: SshCommandPriority.background,
    );

    await monitorStarted.future;
    final interactiveResult = await interactiveQueue.run(
      () async => 'interactive',
      priority: SshCommandPriority.interactive,
    );

    expect(interactiveResult, 'interactive');
    expect(monitorFinished, isFalse);

    releaseMonitor.complete();
    await monitorWork;
  });

  test('foreground capture work cannot block the dedicated input queue',
      () async {
    final foregroundQueue = SshCommandQueue();
    final interactiveQueue = SshCommandQueue();
    final foregroundStarted = Completer<void>();
    final releaseForeground = Completer<void>();
    var foregroundFinished = false;

    final foregroundWork = foregroundQueue.run(() async {
      foregroundStarted.complete();
      await releaseForeground.future;
      foregroundFinished = true;
      return 'capture';
    });

    await foregroundStarted.future;
    final inputResult = await interactiveQueue.run(
      () async => 'input',
      priority: SshCommandPriority.interactive,
    );

    expect(inputResult, 'input');
    expect(foregroundFinished, isFalse);

    releaseForeground.complete();
    await foregroundWork;
  });

  test('commands with the same coalescing key share one execution', () async {
    final queue = SshCommandQueue();
    final blocker = Completer<void>();
    var executionCount = 0;

    final first = queue.run(
      () async {
        executionCount += 1;
        await blocker.future;
        return 'metadata';
      },
      priority: SshCommandPriority.background,
      coalescingKey: 'tmux-metadata',
    );
    final second = queue.run(
      () async {
        executionCount += 1;
        return 'duplicate';
      },
      priority: SshCommandPriority.background,
      coalescingKey: 'tmux-metadata',
    );

    blocker.complete();

    expect(await first, 'metadata');
    expect(await second, 'metadata');
    expect(executionCount, 1);
  });

  test('many duplicate monitor refreshes still execute only once', () async {
    final queue = SshCommandQueue();
    final blocker = Completer<void>();
    var executionCount = 0;

    final requests = List.generate(
      64,
      (_) => queue.run(
        () async {
          executionCount += 1;
          await blocker.future;
          return 'shared-status';
        },
        priority: SshCommandPriority.background,
        coalescingKey: 'tmux-session-status',
      ),
    );

    blocker.complete();
    final results = await Future.wait(requests);

    expect(results, everyElement('shared-status'));
    expect(executionCount, 1);
  });
}
