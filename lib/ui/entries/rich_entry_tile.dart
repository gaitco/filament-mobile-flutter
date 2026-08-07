import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../schema/rich_document.dart';
import '../bidi_text.dart';
import 'entry_widgets.dart';

/// Renders a [RichDocument] (P6e Task 5's parse of Filament's ProseMirror
/// tree) with `RichText`/`TextSpan` for inline runs and `Column` for blocks —
/// the two runtime dependencies this package already has, no more (design
/// spec, "Flutter"). Registered under `EntryKind.rich` in `EntryRegistry`.
///
/// **Links.** Opening a URL needs a platform launcher, a dependency this
/// package will not take, so tapping is host-wired exactly like
/// `RelationSectionWidget.onSeeAllTap`: the host passes its own
/// `EntryRegistry.defaults(onLinkTap: ...)` to `ResourceViewScreen.registry`.
/// [onLinkTap] null — the default, no host wired — renders a link as plain,
/// unstyled text. That is deliberate: this project's own "absence means
/// unavailable" rule caught two dead-affordance bugs in P6d, and a blue
/// underlined span that does nothing when tapped is exactly the disabled
/// corpse that rule exists to prevent.
///
/// **Unknown nodes.** A node type outside the closed vocabulary — a future
/// Filament addition — renders its descendant text as a paragraph rather than
/// vanishing. Silent content loss is the one outcome worse than ugly
/// rendering.
///
/// **Images.** `attrs.src` null (Filament's state cast nulls it for
/// private-visibility attachments) skips the node instead of rendering a
/// broken image.
class RichEntryTile extends StatefulWidget {
  const RichEntryTile({
    required this.document,
    this.label,
    this.onLinkTap,
    super.key,
  });

  final String? label;
  final RichDocument document;

  /// Called with a link mark's `href` when its span is tapped. Null means no
  /// host has wired link handling — see the class doc.
  final void Function(String href)? onLinkTap;

  @override
  State<RichEntryTile> createState() => _RichEntryTileState();
}

class _RichEntryTileState extends State<RichEntryTile> {
  // `TapGestureRecognizer` (a `OneSequenceGestureRecognizer`) tracks pointers
  // through the global gesture arena, so recognizers from a previous build
  // are disposed explicitly rather than left for the garbage collector —
  // this tile lives inside `ResourceViewScreen`'s `ListenableBuilder`, which
  // rebuilds on every provider change (an edit, an action, a delete).
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _recognizerFor(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLinkTap?.call(href);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();

    return Labelled(
      label: widget.label,
      child: _blockNode(context, widget.document.root, this),
    );
  }
}

/// One block-level node. Free functions, not methods, so they can share
/// [_RichEntryTileState] across the recursion — Dart privacy is per-library
/// (this file), not per-class, so [_RichEntryTileState._recognizerFor] is
/// reachable from here without exposing it beyond this file.
Widget _blockNode(
  BuildContext context,
  RichNode node,
  _RichEntryTileState state,
) {
  switch (node.type) {
    case 'doc':
      return _blocks(context, node.children, state);

    case 'paragraph':
      return _textBlock(
        context,
        node,
        state,
        Theme.of(context).textTheme.bodyMedium,
      );

    case 'heading':
      return _textBlock(
        context,
        node,
        state,
        _headingStyle(context, node.attrs.level ?? 1),
      );

    case 'bulletList':
      return _list(context, node.children, state, ordered: false);

    case 'orderedList':
      return _list(context, node.children, state, ordered: true);

    case 'blockquote':
      return DecoratedBox(
        decoration: const BoxDecoration(
          // Directional, like the indent below it — a hardcoded `left` bar
          // would paint under the text once the indent moves to the right
          // under RTL. `DecoratedBox` resolves this itself against ambient
          // `Directionality` (via `createLocalImageConfiguration`), so no
          // explicit direction is threaded through here.
          border: BorderDirectional(
            start: BorderSide(width: 3, color: Color(0xFF9CA3AF)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            top: 4,
            bottom: 4,
          ),
          child: _blocks(context, node.children, state),
        ),
      );

    case 'horizontalRule':
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(),
      );

    case 'image':
      final src = node.attrs.src;
      // Filament's own state cast nulls `src` for a private-visibility
      // attachment — skipped, not rendered broken.
      if (src == null || src.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Image.network(
          src,
          errorBuilder: (context, _, _) => const SizedBox.shrink(),
        ),
      );

    default:
      // A node type outside the closed vocabulary. `content` is preserved
      // precisely by `RichNode.fromJson` for exactly this: fall back to its
      // descendant text as a paragraph rather than dropping it.
      final text = _descendantText(node);
      if (text.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          isolateBidi(text, Directionality.of(context), wholeRun: false),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
  }
}

Widget _blocks(
  BuildContext context,
  List<RichNode> nodes,
  _RichEntryTileState state,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [for (final node in nodes) _blockNode(context, node, state)],
  );
}

