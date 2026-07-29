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
      'lib/pages/settings_llm_section.dart',
      'lib/pages/settings_page.dart',
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
      "title: 'Model'",
      'OpenAI-compatible endpoint',
      'LLM Base URL',
      'Usually ends with /v1',
      'Stored locally',
      "'Show' : 'Hide'",
      "labelText: 'Model'",
      r'Loaded ${_modelIds.length} models',
      'Optional provider hint',
      "child: Text('none')",
      "child: Text('auto')",
      "child: Text('low')",
      "child: Text('medium')",
      "child: Text('high')",
      "child: Text('xhigh')",
      'LLM saved',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final text in forbidden) {
        expect(source, isNot(contains(text)), reason: '$path 仍包含英文界面文案：$text');
      }
    }
  });

  test('LLM 设置不包含英文文案或原始错误提示', () {
    const files = [
      'lib/pages/settings_llm_section.dart',
      'lib/pages/settings_page.dart',
    ];
    const forbidden = [
      r"_toast('$e')",
      r'拉取模型列表失败: $e',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final text in forbidden) {
        expect(source, isNot(contains(text)), reason: '$path 仍包含未清洗的错误提示：$text');
      }
    }
  });

  test('设置页高频区域不包含已知英文文案或原始错误', () {
    const files = [
      'lib/pages/settings_backend_section.dart',
      'lib/pages/settings_display_section.dart',
      'lib/pages/settings_data_section.dart',
    ];
    const forbidden = [
      "title: 'Backend'",
      "title: 'Display'",
      'Data & Diagnostics',
      'Local Go service and token',
      'Navigation mode',
      'Compact host cards',
      'Stream markdown',
      'Probe concurrency',
      'Auto probe interval',
      'Export config',
      'Import config',
      'Backend log',
      'Host keys',
      r"_toast('$e')",
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final text in forbidden) {
        expect(source, isNot(contains(text)), reason: '$path 仍包含英文界面文案或原始错误：$text');
      }
    }
  });
}
