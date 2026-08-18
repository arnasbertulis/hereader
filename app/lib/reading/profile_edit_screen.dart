import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/app_icons.dart';
import 'profile_presentation.dart';
import 'rsvp_view.dart';

/// Identifies the switch that puts a profile back to following the app theme.
///
/// Three `SwitchListTile`s sit on this screen, so a finder by type alone
/// cannot say which. The alternative is the switch's own title, which would
/// tie `reading_surface_test.dart` to a line of copy that has nothing to do
/// with what the test is checking. Same argument as
/// [readerPlayButtonKey] in `reader_screen.dart`.
const Key profileFollowAppKey = Key('profile-follow-app');

/// Edits one reading profile.
///
/// A preset opens read-only with a button to copy it. The alternative —
/// letting the controls move and prompting on the first change — puts a
/// dialog in front of a reader mid-drag on a slider, which is worse than one
/// deliberate tap up front.
///
/// Changes are saved when the screen closes rather than on every control
/// movement. A save queues a sync event, and one per keystroke in the name
/// field would fill the outbox with intermediate states no device needs.
class ProfileEditScreen extends StatefulWidget {
  final ReadingProfile profile;
  final LibraryRepository repository;
  final Future<String> Function() issueStamp;

  const ProfileEditScreen({
    super.key,
    required this.profile,
    required this.repository,
    required this.issueStamp,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late ReadingProfile _draft = widget.profile;
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );

  bool _dirty = false;

  /// Set once a preset has been copied, so the screen pops with the copy and
  /// the caller can move the reader's selection onto it.
  bool _forked = false;

  bool get _editable => !_draft.isBuiltIn;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // -- editing -------------------------------------------------------

  void _update(ReadingProfile Function(ReadingProfile) change) {
    setState(() {
      _draft = change(_draft);
      _dirty = true;
    });
  }

  void _updatePacing(PacingConfig Function(PacingConfig) change) =>
      _update((p) => p.copyWith(pacing: change(p.pacing)));

  void _updatePresentation(
    PresentationConfig Function(PresentationConfig) change,
  ) => _update((p) => p.copyWith(presentation: change(p.presentation)));

  Future<void> _makeCopy() async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = _draft.fork(id: ReadingProfile.newId());

    await widget.repository.saveProfile(copy, hlc: await widget.issueStamp());
    if (!mounted) return;

    setState(() {
      _draft = copy;
      _name.text = copy.name;
      _forked = true;
      _dirty = false;
    });

    messenger.showSnackBar(
      SnackBar(
        content: Text('Editing a copy. ${widget.profile.name} is unchanged.'),
      ),
    );
  }

