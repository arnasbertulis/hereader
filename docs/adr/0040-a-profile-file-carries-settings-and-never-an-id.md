# 0040. A profile file carries settings and a version, never an id, and an import never overwrites

Date: 2026-10-24

## Status

Accepted.

## Context

A reading profile is tuned for one reader's eyes, and the only way to share one
was to be signed in to the same account, which syncs every profile to every
device (ADR 0008). A reader helping another reader, or moving a profile to a
device with no account, had nothing to hand over. The roadmap named it:
exporting and importing a profile as a file.

A file crosses a boundary the sync wire does not. The wire carries events from
this app, written by builds that know this schema; a file can be anything the
reader picked, from a build that does not exist yet, or not a profile at all.

## Decision

### 1. The file is UTF-8 JSON with a format marker and a version

`<profile name>.hereader-profile.json`, holding `format`
(`"hereader.profile"`), `version` (`1`) and `profile`. Characters a filename
cannot hold become `-`; an empty name falls back to `profile`.

A file whose `version` is greater than the one this release knows is refused as
`newerVersion`. This release reads only 1. A later release migrates or rejects
its own older formats, so the number is a promise about what a reader of that
release understands, not a counter that every change must bump.

A file over 64 KiB is refused as `tooLarge` before it is decoded; a real
profile is about 1 KiB. Anything not valid UTF-8 or JSON, not an object, with
the wrong `format`, a `version` that is not a positive integer, or a `profile`
that is not an object is `notAProfile`. Decoding returns a sealed result, so
no bad file can escape as an uncaught error, and each refusal is announced in a
snackbar worded differently per reason. Nothing is stored. This warns rather
than blocks: the reader can pick again.

### 2. The file carries no id

`profile` is `ReadingProfile.toJson()` with `id` removed. The file never holds
an id, a clock stamp, a deletion flag, an account, a token or any book data.

Decoding goes through `ReadingProfile.fromJson` with a freshly minted
`ReadingProfile.newId()` as `id`, the way the sync client reads an event. That
keeps one codec for the wire and the file, so they cannot drift, and field
clamping and fallbacks are the engine's. An `id` inside a file is overwritten.

Because no id travels, exporting a Preset is allowed and writes its settings
under its name, and no importer ever meets a `builtin.` id.

### 3. An import always creates a new profile

Never an overwrite: the id is always fresh, so an import cannot replace a
profile the reader has, or one arriving over sync. It is saved as an ordinary
stored profile and syncs under ADR 0008, with no new sync semantics.

The name is kept, except that ` (imported)` is appended when it equals the name
of any profile currently listed, Preset or stored, or a name the sliding switch
generates for a fork of a Preset. A Preset exported and imported elsewhere
must not appear as a second `Standard`, and an import must not arrive under a
name the switch treats as its own to remove.

The import becomes the active profile and is announced as a duplicate is,
`Now reading with <name>`, with an Undo that restores the previously active
profile. The imported profile stays stored; Delete removes it.

### 4. Where it lives

`Save as file` is in a profile row's overflow menu on the profiles screen, for
every profile. Import is an app-bar action on the same screen. The reader's
profile switcher shares the row but passes no export callback, so it gains
nothing.

Saving uses `FilePicker.saveFile(fileName:, bytes:)` and opening uses
`FilePicker.pickFile` with the `json` extension, so web (a download), Android
and Windows share one code path with no `dart:io`. A `null` from the saver is
either a cancel or the browser having handled the download, and is never
announced as a failure.

## Consequences

- A profile can be shared with no account on any platform the app runs on.
- The format is versioned from the first file, so a future change has a number
  to refuse or migrate on.
- Importing the same file twice stores two profiles, the second named
  ` (imported)` too. The reader deletes the one they do not want.
- A profile edited after export is not linked to its file: there is no id to
  find the original by, which is the point.

## Alternatives considered

- **Carry the id and update in place.** Rejected: a file from anyone could then
  overwrite a profile, or shadow a Preset, and the file would carry state that
  belongs to the sync log.
- **Export only stored profiles.** Rejected: a Preset is often the thing worth
  sharing, and without an id nothing makes it special.
- **A share sheet.** `share_plus` is not a dependency and `saveFile` already
  covers web, Android and Windows.
- **Re-validate fields in the app.** Rejected: `fromJson` already clamps and
  falls back, and a second validator would be a second path writing one fact.

## Verification

`app/test/profile_file_test.dart`: a round trip of a non-default profile keeps
every setting and takes the injected id; the encoded file has no `id`; a
version 2 file is `newerVersion`; a wrong format, non-JSON, non-UTF-8 bytes and
a root array are `notAProfile`; 64 KiB plus one byte is `tooLarge`; a Preset's
export decodes to a profile that is not built in.

`app/test/profiles_screen_test.dart`: `Save as file` hands the injected saver
the expected filename and bytes; an import stores one new profile, makes it
active and shows the Undo snackbar; Undo restores the previous profile and the
import stays stored; an imported Preset becomes `Standard (imported)`; a
refused file stores nothing and shows its reason; a cancelled pick stores
nothing and shows nothing.
