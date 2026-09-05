import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/obs_connection_service.dart';

typedef ObsConnectCallback = Future<void> Function({
  String? password,
  String? port,
});

/// A beginner-facing OBS connection form.
///
/// This widget deliberately leaves connection and validation to the service.
/// The form only collects optional credentials and reports the user's action.
class ObsConnectionCard extends StatefulWidget {
  const ObsConnectionCard({
    super.key,
    this.isChecking = false,
    this.connected = false,
    this.detail,
    this.error,
    this.host,
    this.port,
    this.stage = ObsSetupStage.configNotFound,
    this.onConnect,
    this.onUseAutomatic,
    this.previewBytes,
    this.previewSceneName,
    this.previewError,
    this.isRefreshingPreview = false,
    this.onRefreshPreview,
  });

  final bool isChecking;
  final bool connected;
  final String? detail;
  final String? error;
  final String? host;
  final int? port;

  /// Why the connection is not usable, so the manual fields can reveal
  /// themselves exactly when they are the answer and stay out of the way
  /// otherwise. Afterimage reads the port and password out of OBS's own
  /// configuration in the normal case, so a stranger should never be shown an
  /// empty password box that implies they have done something wrong.
  final ObsSetupStage stage;
  final ObsConnectCallback? onConnect;
  final Future<void> Function()? onUseAutomatic;
  final Uint8List? previewBytes;
  final String? previewSceneName;
  final String? previewError;
  final bool isRefreshingPreview;
  final Future<void> Function()? onRefreshPreview;

  @override
  State<ObsConnectionCard> createState() => _ObsConnectionCardState();
}

class _ObsConnectionCardState extends State<ObsConnectionCard> {
  late final TextEditingController _passwordController =
      TextEditingController();
  late final TextEditingController _portController = TextEditingController();
  bool _showAdvanced = false;
  bool _advancedEdited = false;

  /// Open the manual fields unprompted only when they are genuinely the fix:
  /// OBS rejected the credentials Afterimage found. Every other failure has a
  /// better instruction than "type a port number".
  bool get _revealAdvanced => widget.stage == ObsSetupStage.authRequired;

  @override
  void initState() {
    super.initState();
    _portController.text = widget.port?.toString() ?? '';
  }

  @override
  void didUpdateWidget(covariant ObsConnectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPort = widget.port?.toString() ?? '';
    if (nextPort.isNotEmpty &&
        nextPort != oldWidget.port?.toString() &&
        !_portController.value.composing.isValid) {
      _portController.text = nextPort;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor =
        widget.connected ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    final statusText = widget.isChecking
        ? 'Connecting…'
        : widget.connected
            ? 'Connected'
            : 'Needs connection';
    final connectionDetail = widget.error ??
        widget.detail ??
        'Open OBS first, then connect it here. Afterimage will use OBS to save your video and game sound.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AfterimageTheme.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  connectionDetail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              _StatusLabel(label: statusText, color: statusColor),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.connected && widget.host != null)
            Text(
              'Connected to ${widget.host}:${widget.port ?? 4455}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: statusColor,
                  ),
            ),
          if (widget.previewBytes != null) ...[
            const SizedBox(height: 14),
            _Preview(
              bytes: widget.previewBytes!,
              sceneName: widget.previewSceneName,
            ),
          ] else if (widget.previewError != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.previewError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFFCACA),
                    height: 1.35,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('obs-connect'),
                onPressed: widget.isChecking || widget.onConnect == null
                    ? null
                    : () => unawaited(_connect()),
                icon: widget.isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(widget.connected
                        ? Icons.refresh_rounded
                        : Icons.link_rounded),
                label: Text(widget.connected ? 'Reconnect' : 'Connect OBS'),
              ),
              if (widget.onUseAutomatic != null)
                OutlinedButton(
                  key: const ValueKey('obs-use-automatic'),
                  onPressed: widget.isChecking
                      ? null
                      : () => unawaited(widget.onUseAutomatic!()),
                  child: const Text('Use automatic setup'),
                ),
              if (widget.connected && widget.onRefreshPreview != null)
                OutlinedButton.icon(
                  key: const ValueKey('obs-refresh-preview'),
                  onPressed: widget.isRefreshingPreview
                      ? null
                      : () => unawaited(widget.onRefreshPreview!()),
                  icon: widget.isRefreshingPreview
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: const Text('Refresh preview'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              // ExpansionTile reads `initiallyExpanded` only when its state is
              // first created, so a card that was already on screen as
              // `unreachable` would stay collapsed when the stage later became
              // `authRequired`. Folding the reveal into the key forces a fresh
              // state at that transition, which is the moment the password
              // field is the whole point.
              key: ValueKey('obs-advanced-$_revealAdvanced'),
              initiallyExpanded: _showAdvanced || _revealAdvanced,
              onExpansionChanged: (value) => setState(() {
                _showAdvanced = value;
              }),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Connection options'),
              subtitle: const Text(
                'Only needed when automatic setup cannot connect.',
              ),
              children: [
                TextFormField(
                  key: const ValueKey('obs-port'),
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _advancedEdited = true,
                  decoration: const InputDecoration(
                    labelText: 'OBS port',
                    hintText: 'Usually 4455',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const ValueKey('obs-password'),
                  controller: _passwordController,
                  obscureText: true,
                  onChanged: (_) => _advancedEdited = true,
                  decoration: const InputDecoration(
                    labelText: 'OBS password, if enabled',
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Your password is used for this connection only and is not saved here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() {
    final connect = widget.onConnect!;
    if (!_advancedEdited) {
      return connect();
    }
    return connect(
      password: _passwordController.text,
      port: _portController.text,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.bytes, required this.sceneName});

  final Uint8List bytes;
  final String? sceneName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: Text(
                  'OBS sent a preview that could not be displayed. Check the OBS preview directly.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          if (sceneName != null)
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(
                    sceneName!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