  Future<void> _saveAndClose() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_dirty && _editable) {
      try {
        await widget.repository.saveProfile(
          _draft,
          hlc: await widget.issueStamp(),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save this profile: $e')),
        );
      }
    }

    // The copy is what the caller needs to know about; an ordinary edit
    // reaches the list through the profiles stream on its own.
    navigator.pop(_forked ? _draft : null);
  }

  // -- build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pacing = _draft.pacing;
    final presentation = _draft.presentation;

    // Resolved once and passed down, so the preview and the contrast readout
    // under it report the pair the reader is looking at. The polarity control
    // below reads `presentation` rather than this, because a control shows
    // what the reader chose and not what the app filled in for them.
    final resolved = resolvePresentation(
      presentation,
      Theme.of(context).brightness,
    );

    // Under reader-elicited pacing the reader supplies their own timing, so
    // rate and pause controls have nothing to act on. Disabled rather than
    // hidden: a control that vanishes leaves the reader guessing what
    // changed, while a greyed one shows why it does not apply.
    final timed = pacing.kind != PacingModelKind.elicited;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editable ? _draft.name : '${_draft.name} (preset)'),
        ),
        body: ListView(
          children: [
            _Preview(profile: _draft, presentation: resolved),

            if (!_editable) _PresetBanner(onCopy: _makeCopy, name: _draft.name),

            const _SectionHeader('Name'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                enabled: _editable,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (value) => _update((p) => p.copyWith(name: value)),
              ),
            ),

            // -- pacing ------------------------------------------------
            const _SectionHeader('How the text advances'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<PacingModelKind>(
                segments: const [
                  ButtonSegment(
                    value: PacingModelKind.constant,
                    label: Text('Steady'),
                  ),
                  ButtonSegment(
                    value: PacingModelKind.lengthScaled,
                    label: Text('By length'),
                  ),
                  ButtonSegment(
                    value: PacingModelKind.elicited,
                    label: Text('Manual'),
                  ),
                ],
                selected: {pacing.kind},
                onSelectionChanged: _editable
                    ? (selected) =>
                          _updatePacing((p) => p.copyWith(kind: selected.first))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                describePacingKind(pacing.kind),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            _SettingSlider(
              label: 'Reading speed',
              value: pacing.baseWpm,
              valueLabel: '${pacing.baseWpm.round()} wpm',
              min: 60,
              max: 800,
              divisions: 74,
              enabled: _editable && timed,
              onChanged: (v) => _updatePacing((p) => p.copyWith(baseWpm: v)),
            ),

            _SettingSlider(
              label: 'Length scaling',
              value: pacing.lengthScaleStrength,
              valueLabel: pacing.lengthScaleStrength == 0
                  ? 'off'
                  : '${(pacing.lengthScaleStrength * 100).round()}%',
              min: 0,
              max: 1,
              divisions: 20,
              // At zero this model behaves exactly like the steady one, which
              // is why it is a slider rather than a second mode.
              enabled: _editable && pacing.kind == PacingModelKind.lengthScaled,
              help:
                  'How much a long word is held beyond a short one. At zero '
                  'this reads the same as Steady.',
              onChanged: (v) =>
                  _updatePacing((p) => p.copyWith(lengthScaleStrength: v)),
            ),

            _SettingSlider(
              label: 'Pause at commas',
              value: pacing.clausePause.inMilliseconds.toDouble(),
              valueLabel: '${pacing.clausePause.inMilliseconds} ms',
              min: 0,
              max: 800,
              divisions: 40,
              enabled: _editable && timed,
              onChanged: (v) => _updatePacing(
                (p) =>
                    p.copyWith(clausePause: Duration(milliseconds: v.round())),
              ),
            ),

            _SettingSlider(
              label: 'Pause at sentences',
              value: pacing.sentencePause.inMilliseconds.toDouble(),
              valueLabel: '${pacing.sentencePause.inMilliseconds} ms',
              min: 0,
              max: 1500,
              divisions: 30,
              enabled: _editable && timed,
              onChanged: (v) => _updatePacing(
                (p) => p.copyWith(
                  sentencePause: Duration(milliseconds: v.round()),
                ),
              ),
            ),

            _SettingSlider(
              label: 'Pause at paragraphs',
              value: pacing.paragraphPause.inMilliseconds.toDouble(),
              valueLabel: '${pacing.paragraphPause.inMilliseconds} ms',
              min: 0,
              max: 2000,
              divisions: 40,
              enabled: _editable && timed,
              onChanged: (v) => _updatePacing(
                (p) => p.copyWith(
                  paragraphPause: Duration(milliseconds: v.round()),
                ),
              ),
            ),

            _SettingSlider(
              label: 'Rewind on resume',
              value: _draft.rewindWords.toDouble(),
              valueLabel: _draft.rewindWords == 0
                  ? 'none'
                  : '${_draft.rewindWords} '
                        'word${_draft.rewindWords == 1 ? '' : 's'}',
              min: 0,
              max: 10,
              divisions: 10,
              enabled: _editable,
              help:
                  'How far back to step when you start again after a pause, '
                  'so you re-enter the sentence with some context.',
              onChanged: (v) =>
                  _update((p) => p.copyWith(rewindWords: v.round())),
            ),

            // -- text --------------------------------------------------
            const _SectionHeader('Text'),

            _SettingSlider(
              label: 'Type size',
              value: presentation.fontSizePt,
              valueLabel: '${presentation.fontSizePt.round()} pt',
              min: 12,
              max: 96,
              divisions: 84,
              enabled: _editable,
              onChanged: (v) =>
                  _updatePresentation((p) => p.copyWith(fontSizePt: v)),
            ),

            _SettingSlider(
              label: 'Letter spacing',
              value: presentation.letterSpacingEm,
              valueLabel: presentation.letterSpacingEm == 0
                  ? 'normal'
                  : '+${presentation.letterSpacingEm.toStringAsFixed(2)} em',
              min: 0,
              max: 0.5,
              divisions: 25,
              enabled: _editable,
              help:
                  'Extra space between letters. Reported to help dyslexic '
                  'readers, and disputed in the same year. Offered without a '
                  'claim either way.',
              onChanged: (v) =>
                  _updatePresentation((p) => p.copyWith(letterSpacingEm: v)),
            ),

            _SettingSlider(
              label: 'Position across',
              value: presentation.anchorX,
              valueLabel: '${(presentation.anchorX * 100).round()}%',
              min: 0,
              max: 1,
              divisions: 20,
              enabled: _editable,
              help:
                  'Where the word sits on screen. A blind spot to one side '
                  'is a reason to move it off centre.',
              onChanged: (v) =>
                  _updatePresentation((p) => p.copyWith(anchorX: v)),
            ),

            _SettingSlider(
              label: 'Position down',
              value: presentation.anchorY,
              valueLabel: '${(presentation.anchorY * 100).round()}%',
              min: 0,
              max: 1,
              divisions: 20,
              enabled: _editable,
              onChanged: (v) =>
                  _updatePresentation((p) => p.copyWith(anchorY: v)),
            ),

            _SettingSlider(
              label: 'Fade between words',
              value: presentation.transitionMs.toDouble(),
              valueLabel: presentation.transitionMs == 0
                  ? 'instant'
                  : '${presentation.transitionMs} ms',
              min: 0,
              max: 300,
              divisions: 30,
              enabled: _editable,
              onChanged: (v) => _updatePresentation(
                (p) => p.copyWith(transitionMs: v.round()),
              ),
              warning: fadeWarning(_draft),
            ),

            SwitchListTile(
              title: const Text('Highlight a fixation letter'),
              subtitle: const Text(
                'Marks one letter as a place to look. Offered as a '
                'preference: none of the studies behind this app tested it.',
              ),
              value: presentation.orpHighlight,
              onChanged: _editable
                  ? (v) =>
                        _updatePresentation((p) => p.copyWith(orpHighlight: v))
                  : null,
            ),

            // -- colour ------------------------------------------------
            const _SectionHeader('Colour'),

            SwitchListTile(
              key: profileFollowAppKey,
              title: const Text('Follow the app’s theme'),
              subtitle: const Text(
                'The page turns light or dark along with the rest of the '
                'app. Theme mode is set per device, so this profile can '
                'read light on a phone and dark on a desktop.',
              ),
              value: presentation.polarity == null,
              onChanged: _editable
                  ? (following) => _updatePresentation(
                      // Switching off pins the polarity the app was already
                      // supplying, rather than the class default. The reader
                      // is looking at a surface when they reach for this, and
                      // pinning any other one would change the page they just
                      // decided to keep.
                      (p) =>
                          p.withPolarity(following ? null : resolved.polarity),
                    )
                  : null,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<Polarity>(
                segments: const [
                  ButtonSegment(
                    value: Polarity.darkOnLight,
                    label: Text('Dark on light'),
                  ),
                  ButtonSegment(
                    value: Polarity.lightOnDark,
                    label: Text('Light on dark'),
                  ),
                ],
                // The resolved value, so a profile following the app shows
                // the side it is on. An empty selection would be accurate
                // about the stored field and wrong about the page.
                selected: {resolved.polarity},
                // Disabled while the profile follows, which is how the rate
                // and pause controls behave under elicited pacing. Tapping a
                // side is also how a reader turns following off, so the
                // switch above stays the one way to reach that state.
                onSelectionChanged: _editable && presentation.polarity != null
                    ? (selected) => _updatePresentation(
                        (p) => p.withPolarity(selected.first),
                      )
                    : null,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'This sets the text colour. The background can be tinted '
                'below.',
              ),
            ),

            _BackgroundField(
              presentation: resolved,
              enabled: _editable,
              onChanged: (argb) => _updatePresentation((p) => p.withTint(argb)),
              // `withTint` replaces the hand-written PresentationConfig this
              // used to rebuild field by field. Both nullable fields on that
              // class now have one setter each that can reach null, so
              // clearing a background and clearing a polarity read the same.
              onReset: presentation.tintArgb == null
                  ? null
                  : () => _updatePresentation((p) => p.withTint(null)),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// -- pieces -------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _PresetBanner extends StatelessWidget {
  final String name;
  final VoidCallback onCopy;

  const _PresetBanner({required this.name, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name is a preset and cannot be changed.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Presets stay as they shipped so there is always a known starting '
            'point to come back to.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCopy,
            icon: const Icon(AppIcons.forkProfile),
            label: const Text('Make an editable copy'),
          ),
        ],
      ),
    );
  }
}

