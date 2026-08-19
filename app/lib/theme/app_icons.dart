import 'package:flutter/widgets.dart';

/// Every icon the app draws, named by what it means rather than what it is.
///
/// One file so the weight is decided once. Phosphor ships six, and which one a
/// low-vision reader can actually see is a question worth being able to answer
/// by editing a single line — not by finding fifty call sites. It also means a
/// future family swap is a rewrite of this file plus a font declaration, and
/// nothing else.
///
/// **Light, not Thin.** Thin was the original ask and is the wrong answer for
/// this reader: at 20-24 logical pixels its strokes land near one physical
/// pixel, which is the first thing central field loss takes away, and the app
/// has a high-contrast mode that hairlines actively fight. Light is still a
/// clear step down from Material's mix of filled and outlined glyphs.
///
/// **Fill means selected.** Six of the Material names this replaced were
/// outlined/filled pairs standing in for a selected state. Phosphor gives that
/// as a weight on one glyph, so the pair collapses to one picture and two
/// constants, and selection reads as emphasis rather than as a different
/// shape.
///
/// **Two fonts, not a package.** `phosphor_flutter` cannot be compiled against
/// this Flutter SDK. It declares `PhosphorIconData extends IconData`, and
/// `IconData` is a `final class`, so the front end rejects the package's own
/// source the moment anything imports it. `flutter analyze` does not report
/// this — it does not analyse package sources — so the failure arrives as a
/// compile error at test and build time instead. The fix is the fonts
/// themselves, vendored under `assets/fonts/`, declared in `pubspec.yaml`, and
/// addressed by plain const [IconData]. Phosphor is MIT and the notice sits
/// beside the files.
///
/// That is also the smaller build. The package ships all six weights, about
/// 3MB, to draw glyphs from two of them. And `--tree-shake-icons` subsets what
/// survives, which is why every constant here is `const` and why nothing in
/// the app builds an [IconData] from a variable.
///
/// One deliberate difference from the package: no `matchTextDirection`. It
/// mirrors a glyph under a right-to-left layout, and mirroring [seeAll] or
/// [openSection] is right only in a locale this app does not have. Setting it
/// unread would be a claim about a layout nobody has looked at.
abstract final class AppIcons {
  static const _light = 'PhosphorLight';
  static const _fill = 'PhosphorFill';

  // -- the shell -------------------------------------------------------
  static const tabHome = IconData(0xe2c2, fontFamily: _light);
  static const tabHomeSelected = IconData(0xe2c2, fontFamily: _fill);
  static const tabLibrary = IconData(0xe758, fontFamily: _light);
  static const tabLibrarySelected = IconData(0xe758, fontFamily: _fill);
  static const tabSettings = IconData(0xe432, fontFamily: _light);
  static const tabSettingsSelected = IconData(0xe432, fontFamily: _fill);

  // -- the settings index ----------------------------------------------
  static const sectionAccount = IconData(0xe4c2, fontFamily: _light);
  static const sectionProfiles = IconData(0xe6ee, fontFamily: _light);
  static const sectionAppearance = IconData(0xe6c8, fontFamily: _light);
  static const sectionReading = IconData(0xe8f2, fontFamily: _light);
  static const sectionSync = IconData(0xe094, fontFamily: _light);
  static const sectionAbout = IconData(0xe2ce, fontFamily: _light);

  /// The affordance on an index row. A caret rather than a chevron, matching
  /// the one the sort and filter menus already drop.
  static const openSection = IconData(0xe13a, fontFamily: _light);

  // -- account and sync ------------------------------------------------

  /// The account row on its own screen, which states signed in or not and so
  /// carries the distinction in the glyph too. [sectionAccount] is the index
  /// row pointing at that screen, and is the same picture at rest.
  static const accountSignedIn = IconData(0xe4c2, fontFamily: _fill);
  static const accountSignedOut = IconData(0xe4c2, fontFamily: _light);

  static const device = IconData(0xeba4, fontFamily: _light);
  static const syncSignedOut = IconData(0xe1b6, fontFamily: _light);
  static const syncRunning = IconData(0xe094, fontFamily: _light);
  static const syncOffline = IconData(0xe1b6, fontFamily: _fill);
  static const syncFailed = IconData(0xe4e2, fontFamily: _light);
  static const syncIdle = IconData(0xe1b0, fontFamily: _light);

  // -- adding something to read ----------------------------------------
  static const add = IconData(0xe3d4, fontFamily: _light);
  static const importFile = IconData(0xe61e, fontFamily: _light);
  static const writeNote = IconData(0xe34c, fontFamily: _light);
  static const pasteText = IconData(0xe198, fontFamily: _light);

  // -- the library and home --------------------------------------------
  static const seeAll = IconData(0xe06c, fontFamily: _light);
  static const resume = IconData(0xe3d2, fontFamily: _light);
  static const openMenu = IconData(0xe136, fontFamily: _light);
  static const flipSortDirection = IconData(0xe098, fontFamily: _light);

  // -- the reader ------------------------------------------------------
  static const play = IconData(0xe3d0, fontFamily: _light);
  static const pause = IconData(0xe39e, fontFamily: _light);

  /// A list rather than a book. The note at the reader's chapter button says
  /// why the two pictures have to stay apart.
  static const chapters = IconData(0xe2f0, fontFamily: _light);

  static const closeBook = IconData(0xe4f6, fontFamily: _light);
  static const readingProfile = IconData(0xe432, fontFamily: _light);

  /// Forward to the start of the next sentence, and of the next paragraph.
  ///
  /// Transport glyphs rather than the pilcrow, which is the picture of
  /// "paragraph" and carries no direction. Both of these have to read as
  /// *forward* before they read as anything else, since they sit in a row
  /// where the reader's only backward control is a tap zone with no glyph at
  /// all. Two triangles for the longer of the two jumps. See ADR 0020.
  static const skipSentence = IconData(0xe5a6, fontFamily: _light);
  static const skipParagraph = IconData(0xe6a6, fontFamily: _light);

  // -- profile editing -------------------------------------------------
  static const forkProfile = IconData(0xe1ca, fontFamily: _light);
  static const contrastPasses = IconData(0xe184, fontFamily: _light);
  static const contrastWarns = IconData(0xe4e0, fontFamily: _light);

  /// Beside a slider whose current value is worth a word. The same glyph as
  /// [contrastWarns] and a different fact: that one reports a measurement,
  /// this one reports a setting, and the two could want to diverge.
  static const settingWarns = IconData(0xe4e0, fontFamily: _light);

  /// Selected and unselected in a list of choices.
  ///
  /// Phosphor's `radio-button` is a ring with a filled centre and `circle` is
  /// the bare ring, so the pair reads the way Material's did without needing a
  /// second weight.
  static const chosen = IconData(0xeb08, fontFamily: _light);
  static const notChosen = IconData(0xe18a, fontFamily: _light);

  /// Confirming a colour swatch, drawn over the colour itself.
  static const confirm = IconData(0xe182, fontFamily: _light);

  /// The overflow menu on a row — a book tile, a profile row — for actions
  /// that are not the row's own tap.
  static const tileMenu = IconData(0xe208, fontFamily: _light);

  // -- what the reading settings page states ---------------------------
  static const placeIsSaved = IconData(0xe0ea, fontFamily: _light);
  static const pausesWhenHidden = IconData(0xe3a0, fontFamily: _light);
  static const frontMatterOffered = IconData(0xe062, fontFamily: _light);
  static const chaptersFromTheBook = IconData(0xe2f4, fontFamily: _light);
}
