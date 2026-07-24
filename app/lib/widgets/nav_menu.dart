import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

/// Destinations shared by bottom bar and top-left menu.
class AppNav {
  static const labels = ['主机', 'Agent', '终端', '文件', '记录', '设置'];
  static const icons = [
    Icons.dns_outlined,
    Icons.smart_toy_outlined,
    Icons.terminal,
    Icons.folder_outlined,
    Icons.history,
    Icons.settings_outlined,
  ];
  static const selectedIcons = [
    Icons.dns,
    Icons.smart_toy,
    Icons.terminal,
    Icons.folder,
    Icons.history,
    Icons.settings,
  ];
}

/// Provides tab index + switcher to pages (for top-left menu mode).
class NavScope extends InheritedWidget {
  const NavScope({
    super.key,
    required this.index,
    required this.go,
    required this.menuMode,
    required super.child,
  });

  final int index;
  final ValueChanged<int> go;
  final bool menuMode;

  static NavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavScope>();

  @override
  bool updateShouldNotify(NavScope old) =>
      index != old.index || menuMode != old.menuMode;
}

/// Leading control shown only when navMode == menu.
class NavMenuButton extends StatelessWidget {
  const NavMenuButton({super.key, this.color});

  final Color? color;

  /// Use as AppBar.leading — returns null in bottom-nav mode so title is not indented.
  static Widget? leadingOf(BuildContext context, {Color? color}) {
    final nav = NavScope.maybeOf(context);
    if (nav == null || !nav.menuMode) return null;
    return NavMenuButton(color: color);
  }

  static double leadingWidthOf(BuildContext context) {
    final nav = NavScope.maybeOf(context);
    if (nav == null || !nav.menuMode) return 0;
    return 44;
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavScope.maybeOf(context);
    if (nav == null || !nav.menuMode) {
      return const SizedBox.shrink();
    }
    final c = color ?? AppColors.text;
    return PopupMenuButton<int>(
      tooltip: '功能菜单',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      onSelected: nav.go,
      itemBuilder: (_) => [
        for (var i = 0; i < AppNav.labels.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Row(
              children: [
                Icon(
                  nav.index == i ? AppNav.selectedIcons[i] : AppNav.icons[i],
                  size: 18,
                  color: nav.index == i ? AppColors.accentSoft : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppNav.labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: nav.index == i ? FontWeight.w700 : FontWeight.w400,
                      color: nav.index == i ? AppColors.accentSoft : AppColors.text,
                    ),
                  ),
                ),
                if (nav.index == i)
                  const Icon(Icons.check, size: 16, color: AppColors.accentSoft),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 40,
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu, size: 20, color: c),
            Icon(Icons.arrow_drop_down, size: 16, color: c.withAlpha(0xAA)),
          ],
        ),
      ),
    );
  }
}