/// A live sample of the profile, drawn by the reading surface itself.
///
/// Not an approximation of `RsvpView` but an instance of it, which is the
/// point: a preview that draws its own sample word will disagree with the
/// real thing eventually, and this one did — it painted the polarity
/// defaults from `profile_presentation.dart` while the reader saw a
/// different set hardcoded in `rsvp_view.dart`, so the contrast readout
/// below measured colours the app never put on screen.
///
/// It runs a real [PlaybackSession] over one fixed sentence rather than
/// showing a still word. Pacing is most of what a profile decides, and the
/// speed, pause and fade controls had no feedback at all: a reader set
/// 250 wpm and found out what that meant by opening a book.
///
/// It starts paused. An accessibility app should not flash text at someone
/// who is trying to read slider labels, and a preview that animates on its
/// own would mean `pumpAndSettle` never settles in any test that opens this
/// screen.
class _Preview extends StatefulWidget {
  final ReadingProfile profile;

  /// The same profile's presentation, with its polarity already decided.
  ///
  /// Passed in rather than resolved here, so this preview and the contrast
  /// readout beneath it cannot answer that question differently. The whole
  /// profile still comes too: the session takes its pacing.
  final ResolvedPresentation presentation;

  const _Preview({required this.profile, required this.presentation});

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  /// Two sentences, a clause break, and words from two to seven letters, so
  /// every pacing control has something to act on. Fixed rather than drawn
  /// from the reader's library: a preview that changes with the book would
  /// make two profiles impossible to compare.
  static const _sample =
      'Reading, one word at a time. The words come to you, so your eyes '
      'need not go looking.';

