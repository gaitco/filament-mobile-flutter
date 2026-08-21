import 'package:flutter/widgets.dart';

/// LEFT-TO-RIGHT ISOLATE / POP DIRECTIONAL ISOLATE. Wrapping a run in these
/// keeps its own internal ordering intact no matter which way the paragraph
/// around it resolves — the fix the design spec measured directly.
///
/// Built via [String.fromCharCode], not a literal in source: the review
/// that flagged this as a minor found that writing the character as a
/// `\uXXXX` escape inside a plain string literal is equally clean under
/// `dart analyze` and `const`-eligible, and it's the
/// better choice *if it can be typed reliably* — but round-tripping a bare
/// `\u` escape through this session's own tool-call encoding proved
/// unreliable (it kept arriving as the literal directional glyph instead of
/// the six-character escape, re-triggering the exact
/// `text_direction_code_point_in_literal` warning this exists to avoid).
/// `fromCharCode` has no such ambiguity — it names the code point as a
/// plain decimal literal — at the cost of `final` instead of `const`.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// A digit in any of the three numeral systems an Arabic or Persian panel
/// actually writes numbers in: ASCII, Arabic-Indic (`٠`–`٩`, U+0660–0669) and
/// Extended Arabic-Indic (`۰`–`۹`, U+06F0–06F9).
///
/// Dart's `\d` is ASCII-only, so the first version of this pattern silently
/// skipped the eastern forms — the numerals an `ar` panel is *most* likely to
/// contain, reversing under RTL with exactly the same measured signature as
/// the ASCII defect this file exists to fix (whole-branch review, Important
/// 3). Written as `\uXXXX` escapes rather than literal glyphs so the source
/// stays readable in an LTR editor.
const String _digit = r'[\d\u0660-\u0669\u06F0-\u06F9]';

/// Two or more digit groups separated by spaces or hyphens, with an optional
/// leading `+` — a phone number, a spaced IBAN, a hyphenated tax number
/// (design spec, "Grouped digits really do reverse"). Deliberately tight: a
/// single unbroken token (a year, a count, an ID) never matches, because the
/// bidi algorithm does not reorder characters *within* one run — only
/// separate runs relative to each other — so isolating an unbroken token
/// would be invisible-character noise with nothing to fix. A price
/// (`19.99`) doesn't match either: `.` isn't a listed separator.
///
/// `(?<!\w)` is a leading token boundary: without it a word ending in a
/// digit donated its last character to the run, and `line1 10 20` isolated
/// `1 10 20`. The guard costs nothing — a genuine grouped run is always
/// preceded by a space, a start-of-string or punctuation, none of which is
/// `\w` — and every negative case stays negative, since a guard can only
/// ever match less.
///
/// ponytail: there is deliberately no TRAILING boundary to match it, and the
/// asymmetry is measured rather than lazy. A raw ISO timestamp still isolates
/// only its date half (`2026-03-24` out of `2026-03-24T08:41:19Z`), which is
/// harmless — the relative order of what is isolated is unchanged — and a
/// `(?!\w)` guard makes it strictly WORSE: the regex backtracks from
/// `2026-03-24` (rejected, `T` follows) to `2026-03` (accepted, `-` is not
/// `\w`), splitting the date itself. Revisit only if a card title ever
/// renders a raw timestamp visibly wrong.
///
/// Note `\w` is ASCII-only, like `\d` was: an Arabic word ending in an
/// eastern numeral (`سطر١ ١٠ ٢٠`) is not guarded. Left alone deliberately —
/// widening the guard is not the same measured-free change as adding it,
/// and no evidence says that shape occurs.
final RegExp _groupedDigits = RegExp('(?<!\\w)\\+?$_digit+(?:[ -]$_digit+)+');

