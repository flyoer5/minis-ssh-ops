part of 'agent_page.dart';

extension _AgentPageComposer on _AgentPageState {
  Widget _buildComposer(AppState state) {
    return ImeInset(
      usePadding: false,
      reservedBottom: kBottomNavigationBarHeight,
      fillColor: AppColors.bg,
      child: Material(
        color: AppColors.bg,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.surface2)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  expands: _expanding,
                  style: TextStyle(fontSize: state.effectiveAgentFontSize(), color: AppColors.text),
                  textInputAction: state.agentEnterToSend ? TextInputAction.send : TextInputAction.newline,
                  onChanged: (v) => setState(() => _expanding = v.length > 100),
                  onSubmitted: (_) {
                    if (state.agentEnterToSend && !(_busy || state.agentBusy)) {
                      _send(state);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: state.selectedHostId == null
                        ? '先选择主机'
                        : ((_busy || state.agentBusy)
                            ? '生成中... 可输入，发送将停止当前轮'
                            : (state.agentEnterToSend ? '输入消息 · 回车发送' : '输入消息 · 回车换行')),
                    hintStyle: const TextStyle(color: AppColors.textFaint),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.linkFocus),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    counterText: '',
                    suffixIcon: _expanding
                        ? IconButton(
                            tooltip: '收起',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() => _expanding = false);
                              _input.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: (_busy || state.agentBusy)
                    ? AppColors.danger
                    : ((!state.backendOk || state.selectedHostId == null)
                        ? AppColors.surface2
                        : AppColors.sendGreen),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: (_busy || state.agentBusy) ? '停止生成' : '发送',
                  onPressed: (!state.backendOk || state.selectedHostId == null)
                      ? null
                      : () {
                          if (_busy || state.agentBusy) {
                            _stopGeneration(state);
                          } else {
                            _send(state);
                          }
                        },
                  icon: Icon(
                    (_busy || state.agentBusy) ? Icons.stop_rounded : Icons.arrow_upward,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
