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
}
