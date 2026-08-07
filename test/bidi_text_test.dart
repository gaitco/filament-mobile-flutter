// Task 5 of the P6f RTL/i18n plan: grouped digit runs (a phone number, a
// hyphenated tax number, a spaced IBAN) stop reversing inside RTL text.
//
// This task's own named trap: a test asserting the output *contains* U+2066
// (LEFT-TO-RIGHT ISOLATE) passes whether or not the text actually renders in
// order — it tests that a character got inserted, not that the bug is fixed.
// Every positive case below is proven by **measured glyph order** — the same
// method the defect itself was found with (design spec, "Grouped digits
// really do reverse"): lay the string out with `TextPainter` under RTL, use
// `getBoxesForSelection` to find where the first and last digit groups
// actually paint, and assert their x-offsets are in reading order. The
// isolate characters are asserted too, but only as a secondary detail
// alongside the glyph proof — never standing in for it.

import 'package:filament_mobile/ui/bidi_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// LEFT-TO-RIGHT ISOLATE / POP DIRECTIONAL ISOLATE, built via
// `String.fromCharCode` rather than a literal in source — same reason as
// `bidi_text.dart`: it keeps the analyzer's
// `text_direction_code_point_in_literal` check quiet.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// The x-offset of [needle]'s first glyph once [text] is laid out under
/// [direction] — the exact measurement the design spec's own defect report
/// used. A wide `maxWidth` keeps the whole string on one line so wrapping
/// never confounds the offsets.
double _xOffsetOf(String text, String needle, TextDirection direction) {
  final start = text.indexOf(needle);
  assert(start >= 0, '"$needle" must actually appear in "$text"');

  final painter = TextPainter(
    text: TextSpan(text: text),
    textDirection: direction,
  )..layout(maxWidth: 2000);

  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + needle.length),
  );
  return boxes.first.left;
}

