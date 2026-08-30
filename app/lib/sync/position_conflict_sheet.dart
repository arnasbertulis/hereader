import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/database.dart' as db;
import '../data/library_repository.dart';
import '../reading/library_book.dart';
import 'sync_engine.dart';

/// One candidate position, resolved against this device's copy of the book.
class _Candidate {
  final Locator locator;

  /// Where this actually lands, or null if the block is not in this copy.
  ///
  /// Resolved here rather than taken from the payload: the token index a
  /// client sends is an unverified hint for the service's divergence check,
  /// and showing it to a reader would promise a place they will not land in
  /// if the two disagree.
  final int? tokenIndex;

  /// The book text this position was resolved against, kept so progress can
  /// be read from [TokenizedText.progressAt] instead of a second copy of its
  /// arithmetic.
  final TokenizedText? text;

  const _Candidate({
    required this.locator,
    required this.tokenIndex,
    required this.text,
  });

  bool get isResolvable => tokenIndex != null;

  double? get progress =>
      tokenIndex == null || text == null ? null : text!.progressAt(tokenIndex!);

  static _Candidate from(Map<String, dynamic> payload, TokenizedText? text) {
    final locator = Locator(
      blockId: payload['blockId'] as String,
      charOffset: (payload['charOffset'] as num?)?.toInt() ?? 0,
      parserVersion: (payload['parserVersion'] as num?)?.toInt() ?? 0,
    );

    return _Candidate(
      locator: locator,
      tokenIndex: text?.indexOf(locator),
      text: text,
    );
  }
}

/// Asks the reader which position they meant.
///
/// The service surfaces a conflict only when two devices are far enough
/// apart that picking one silently would drop the reader in the wrong part
/// of the book. Everything closer resolves without asking, so anything
/// reaching this screen is a real question.
class PositionConflictSheet extends StatefulWidget {
  final db.PositionConflict conflict;
  final String bookTitle;
  final LibraryRepository repository;
  final SyncEngine sync;

  /// Overridable so a test can resolve a candidate's position without going
  /// through the real [BookImporter]'s `compute()` isolate, the way
  /// `FreeBooksScreen.bookImporter` already does.
  final BookImporter bookImporter;

  const PositionConflictSheet({
    super.key,
    required this.conflict,
    required this.bookTitle,
    required this.repository,
    required this.sync,
    this.bookImporter = const BookImporter(),
  });

  /// Shows the sheet and settles the conflict with whatever is chosen.
  ///
  /// Not dismissible: leaving it unanswered means the question returns on
  /// the next sync, which is worse than deciding now. Nothing is lost by
  /// choosing, since the reader can rewind once they are reading.
  static Future<void> show(
    GlobalKey<NavigatorState> navigatorKey, {
    required db.PositionConflict conflict,
    required String bookTitle,
    required LibraryRepository repository,
    required SyncEngine sync,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return Future.value();

    return showModalBottomSheet<void>(
      context: navigator.context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => PositionConflictSheet(
        conflict: conflict,
        bookTitle: bookTitle,
        repository: repository,
        sync: sync,
      ),
    );
  }

  @override
  State<PositionConflictSheet> createState() => _PositionConflictSheetState();
}

class _PositionConflictSheetState extends State<PositionConflictSheet> {
  _Candidate? _ours;
  _Candidate? _theirs;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// Parses the book so both positions can be reported as where they
  /// actually land.
  ///
  /// Costs a few hundred milliseconds, which is acceptable for a question
  /// asked rarely and answered once.
  Future<void> _resolve() async {
    TokenizedText? text;

    try {
      final stored = await widget.repository.storedBookOf(
        widget.conflict.bookId,
      );
      if (stored != null) {
        text = (await widget.bookImporter.reopenStored(
          stored.bytes,
          sourceFormat: BookSourceFormat.fromName(stored.sourceFormat),
          id: widget.conflict.bookId,
          title: stored.title,
        )).text;
      }
    } catch (_) {
      // The book is not on this device, or will not parse. Both positions
      // are then unresolvable, which the sheet says plainly.
    }

    if (!mounted) return;

    setState(() {
      _ours = _Candidate.from(
        jsonDecode(widget.conflict.oursJson) as Map<String, dynamic>,
        text,
      );
      _theirs = _Candidate.from(
        jsonDecode(widget.conflict.theirsJson) as Map<String, dynamic>,
        text,
      );
      _loading = false;
    });
  }