/// A `bulletList`/`orderedList`'s items, each a marker beside its own block
/// content — a `listItem` almost always wraps a `paragraph`, but its content
/// renders through [_blocks] rather than assuming that shape.
Widget _list(
  BuildContext context,
  List<RichNode> items,
  _RichEntryTileState state, {
  required bool ordered,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, item) in items.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  ordered ? '${index + 1}.' : '•',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(child: _blocks(context, item.children, state)),
            ],
          ),
        ),
    ],
  );
}

/// A `paragraph` or `heading`: its `text` children laid out as one span
/// tree, so marks within a run (bold beside plain beside a link) sit on one
/// line instead of wrapping as separate widgets.
///
/// `Text.rich`, not a bare `RichText`: `RichText.textScaler` defaults to
/// [TextScaler.noScaling], so a bare `RichText` ignores the user's system
/// font-size setting while every other tile in this package (all built on
/// `Text`) honours it — at 2x text scale a bullet marker would double while
/// the body text beside it stayed put. `Text.rich` reads
/// `MediaQuery.textScalerOf(context)` like any other `Text`. It also makes
/// this content visible to a plain `find.text()` in tests, since
/// `flutter_test` ignores a standalone `RichText` by default.
Widget _textBlock(
  BuildContext context,
  RichNode node,
  _RichEntryTileState state,
  TextStyle? style,
) {
  final spans = [
    for (final child in node.children) _span(context, child, state),
  ];

  final text = Text.rich(
    TextSpan(
      style: style,
      // A blank ProseMirror paragraph (no children at all) is a
      // deliberate blank-line separator, not nothing — a single space
      // keeps the line's height instead of collapsing it to zero.
      children: spans.isEmpty ? const [TextSpan(text: ' ')] : spans,
    ),
    textAlign: _textAlignOf(node.attrs.textAlign),
    // The paragraph resolves its OWN direction from its own content, rather
    // than inheriting the panel's and letting neutral characters drift to the
    // wrong end. An English sentence inside an `ar` panel rendered
    // `.finish. See the care guide for details` — the full stop is
    // bidi-neutral, so it took the panel's RTL direction and led the line.
    //
    // This is the paragraph-level counterpart of `isolateBidi`, and it exists
    // because a paragraph here is composed from several mark leaves: isolating
    // each leaf individually would fix the punctuation but change how the
    // whole paragraph lays out (measured — a blockquote lost its RTL indent),
    // so the leaves stay unisolated (`wholeRun: false`) and the paragraph is
    // told its direction instead. Null keeps the ambient direction, which is
    // right for a paragraph with no strong character of its own.
    textDirection: directionOf(_descendantText(node)),
  );

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    // `LayoutBuilder`, not a bare `SizedBox(width: double.infinity)`: every
    // ancestor Column here (`_blocks`, `Labelled`) uses
    // `CrossAxisAlignment.start`, which lets a child shrink-wrap to its own
    // content width — so without stretching, `textAlign` above has nothing
    // to align *within* and is a dead argument. But `RichEntryTile` is
    // exported public API, and a host embedding it under an unbounded width
    // (a horizontal `SingleChildScrollView`/`Row`) would have a bare
    // `SizedBox(width: double.infinity)` demand infinite width and crash —
    // a real regression this package doesn't get to cause in someone else's
    // tree. Stretching only when the incoming width is actually bounded
    // gives `textAlign` room to work in the normal (bounded) case and
    // degrades to the old shrink-wrapped behaviour — no visible alignment,
    // no exception — in the unbounded one.
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedWidth
          ? SizedBox(width: double.infinity, child: text)
          : text,
    ),
  );
}

