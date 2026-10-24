import 'dart:convert';
import 'dart:typed_data';

import 'package:app/reading/profile_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

const _custom = ReadingProfile(
  id: 'p.1.aaaaaaaa',
  name: 'Evening',
  pacing: PacingConfig(
    baseWpm: 410,
    clausePause: Duration(milliseconds: 130),
    sentencePause: Duration(milliseconds: 310),
  ),
  presentation: PresentationConfig(
    fontSizePt: 64,
    orpHighlight: true,
    transitionMs: 80,
  ),
  rewindWords: 5,
);

void main() {
  group('encodeProfileFile', () {
    test('writes the format, the version and the settings, never an id', () {
      final root =
          jsonDecode(utf8.decode(encodeProfileFile(_custom)))
              as Map<String, dynamic>;

      expect(root['format'], 'hereader.profile');
      expect(root['version'], 1);
      expect(root.keys, unorderedEquals(['format', 'version', 'profile']));

      final profile = root['profile'] as Map<String, dynamic>;
      expect(profile.containsKey('id'), isFalse);
      expect(profile['name'], 'Evening');
      expect(profile['rewindWords'], 5);
      expect((profile['pacing'] as Map)['baseWpm'], 410);
      expect((profile['pacing'] as Map)['sentencePauseMs'], 310);
      expect((profile['presentation'] as Map)['fontSizePt'], 64);
      expect((profile['presentation'] as Map)['orpHighlight'], true);
    });
  });

  group('profileFileName', () {
    ReadingProfile named(String name) =>
        ReadingProfile(id: 'p.1.a', name: name);

    test('is the name plus the profile-file extension', () {
      expect(
        profileFileName(named('Evening')),
        'Evening.hereader-profile.json',
      );
    });

    test('turns characters a filename cannot hold into dashes', () {
      expect(
        profileFileName(named(r'a/b\c:d*e?f"g<h>i|j')),
        'a-b-c-d-e-f-g-h-i-j.hereader-profile.json',
      );
    });

    test('falls back to profile for an empty name', () {
      expect(profileFileName(named('')), 'profile.hereader-profile.json');
      expect(profileFileName(named('   ')), 'profile.hereader-profile.json');
    });
  });

  group('decodeProfileFile', () {
    test('round-trips every setting and takes the injected id', () {
      final result = decodeProfileFile(
        encodeProfileFile(_custom),
        id: 'p.2.bbbbbbbb',
      );

      expect(result, isA<ProfileFileDecoded>());
      final profile = (result as ProfileFileDecoded).profile;
      expect(profile.id, 'p.2.bbbbbbbb');
      expect(profile.name, 'Evening');
      expect(profile.pacing.baseWpm, 410);
      expect(profile.pacing.clausePause, const Duration(milliseconds: 130));
      expect(profile.pacing.sentencePause, const Duration(milliseconds: 310));
      expect(profile.presentation.fontSizePt, 64);
      expect(profile.presentation.orpHighlight, isTrue);
      expect(profile.presentation.transitionMs, 80);
      expect(profile.rewindWords, 5);
      expect(profile, _custom.copyWith(id: 'p.2.bbbbbbbb'));
    });

    test('reads a hand-written file and ignores an id inside it', () {
      final result = decodeProfileFile(
        _bytes('''
{
  "format": "hereader.profile",
  "version": 1,
  "profile": {
    "id": "builtin.standard",
    "name": "From a friend",
    "pacing": {"baseWpm": 300},
    "rewindWords": 3
  }
}
'''),
        id: 'p.3.cccccccc',
      );

      final profile = (result as ProfileFileDecoded).profile;
      expect(profile.id, 'p.3.cccccccc');
      expect(profile.isBuiltIn, isFalse);
      expect(profile.name, 'From a friend');
      expect(profile.pacing.baseWpm, 300);
      expect(profile.rewindWords, 3);
    });

    test('a Preset exported decodes to a profile that is not built in', () {
      final result = decodeProfileFile(
        encodeProfileFile(Presets.standard),
        id: 'p.4.dddddddd',
      );

      final profile = (result as ProfileFileDecoded).profile;
      expect(profile.isBuiltIn, isFalse);
      expect(profile.name, Presets.standard.name);
    });

    ProfileFileRejection? rejection(Uint8List bytes) {
      final result = decodeProfileFile(bytes, id: 'p.5.eeeeeeee');
      return result is ProfileFileRejected ? result.reason : null;
    }

    test('rejects a newer version', () {
      expect(
        rejection(
          _bytes(
            '{"format":"hereader.profile","version":2,"profile":{"name":"x"}}',
          ),
        ),
        ProfileFileRejection.newerVersion,
      );
    });

    test('rejects a wrong format, non-JSON, a root array, bad shapes', () {
      for (final text in [
        '{"format":"other","version":1,"profile":{}}',
        'not json at all',
        '[1,2,3]',
        '{"format":"hereader.profile","version":"1","profile":{}}',
        '{"format":"hereader.profile","version":1,"profile":[]}',
        '{"format":"hereader.profile","version":1}',
      ]) {
        expect(
          rejection(_bytes(text)),
          ProfileFileRejection.notAProfile,
          reason: text,
        );
      }
    });

    test('rejects bytes that are not UTF-8', () {
      expect(
        rejection(Uint8List.fromList([0xff, 0xfe, 0xfd])),
        ProfileFileRejection.notAProfile,
      );
    });

    test('rejects a file over 64 KiB before reading it', () {
      expect(
        rejection(Uint8List(64 * 1024 + 1)),
        ProfileFileRejection.tooLarge,
      );
    });

    test('takes a file of exactly 64 KiB to the format check', () {
      expect(rejection(Uint8List(64 * 1024)), ProfileFileRejection.notAProfile);
    });
  });
}