  late final TokenizedText _text = TokenizedText.from(const [
    (id: 'preview', text: _sample),
    // Offsets here belong to no normalizer, so parserVersion is 0 for the
    // same reason the paste screen uses it: this text came from a string
    // literal, not from a parsed book.
  ], parserVersion: 0);

  late final PlaybackSession _session = PlaybackSession(
    tokens: _text.tokens,
    profile: widget.profile,
  );

  StreamSubscription<PlaybackUpdate>? _sub;

  //// The session emits nothing until something happens to it, so the first
  /// frame comes from the session's own description of itself.
  late PlaybackUpdate _update = _session.current;

  @override
  void initState() {
    super.initState();

    _sub = _session.updates.listen((update) {
      if (!mounted) return;

      // Loops rather than stopping on the last word. A preview that runs out
      // reads as something having gone wrong, and the reader is comparing
      // settings rather than finishing a text. Safe to re-enter the session
      // from here because the update stream is an asynchronous broadcast.
      if (update.state == PlaybackState.finished) {
        _session.seekToIndex(0);
        _session.play();
        return;
      }

      setState(() => _update = update);
    });
  }

  @override
  void didUpdateWidget(covariant _Preview oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Presentation reaches the surface as a prop and applies on the next
    // frame regardless. This is for pacing, which the session owns.
    if (!identical(oldWidget.profile, widget.profile)) {
      _session.profile = widget.profile;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.dispose();
    super.dispose();
  }

  /// Mirrors the reading surface: a tap advances when the profile says the
  /// reader advances, and starts or stops the stream otherwise. Previewing
  /// elicited pacing means pressing the thing yourself, which is the whole
  /// content of that setting.
  void _onTap() {
    if (_session.state == PlaybackState.awaitingAdvance) {
      _session.advance();
      return;
    }
    _toggle();
  }

  void _toggle() {
    if (_session.state == PlaybackState.playing ||
        _session.state == PlaybackState.awaitingAdvance) {
      _session.pause();
    } else {
      _session.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final surface = surfaceArgbFor(presentation);
    final ink = inkArgbFor(presentation.polarity);

    final running =
        _session.state == PlaybackState.playing ||
        _session.state == PlaybackState.awaitingAdvance;
    final awaiting = _session.state == PlaybackState.awaitingAdvance;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _onTap,
                  behavior: HitTestBehavior.opaque,
                  // Clipped because the surface honours the profile's type
                  // size, and 96pt has no reason to fit a 200px box.
                  child: ClipRect(
                    child: RsvpView(
                      update: _update,
                      presentation: presentation,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  onPressed: _toggle,
                  icon: Icon(running ? AppIcons.pause : AppIcons.play),
                  tooltip: running ? 'Stop the preview' : 'Preview reading',
                ),
              ),
              if (awaiting)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Text(
                    'Tap the preview to advance',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorOf(ink)),
                  ),
                ),
            ],
          ),
        ),
        _ContrastReadout(foregroundArgb: ink, backgroundArgb: surface),
      ],
    );
  }
}

