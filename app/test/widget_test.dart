import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

void main() {
  test('buildAppTheme is dark Material 3', () {
    final t = buildAppTheme();
    expect(t.useMaterial3, isTrue);
    expect(t.brightness, equals(Brightness.dark));
    expect(t.scaffoldBackgroundColor, AppColors.bg);
  });

  test('AppColors tokens are stable', () {
    expect(AppColors.bg.toARGB32(), 0xFF0D1117);
    expect(AppColors.danger.toARGB32(), 0xFFF85149);
    expect(AppColors.success.toARGB32(), 0xFF3FB950);
  });
}
