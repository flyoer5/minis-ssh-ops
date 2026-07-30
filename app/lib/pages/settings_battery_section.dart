part of 'settings_page.dart';

extension _SettingsPageBatterySection on _SettingsPageState {
  Widget _batterySection(AppState state) {
    return _section(
      icon: Icons.battery_charging_full,
      accent: AppColors.success,
      title: '后台运行',
      subtitle: '减少系统对后台任务的限制',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('电池优化豁免', style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            state.batteryIgnored ? '已允许后台运行' : '尚未获得豁免',
            style: TextStyle(
              fontSize: 11.5,
              color: state.batteryIgnored ? AppColors.success : AppColors.warning,
            ),
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              await state.requestBatteryExempt();
              _toast(state.batteryIgnored ? '已允许应用在后台运行' : '请在系统设置中允许后台运行');
            },
            child: const Text('申请豁免'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => state.openBatterySettings(),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('打开系统设置'),
          ),
        ),
      ],
    );
  }
}
