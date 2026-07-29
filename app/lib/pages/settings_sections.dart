part of 'settings_page.dart';

extension _SettingsPageSectionBuilders on _SettingsPageState {
  List<Widget> _buildSettingsSections(AppState state) {
    return [
      _backendSection(state),
      _llmSection(state),
      _displaySection(state),
      _behaviorSection(state),
      _connectivitySection(state),
      _batterySection(state),
      _dataSection(state),
      _aboutSection(state),
    ];
  }
}