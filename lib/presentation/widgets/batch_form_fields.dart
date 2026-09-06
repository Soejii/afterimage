import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/setup_models.dart';

/// The free-text replay count, shown only for a custom batch size.
class CustomReplayCountField extends StatefulWidget {
  const CustomReplayCountField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<CustomReplayCountField> createState() => _CustomReplayCountFieldState();
}

class _CustomReplayCountFieldState extends State<CustomReplayCountField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toString());

  @override
  void didUpdateWidget(covariant CustomReplayCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value.toString()) {
      _controller.value = TextEditingValue(
        text: widget.value.toString(),
        selection:
            TextSelection.collapsed(offset: widget.value.toString().length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const ValueKey('custom-replay-count'),
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        final count = int.tryParse(value);
        if (count != null) {
          widget.onChanged(count);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Number of replays',
        helperText: 'Choose a number from 1 to 1000.',
        prefixIcon: Icon(Icons.format_list_numbered_rounded),
      ),
    );
  }
}

/// One replay-control choice, with its availability on this machine.
///
/// An unavailable mode stays selectable only when it is already the selection,
/// so the user can see why their choice is blocked. Afterimage never quietly
/// moves them to a different control method.
class InputModeTile extends StatelessWidget {
  const InputModeTile({
    super.key,
    required this.mode,
    required this.available,
    required this.availabilityDetail,
    required this.checking,
    required this.enabled,
  });

  final InputMode mode;
  final bool available;
  final String? availabilityDetail;
  final bool checking;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reportedDetail = availabilityDetail?.trim();
    final availability = checking
        ? 'Checking availability…'
        : reportedDetail != null && reportedDetail.isNotEmpty
            ? reportedDetail
            : available
                ? 'Ready on this machine.'
                : 'Availability could not be determined.';
    return RadioListTile<InputMode>(
      key: ValueKey('input-mode-${mode.name}'),
      value: mode,
      enabled: enabled,
      title: Text(_friendlyInputTitle(mode)),
      subtitle: Text('${_friendlyInputDescription(mode)} $availability'),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  String _friendlyInputTitle(InputMode mode) {
    return mode == InputMode.keyboard
        ? 'Use keyboard controls'
        : 'Use controller controls';
  }

  String _friendlyInputDescription(InputMode mode) {
    return mode == InputMode.keyboard
        ? 'Afterimage sends the replay menu keys for you.'
        : 'Afterimage sends menu input through the selected controller.';
  }
}

/// Where finished recordings are saved.
///
/// There is deliberately no default. An empty value keeps recording locked, so
/// Afterimage never picks a place on someone's disk to write video without
/// being told.
class OutputFolderField extends StatefulWidget {
  const OutputFolderField({
    super.key,
    required this.value,
    required this.enabled,
    required this.isPicking,
    required this.onChanged,
    required this.onBrowse,
  });

  final String value;
  final bool enabled;
  final bool isPicking;
  final ValueChanged<String> onChanged;
  final Future<void> Function()? onBrowse;

  @override
  State<OutputFolderField> createState() => _OutputFolderFieldState();
}

class _OutputFolderFieldState extends State<OutputFolderField> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant OutputFolderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_textController.text != widget.value &&
        widget.value != oldWidget.value) {
      _textController.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const ValueKey('output-folder'),
      controller: _textController,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: 'Choose an output folder…',
        prefixIcon: const Icon(Icons.folder_outlined),
        suffixIcon: widget.isPicking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: const ValueKey('browse-output-folder'),
                onPressed: widget.enabled && widget.onBrowse != null
                    ? () => unawaited(widget.onBrowse!())
                    : null,
                tooltip: 'Choose an output folder',
                icon: const Icon(Icons.folder_open_outlined),
              ),
      ),
    );
  }
}
