# Test fixtures

## romeo-and-juliet.epub

Project Gutenberg ebook 1513, *Romeo and Juliet* by William Shakespeare.

Source: https://www.gutenberg.org/ebooks/1513

Public domain in the United States. The Project Gutenberg licence is included
inside the file itself.

Committed deliberately. Every other fixture in this package is synthetic and
only tests assumptions this codebase already makes; this one was produced by
someone else's toolchain and is the only test that can catch those assumptions
being wrong.

The exact block and character counts asserted in `test/epub_golden_test.dart`
are observed output. If a normalizer change moves them, that is a real change
to stored reading positions: update the numbers and bump `kParserVersion`
in the same commit.
