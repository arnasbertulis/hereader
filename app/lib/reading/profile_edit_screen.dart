import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'profile_presentation.dart';

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
            _Preview(profile: _draft),

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
                selected: {presentation.polarity},
                onSelectionChanged: _editable
                    ? (selected) => _updatePresentation(
                        (p) => p.copyWith(polarity: selected.first),
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
              presentation: presentation,
              enabled: _editable,
              onChanged: (argb) =>
                  _updatePresentation((p) => p.copyWith(tintArgb: argb)),
              onReset: presentation.tintArgb == null
                  ? null
                  : () => _updatePresentation(
                      (p) => PresentationConfig(
                        mode: p.mode,
                        anchorX: p.anchorX,
                        anchorY: p.anchorY,
                        fontFamily: p.fontFamily,
                        fontSizePt: p.fontSizePt,
                        letterSpacingEm: p.letterSpacingEm,
                        chunkSize: p.chunkSize,
                        polarity: p.polarity,
                        // Rebuilt rather than copied: copyWith cannot set a
                        // nullable field back to null, and null here means
                        // "follow the polarity" rather than any one colour.
                        tintArgb: null,
                        orpHighlight: p.orpHighlight,
                        transitionMs: p.transitionMs,
                      ),
                    ),
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
            icon: const Icon(Icons.copy),
            label: const Text('Make an editable copy'),
          ),
        ],
      ),
    );
  }
}

/// A live sample of the profile.
///
/// Approximate rather than authoritative: this draws the word itself instead
/// of going through the reading surface, so it shows size, spacing, colour
/// and position but not the fixation highlight or the fade. If `rsvp_view`
/// converts points to logical pixels, apply the same conversion here.
class _Preview extends StatelessWidget {
  final ReadingProfile profile;
  const _Preview({required this.profile});

  @override
  Widget build(BuildContext context) {
    final presentation = profile.presentation;
    final surface = surfaceArgbFor(presentation);
    final ink = inkArgbFor(presentation.polarity);

    return Column(
      children: [
        ClipRect(
          child: Container(
            height: 200,
            width: double.infinity,
            color: colorOf(surface),
            child: Align(
              alignment: Alignment(
                presentation.anchorX * 2 - 1,
                presentation.anchorY * 2 - 1,
              ),
              child: Text(
                'reading',
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: colorOf(ink),
                  fontSize: presentation.fontSizePt,
                  fontFamily: presentation.fontFamily,
                  letterSpacing:
                      presentation.letterSpacingEm * presentation.fontSizePt,
                ),
              ),
            ),
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
            warn ? Icons.warning_amber : Icons.check_circle_outline,
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
  final PresentationConfig presentation;
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
                  presentation.tintArgb == null
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
