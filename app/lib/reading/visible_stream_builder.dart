import 'dart:async';

import 'package:flutter/widgets.dart';

/// A [StreamBuilder] that only applies an emission while its tab is the one
/// showing.
///
/// Home's continue tile and the Library shelf both keep a live subscription
/// to the library-summary stream even while their tab sits hidden under
/// another one — see `app_shell.dart`'s `_FadingIndexedStack`, which keeps
/// every tab mounted so the Library's scroll offset survives a look at
/// Settings. That is deliberate, but it means every timed position save
/// during playback (ADR 0011, `reader_screen.dart`'s `_saveInterval`)
/// re-emits the stream and rebuilds both hidden widgets on the frame path —
/// see issue #472.
///
/// `_FadingIndexedStack` already marks a hidden tab with
/// `TickerMode(enabled: false, ...)` so its animations pause. This widget
/// reads that same signal: while [TickerMode.valuesOf] reports the tab is
/// not showing, an emission is buffered rather than applied, so nothing
/// rebuilds.
/// The moment the tab becomes the visible one again, the latest buffered
/// emission is applied immediately, so the widget never shows a stale value.
/// A tab that is visible throughout sees every emission with no added
/// latency.
class VisibleStreamBuilder<T> extends StatefulWidget {
  const VisibleStreamBuilder({
    required this.stream,
    required this.builder,
    super.key,
  });

  final Stream<T> stream;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<VisibleStreamBuilder<T>> createState() =>
      _VisibleStreamBuilderState<T>();
}

class _VisibleStreamBuilderState<T> extends State<VisibleStreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  AsyncSnapshot<T> _applied = AsyncSnapshot<T>.nothing();
  AsyncSnapshot<T>? _pending;

  // Assume visible until the first `didChangeDependencies` reads the real
  // value, so a widget that is never hidden never buffers unnecessarily.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.stream.listen(
      (data) =>
          _onEvent(AsyncSnapshot<T>.withData(ConnectionState.active, data)),
      onError: (Object error, StackTrace stackTrace) => _onEvent(
        AsyncSnapshot<T>.withError(ConnectionState.active, error, stackTrace),
      ),
    );
  }

  void _onEvent(AsyncSnapshot<T> snapshot) {
    if (_visible) {
      setState(() => _applied = snapshot);
    } else {
      // Overwrites any earlier buffered snapshot: only the latest value
      // matters once the tab is visible again.
      _pending = snapshot;
    }
  }

  @override
  void didUpdateWidget(covariant VisibleStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream) {
      _subscription?.cancel();
      _pending = null;
      _subscribe();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible && _pending != null) {
      // Runs ahead of this frame's build, so the catch-up lands in the same
      // frame that made the tab visible again rather than one frame later.
      _applied = _pending!;
      _pending = null;
    }
    _visible = visible;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _applied);
}
