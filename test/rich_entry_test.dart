import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/rich_document.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/entries/rich_entry_tile.dart';
import 'package:filament_mobile/ui/entry_registry.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

RichDocument doc(Map<String, dynamic> root) =>
    RichDocument.fromJson({'doc': root, 'text': ''}, 'test.__rich');

/// Finds the [TextSpan] carrying exactly [text], searching the whole tree of
/// every [RichText] on screen. `_textBlock` builds `Text.rich`, which wraps
/// the tile's own span one level deeper (inside `Text.build`'s own outer
/// `TextSpan`), so this recurses to any depth rather than assuming a fixed
/// shape.
TextSpan spanWithText(WidgetTester tester, String text) {
  TextSpan? search(InlineSpan span) {
    if (span is! TextSpan) return null;
    if (span.text == text) return span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (search(child) case final found?) return found;
    }
    return null;
  }

  for (final element in tester.widgetList<RichText>(find.byType(RichText))) {
    if (search(element.text) case final found?) return found;
  }
  fail('no TextSpan with text "$text" found among the rendered RichTexts');
}

void main() {
  group('RichEntryTile — blocks render distinguishably', () {
    // Every node type the vocabulary defines, in one document, each holding
    // text unique enough to assert on independently.
    final document = doc({
      'type': 'doc',
      'content': [
        {
          'type': 'heading',
          'attrs': {'level': 1},
          'content': [
            {'type': 'text', 'text': 'Heading'},
          ],
        },
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'Body text'},
          ],
        },
        {
          'type': 'bulletList',
          'content': [
            {
              'type': 'listItem',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'bullet one'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'type': 'orderedList',
          'content': [
            {
              'type': 'listItem',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'ordered one'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'type': 'blockquote',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'quoted text'},
              ],
            },
          ],
        },
        {'type': 'horizontalRule'},
      ],
    });

    testWidgets('a heading renders larger than body text', (tester) async {
      await tester.pumpWidget(host(RichEntryTile(document: document)));

      // `Text.rich`'s own `textSpan` field is exactly the span this tile
      // built (`_textBlock`'s `style` argument), before `Text.build()` wraps
      // it under a `DefaultTextStyle`-derived outer span — reading it
      // directly is simpler than digging into the rendered `RichText` tree.
      final heading = tester.widget<Text>(find.text('Heading')).textSpan!;
      final body = tester.widget<Text>(find.text('Body text')).textSpan!;

      expect(
        heading.style!.fontSize! > body.style!.fontSize!,
        isTrue,
        reason: 'heading fontSize should exceed body fontSize',
      );
    });

    testWidgets('list items are bulleted or numbered', (tester) async {
      await tester.pumpWidget(host(RichEntryTile(document: document)));

      expect(find.text('•'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('bullet one'), findsOneWidget);
      expect(find.text('ordered one'), findsOneWidget);
    });

    testWidgets('a blockquote is indented with a border', (tester) async {
      await tester.pumpWidget(host(RichEntryTile(document: document)));

      final bordered = find.ancestor(
        of: find.text('quoted text'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border != null,
        ),
      );
      expect(bordered, findsOneWidget);
    });

    testWidgets('a horizontal rule draws a divider', (tester) async {
      await tester.pumpWidget(host(RichEntryTile(document: document)));

      expect(find.byType(Divider), findsOneWidget);
    });

    // ProseMirror emits a childless `paragraph` as a deliberate blank-line
    // separator between two other blocks — collapsing it to zero height
    // would run the surrounding paragraphs together, losing the author's
    // spacing.
    testWidgets('a blank paragraph keeps a line of space, not zero height', (
      tester,
    ) async {
      final withGap = doc({
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'above'},
            ],
          },
          {'type': 'paragraph', 'content': <dynamic>[]},
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'below'},
            ],
          },
        ],
      });

      await tester.pumpWidget(host(RichEntryTile(document: withGap)));

      final above = tester.getBottomLeft(find.text('above'));
      final below = tester.getTopLeft(find.text('below'));

      // Two paragraphs' own vertical padding (4 + 4 either side) accounts
      // for at most 16px; a genuine blank line adds a further line height
      // on top of that gap.
      expect(below.dy - above.dy, greaterThan(30));
    });
  });

  group('RichEntryTile — accessibility', () {
    // `RichText.textScaler` defaults to `TextScaler.noScaling` — a bare
    // `RichText` ignores the user's system font-size setting entirely,
    // while every other tile in this package (all built on `Text`) honours
    // it. `Text.rich` reads `MediaQuery.textScalerOf(context)` like any
    // other `Text`.
    testWidgets('inline text grows with the ambient text scaler', (
      tester,
    ) async {
      final document = doc({
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'scaled text'},
            ],
          },
        ],
      });

      Future<double> heightAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: RichEntryTile(document: document)),
            ),
          ),
        );
        return tester.getSize(find.text('scaled text')).height;
      }

      final base = await heightAt(1);
      final scaled = await heightAt(2);

      expect(
        scaled,
        greaterThan(base * 1.5),
        reason: 'doubling the text scaler should roughly double the height',
      );
    });
  });

  group('RichEntryTile — marks render', () {
    final document = doc({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': 'bold',
              'marks': [
                {'type': 'bold'},
              ],
            },
            {
              'type': 'text',
              'text': 'italic',
              'marks': [
                {'type': 'italic'},
              ],
            },
            {
              'type': 'text',
              'text': 'strike',
              'marks': [
                {'type': 'strike'},
              ],
            },
            {
              'type': 'text',
              'text': 'underline',
              'marks': [
                {'type': 'underline'},
              ],
            },
            {
              'type': 'text',
              'text': 'code',
              'marks': [
                {'type': 'code'},
              ],
            },
          ],
        },
      ],
    });

    testWidgets(
      'bold, italic, strike, underline and code each style their run',
      (tester) async {
        await tester.pumpWidget(host(RichEntryTile(document: document)));

        expect(spanWithText(tester, 'bold').style?.fontWeight, FontWeight.bold);
        expect(
          spanWithText(tester, 'italic').style?.fontStyle,
          FontStyle.italic,
        );
        expect(
          spanWithText(tester, 'strike').style?.decoration,
          TextDecoration.lineThrough,
        );
        expect(
          spanWithText(tester, 'underline').style?.decoration,
          TextDecoration.underline,
        );
        expect(spanWithText(tester, 'code').style?.fontFamily, 'monospace');
      },
    );

    // `TextStyle.merge` replaces `decoration` rather than combining it, so
    // accumulating marks naively would let the last decoration mark win and
    // silently drop the others — content loss, not just a cosmetic miss.
    testWidgets('overlapping decoration marks combine instead of colliding', (
      tester,
    ) async {
      final tapped = <String>[];
      final combined = doc({
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {
                'type': 'text',
                'text': 'struckline',
                'marks': [
                  {'type': 'strike'},
                  {'type': 'underline'},
                ],
              },
              {
                'type': 'text',
                'text': 'linkstrike',
                'marks': [
                  {'type': 'strike'},
                  {
                    'type': 'link',
                    'attrs': {'href': 'https://x.test'},
                  },
                ],
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(
        host(RichEntryTile(document: combined, onLinkTap: tapped.add)),
      );

      final struckline = spanWithText(tester, 'struckline').style!.decoration!;
      expect(struckline.contains(TextDecoration.lineThrough), isTrue);
      expect(struckline.contains(TextDecoration.underline), isTrue);

      // A link mark contributes its own `underline` (the P6d styling), so a
      // struck-through link should carry both, not just the link's.
      final linkstrike = spanWithText(tester, 'linkstrike').style!.decoration!;
      expect(linkstrike.contains(TextDecoration.lineThrough), isTrue);
      expect(linkstrike.contains(TextDecoration.underline), isTrue);
    });
  });

  group('RichEntryTile — links', () {
    RichDocument linkDoc(String text) => doc({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': text,
              'marks': [
                {
                  'type': 'link',
                  'attrs': {'href': 'https://x.test'},
                },
              ],
            },
          ],
        },
      ],
    });

    // The failure this project keeps repeating is a test that passes
    // against nothing: an unwired-link test must prove the ABSENCE of link
    // styling and of a tap handler, not merely that the text is on screen.
    testWidgets(
      'an unwired host renders a link as plain text with no link styling',
      (tester) async {
        await tester.pumpWidget(
          host(RichEntryTile(document: linkDoc('plain link'))),
        );

        expect(find.text('plain link'), findsOneWidget);

        final span = spanWithText(tester, 'plain link');
        expect(span.recognizer, isNull);
        expect(span.style?.color, isNull);
        expect(span.style?.decoration, isNull);
      },
    );

    testWidgets('a wired host makes the link tappable and reports its href', (
      tester,
    ) async {
      final tapped = <String>[];

      await tester.pumpWidget(
        host(RichEntryTile(document: linkDoc('tap me'), onLinkTap: tapped.add)),
      );

      final span = spanWithText(tester, 'tap me');
      expect(span.recognizer, isA<TapGestureRecognizer>());
      expect(span.style?.color, isNotNull);
      expect(span.style?.decoration, TextDecoration.underline);

      // A real hit test through the render tree — not calling the
      // recognizer's callback directly — so this exercises the position a
      // wiring bug would actually occupy.
      await tester.tapOnText(find.textRange.ofSubstring('tap me'));

      expect(tapped, ['https://x.test']);
    });
  });

  group('RichEntryTile — images', () {
    testWidgets('an image with no src is skipped, not rendered broken', (
      tester,
    ) async {
      final document = doc({
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'before'},
            ],
          },
          {'type': 'image', 'attrs': <String, dynamic>{}},
          {
            'type': 'paragraph',
            'content': [
              {'type': 'text', 'text': 'after'},
            ],
          },
        ],
      });

      await tester.pumpWidget(host(RichEntryTile(document: document)));

      expect(find.byType(Image), findsNothing);
      expect(find.text('before'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RichEntryTile — unknown nodes', () {
    // The node sits as a CHILD of `doc`, not as the parse root — `doc` is
    // always the literal root, so an unknown node never occupies that
    // position in a real document. Task 5's own review caught a test that
    // parsed the unknown node AS the root, which let a child-level filter
    // that deleted content pass fully green.
    testWidgets(
      'an unknown block node renders its descendant text as a paragraph, '
      'without losing its known sibling',
      (tester) async {
        final document = doc({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'known paragraph'},
              ],
            },
            {
              'type': 'customBlock',
              'content': [
                {'type': 'text', 'text': 'unknown '},
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'nested text'},
                  ],
                },
              ],
            },
          ],
        });

        await tester.pumpWidget(host(RichEntryTile(document: document)));

        expect(find.text('known paragraph'), findsOneWidget);
        expect(find.text('unknown nested text'), findsOneWidget);
      },
    );

    testWidgets(
      'an unknown inline node keeps its text inside a known paragraph',
      (tester) async {
        final document = doc({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'before '},
                {
                  'type': 'futureInline',
                  'content': [
                    {'type': 'text', 'text': 'kept'},
                  ],
                },
                {'type': 'text', 'text': ' after'},
              ],
            },
          ],
        });

        await tester.pumpWidget(host(RichEntryTile(document: document)));

        final richText = tester.widget<RichText>(find.byType(RichText).first);
        expect(richText.text.toPlainText(), 'before kept after');
      },
    );
  });

  group('EntryRegistry — EntryKind.rich', () {
    SchemaComponent richComponent() => SchemaComponent.fromJson(const {
      'type': 'rich_entry',
      'name': 'body',
      'label': 'Body',
    }, 'infolist[0]');

    testWidgets(
      'renders the parsed document through the registry, not the raw markup',
      (tester) async {
        final record = ResourceRecord.fromJson(const {
          'id': 1,
          'body': '<p>Hello <strong>world</strong></p>',
          'body.__rich': {
            'doc': {
              'type': 'doc',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'Hello world'},
                  ],
                },
              ],
            },
            'text': 'Hello world',
          },
        }, 'id');

        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => EntryRegistry.defaults().build(
                context,
                richComponent(),
                record,
              ),
            ),
          ),
        );

        expect(find.text('Body'), findsOneWidget);
        expect(find.text('Hello world'), findsOneWidget);
        // Proves the document was rendered, not the raw column dumped as
        // text — a test that only checked the label, or checked for text
        // containing "Hello", would pass even if the raw markup leaked
        // through.
        expect(find.textContaining('<p>'), findsNothing);
        expect(find.textContaining('<strong>'), findsNothing);
      },
    );

    testWidgets(
      'with no __rich sibling, falls back to the raw string like `text`',
      (tester) async {
        final record = ResourceRecord.fromJson(const {
          'id': 1,
          'body': '<p>raw markup</p>',
        }, 'id');

        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => EntryRegistry.defaults().build(
                context,
                richComponent(),
                record,
              ),
            ),
          ),
        );

        expect(find.text('<p>raw markup</p>'), findsOneWidget);
      },
    );

    testWidgets('threads onLinkTap from EntryRegistry.defaults into the tile', (
      tester,
    ) async {
      final tapped = <String>[];
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'body': 'raw',
        'body.__rich': {
          'doc': {
            'type': 'doc',
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': 'wired link',
                    'marks': [
                      {
                        'type': 'link',
                        'attrs': {'href': 'https://x.test'},
                      },
                    ],
                  },
                ],
              },
            ],
          },
          'text': 'wired link',
        },
      }, 'id');

      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => EntryRegistry.defaults(
              onLinkTap: tapped.add,
            ).build(context, richComponent(), record),
          ),
        ),
      );

      await tester.tapOnText(find.textRange.ofSubstring('wired link'));
      expect(tapped, ['https://x.test']);
    });
  });

  group('ResourceCard — a rich column shows plain text, not markup', () {
    testWidgets('reads <field>.__rich.text instead of the raw column', (
      tester,
    ) async {
      // The fixture MUST carry the `__rich` sibling: a payload without one
      // would pass this test by coincidence (the raw value happens to
      // contain no markup) and prove nothing about the read path this test
      // exists to cover.
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'body': '<p>Hello <strong>world</strong></p>',
        'body.__rich': {
          'doc': {'type': 'doc', 'content': <dynamic>[]},
          'text': 'Hello world',
        },
      }, 'id');

      await tester.pumpWidget(
        host(
          ResourceCard(
            layout: const CardLayout(titleField: 'body'),
            record: record,
          ),
        ),
      );

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.textContaining('<p>'), findsNothing);
      expect(find.textContaining('<strong>'), findsNothing);
    });

    testWidgets('a field with no __rich sibling still shows its raw value', (
      tester,
    ) async {
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'name': 'plain field',
      }, 'id');

      await tester.pumpWidget(
        host(
          ResourceCard(
            layout: const CardLayout(titleField: 'name'),
            record: record,
          ),
        ),
      );

      expect(find.text('plain field'), findsOneWidget);
    });
  });
}
