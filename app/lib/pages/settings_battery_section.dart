part of 'settings_page.dart';

extension _SettingsPageBatterySection on _SettingsPageState {
  Widget _batterySection(AppState state) {
    return _section(
      icon: Icons.battery_charging_full,
      accent: AppColors.success,
      title: '电池与后台运行',
      subtitle: '提高应用后台存活能力',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Battery optimization', style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            state.batteryIgnored ? 'Ignored' : 'Not ignored',
            style: TextStyle(
              fontSize: 11.5,
              color: state.batteryIgnored ? AppColors.success : AppColors.warning,
            ),
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              await state.requestBatteryExempt();
              _toast(state.batteryIgnored ? 'granted' : 'check system settings');
            },
            child: const Text('申请权限'),
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
