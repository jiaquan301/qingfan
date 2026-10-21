import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/qingfan_controller.dart';
import 'q_style.dart';

/// Settings are live and autosaved. No duplicate topmost toggle or save CTA.
class SettingsPane extends StatefulWidget {
  const SettingsPane({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final QingfanController controller;
  final VoidCallback onClose;

  @override
  State<SettingsPane> createState() => _SettingsPaneState();
}

class _SettingsPaneState extends State<SettingsPane> {
  late final List<TextEditingController> _numbers;
  late final List<FocusNode> _focusNodes;
  static const _labels = ['专注时间', '短休息', '长休息'];

  @override
  void initState() {
    super.initState();
    final e = widget.controller.engine;
    _numbers = [
      TextEditingController(text: e.focusMinutes.toString()),
      TextEditingController(text: e.shortBreakMinutes.toString()),
      TextEditingController(text: e.longBreakMinutes.toString()),
    ];
    _focusNodes = List.generate(3, (_) => FocusNode());
    for (var i = 0; i < 3; i++) {
      final index = i;
      _focusNodes[i].addListener(() {
        if (!_focusNodes[index].hasFocus) _commit(index);
      });
    }
  }

  List<int> get _durations {
    final e = widget.controller.engine;
    return [e.focusMinutes, e.shortBreakMinutes, e.longBreakMinutes];
  }

  void _commit(int index) {
    final before = _durations;
    final parsed = int.tryParse(_numbers[index].text.trim());
    final corrected = (parsed ?? before[index]).clamp(1, 180);
    final values = List<int>.from(before);
    values[index] = corrected;
    widget.controller.configureTimes(values[0], values[1], values[2]);
    _numbers[index].value = TextEditingValue(
      text: corrected.toString(),
      selection: TextSelection.collapsed(offset: corrected.toString().length),
    );
  }

  void _step(int index, int delta) {
    _focusNodes[index].unfocus();
    final values = _durations;
    final next = (values[index] + delta).clamp(1, 180);
    widget.controller.configureTimes(
      index == 0 ? next : values[0],
      index == 1 ? next : values[1],
      index == 2 ? next : values[2],
    );
    _numbers[index].value = TextEditingValue(
      text: next.toString(),
      selection: TextSelection.collapsed(offset: next.toString().length),
    );
  }

  void _close() {
    for (var i = 0; i < 3; i++) {
      _commit(i);
    }
    widget.onClose();
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    for (final controller in _numbers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _durationRow(int index) {
    final current = _durations[index];
    return SizedBox(
      height: 57,
      child: Row(
        children: [
          Expanded(child: Text(_labels[index], style: QStyle.section)),
          Container(
            width: 146,
            height: 39,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              border: Border.all(color: QStyle.line),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                _stepButton(
                  key: Key('durationMinus$index'),
                  icon: Icons.remove_rounded,
                  tooltip: '${_labels[index]}减少一分钟',
                  enabled: current > 1,
                  onPressed: () => _step(index, -1),
                ),
                Expanded(
                  child: TextField(
                    key: Key('durationInput$index'),
                    controller: _numbers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    style: QStyle.section.copyWith(
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: (_) => _commit(index),
                    onTapOutside: (_) => _focusNodes[index].unfocus(),
                  ),
                ),
                _stepButton(
                  key: Key('durationPlus$index'),
                  icon: Icons.add_rounded,
                  tooltip: '${_labels[index]}增加一分钟',
                  enabled: current < 180,
                  onPressed: () => _step(index, 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(
            width: 25,
            child: Text('分', style: QStyle.detail),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 17),
        constraints: const BoxConstraints.tightFor(width: 34, height: 36),
        padding: EdgeInsets.zero,
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Material(
      color: QStyle.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 17, 22, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QPanelHeader(title: '偏好设置', onClose: _close),
            const SizedBox(height: 18),
            Text('计时', style: QStyle.detail),
            const SizedBox(height: 7),
            for (var i = 0; i < 3; i++) _durationRow(i),
            const SizedBox(height: 16),
            Text('外观', style: QStyle.detail),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  const Expanded(
                    child: Text('背景透明度', style: QStyle.section),
                  ),
                  SizedBox(
                    width: 166,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: QStyle.jade,
                        inactiveTrackColor: QStyle.line,
                        thumbColor: QStyle.jade,
                      ),
                      child: Slider(
                        key: const Key('glassOpacity'),
                        value: c.glassOpacity,
                        min: .7,
                        max: 1,
                        divisions: 6,
                        onChanged: c.setOpacity,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 43,
                    child: Text(
                      '${(c.glassOpacity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: QStyle.section.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('修改会自动保存，并实时应用于表盘。', style: QStyle.detail),
            const Spacer(),
            Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '青番 · 让专注回归简单',
                style: QStyle.detail.copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