/// Wraps every grouped-digit run in [text] with LRI…PDI so it keeps its own
/// left-to-right order when laid out inside an RTL paragraph, instead of the
/// bidi algorithm reordering the *groups* themselves — the
/// `+20 2 2411 8610` → `8610 2411 2 20+` defect this exists to fix.
///
/// A no-op when [direction] is not RTL (returns [text] itself, unchanged) —
/// the reversal only happens inside an RTL paragraph, so there is nothing to
/// isolate against under LTR. Also a no-op on text this has already
/// processed, guarded by [text] containing an LRI at all.
///
/// ponytail: that guard is whole-string, not per-match — a value that
/// concatenated an already-isolated fragment with a fresh, un-isolated run
/// would have the fresh run skipped too. A per-match version (skip a match
/// immediately preceded by LRI) was tried and reverted: `\+?` being optional
/// lets the regex re-anchor one character later — right after a
/// previously-wrapped run's own leading `+` — where the lookbehind no
/// longer sees an LRI, producing a genuine double-wrap (a second LRI/PDI
/// pair nested just inside the first one, around everything after the `+`),
/// a worse bug than the one it was meant to fix.
/// The correct narrow fix (walk the string, skip existing LRI…PDI spans
/// verbatim, isolate only the text between them) is real extra code for a
/// shape that doesn't occur at any of this package's five call sites
/// (`entry_widgets`, `semantic_badge`, `card_fields`, `rich_entry_tile`,
/// `dashboard_screen`) — each isolates one field's fresh raw string exactly
/// once, never a concatenation of previously-isolated and fresh text. Revisit if a caller
/// ever does that concatenation.

/// The direction a run of text would resolve to on its own, or null when it
/// has no strong character at all — digits, punctuation and spaces are all
/// bidi-neutral or weak, so a phone number or a price has none.
///
/// A composed paragraph uses this instead of [isolateBidi]: a paragraph built
/// from several mark leaves cannot isolate each leaf without changing how the
/// whole thing lays out, but it *can* be told its own direction, which is what
/// the bidi algorithm needed all along. `rich_entry_tile` passes the result
/// to `Text.rich`.
///
/// This is the standard "first-strong" rule the Unicode algorithm uses to
/// give a paragraph its own base direction, hand-rolled because this package
/// takes no `intl` dependency. The RTL ranges are the scripts a Filament
/// panel actually ships translations for — Hebrew, Arabic and its supplement
/// and presentation forms, Syriac, Thaana, N'Ko — and anything else with a
/// case mapping is treated as strong LTR.
TextDirection? directionOf(String text) {
  final ltr = _firstStrongIsLtr(text);
  if (ltr == null) return null;
  return ltr ? TextDirection.ltr : TextDirection.rtl;
}

/// The first *strong* character's direction, or null when the string has none.
bool? _firstStrongIsLtr(String text) {
  for (final rune in text.runes) {
    final isRtl =
        (rune >= 0x0590 && rune <= 0x08FF) || // Hebrew … Arabic Extended-A
        (rune >= 0xFB1D && rune <= 0xFDFF) || // Hebrew/Arabic presentation
        (rune >= 0xFE70 && rune <= 0xFEFF); // Arabic presentation forms-B
    if (isRtl) return false;

    final isLtr =
        (rune >= 0x0041 && rune <= 0x005A) || // A–Z
        (rune >= 0x0061 && rune <= 0x007A) || // a–z
        (rune >= 0x00C0 && rune <= 0x058F); // Latin-1 supplement … Armenian
    if (isLtr) return true;
  }
  return null;
}

String isolateBidi(
  String text,
  TextDirection direction, {
  bool wholeRun = true,
}) {
  if (direction != TextDirection.rtl) return text;
  if (text.contains(_lri)) return text;

  // A whole run whose own base direction opposes the paragraph's is isolated
  // entire, because the damage is not confined to digits. Measured on a real
  // screenshot from the owner's simulator: an English review body inside an
  // `ar` panel rendered `.Great lamp, sturdy base` — the trailing full stop
  // is bidi-NEUTRAL, so it takes the paragraph direction and lands at the
  // wrong end of the sentence. `x(Great)=14.0, x(.)=0.0` plain against
  // `x(Great)=0.0, x(.)=322.0` isolated.
  //
  // This subsumes nothing: a grouped-digit run has NO strong character at
  // all (digits are weak), so first-strong returns null for a phone number
  // and the per-run rule below still does that work. The two rules cover
  // disjoint cases and both are needed.
  // `wholeRun: false` is passed by the one caller that hands this a FRAGMENT
  // rather than a standalone value: `rich_entry_tile`'s `_span`, which is
  // invoked per mark leaf, so several calls compose a single paragraph.
  // Isolating each leaf on its own does not just fix punctuation there — it
  // changes how the paragraph lays out, because each isolate is positioned as
  // a unit. Measured: it moved a blockquote's quoted text flush against a
  // plain paragraph, losing the indent the RTL layout had given it. A whole
  // paragraph's direction is the bidi algorithm's job once it can see the
  // whole paragraph; a fragment must not pre-empt it.
  if (wholeRun && _firstStrongIsLtr(text) == true) return '$_lri$text$_pdi';

  return text.replaceAllMapped(
    _groupedDigits,
    (match) => '$_lri${match[0]}$_pdi',
  );
}
