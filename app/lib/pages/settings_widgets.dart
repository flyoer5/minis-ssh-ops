part of 'settings_page.dart';

  Widget _section({
    required IconData icon,
    required Color accent,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(0x22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withAlpha(0x55)),
                  ),
                  child: Icon(icon, size: 15, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.25)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surface2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.chipBlue),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
        if (hint != null)
          Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
      ],
    );
  }

  Widget _portChip(String baseUrl) {
    var label = '端口 ?';
    try {
      final u = Uri.tryParse(baseUrl);
      if (u != null && u.hasPort) {
        label = '端口 ${u.port}';
      } else if (u != null && u.host.isNotEmpty) {
        label = u.scheme == 'https' ? '端口 443' : '端口 80';
      }
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withAlpha(0x22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accentDeep.withAlpha(0x55)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.chipBlue)),
    );
  }

  Widget _statusChip(bool ok, String text) {
    final c = ok ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(0x18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withAlpha(0x66)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, size: 12, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
