import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import 'library_book.dart';

/// Height of a cover as a multiple of its width. Close enough to a trade
/// paperback that a real cover fills the box rather than being letterboxed
/// inside it.
const double kCoverAspect = 1.5;

/// Below this width the generated face has no room for a readable title —
/// the same box Home draws its continue tile cover at
/// (`_continueTileCoverWidth`, home_screen.dart) — so it falls back to a
/// glyph instead. Picked against a screenshot: issue #335.
const double _noteFaceGlyphMaxWidth = 72;

/// A book's cover, or a generated stand-in when it has none.
///
/// An EPUB whose publisher declared no cover, one whose cover failed to
/// decode, and every book imported before covers were stored all land on the
/// generated face with no title of its own — that is real content the book
/// turned out not to have, and drawing nothing there would make a grid of
/// mostly blank boxes look broken rather than plain.
///
/// A Note has no cover to be missing: its generated face carries its own
/// title, since the title *is* the tile's one piece of content. See
/// [BookSourceFormat].
class BookCoverImage extends StatelessWidget {
  /// Decides the band colour. The same book gets the same band on every
  /// device, because the id is the same on every device.
  final String bookId;

  /// Whether this is an EPUB or a Note. Only a Note's generated face shows a
  /// title; an EPUB with no cover keeps the plain band.
  final BookSourceFormat sourceFormat;

  /// The book's title, drawn on a Note's generated face above the band's
  /// width threshold. Ignored for an EPUB.
  final String title;

  /// The stored image, or null for the generated face.
  final Uint8List? bytes;

  /// Laid-out width. The height follows from [kCoverAspect].
  final double width;

  const BookCoverImage({
    super.key,
    required this.bookId,
    required this.sourceFormat,
    required this.title,
    required this.width,
    this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    final image = bytes;

    Widget generatedFace() => _GeneratedFace(
      bookId: bookId,
      sourceFormat: sourceFormat,
      title: title,
      width: width,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: width,
        height: width * kCoverAspect,
        child: image == null
            ? generatedFace()
            : Image.memory(
                image,
                fit: BoxFit.cover,
                // Decoded at the size it is drawn at. Publishers ship covers
                // at print resolution, so a 1600px image would otherwise be
                // decoded in full to fill a 172px box, on the target where
                // decode happens on the thread that draws frames.
                cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                // A stored image that will not decode is a broken picture,
                // not a broken book.
                errorBuilder: (context, _, _) => generatedFace(),
              ),
      ),
    );
  }
}

/// A book's cover once its bytes have been read.
///
/// Takes a future rather than bytes, so a widget rebuild does not force a
/// fresh read. Neither shelf memoizes this itself: `LibraryRepository`
/// already remembers one future per book id and clears it the moment a
/// write could have changed the cover, so a grid rebuilding its tiles on
/// every scroll and text-scale change gets the same future back for free.
class BookCoverFuture extends StatelessWidget {
  final String bookId;
  final BookSourceFormat sourceFormat;
  final String title;
  final Future<Uint8List?> cover;
  final double width;

  const BookCoverFuture({
    super.key,
    required this.bookId,
    required this.sourceFormat,
    required this.title,
    required this.cover,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: cover,
      builder: (context, snapshot) => BookCoverImage(
        bookId: bookId,
        sourceFormat: sourceFormat,
        title: title,
        width: width,
        // Null while the read is in flight, which draws the generated face
        // and then replaces it. No spinner: a blob read off a local database
        // finishes inside a frame or two, and a spinner per tile would be
        // more motion than the thing it is reporting on.
        bytes: snapshot.data,
      ),
    );
  }
}

/// The stand-in cover: a neutral card under a coloured band.
///
/// The band is the only place in the app where a colour comes from anything
/// but the reader's accent, and it earns that: a shelf of identical grey
/// rectangles is harder to scan than a shelf where each book keeps the same
/// stripe every time you look at it.
///
/// An EPUB with no cover draws the band alone — a missing cover is content
/// the book genuinely does not have. A Note has no cover to be missing, so
/// its face carries its own title above the band; below
/// [_noteFaceGlyphMaxWidth] the title would be unreadable and would only
/// repeat the label already beside the tile, so the face draws a note glyph
/// instead.
class _GeneratedFace extends StatelessWidget {
  final String bookId;
  final BookSourceFormat sourceFormat;
  final String title;
  final double width;

  const _GeneratedFace({
    required this.bookId,
    required this.sourceFormat,
    required this.title,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;

    final band = SizedBox(
      height: AppSpacing.sm,
      child: ColoredBox(color: _bandColorFor(bookId, scheme.brightness)),
    );
    final fill = Expanded(child: _faceFill(theme, scheme));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant, width: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // A Note's title reads before its identity band, matching the
        // decision on #335: the band is decorative, the title is content.
        // Every other face (an EPUB with no cover, or a Note too narrow for
        // its title) keeps the band on top, as it always has.
        children: _showsTitle ? [fill, band] : [band, fill],
      ),
    );
  }

  bool get _showsTitle =>
      sourceFormat == BookSourceFormat.note && width > _noteFaceGlyphMaxWidth;

  Widget _faceFill(ThemeData theme, ColorScheme scheme) {
    if (sourceFormat != BookSourceFormat.note) {
      // Today's face: an EPUB with no cover, or one that failed to decode.
      // The tile underneath already carries the title; repeating it here
      // would read as a bug, not as content.
      return ColoredBox(color: scheme.surfaceContainerHigh);
    }

    if (width <= _noteFaceGlyphMaxWidth) {
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            AppIcons.writeNote,
            size: AppSpacing.xxl,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ),
    );
  }
}

/// The band colour for [bookId].
///
/// Muted rather than saturated, so a wall of them reads as a bookshelf
/// rather than as a colour chart, and dimmer in the dark scheme for the same
/// reason the neutral ramp never reaches white.
Color _bandColorFor(String bookId, Brightness brightness) => HSLColor.fromAHSL(
  1,
  _hueFor(bookId),
  0.35,
  brightness == Brightness.light ? 0.52 : 0.40,
).toColor();

/// A hue from 0 to 360 for [bookId], the same on every target.
///
/// ADR 0009 keeps target-sensitive arithmetic out of `app/`, and this stays
/// here by staying out of that category rather than by being trusted. There
/// is no shift and no bit manipulation, and the modulo runs on every step, so
/// the largest value this ever holds is 359 times 31 plus a code unit, under
/// 77000. Every target represents that exactly.
///
/// Weak as a hash and strong enough for a stripe. Two books can share a hue;
/// the title underneath is what identifies the book.
double _hueFor(String bookId) {
  var hue = 0;
  for (final unit in bookId.codeUnits) {
    hue = (hue * 31 + unit) % 360;
  }

  return hue.toDouble();
}