/// Maps the server's closed `textAlign` vocabulary
/// (`RichContentRenderer.php:505`'s `alignments`: `start`, `center`, `end`,
/// `justify` — no `left`/`right`) onto Flutter's [TextAlign]. `start`/`end`
/// are direction-aware by construction — the same value renders on the
/// correct side whether the ambient [Directionality] is LTR or RTL, with no
/// separate RTL branch needed here. Null or anything outside the vocabulary
/// returns null — `Text.rich`'s own default — rather than forcing an
/// alignment the node never asked for.
TextAlign? _textAlignOf(String? raw) => switch (raw) {
  'start' => TextAlign.start,
  'center' => TextAlign.center,
  'end' => TextAlign.end,
  'justify' => TextAlign.justify,
  _ => null,
};

/// One `text` leaf → one [InlineSpan], isolated independently of its
/// siblings (fix round 1, minor 5: a phone number split across a mark
/// boundary — e.g. its first group bold, the rest plain — arrives here as
/// two separate leaves, and neither one alone matches
/// [isolateBidi]'s pattern, so neither gets isolated. Accepted as a
/// known ceiling: a marked-up run splitting mid-group is rare, and merging
/// leaves before isolating would mean re-deriving which merged characters
/// came from which mark to rebuild the per-leaf `TextSpan`s afterward — a
/// real restructure for a case this narrow.
InlineSpan _span(
  BuildContext context,
  RichNode node,
  _RichEntryTileState state,
) {
  if (node.type != 'text') {
    // An inline position holding something other than a text leaf — the
    // same "never lose it" fallback [_blockNode]'s default arm applies to
    // blocks.
    return TextSpan(
      text: isolateBidi(
        _descendantText(node),
        Directionality.of(context),
        wholeRun: false,
      ),
    );
  }

  var style = const TextStyle();
  // `TextStyle.merge` replaces `decoration` outright rather than combining
  // it — a struck-through, underlined run would merge down to underline
  // only. Decorations accumulate here and combine once at the end via
  // `TextDecoration.combine`, so `strike` + `underline`, or `strike` on a
  // link (which also carries `underline`), both survive.
  final decorations = <TextDecoration>[];
  GestureRecognizer? recognizer;

  for (final mark in node.marks) {
    switch (mark.type) {
      case 'bold':
        style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
      case 'italic':
        style = style.merge(const TextStyle(fontStyle: FontStyle.italic));
      case 'strike':
        decorations.add(TextDecoration.lineThrough);
      case 'underline':
        decorations.add(TextDecoration.underline);
      case 'code':
        style = style.merge(
          const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Color(0x14000000),
          ),
        );
      case 'link':
        final href = mark.href;
        // No host wired, or a malformed link mark carrying no href: plain
        // text, no styling, no recognizer. The P6d "no disabled corpses"
        // rule — a styled span that does nothing on tap is worse than a
        // plain one.
        if (href == null || state.widget.onLinkTap == null) continue;
        style = style.merge(const TextStyle(color: Color(0xFF2563EB)));
        decorations.add(TextDecoration.underline);
        recognizer = state._recognizerFor(href);
    }
  }

  if (decorations.isNotEmpty) {
    style = style.merge(
      TextStyle(decoration: TextDecoration.combine(decorations)),
    );
  }

  final text = isolateBidi(
    node.text ?? '',
    Directionality.of(context),
    wholeRun: false,
  );
  return TextSpan(text: text, style: style, recognizer: recognizer);
}

/// Every `text` leaf under [node], concatenated — the fallback content for a
/// node type outside the closed vocabulary.
String _descendantText(RichNode node) {
  if (node.type == 'text') return node.text ?? '';
  return [for (final child in node.children) _descendantText(child)].join();
}

TextStyle? _headingStyle(BuildContext context, int level) {
  final theme = Theme.of(context).textTheme;
  final base = switch (level) {
    1 => theme.headlineSmall,
    2 => theme.titleLarge,
    3 => theme.titleMedium,
    _ => theme.titleSmall,
  };
  return base?.copyWith(fontWeight: FontWeight.bold);
}
