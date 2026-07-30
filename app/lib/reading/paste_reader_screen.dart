import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'rsvp_view.dart';

/// Paste any text and read it. Kept permanently, not scaffolding: it is the
/// quickest way to try the engine against arbitrary text, including languages
/// the tokenizer has not been tuned for.
class PasteReaderScreen extends StatefulWidget {
  const PasteReaderScreen({super.key});

  @override
  State<PasteReaderScreen> createState() => _PasteReaderScreenState();
}

class _PasteReaderScreenState extends State<PasteReaderScreen> {
  final _controller = TextEditingController();
  ReadingProfile _profile = Presets.standard;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    final tokens = Tokenizer().tokenize(_controller.text);
    if (tokens.isEmpty) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(tokens: tokens, profile: _profile),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Paste text')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _profile.id,
              decoration: const InputDecoration(
                labelText: 'Reading profile',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in Presets.all)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(() => _profile = Presets.byId(id)!);
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Paste a chapter here',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: hasText ? _start : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text('Read this'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen reading surface. Controls appear when the session is not
/// playing and get out of the way when it is.
class ReaderScreen extends StatefulWidget {
  final List<Token> tokens;
  final ReadingProfile profile;

  const ReaderScreen({
    super.key,
    required this.tokens,
    required this.profile,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PlaybackSession _session;
  StreamSubscription<PlaybackUpdate>? _sub;
  PlaybackUpdate? _update;

  @override
  void initState() {
    super.initState();
    _session = PlaybackSession(
      tokens: widget.tokens,
      profile: widget.profile,
    );
    _sub = _session.updates.listen((u) {
      if (mounted) setState(() => _update = u);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_session.state == PlaybackState.playing ||
        _session.state == PlaybackState.awaitingAdvance) {
      _session.pause();
    } else {
      _session.play();
    }
  }

  /// Tapping the surface advances under elicited pacing, and toggles
  /// play/pause otherwise.
  void _onSurfaceTap() {
    if (_session.state == PlaybackState.awaitingAdvance) {
      _session.advance();
    } else {
      _toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    final showControls = state != PlaybackState.playing;
    final progress = widget.tokens.isEmpty
        ? 0.0
        : (_session.index + 1) / widget.tokens.length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _onSurfaceTap,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _session.advance,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _session.rewind,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: GestureDetector(
            onTap: _onSurfaceTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RsvpView(
                    update: _update,
                    presentation: widget.profile.presentation,
                  ),
                ),
                if (state == PlaybackState.finished)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: Text('End of text'),
                    ),
                  ),
                if (showControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _Controls(
                      state: state,
                      progress: progress,
                      onBack: () => Navigator.of(context).maybePop(),
                      onRewind: () => _session.rewind(5),
                      onToggle: _toggle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final PlaybackState state;
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onRewind;
  final VoidCallback onToggle;

  const _Controls({
    required this.state,
    required this.progress,
    required this.onBack,
    required this.onRewind,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      PlaybackState.awaitingAdvance => 'Tap to advance',
      PlaybackState.finished => 'Done',
      _ => 'Read',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: onBack,
                  iconSize: 32,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
                IconButton.filledTonal(
                  onPressed: onRewind,
                  iconSize: 32,
                  icon: const Icon(Icons.replay_5),
                  tooltip: 'Back five words',
                ),
                FilledButton.icon(
                  onPressed: onToggle,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 56),
                  ),
                  icon: Icon(state == PlaybackState.playing
                      ? Icons.pause
                      : Icons.play_arrow),
                  label: Text(label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
