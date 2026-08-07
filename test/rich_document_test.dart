import 'dart:convert';
import 'dart:io';

import 'package:filament_mobile/schema/json_reader.dart';
import 'package:filament_mobile/schema/rich_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read from `contract/record-payload.json` — the golden RecordSnapshotTest
/// writes through the real `/api/mobile-panel/rich/{id}` endpoint over the
/// same bold-run-and-link markup `RichPayloadTest.php` seeds — rather than
/// hand-typed here. A hand-typed copy is exactly the gap Task 7's Step 0
/// closed: the envelope key `'doc'` was hardcoded independently in
/// RecordSerializer.php and in this constant, so a coordinated rename on
/// both sides would have kept both suites green and broken the wire. Reading
/// the golden means a rename on either side now fails loudly here instead.
///
/// Not hand-built: this project has shipped a test that passed against
/// nothing nine times, most recently a fixture whose document was empty, so
/// this one resolves the real bold-run-and-link document rather than a
/// stand-in.
final bannerBodyHtmlRich =
    (jsonDecode(File('../../contract/record-payload.json').readAsStringSync())
            as Map<String, dynamic>)['data']['body_html.__rich']
        as Map<String, dynamic>;

void main() {
  group('RichDocument.fromJson — the golden banners.body_html document', () {
    late RichDocument document;

    setUp(() {
      document = RichDocument.fromJson(bannerBodyHtmlRich, 'body_html.__rich');
    });

    test('carries the flattened plain text a card reads', () {
      expect(document.text, 'Hello world and link');
    });

    test('the root is a doc wrapping one paragraph', () {
      expect(document.root.type, 'doc');
      expect(document.root.children, hasLength(1));

      final paragraph = document.root.children.single;
      expect(paragraph.type, 'paragraph');
      expect(paragraph.attrs.textAlign, 'start');
    });

    test('the paragraph carries the real bold run', () {
      final paragraph = document.root.children.single;
      final bold = paragraph.children.firstWhere((n) => n.text == 'world');

      expect(bold.marks.single.type, 'bold');
      expect(bold.marks.single.href, isNull);
    });

    test('the paragraph carries the real link, not a link Filament\'s own '
        'renderer would have silently dropped', () {
      // The bare-editor trap the design spec measured: a plain `Tiptap\Editor`
      // produces a well-formed document missing the link mark entirely. A
      // document that still carries `href` here is evidence the fixture is
      // real Filament output, not a hand-rolled stand-in that merely parses.
      final paragraph = document.root.children.single;
      final link = paragraph.children.firstWhere((n) => n.text == 'link');

      expect(link.marks.single.type, 'link');
      expect(link.marks.single.href, 'https://example.test');
    });

    test('reassembling every text node matches the flattened text', () {
      final buffer = StringBuffer();
      void walk(RichNode node) {
        if (node.text != null) buffer.write(node.text);
        for (final child in node.children) {
          walk(child);
        }
      }

      walk(document.root);

      expect(buffer.toString(), document.text);
    });
  });

  group('RichNode.fromJson — every node type', () {
    test('paragraph', () {
      final node = RichNode.fromJson(const {
        'type': 'paragraph',
        'content': [
          {'type': 'text', 'text': 'hi'},
        ],
      }, 'n');

      expect(node.type, 'paragraph');
      expect(node.children.single.text, 'hi');
    });

    test('heading carries its level', () {
      final node = RichNode.fromJson(const {
        'type': 'heading',
        'attrs': {'level': 2, 'textAlign': 'center'},
      }, 'n');

      expect(node.attrs.level, 2);
      expect(node.attrs.textAlign, 'center');
    });

    test('bulletList, orderedList and listItem nest as containers', () {
      final node = RichNode.fromJson(const {
        'type': 'bulletList',
        'content': [
          {
            'type': 'listItem',
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {'type': 'text', 'text': 'one'},
                ],
              },
            ],
          },
        ],
      }, 'n');

      expect(node.type, 'bulletList');
      final item = node.children.single;
      expect(item.type, 'listItem');
      expect(item.children.single.type, 'paragraph');
      expect(item.children.single.children.single.text, 'one');

      final ordered = RichNode.fromJson(const {'type': 'orderedList'}, 'n');
      expect(ordered.type, 'orderedList');
      expect(ordered.children, isEmpty);
    });

    test('blockquote wraps its content', () {
      final node = RichNode.fromJson(const {
        'type': 'blockquote',
        'content': [
          {'type': 'paragraph'},
        ],
      }, 'n');

      expect(node.type, 'blockquote');
      expect(node.children.single.type, 'paragraph');
    });

    test('horizontalRule is a leaf', () {
      final node = RichNode.fromJson(const {'type': 'horizontalRule'}, 'n');

      expect(node.type, 'horizontalRule');
      expect(node.children, isEmpty);
    });

    test('image carries src', () {
      final node = RichNode.fromJson(const {
        'type': 'image',
        'attrs': {'src': 'https://x.test/a.png'},
      }, 'n');

      expect(node.attrs.src, 'https://x.test/a.png');
    });

    test('image without src parses with a null src, not a throw', () {
      // Filament's own state cast nulls attrs.src for a private-visibility
      // attachment (design spec, "Images"). Task 6 skips rendering it; this
      // parser must not fail the whole document over it.
      final node = RichNode.fromJson(const {'type': 'image'}, 'n');

      expect(node.attrs.src, isNull);
    });

    test('text carries its string', () {
      final node = RichNode.fromJson(const {
        'type': 'text',
        'text': 'plain',
      }, 'n');

      expect(node.text, 'plain');
      expect(node.children, isEmpty);
    });
  });

  group('RichNode.fromJson — every mark', () {
    RichNode textWithMark(Map<String, dynamic> mark) => RichNode.fromJson({
      'type': 'text',
      'text': 'x',
      'marks': [mark],
    }, 'n');

    test('bold, italic, strike, underline and code carry no attrs', () {
      for (final type in ['bold', 'italic', 'strike', 'underline', 'code']) {
        final node = textWithMark({'type': type});
        expect(node.marks.single.type, type, reason: type);
        expect(node.marks.single.href, isNull, reason: type);
      }
    });

    test('link carries href', () {
      final node = textWithMark({
        'type': 'link',
        'attrs': {'href': 'https://x.test'},
      });

      expect(node.marks.single.type, 'link');
      expect(node.marks.single.href, 'https://x.test');
    });
  });

  group('RichNode.fromJson — an unrecognised node type', () {
    test('survives as the parse root, keeping its descendant text', () {
      // Root-level case: proves RichNode itself never validates `type`
      // against the closed vocabulary — kills a mutation that makes an
      // unrecognised `type` throw in fromJson. Kept alongside the nested
      // case below rather than replaced by it: this is the one that catches
      // a throw-on-unknown-type regression; the nested one is the one that
      // catches a drop-unknown-type regression.
      final node = RichNode.fromJson(const {
        'type': 'table',
        'content': [
          {'type': 'text', 'text': 'cell one'},
        ],
      }, 'n');

      expect(node.type, 'table');
      expect(node.children.single.text, 'cell one');
    });

    test('survives nested inside doc alongside a recognised sibling, '
        'keeping its descendant text', () {
      // The position that actually occurs. A novel node type is never the
      // parse root of a real document — it is a CHILD of `doc`, sitting
      // among known siblings (a paragraph before it, here). A
      // closed-vocabulary filter applied at the child level in
      // `_childrenFrom` — the natural place someone would add one,
      // mirroring `SchemaComponent`'s `UnknownComponent` dispatch — would
      // delete this node and its content while the root-level test above
      // keeps passing, because that test never puts the unrecognised type
      // where content actually goes missing from. This test exercises
      // that exact position: Task 6 renders `table` as a paragraph of its
      // surviving text, and there must be text left to render.
      final document = RichDocument.fromJson(const {
        'doc': {
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'before'},
              ],
            },
            {
              'type': 'table',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'cell one'},
                  ],
                },
              ],
            },
          ],
        },
        'text': 'before cell one',
      }, 'body_html.__rich');

      expect(document.root.children, hasLength(2));

      final table = document.root.children[1];
      expect(table.type, 'table');
      expect(
        table.children.single.children.single.text,
        'cell one',
        reason: 'descendant text must survive an unrecognised node type',
      );
    });
  });

  group('RichNode.fromJson — malformed children', () {
    test('a child missing type is dropped without costing its siblings', () {
      final node = RichNode.fromJson(const {
        'type': 'paragraph',
        'content': [
          {'type': 'text', 'text': 'good'},
          {'no_type': true},
          {'type': 'text', 'text': 'also good'},
        ],
      }, 'n');

      expect(node.children.map((n) => n.text), ['good', 'also good']);
    });

    test('a child that is not even an object is dropped', () {
      final node = RichNode.fromJson(const {
        'type': 'paragraph',
        'content': [
          {'type': 'text', 'text': 'good'},
          'not an object',
          42,
        ],
      }, 'n');

      expect(node.children.single.text, 'good');
    });

    test('a malformed mark is dropped without costing the node', () {
      final node = RichNode.fromJson(const {
        'type': 'text',
        'text': 'x',
        'marks': [
          {'type': 'bold'},
          {'no_type': true},
          'not an object',
        ],
      }, 'n');

      expect(node.marks.single.type, 'bold');
    });
  });

  group('RichNode.fromJson — contract violations', () {
    test('content arriving as the wrong type throws', () {
      expect(
        () => RichNode.fromJson(const {
          'type': 'paragraph',
          'content': 'not a list',
        }, 'n'),
        throwsA(isA<SchemaFormatException>()),
      );
    });

    test('a node with no type throws', () {
      expect(
        () => RichNode.fromJson(const {'text': 'x'}, 'n'),
        throwsA(isA<SchemaFormatException>()),
      );
    });
  });

  group('RichDocument.fromJson — contract violations', () {
    test('a sibling with no doc throws', () {
      expect(
        () => RichDocument.fromJson(const {'text': 'x'}, 'body_html.__rich'),
        throwsA(isA<SchemaFormatException>()),
      );
    });
  });
}
