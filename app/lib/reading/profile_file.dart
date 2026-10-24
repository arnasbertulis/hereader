import 'dart:convert';
import 'dart:typed_data';

import 'package:rsvp_engine/rsvp_engine.dart';

/// The `format` value every profile file carries.
const profileFileFormat = 'hereader.profile';

/// The only version of the file format this release reads and writes. A file
/// naming a greater one is [ProfileFileRejection.newerVersion]; a later
/// release migrates or rejects its own older formats.
const profileFileVersion = 1;

/// Larger than this is refused before it is decoded. A real profile is about
/// 1 KiB, so this is a ceiling on what a mis-picked file can cost, not a
/// limit a reader will meet.
const profileFileMaxBytes = 64 * 1024;

/// Why a file was not taken as a profile.
enum ProfileFileRejection {
  /// Over [profileFileMaxBytes].
  tooLarge,

  /// Not UTF-8, not JSON, not an object, or not this format.
  notAProfile,

  /// A version greater than [profileFileVersion].
  newerVersion,
}

/// What [decodeProfileFile] made of a file. A result rather than a throw, so
/// the caller must say what a rejection looks like and a bad file can never
/// escape as an uncaught error.
sealed class ProfileFileResult {
  const ProfileFileResult();
}

class ProfileFileDecoded extends ProfileFileResult {
  final ReadingProfile profile;

  const ProfileFileDecoded(this.profile);
}

class ProfileFileRejected extends ProfileFileResult {
  final ProfileFileRejection reason;

  const ProfileFileRejected(this.reason);
}

/// Writes [profile] as a profile file: its settings and its name, nothing
/// else.
///
/// The id is dropped. A file never carries an id, a clock stamp, a deletion
/// flag, an account or any book data, so exporting a Preset writes ordinary
/// settings and no importer ever meets a built-in id.
Uint8List encodeProfileFile(ReadingProfile profile) {
  final settings = profile.toJson()..remove('id');
  final document = <String, dynamic>{
    'format': profileFileFormat,
    'version': profileFileVersion,
    'profile': settings,
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(document)),
  );
}

/// The name a saved file is offered under: `<name>.hereader-profile.json`.
///
/// Characters a filename cannot hold become `-`; a name with nothing left
/// falls back to `profile`.
String profileFileName(ReadingProfile profile) {
  final cleaned = profile.name
      .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '-')
      .trim();
  return '${cleaned.isEmpty ? 'profile' : cleaned}.hereader-profile.json';
}

/// Reads a profile file into a profile carrying [id].
///
/// Goes through [ReadingProfile.fromJson], the codec the sync client uses, so
/// field clamping and fallbacks are the engine's and the file cannot drift
/// from the wire. Any `id` inside the file is ignored: [id] always wins.
ProfileFileResult decodeProfileFile(Uint8List bytes, {required String id}) {
  const notAProfile = ProfileFileRejected(ProfileFileRejection.notAProfile);

  if (bytes.length > profileFileMaxBytes) {
    return const ProfileFileRejected(ProfileFileRejection.tooLarge);
  }

  final Object? root;
  try {
    root = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return notAProfile;
  }

  if (root is! Map<String, dynamic>) return notAProfile;
  if (root['format'] != profileFileFormat) return notAProfile;

  final version = root['version'];
  if (version is! int || version < 1) return notAProfile;
  if (version > profileFileVersion) {
    return const ProfileFileRejected(ProfileFileRejection.newerVersion);
  }

  final settings = root['profile'];
  if (settings is! Map<String, dynamic>) return notAProfile;

  return ProfileFileDecoded(ReadingProfile.fromJson({...settings, 'id': id}));
}
