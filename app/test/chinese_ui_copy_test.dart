import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('高频页面不包含已知英文界面文案', () {
    const files = [
      'lib/pages/agent_session_sheets.dart',
      'lib/pages/files_page_actions.dart',
      'lib/pages/files_page_layout.dart',
      'lib/pages/files_page_pane.dart',
      'lib/pages/files_page_transfers.dart',
      'lib/pages/settings_connectivity_section.dart',
      'lib/pages/settings_data_section.dart',
      'lib/state/agent_chat_controller_turns.dart',
      'lib/state/app_state.dart',
    ];
    const forbidden = [
      'Select a host first',
      'No sessions yet',
      'Untitled session',
      'Delete session',
      'Create folder',
      'Create file',
      'Copy to other pane',
      'Move to other pane',
      'Select at least one item first',
      "Text('Close')",
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final text in forbidden) {
        expect(source, isNot(contains(text)), reason: '$path 仍包含英文界面文案：$text');
      }
    }
  });
}