  Future<void> _choose(_Candidate candidate) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.sync.resolveConflict(
        serverId: widget.conflict.serverId,
        bookId: widget.conflict.bookId,
        chosen: candidate.locator,
        // The resolved index, not the hint that arrived: the service uses
        // this to judge the next divergence, and a wrong value there means
        // a prompt that was not needed or a missed one that was.
        tokenIndex: candidate.tokenIndex ?? 0,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'Could not save that choice. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final ours = _ours!;
    final theirs = _theirs!;

    final furtherIsTheirs =
        ours.tokenIndex != null &&
        theirs.tokenIndex != null &&
        theirs.tokenIndex! > ours.tokenIndex!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Two places in this book', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'You read ${widget.bookTitle} on more than one device. '
              'Where would you like to carry on?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            _PositionOption(
              candidate: ours,
              onPressed: _busy || !ours.isResolvable
                  ? null
                  : () => _choose(ours),
              emphasised: !furtherIsTheirs,
            ),
            const SizedBox(height: 12),
            _PositionOption(
              candidate: theirs,
              onPressed: _busy || !theirs.isResolvable
                  ? null
                  : () => _choose(theirs),
              emphasised: furtherIsTheirs,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              'Whichever you pick becomes the position on every device. '
              'You can still rewind once you are reading.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One choice.
///
/// Labelled by where it is in the book rather than which device wrote it.
/// The service's idea of "ours" is whichever write last won, which is not
/// reliably this device, and a reader cares where they will land rather than
/// which machine put it there.
class _PositionOption extends StatelessWidget {
  final _Candidate candidate;
  final VoidCallback? onPressed;

  /// Marks the position further into the book. Emphasised, not chosen:
  /// furthest is usually what a reader wants and not always.
  final bool emphasised;

  const _PositionOption({
    required this.candidate,
    required this.onPressed,
    this.emphasised = false,
  });

  String get _label {
    if (!candidate.isResolvable) return 'Not in this copy of the book';

    final progress = candidate.progress;
    if (progress == null) return 'Around word ${candidate.tokenIndex! + 1}';

    return '${(progress * 100).round()}% through';
  }

  String get _detail => candidate.isResolvable
      ? 'Word ${candidate.tokenIndex}'
      : 'This position was saved from a differently parsed copy';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(_label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _detail,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return emphasised
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

/// Watches for conflicts and asks about them one at a time.
///
/// Shows the sheet through a navigator key rather than the build context, so
/// a divergence arriving mid-chapter is asked about immediately rather than
/// waiting for the reader to return to the library.
class ConflictWatcher extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const ConflictWatcher({
    super.key,
    required this.repository,
    required this.sync,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<ConflictWatcher> createState() => _ConflictWatcherState();
}

class _ConflictWatcherState extends State<ConflictWatcher> {
  bool _showing = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();

    // Syncing on resume rather than only on a five minute timer: a reader
    // returning to this device has probably just put down another one, and
    // that is exactly when a divergence exists to be found.
    _lifecycle = AppLifecycleListener(onResume: () => widget.sync.syncNow());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<db.PositionConflict>>(
      stream: widget.repository.watchConflicts(),
      builder: (context, snapshot) {
        final conflicts = snapshot.data ?? const [];

        if (conflicts.isNotEmpty && !_showing) {
          // After the frame: showing a sheet during build is not allowed,
          // and the stream fires during one.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _prompt(conflicts.first);
          });
        }

        return widget.child;
      },
    );
  }

  Future<void> _prompt(db.PositionConflict conflict) async {
    if (_showing) return;
    _showing = true;

    try {
      final books = await widget.repository.watchLibrary().first;
      if (!mounted) return;

      final book = books.where((b) => b.id == conflict.bookId).firstOrNull;

      await PositionConflictSheet.show(
        widget.navigatorKey,
        conflict: conflict,
        bookTitle: book?.title ?? 'this book',
        repository: widget.repository,
        sync: widget.sync,
      );
    } finally {
      _showing = false;
    }
  }
}
