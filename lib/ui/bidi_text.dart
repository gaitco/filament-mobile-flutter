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
/// (`entry_widgets`, `semantic_badge`, `resource_card`, `rich_entry_tile`,
/// `dashboard_screen`) — each isolates one field's fresh raw string exactly
/// once, never a concatenation of previously-isolated and fresh text. Revisit if a caller
/// ever does that concatenation.
String isolateGroupedDigits(String text, TextDirection direction) {
  if (direction != TextDirection.rtl) return text;
  if (text.contains(_lri)) return text;

  return text.replaceAllMapped(
    _groupedDigits,
    (match) => '$_lri${match[0]}$_pdi',
  );
}
