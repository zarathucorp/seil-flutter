import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/shared/models.dart';

void main() {
  group('terminalAttentionFromTmux', () {
    test('separates direct events from current running state', () {
      expect(
        terminalAttentionFromTmuxDirectEvent(
          terminalTitle: '[ ! ] Action Required | Codex | project',
        ),
        TerminalAttentionState.actionRequired,
      );
      expect(
        terminalAttentionFromTmuxDirectEvent(windowBellFlag: '1'),
        TerminalAttentionState.completed,
      );
      expect(
        terminalAttentionFromTmuxCurrentState(
          terminalTitle: '⠋ Codex | Working | seil-flutter-public',
        ),
        TerminalAttentionState.running,
      );
    });

    test('detects running spinner from terminal title', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '⠋ Codex | Working | seil-flutter-public',
        ),
        TerminalAttentionState.running,
      );
    });

    test('detects Claude running state from pane title spinner', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '⠐ Run echo command for probe action',
        ),
        TerminalAttentionState.running,
      );
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
        ),
        TerminalAttentionState.running,
      );
    });

    test('does not treat idle Claude title as running', () {
      expect(
        terminalAttentionFromTmux(terminalTitle: '✳ Claude Code'),
        TerminalAttentionState.none,
      );
    });

    test('detects action required title before running state', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '[ ! ] Action Required | Codex | project',
        ),
        TerminalAttentionState.actionRequired,
      );
    });

    test('detects completed state from tmux bell flag', () {
      expect(
        terminalAttentionFromTmux(windowBellFlag: '1'),
        TerminalAttentionState.completed,
      );
    });

    test('keeps generic activity out of completed state', () {
      expect(
        terminalAttentionFromTmux(
          windowFlags: '#',
          windowActivityFlag: '1',
        ),
        TerminalAttentionState.none,
      );
    });

    test('detects generic foreground jobs as running', () {
      expect(
        terminalAttentionFromTmux(
          paneCurrentCommand: 'make',
        ),
        TerminalAttentionState.running,
      );
      expect(
        terminalAttentionFromTmux(
          paneCurrentCommand: '/usr/bin/flutter',
        ),
        TerminalAttentionState.running,
      );
    });

    test('does not treat idle or interactive pane commands as running', () {
      expect(
        terminalAttentionFromTmux(paneCurrentCommand: 'zsh'),
        TerminalAttentionState.none,
      );
      expect(
        terminalAttentionFromTmux(paneCurrentCommand: 'claude'),
        TerminalAttentionState.none,
      );
    });

    test('keeps running while captured screen shows interrupt hint', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          terminalScreen: 'esc to interrupt\n✻ Worked for 4s',
        ),
        TerminalAttentionState.running,
      );
    });

    test('ignores stale tmux title when title running is disabled', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          allowTitleRunning: false,
        ),
        TerminalAttentionState.none,
      );
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          terminalScreen: 'esc to interrupt',
          allowTitleRunning: false,
        ),
        TerminalAttentionState.running,
      );
    });
  });

  group('terminalAttentionFromTerminalOutput', () {
    test('detects OSC title running state', () {
      expect(
        terminalAttentionFromTerminalOutput(
          '\x1b]0;⠋ Codex | Working | seil-flutter-public\x07',
        ),
        TerminalAttentionState.running,
      );
    });

    test('detects OSC notification as completed', () {
      expect(
        terminalAttentionFromTerminalOutput('\x1b]9;task finished\x07'),
        TerminalAttentionState.completed,
      );
    });

    test('detects action required notification', () {
      expect(
        terminalAttentionFromTerminalOutput(
          '\x1b]9;Action Required: approve command\x07',
        ),
        TerminalAttentionState.actionRequired,
      );
    });

    test('does not treat OSC title terminator bell as completed', () {
      expect(
        terminalAttentionFromTerminalOutput('\x1b]0;plain title\x07'),
        TerminalAttentionState.none,
      );
      expect(
        terminalOutputHasAttentionCue('\x1b]0;plain title\x07'),
        isTrue,
      );
    });

    test('detects standalone bell as completed', () {
      expect(
        terminalAttentionFromTerminalOutput('\x07'),
        TerminalAttentionState.completed,
      );
    });
  });

  test('maxTerminalAttentionState prefers actionable states', () {
    expect(
      maxTerminalAttentionState(
        TerminalAttentionState.completed,
        TerminalAttentionState.running,
      ),
      TerminalAttentionState.running,
    );
    expect(
      maxTerminalAttentionState(
        TerminalAttentionState.actionRequired,
        TerminalAttentionState.running,
      ),
      TerminalAttentionState.actionRequired,
    );
  });

  group('terminalAttentionFromFallbackTransition', () {
    test('marks title return from running as completed', () {
      expect(
        terminalAttentionFromFallbackTransition(
          previous: TerminalAttentionState.running,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.completed,
      );
    });

    test('keeps completed state until a new active state is observed', () {
      expect(
        terminalAttentionFromFallbackTransition(
          previous: TerminalAttentionState.completed,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.completed,
      );
    });

    test('new running state overrides previous completed state', () {
      expect(
        terminalAttentionFromFallbackTransition(
          previous: TerminalAttentionState.completed,
          current: TerminalAttentionState.running,
        ),
        TerminalAttentionState.running,
      );
    });

    test('keeps action required state until a new active state is observed',
        () {
      expect(
        terminalAttentionFromFallbackTransition(
          previous: TerminalAttentionState.actionRequired,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.actionRequired,
      );
    });
  });
}
