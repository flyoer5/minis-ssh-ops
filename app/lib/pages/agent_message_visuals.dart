
part of 'agent_page.dart';

class _MdBody extends StatelessWidget {
  final String data;
  final Color baseColor;
  final double fontSize;

  const _MdBody({required this.data, required this.baseColor, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, height: 1.55, color: baseColor);
    final style = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: base.copyWith(fontSize: fontSize + 6, fontWeight: FontWeight.w800),
      h2: base.copyWith(fontSize: fontSize + 4, fontWeight: FontWeight.w800),
      h3: base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
      strong: base.copyWith(fontWeight: FontWeight.w800),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: AppColors.textMuted),
      listIndent: 20,
      blockquote: base.copyWith(color: AppColors.textMuted),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize - 1.5,
        color: AppColors.codeRed,
        backgroundColor: AppColors.surface2,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      a: base.copyWith(color: AppColors.accentSoft, decoration: TextDecoration.underline),
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base.copyWith(fontSize: fontSize - 1),
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      blockSpacing: 8,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: style,
      shrinkWrap: true,
      fitContent: true,
      onTapLink: (text, href, title) {},
    );
  }
}

class _BlinkCursor extends StatefulWidget {
  final double fontSize;
  const _BlinkCursor({this.fontSize = 15});

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 530))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.15, end: 1.0).animate(_c),
      child: Text(
        '|',
        style: TextStyle(fontSize: widget.fontSize, color: AppColors.accentSoft, height: 1),
      ),
    );
  }
}

class _OvChip extends StatelessWidget {
  final String label;
  const _OvChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withAlpha(0x28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.accentSoft, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Mirrors Minis message parts:
///   toolUse    -> header: name + description, body: command (collapsed)
///   toolResult -> header: name + success, body: output (expandable)
class _MinisToolBlock extends StatefulWidget {
  final ChatMessage msg;
  final String part;
  final double fontSize;
  final bool collapseSuccess;
  final VoidCallback? onCopy;

  const _MinisToolBlock({
    required this.msg,
    required this.part,
    this.fontSize = 15,
    this.collapseSuccess = true,
    this.onCopy,
  });

  @override
  State<_MinisToolBlock> createState() => _MinisToolBlockState();
}

class _MinisToolBlockState extends State<_MinisToolBlock> {
  bool _open = false;

  bool get _autoClosed => widget.collapseSuccess && (widget.msg.meta?['success'] == true) && widget.part == 'toolResult';

  @override
  Widget build(BuildContext context) {
    final meta = widget.msg.meta ?? const {};
    final name = meta['name']?.toString() ?? 'tool';
    final desc = meta['description']?.toString() ?? '';
    final command = meta['command']?.toString() ?? widget.msg.content;
    final output = meta['output']?.toString() ?? '';
    final success = meta['success'];
    final pendingConfirm = meta['pendingConfirm'] == true;
    final color = pendingConfirm
        ? AppColors.warning
        : (success == null ? AppColors.textMuted : (success == true ? AppColors.success : AppColors.danger));

    final body = widget.part == 'toolResult' ? output : command;
    final open = _autoClosed ? _open : true;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body.isEmpty || !_autoClosed ? null : () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(
                  widget.part == 'toolResult'
                      ? (success == true ? Icons.check_circle_outline : Icons.error_outline)
                      : Icons.settings_outlined,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    desc.isNotEmpty ? desc : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: widget.fontSize - 2, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                if (body.isNotEmpty && _autoClosed)
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textFaint),
              ],
            ),
          ),
          if ((open || !_autoClosed) && body.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              body,
              style: TextStyle(fontFamily: 'monospace', fontSize: widget.fontSize - 3, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}
