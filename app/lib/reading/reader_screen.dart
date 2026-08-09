import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'library_book.dart';
import 'profile_presentation.dart';
import 'rsvp_view.dart';

/// Where the reader stopped.
///
/// The token index travels alongside the locator because the service has no
/// copy of the book and cannot work out how far apart two positions are
/// without it. The locator remains the authoritative position; this is only
/// a hint for judging divergence.
class ReadingResult {
  final Locator locator;
  final int tokenIndex;

  const ReadingResult({required this.locator, required this.tokenIndex});
}

/// Full-screen reading surface for a book.
///
/// Pops with a [ReadingResult] so the library can record and sync it.
class ReaderScreen extends StatefulWidget {
  final LibraryBook book;
  final LibraryRepository repository;

  /// Supplies a clock stamp. Pass `syncEngine.issueStamp`.
  final Future<String> Function() issueStamp;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.repository,
    required this.issueStamp,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PlaybackSession _session;
  StreamSubscription<PlaybackUpdate>? _sub;
  PlaybackUpdate? _update;

  /// Standard until the stored choice loads. The session is built
  /// synchronously in [initState] and reading can begin before a database
  /// read returns, so the profile is swapped in rather than waited for.
  ReadingProfile _profile = Presets.standard;

  @override
  void initState() {
    super.initState();
    _session = PlaybackSession(
      tokens: widget.book.text.tokens,
      profile: _profile,
      startIndex: widget.book.resumeIndex,
    );
    _sub = _session.updates.listen((u) {
      if (mounted) setState(() => _update = u);
    });

    _restoreProfile();
  }

  Future<void> _restoreProfile() async {
    final profile = await widget.repository.activeProfile();
    if (!mounted || profile.id == _profile.id) return;

    setState(() {
      _profile = profile;
      _session.profile = profile;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.dispose();
    super.dispose();
  }

  ReadingResult? get _result {
    final locator = widget.book.text.locatorAt(_session.index);
    if (locator == null) return null;

    return ReadingResult(locator: locator, tokenIndex: _session.index);
  }

  void _toggle() {
    if (_session.state == PlaybackState.playing ||
        _session.state == PlaybackState.awaitingAdvance) {
      _session.pause();
    } else {
      _session.play();
    }
  }

  void _onSurfaceTap() {
    if (_session.state == PlaybackState.awaitingAdvance) {
      _session.advance();
    } else {
      _toggle();
    }
  }

  /// Switches profile mid-book.
  ///
  /// Lists what is actually on this device rather than the built-in presets
  /// alone, so a profile made in settings or synced from another device can
  /// be chosen here. Making and editing profiles lives in settings; this is
  /// only a switcher.
  Future<void> _pickProfile() async {
    _session.pause();

    final chosen = await showModalBottomSheet<ReadingProfile>(
      context: context,
      builder: (_) => SafeArea(
        child: StreamBuilder<List<ReadingProfile>>(
          stream: widget.repository.watchProfiles(),
          builder: (context, snapshot) {
            final profiles = snapshot.data;
            if (profiles == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return ListView(
              shrinkWrap: true,
              children: [
                for (final profile in profiles)
                  ListTile(
                    title: Text(profile.name),
                    subtitle: Text(describeProfile(profile)),
                    selected: profile.id == _profile.id,
                    onTap: () => Navigator.of(context).pop(profile),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      _profile = chosen;
      _session.profile = chosen;
    });

    // Remembered on this device only. Which profile is in use is not synced:
    // a phone read outdoors and a desktop in a dim room can want different
    // ones, and a shared pointer would have each undo the other.
    await widget.repository.setActiveProfile(
      chosen.id,
      hlc: await widget.issueStamp(),
    );
  }

  void _close() => Navigator.of(context).pop(_result);

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    final showControls = state != PlaybackState.playing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _onSurfaceTap,
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              _session.advance,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _session.rewind,
          const SingleActivator(LogicalKeyboardKey.escape): _close,
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
                      presentation: _profile.presentation,
                    ),
                  ),
                  if (state == PlaybackState.finished)
                    const Center(child: Text('End of book')),
                  if (showControls)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _Controls(
                        state: state,
                        progress: widget.book.text.progressAt(_session.index),
                        onClose: _close,
                        onRewind: () => _session.rewind(5),
                        onToggle: _toggle,
                        onProfile: _pickProfile,
                      ),
                    ),
                ],
              ),
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
  final VoidCallback onClose;
  final VoidCallback onRewind;
  final VoidCallback onToggle;
  final VoidCallback onProfile;

  const _Controls({
    required this.state,
    required this.progress,
    required this.onClose,
    required this.onRewind,
    required this.onToggle,
    required this.onProfile,
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
                  onPressed: onClose,
                  iconSize: 32,
                  icon: const Icon(Icons.close),
                  tooltip: 'Back to library',
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
                  icon: Icon(
                    state == PlaybackState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(label),
                ),
                IconButton.filledTonal(
                  onPressed: onProfile,
                  iconSize: 32,
                  icon: const Icon(Icons.tune),
                  tooltip: 'Reading profile',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