/// Says how legible the current colours are, and does not act on it.
///
/// A reader with light sensitivity may want a low ratio deliberately. The
/// point is that nobody arrives at dark grey on black without being told.
///
/// Judges the ink against the surface, and nothing else. The fixation letter
/// has its own fixed colour that is not measured here: it is a marker rather
/// than text, and a reader who cannot make it out loses a hint rather than a
/// word. Worth revisiting if it ever becomes configurable.
class _ContrastReadout extends StatelessWidget {
  final int foregroundArgb;
  final int backgroundArgb;

  const _ContrastReadout({
    required this.foregroundArgb,
    required this.backgroundArgb,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = contrastRatio(foregroundArgb, backgroundArgb);
    final rating = rateContrast(ratio);

    final colors = Theme.of(context).colorScheme;
    final warn =
        rating == ContrastRating.low || rating == ContrastRating.veryLow;

    return Container(
      width: double.infinity,
      color: warn ? colors.errorContainer : colors.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            warn ? AppIcons.contrastWarns : AppIcons.contrastPasses,
            size: 20,
            color: warn ? colors.onErrorContainer : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${contrastLabel(rating)} — ${ratio.toStringAsFixed(1)} to 1. '
              '${contrastAdvice(rating)}',
              style: TextStyle(color: warn ? colors.onErrorContainer : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String? help;

  /// Shown below [help], in the error colour. For a value that is legal and
  /// saveable but produces something the reader probably did not intend.
  final String? warning;
  final ValueChanged<double> onChanged;

  const _SettingSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.enabled = true,
    this.help,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.disabledColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: enabled ? null : TextStyle(color: dim)),
              Text(
                valueLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: enabled ? null : dim,
                ),
              ),
            ],
          ),
          Slider(
            // Clamped because a profile written by another build may sit
            // outside the range this one offers, and Slider throws rather
            // than pinning.
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(help!, style: theme.textTheme.bodySmall),
            ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.settingWarns,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Background colour, as red, green and blue.
///
/// Sliders rather than a colour wheel: this app is used by people who cannot
/// reliably hit a small target, and three large tracks are easier than a
/// gradient square. Alpha is fixed opaque, since a translucent reading
/// background would composite against whatever the platform put behind it.
class _BackgroundField extends StatelessWidget {
  final ResolvedPresentation presentation;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReset;

  const _BackgroundField({
    required this.presentation,
    required this.enabled,
    required this.onChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final argb = surfaceArgbFor(presentation);
    final red = redOf(argb);
    final green = greenOf(argb);
    final blue = blueOf(argb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorOf(argb),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  presentation.config.tintArgb == null
                      ? 'Following the polarity — ${hexOf(argb)}'
                      : hexOf(argb),
                ),
              ),
              if (onReset != null)
                TextButton(
                  onPressed: enabled ? onReset : null,
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
        _SettingSlider(
          label: 'Red',
          value: red.toDouble(),
          valueLabel: '$red',
          min: 0,
          max: 255,
          divisions: 255,
          enabled: enabled,
          onChanged: (v) => onChanged(argbFrom(v.round(), green, blue)),
        ),
        _SettingSlider(
          label: 'Green',
          value: green.toDouble(),
          valueLabel: '$green',
          min: 0,
          max: 255,
          divisions: 255,
          enabled: enabled,
          onChanged: (v) => onChanged(argbFrom(red, v.round(), blue)),
        ),
        _SettingSlider(
          label: 'Blue',
          value: blue.toDouble(),
          valueLabel: '$blue',
          min: 0,
          max: 255,
          divisions: 255,
          enabled: enabled,
          onChanged: (v) => onChanged(argbFrom(red, green, v.round())),
        ),
      ],
    );
  }
}
