part of 'agent_page.dart';

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final double fontSize;
  final bool streaming;

  const _Bubble({super.key, required this.msg, this.fontSize = 15, this.streaming = false});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
      );
    }
  }

  String get _part {
    switch (msg.kind) {
      case ChatKind.toolUse:
        return 'toolUse';
      case ChatKind.toolResult:
      case ChatKind.stepResult:
        return 'toolResult';
      case ChatKind.reasoning:
        return 'reasoning';
      case ChatKind.error:
        return 'error';
      case ChatKind.plan:
        return 'plan';
      case ChatKind.status:
        return msg.meta?['part']?.toString() ?? 'status';
      case ChatKind.text:
        return msg.meta?['part']?.toString() ?? 'text';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = fontSize;
    final part = _part;

    if (msg.kind == ChatKind.plan) {
      return _ConfirmPlanCard(msg: msg, fontSize: fs);
    }

    final isUser = msg.role == 'user';
    if (isUser) {
      if (msg.content.startsWith('用户已确认并执行以下命令：')) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已确认执行，Agent 继续处理中',
                  style: TextStyle(fontSize: fs - 2.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth * 0.78 : 280.0;
          return Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onLongPress: () => _copy(context, msg.content),
              child: Container(
                constraints: BoxConstraints(maxWidth: maxW),
                margin: const EdgeInsets.only(bottom: 8, left: 40),
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: fs > 16 ? 9 : 7),
                decoration: const BoxDecoration(
                  color: AppColors.userBubble,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: SelectableText(
                  msg.content,
                  style: TextStyle(height: 1.35, color: Colors.white, fontSize: fs - 0.5),
                ),
              ),
            ),
          );
        },
      );
    }

    if (part == 'toolUse' || part == 'toolResult') {
      final collapse = context.select((AppState s) => s.agentCollapseTools);
      return _MinisToolBlock(
        msg: msg,
        part: part,
        fontSize: fs,
        collapseSuccess: collapse,
        onCopy: () => _copy(context, _copyText),
      );
    }

    if (part == 'status' || msg.kind == ChatKind.status) {
      final stop = msg.meta?['interrupted'] == true || msg.content.contains('Stopped') || msg.content.contains('Canceled');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Row(
          children: [
            if (stop) ...[
              const Icon(Icons.stop_circle_outlined, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                msg.content,
                style: TextStyle(
                  fontSize: fs - 2.5,
                  color: stop ? AppColors.warning : AppColors.textMuted,
                  fontWeight: stop ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.kind == ChatKind.reasoning || part == 'reasoning') {
      if (!context.select((AppState s) => s.agentShowReasoning)) {
        return const SizedBox.shrink();
      }
      return _ReasoningBlock(
        content: msg.content,
        fontSize: fs,
        interrupted: msg.meta?['interrupted'] == true,
        onCopy: () => _copy(context, msg.content),
      );
    }

    if (msg.kind == ChatKind.error || part == 'error') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.errorPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.errorBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.dangerSoft),
                const SizedBox(width: 6),
                Text(
                  'Error',
                  style: TextStyle(fontSize: fs - 3, fontWeight: FontWeight.w700, color: AppColors.dangerSoft),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _copy(context, msg.content),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy_all, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _MdBody(data: msg.content, baseColor: AppColors.dangerSoft, fontSize: fs - 1),
          ],
        ),
      );
    }

    final streamMd = context.read<AppState>().streamMarkdown;
    final useMd = !streaming || streamMd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.meta?['interrupted'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Interrupted',
                style: TextStyle(fontSize: fs - 4, color: AppColors.warning, fontWeight: FontWeight.w700),
              ),
            ),
          if (useMd)
            _MdBody(data: msg.content, baseColor: AppColors.text, fontSize: fs)
          else
            SelectableText(
              msg.content,
              style: TextStyle(fontSize: fs, height: 1.45, color: AppColors.text),
            ),
          if (streaming)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _BlinkCursor(fontSize: fs),
            ),
        ],
      ),
    );
  }

  String get _copyText {
    final cmd = msg.meta?['command']?.toString() ?? '';
    if (cmd.isNotEmpty && msg.content.isNotEmpty) return '\$ $cmd\n${msg.content}';
    if (cmd.isNotEmpty) return cmd;
    return msg.content;
  }
}
