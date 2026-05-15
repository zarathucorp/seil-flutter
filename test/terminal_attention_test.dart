import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/shared/models.dart';

void main() {
  group('terminalAttentionFromTmux', () {
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

    test('detects Claude completed state from captured screen tail', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          terminalScreen: '● READY\n✻ Cooked for 2s\n❯',
        ),
        TerminalAttentionState.completed,
      );
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          terminalScreen: '● Bash(echo seil_probe_action)\n✻ Worked for 4s\n❯',
        ),
        TerminalAttentionState.completed,
      );
    });

    test('keeps Claude running while captured screen shows interrupt hint', () {
      expect(
        terminalAttentionFromTmux(
          terminalTitle: '✳ Run echo command for probe action',
          terminalScreen: 'esc to interrupt\n✻ Worked for 4s',
        ),
        TerminalAttentionState.running,
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

  group('terminalAttentionFromTransition', () {
    test('marks title return from running as completed', () {
      expect(
        terminalAttentionFromTransition(
          previous: TerminalAttentionState.running,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.completed,
      );
    });

    test('keeps completed state until a new active state is observed', () {
      expect(
        terminalAttentionFromTransition(
          previous: TerminalAttentionState.completed,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.completed,
      );
    });

    test('new running state overrides previous completed state', () {
      expect(
        terminalAttentionFromTransition(
          previous: TerminalAttentionState.completed,
          current: TerminalAttentionState.running,
        ),
        TerminalAttentionState.running,
      );
    });

    test('keeps action required state until a new active state is observed',
        () {
      expect(
        terminalAttentionFromTransition(
          previous: TerminalAttentionState.actionRequired,
          current: TerminalAttentionState.none,
        ),
        TerminalAttentionState.actionRequired,
      );
    });
  });
}