void main() {
  test('a latin sentence keeps its full stop at the end under RTL', () {
    // Reported from the owner's own simulator: an English review body inside
    // an `ar` panel rendered `.Great lamp, sturdy base` — the trailing full
    // stop at the WRONG END. A period is bidi-NEUTRAL, so inside an RTL
    // paragraph it takes the paragraph's direction and lands at the left.
    //
    // Measured, not asserted on the isolate characters: plain gave
    // x(Great)=14.0 / x(.)=0.0, isolated gave x(Great)=0.0 / x(.)=322.0.
    const raw = 'Great lamp, sturdy base.';

    expect(
      _xOffsetOf(raw, '.', TextDirection.rtl),
      lessThan(_xOffsetOf(raw, 'Great', TextDirection.rtl)),
      reason: 'the defect itself — without this the fix proves nothing',
    );

    final fixed = isolateBidi(raw, TextDirection.rtl);
    expect(
      _xOffsetOf(fixed, '.', TextDirection.rtl),
      greaterThan(_xOffsetOf(fixed, 'Great', TextDirection.rtl)),
    );
  });

  test('an arabic sentence is not wrapped whole, so its digits still are', () {
    // First-strong is Arabic, so the paragraph and the text agree and there is
    // nothing to isolate at run level — the per-group rule keeps doing the
    // work it always did. Asserting the whole string were wrapped would be
    // asserting a bug: it would isolate Arabic inside Arabic.
    final out = isolateBidi('اتصل بنا على +20 2 2411 8610', TextDirection.rtl);

    expect(out.startsWith(_lri), isFalse);
    expect(out.contains('$_lri+20 2 2411 8610$_pdi'), isTrue);
  });

  test('a rich-text fragment is never wrapped whole', () {
    // `wholeRun: false` is what `rich_entry_tile` passes, because it calls
    // this once per mark leaf and several calls compose ONE paragraph.
    // Wrapping each leaf changes how that paragraph lays out — measured: it
    // moved a blockquote's quoted text flush against a plain paragraph,
    // losing the indent RTL had given it.
    expect(
      isolateBidi('Great lamp.', TextDirection.rtl, wholeRun: false),
      'Great lamp.',
    );
    expect(
      isolateBidi('Great lamp.', TextDirection.rtl),
      '$_lri'
      'Great lamp.'
      '$_pdi',
    );
  });

  testWidgets('a phone number inside Arabic text renders in order under RTL', (
    tester,
  ) async {
    const raw = 'اتصل بنا على +20 2 2411 8610 اليوم';

    // Baseline: prove the string really does reverse unisolated, the same
    // way the defect was measured — the leading group (+20) must land to
    // the *right* of the trailing group (8610).
    final plainFirst = _xOffsetOf(raw, '+20', TextDirection.rtl);
    final plainLast = _xOffsetOf(raw, '8610', TextDirection.rtl);
    expect(
      plainFirst,
      greaterThan(plainLast),
      reason:
          'unisolated grouped digits should reverse under RTL — '
          'if this fails the baseline itself is wrong, not the fix',
    );

    final isolated = isolateBidi(raw, TextDirection.rtl);

    final isolatedFirst = _xOffsetOf(isolated, '+20', TextDirection.rtl);
    final isolatedLast = _xOffsetOf(isolated, '8610', TextDirection.rtl);
    expect(
      isolatedFirst,
      lessThan(isolatedLast),
      reason:
          'isolated, the leading group must render left of the '
          'trailing one — reading order preserved',
    );

    // Secondary detail only, never the proof: the isolate characters
    // themselves are present.
    expect(isolated, contains(_lri));
    expect(isolated, contains(_pdi));
  });

  test('the same string under LTR is unchanged', () {
    const raw = 'Call us on +20 2 2411 8610 today';
    expect(isolateBidi(raw, TextDirection.ltr), same(raw));
  });

  test('a bare year is not isolated', () {
    const raw = 'تقرير عام 2024 السنوي';
    final result = isolateBidi(raw, TextDirection.rtl);
    expect(result, raw);
    expect(result, isNot(contains(_lri)));
  });

  test('a price is not isolated', () {
    const raw = 'السعر 19.99 دولار';
    final result = isolateBidi(raw, TextDirection.rtl);
    expect(result, raw);
    expect(result, isNot(contains(_lri)));
  });

  test('a single unbroken token is not isolated', () {
    const raw = 'رقم الحساب 1234567890123 مسجل';
    final result = isolateBidi(raw, TextDirection.rtl);
    expect(result, raw);
    expect(result, isNot(contains(_lri)));
  });

  testWidgets('a hyphenated tax number renders in order under RTL', (
    tester,
  ) async {
    const raw = 'البطاقة الضريبية 761-164-529 مسجلة';

    final isolated = isolateBidi(raw, TextDirection.rtl);
    expect(isolated, contains(_lri));
    expect(isolated, contains(_pdi));

    final first = _xOffsetOf(isolated, '761', TextDirection.rtl);
    final last = _xOffsetOf(isolated, '529', TextDirection.rtl);
    expect(
      first,
      lessThan(last),
      reason:
          '761 must render left of 529 — the group order the source '
          'string actually has',
    );
  });

  // Whole-branch review, Important 3: Dart's `\d` is ASCII-only, so
  // Arabic-Indic (٠-٩, U+0660–0669) and Extended Arabic-Indic (۰-۹,
  // U+06F0–06F9) digit groups — the numerals an Arabic panel is MOST likely
  // to contain — reversed exactly the same way and were never isolated.
  //
  // The eastern strings below are derived from the ASCII ones by code point
  // rather than typed as literals: a source file mixing RTL text, a `+` and
  // eastern numerals renders in an order that has nothing to do with its
  // logical order, so a literal is unreviewable — and the analyzer's
  // `text_direction_code_point_in_literal` check exists for the same reason.
  group('eastern digits reverse identically and are isolated identically', () {
    /// [ascii] with every ASCII digit replaced by the numeral at [base]
    /// (0x0660 Arabic-Indic, 0x06F0 Extended Arabic-Indic). Logical order is
    /// untouched, so the needles below map one-for-one.
    String eastern(String ascii, int base) => ascii.replaceAllMapped(
      RegExp(r'\d'),
      (match) => String.fromCharCode(base + int.parse(match[0]!)),
    );

    for (final (name, base) in const [
      ('Arabic-Indic (U+0660)', 0x0660),
      ('Extended Arabic-Indic (U+06F0)', 0x06F0),
    ]) {
      testWidgets('$name — a phone number renders in order under RTL', (
        tester,
      ) async {
        final raw = eastern('اتصل بنا على +20 2 2411 8610 اليوم', base);
        final first = eastern('+20', base);
        final last = eastern('8610', base);

        // Same baseline the ASCII case carries: prove the string really does
        // reverse unisolated before claiming the isolation fixed anything.
        expect(
          _xOffsetOf(raw, first, TextDirection.rtl),
          greaterThan(_xOffsetOf(raw, last, TextDirection.rtl)),
          reason:
              'unisolated eastern digit groups should reverse under RTL — '
              'if this fails the baseline itself is wrong, not the fix',
        );

        final isolated = isolateBidi(raw, TextDirection.rtl);

        expect(
          _xOffsetOf(isolated, first, TextDirection.rtl),
          lessThan(_xOffsetOf(isolated, last, TextDirection.rtl)),
          reason:
              'isolated, the leading group must render left of the trailing '
              'one — the same guarantee ASCII digits already had',
        );
      });

      testWidgets('$name — a bare year and a price stay unisolated', (
        tester,
      ) async {
        // Widening the character class must not widen what MATCHES: a single
        // unbroken run has nothing to reorder, and `.` is not a separator.
        for (final ascii in const [
          'تقرير عام 2024 السنوي',
          'السعر 19.99 دولار',
          'رقم الحساب 1234567890123 مسجل',
        ]) {
          final raw = eastern(ascii, base);
          expect(isolateBidi(raw, TextDirection.rtl), raw);
          expect(isolateBidi(raw, TextDirection.rtl), isNot(contains(_lri)));
        }
      });
    }
  });

  test('a word ending in a digit keeps that digit out of the isolate', () {
    // Whole-branch review, Minor 3, leading half: with no boundary before the
    // run, `line1 10 20` isolated `1 10 20` — the word's own last character
    // pulled into the isolate. A `(?<!\w)` guard closes it.
    //
    // Asserted as string equality, not glyph order: the two candidate
    // outputs isolate the SAME visible characters in the same order, so a
    // measurement cannot tell them apart. Which characters got wrapped is
    // exactly what is under test.
    // Arabic-leading deliberately: since the isolation widened to cover a
    // whole run whose base direction opposes the paragraph's, a string
    // STARTING in Latin is wrapped entire and never reaches the per-run
    // pattern at all. The `(?<!\w)` guard is now exercised only where the
    // paragraph and the run agree in direction — an Arabic sentence quoting
    // an ASCII token — which is exactly where it still has work to do.
    expect(
      isolateBidi('اتصل line1 10 20', TextDirection.rtl),
      'اتصل line1 $_lri'
      '10 20'
      '$_pdi',
    );
  });

  test('applying the helper twice does not double-wrap', () {
    const raw = 'اتصل بنا على +20 2 2411 8610 اليوم';

    final once = isolateBidi(raw, TextDirection.rtl);
    final twice = isolateBidi(once, TextDirection.rtl);

    expect(twice, once);
    expect(_lri.allMatches(twice).length, 1);
    expect(_pdi.allMatches(twice).length, 1);
  });
}
