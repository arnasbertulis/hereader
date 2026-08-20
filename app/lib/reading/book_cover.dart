import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Height of a cover as a multiple of its width. Close enough to a trade
/// paperback that a real cover fills the box rather than being letterboxed
/// inside it.
const double kCoverAspect = 1.5;

/// A book's cover, or a generated stand-in when it has none.
///
/// Pasted text and books whose publisher declared no cover both land on the
/// generated face, and so does every book imported before covers were stored.
/// Drawing nothing in those cases would make a grid of mostly blank boxes
/// look broken rather than plain.
///
/// Takes no title. The face draws none — the tile underneath already carries
/// it — so the only thing identifying a book here is the band colour, which
/// comes from the id.
class BookCoverImage extends StatelessWidget {
  /// Decides the band colour. The same book gets the same band on every
  /// device, because the id is the same on every device.
  final String bookId;

  /// The stored image, or null for the generated face.
  final Uint8List? bytes;

  /// Laid-out width. The height follows from [kCoverAspect].
  final double width;

  const BookCoverImage({
    super.key,
    required this.bookId,
    required this.width,
    this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    final image = bytes;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: width,
        height: width * kCoverAspect,
        child: image == null
            ? _GeneratedFace(bookId: bookId)
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
                errorBuilder: (context, _, _) => _GeneratedFace(bookId: bookId),
              ),
      ),
    );
  }
}

/// A book's cover once its bytes have been read.
///
/// Takes a future rather than bytes, so the caller decides how long a read
/// is remembered. The library memoizes one future per book because a grid
/// rebuilds its tiles on every scroll and text-scale change; Home keeps a
/// much smaller map for the few books it draws.
class BookCoverFuture extends StatelessWidget {
  final String bookId;
  final Future<Uint8List?> cover;
  final double width;

  const BookCoverFuture({
    super.key,
    required this.bookId,
    required this.cover,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: cover,
      builder: (context, snapshot) => BookCoverImage(
        bookId: bookId,
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
class _GeneratedFace extends StatelessWidget {
  final String bookId;

  const _GeneratedFace({required this.bookId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant, width: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSpacing.sm,
            child: ColoredBox(color: _bandColorFor(bookId, scheme.brightness)),
          ),
          // No title here. The tile below already draws it, and a stand-in
          // cover repeating text six pixels from itself reads as a bug, not
          // as content.
          Expanded(child: ColoredBox(color: scheme.surfaceContainerHigh)),
        ],
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
