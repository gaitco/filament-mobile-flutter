import 'package:equatable/equatable.dart';

import 'json_reader.dart';

/// A parsed rich-text document — the client's read of the ProseMirror tree
/// TipTap/Filament's `RichContentRenderer` publishes as `<path>.__rich.doc`,
/// alongside the flattened `<path>.__rich.text` a card reads instead
/// (design spec, "Wire shape"). The sibling is absent entirely when there is
/// nothing to convert — absence means unavailable, and every consumer falls
/// back to the raw string; that fallback happens above this parser, which
/// only ever sees a sibling that exists.
///
/// The vocabulary is small and closed (design spec, "measured, closed,
/// complete"): ten node types, six marks. This parser does not enforce that
/// closure — an unrecognised node or mark is carried through with its raw
/// `type` string rather than dropped, so a future Filament version adding one
/// degrades to a paragraph of its descendant text (Task 6) instead of
/// deleting content silently.
class RichDocument extends Equatable {
  const RichDocument({required this.root, required this.text});

  /// [json] is the `<path>.__rich` sibling itself — `{"doc": …, "text": …}`
  /// — not the bare ProseMirror tree.
  factory RichDocument.fromJson(Map<String, dynamic> json, String path) {
    return RichDocument(
      root: RichNode.fromJson(
        req<Map<String, dynamic>>(json, 'doc', path),
        '$path.doc',
      ),
      text: opt<String>(json, 'text') ?? '',
    );
  }

  /// The document tree, rooted at a `doc` node.
  final RichNode root;

  /// The flattened plain text a card reads instead of walking [root] —
  /// carried here too so a consumer holding a [RichDocument] does not need
  /// the sibling's raw JSON a second time.
  final String text;

  @override
  List<Object?> get props => [root, text];
}

/// One node of the ProseMirror tree: `doc`, `paragraph`, `text`, `heading`,
/// `bulletList`, `orderedList`, `listItem`, `blockquote`, `horizontalRule`,
/// `image` — or a type this build does not recognise, carried through by its
/// raw string rather than rejected (see [RichDocument]'s doc).
class RichNode extends Equatable {
  const RichNode({
    required this.type,
    required this.attrs,
    required this.marks,
    this.text,
    this.children = const [],
  });

  factory RichNode.fromJson(Map<String, dynamic> json, String path) {
    return RichNode(
      type: req<String>(json, 'type', path),
      attrs: RichAttrs.fromJson(object(json, 'attrs', path) ?? const {}),
      marks: _marksFrom(json),
      text: opt<String>(json, 'text'),
      children: _childrenFrom(json, path),
    );
  }

  /// Parses `content` one child at a time, matching
  /// `RepeaterComponent._templateFrom`'s discipline: a single malformed
  /// child — missing `type`, or not even an object — is dropped rather than
  /// failing the whole node. `content` itself absent reads as no children (a
  /// leaf node); present but not a list is a genuine contract violation and
  /// throws, the same distinction [object] draws for a whole container
  /// arriving as the wrong shape.
  static List<RichNode> _childrenFrom(Map<String, dynamic> json, String path) {
    final raw = json['content'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw SchemaFormatException(
        '$path.content',
        'expected List, got ${raw.runtimeType}',
      );
    }

    final children = <RichNode>[];
    for (var index = 0; index < raw.length; index++) {
      final node = raw[index];
      if (node is! Map<String, dynamic>) continue;
      try {
        children.add(RichNode.fromJson(node, '$path.content[$index]'));
      } on SchemaFormatException {
        continue;
      }
    }
    return children;
  }

  /// A malformed mark — not an object, or missing `type` — is dropped rather
  /// than failing the node it decorates. `marks` absent or the wrong shape
  /// reads as no marks: the scalar-widening licence [opt] documents, not the
  /// stricter contract-violation rule [object] applies to a whole container.
  static List<RichMark> _marksFrom(Map<String, dynamic> json) {
    final raw = json['marks'];
    if (raw is! List) return const [];

    final marks = <RichMark>[];
    for (final mark in raw) {
      if (mark is! Map<String, dynamic>) continue;
      final type = opt<String>(mark, 'type');
      if (type == null) continue;
      final attrs = mark['attrs'];
      marks.add(
        RichMark(
          type: type,
          href: attrs is Map<String, dynamic>
              ? opt<String>(attrs, 'href')
              : null,
        ),
      );
    }
    return marks;
  }

  /// The raw contract discriminator — kept even for a type this build does
  /// not otherwise recognise, so a caller can special-case it if it wants to.
  final String type;

  final RichAttrs attrs;
  final List<RichMark> marks;

  /// Set only on a `text` node.
  final String? text;

  /// Child nodes, e.g. a `paragraph`'s inline content or a `bulletList`'s
  /// items. Empty for a leaf (`text`, `horizontalRule`, `image`).
  final List<RichNode> children;

  @override
  List<Object?> get props => [type, attrs, marks, text, children];
}

/// A mark applied to a `text` node — `bold`, `italic`, `link`, `strike`,
/// `underline` or `code`. Only `link` carries an attribute in the closed
/// vocabulary (design spec), so [href] is the one typed extra rather than a
/// generic bag.
class RichMark extends Equatable {
  const RichMark({required this.type, this.href});

  final String type;
  final String? href;

  @override
  List<Object?> get props => [type, href];
}

/// The attrs a node in the closed vocabulary carries: `textAlign` on
/// `paragraph`/`heading`, `level` on `heading`, `src` on `image`. All three
/// live on one small value type rather than a `RichNode` subclass per node
/// kind, since no node carries more than one of them.
class RichAttrs extends Equatable {
  const RichAttrs({this.textAlign, this.level, this.src});

  factory RichAttrs.fromJson(Map<String, dynamic> json) {
    return RichAttrs(
      textAlign: opt<String>(json, 'textAlign'),
      level: opt<int>(json, 'level'),
      src: opt<String>(json, 'src'),
    );
  }

  final String? textAlign;
  final int? level;
  final String? src;

  @override
  List<Object?> get props => [textAlign, level, src];
}
