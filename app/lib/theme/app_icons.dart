import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Every icon the app draws, named by what it means rather than what it is.
///
/// One file so the weight is decided once. Phosphor ships six, and which one a
/// low-vision reader can actually see is a question worth being able to answer
/// by editing a single line — not by finding fifty call sites. It also means a
/// future family swap is a rewrite of this file and nothing else.
///
/// **Light, not Thin.** Thin was the original ask and is the wrong answer for
/// this reader: at 20-24 logical pixels its strokes land near one physical
/// pixel, which is the first thing central field loss takes away, and the app
/// has a high-contrast mode that hairlines actively fight. Light is still a
/// clear step down from Material's mix of filled and outlined glyphs.
///
/// **`PhosphorIconsLight.x`, never `PhosphorIcons.x(style)`.** The per-weight
/// classes are `static const` under `@staticIconProvider`, which is what
/// Flutter's icon tree-shaker looks for. The style-argument API returns a
/// non-const `IconData`, and one of those anywhere in the app fails the build
/// under `--tree-shake-icons` — the fallback being all six fonts, about 3MB,
/// to draw thirty-odd glyphs.
///
/// **Fill means selected.** Six of the Material names were outlined/filled
/// pairs standing in for a selected state. Phosphor gives that as a weight on
/// one glyph, so the pair collapses to one name and two constants, and
/// selection reads as emphasis rather than as a different shape.
abstract final class AppIcons {
  // -- the shell -------------------------------------------------------
  static const tabHome = PhosphorIconsLight.house;
  static const tabHomeSelected = PhosphorIconsFill.house;
  static const tabLibrary = PhosphorIconsLight.books;
  static const tabLibrarySelected = PhosphorIconsFill.books;
  static const tabSettings = PhosphorIconsLight.sliders;
  static const tabSettingsSelected = PhosphorIconsFill.sliders;

  // -- the settings index ----------------------------------------------
  static const sectionAccount = PhosphorIconsLight.user;
  static const sectionProfiles = PhosphorIconsLight.textAa;
  static const sectionAppearance = PhosphorIconsLight.palette;
  static const sectionReading = PhosphorIconsLight.bookOpenText;
  static const sectionSync = PhosphorIconsLight.arrowsClockwise;
  static const sectionAbout = PhosphorIconsLight.info;

  /// The affordance on an index row. A caret rather than a chevron, matching
  /// the one the sort and filter menus already drop.
  static const openSection = PhosphorIconsLight.caretRight;

  // -- account and sync ------------------------------------------------
  static const accountSignedIn = PhosphorIconsFill.user;
  static const device = PhosphorIconsLight.devices;
  static const syncSignedOut = PhosphorIconsLight.cloudSlash;
  static const syncRunning = PhosphorIconsLight.arrowsClockwise;
  static const syncOffline = PhosphorIconsFill.cloudSlash;
  static const syncFailed = PhosphorIconsLight.warningCircle;
  static const syncIdle = PhosphorIconsLight.cloudCheck;

  // -- adding something to read ----------------------------------------
  static const add = PhosphorIconsLight.plus;
  static const importFile = PhosphorIconsLight.fileArrowUp;
  static const writeNote = PhosphorIconsLight.notePencil;
  static const pasteText = PhosphorIconsLight.clipboardText;

  // -- the library and home --------------------------------------------
  static const seeAll = PhosphorIconsLight.arrowRight;
  static const resume = PhosphorIconsLight.playCircle;
  static const openMenu = PhosphorIconsLight.caretDown;
  static const flipSortDirection = PhosphorIconsLight.arrowsDownUp;
  static const tileMenu = PhosphorIconsLight.dotsThreeVertical;

  // -- the reader ------------------------------------------------------
  static const play = PhosphorIconsLight.play;
  static const pause = PhosphorIconsLight.pause;
  static const chapters = PhosphorIconsLight.list;
  static const closeBook = PhosphorIconsLight.x;
  static const readingProfile = PhosphorIconsLight.sliders;

  // -- profile editing -------------------------------------------------
  static const forkProfile = PhosphorIconsLight.copy;
  static const contrastPasses = PhosphorIconsLight.checkCircle;
  static const contrastWarns = PhosphorIconsLight.warning;

  /// Selected and unselected in a list of choices.
  ///
  /// Phosphor's `radioButton` is a ring with a filled centre and `circle` is
  /// the bare ring, so the pair reads the same way Material's did without
  /// needing a second weight.
  static const chosen = PhosphorIconsLight.radioButton;
  static const notChosen = PhosphorIconsLight.circle;

  /// Confirming a colour swatch, drawn over the colour itself.
  static const confirm = PhosphorIconsLight.check;

  // -- what the reading settings page states ---------------------------
  static const placeIsSaved = PhosphorIconsLight.bookmarkSimple;
  static const pausesWhenHidden = PhosphorIconsLight.pauseCircle;
  static const frontMatterOffered = PhosphorIconsLight.arrowLineLeft;
  static const chaptersFromTheBook = PhosphorIconsLight.listDashes;
}
