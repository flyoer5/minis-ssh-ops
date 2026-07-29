part of 'agent_page.dart';

class _ReasoningBlock extends StatefulWidget {
  final String content;
  final double fontSize;
  final bool interrupted;
  final VoidCallback onCopy;

  const _ReasoningBlock({required this.content, required this.onCopy, this.fontSize = 15, this.interrupted = false});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = preview.length > 72 ? '${preview.substring(0, 72)}...' : preview;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.thinkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.thinkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 16, color: AppColors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Thinking',
                              style: TextStyle(
                                fontSize: widget.fontSize - 3,
                                fontWeight: FontWeight.w700,
                                color: AppColors.purple,
                              ),
                            ),
                            if (widget.interrupted) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Interrupted',
                                style: TextStyle(
                                  fontSize: widget.fontSize - 4,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!_open && short.isNotEmpty)
                          Text(
                            short,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: widget.fontSize - 3.5, color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCopy,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.surface2)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: widget.fontSize - 2,
                  height: 1.45,
                  color: AppColors.monoGray,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
