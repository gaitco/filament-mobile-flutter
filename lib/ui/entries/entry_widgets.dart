import 'package:flutter/material.dart';

import '../bidi_text.dart';
import '../semantic_badge.dart';

/// The tiles an infolist is built from. Every one of them is label-above-value,
/// so they share [Labelled] and differ only in how the value is drawn.
///
/// A missing value is never an error here: the server sends whatever the record
/// holds, and a null renders as an em dash (or, for an image, a placeholder)
/// so an empty optional field looks intentional rather than broken.

/// A plain text entry — also, for now, where a date entry lands.
///
/// A date renders raw, exactly as the server serialised it.
/// `EntryComponent.format` carries an `intl` pattern that nothing here applies:
/// formatting it needs the `intl` package, and P1 ships zero new runtime
/// dependencies. A known gap, waiting on a phase that can take the dependency.
class EntryTile extends StatelessWidget {
  const EntryTile({this.label, this.value, super.key});

  final String? label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    // Grouped digits (a phone number, a spaced IBAN, a hyphenated tax
    // number) reverse inside RTL text otherwise — see `bidi_text.dart`. A
    // no-op under LTR and on plain prose with no such run.
    final text = value == null
        ? _emptyValue
        : isolateBidi(value!, Directionality.of(context));

    return Labelled(
      label: label,
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// A boolean entry as a tick or a cross — never the word `true`.
class BooleanEntryTile extends StatelessWidget {
  const BooleanEntryTile({required this.value, this.label, super.key});

  final String? label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Labelled(
      label: label,
      child: Icon(
        value ? Icons.check_circle : Icons.cancel,
        color: value ? const Color(0xFF16A34A) : const Color(0xFF6B7280),
        size: 20,
      ),
    );
  }
}

/// A remote image, degrading to a placeholder box when the URL is null or the
/// fetch fails. A media-library field that serialises as null is a known
/// server-side gap; it must not look like a crash.
class ImageEntryTile extends StatelessWidget {
  const ImageEntryTile({this.label, this.url, super.key});

  final String? label;
  final String? url;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final url = this.url;

    return Labelled(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: url == null || url.isEmpty
            ? _placeholder(context)
            : Image.network(
                url,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined),
    );
  }
}

/// A badge entry, sharing [SemanticBadge] with the list card so one value keeps
/// one colour across both screens.
class BadgeEntryTile extends StatelessWidget {
  const BadgeEntryTile({
    this.label,
    this.value,
    this.colors = const {},
    super.key,
  });

  final String? label;
  final String? value;
  final Map<String, String> colors;

  @override
  Widget build(BuildContext context) {
    final value = this.value;

    return Labelled(
      label: label,
      child: value == null
          ? Text(_emptyValue, style: Theme.of(context).textTheme.bodyMedium)
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: SemanticBadge(value: value, colors: colors),
            ),
    );
  }
}

/// A layout component's children under its heading. Every layout kind renders
/// the same way on a phone — a grid's columns collapse to one — so `kind` and
/// `columns` are carried by the schema but unused until a tablet renderer wants
/// them.
class SectionTile extends StatelessWidget {
  const SectionTile({required this.children, this.label, super.key});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(label!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

const String _emptyValue = '—';

/// The one shape every entry shares: a small label with its value beneath.
///
/// Public — not just this file's tiles — so `RichEntryTile`
/// (`rich_entry_tile.dart`) wraps in the same shape rather than
/// re-implementing it.
class Labelled extends StatelessWidget {
  const Labelled({required this.child, this.label, super.key});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A label needs to read as a *label*, not as a sibling line of the value
    // it names. Before this it used `labelMedium` at full opacity directly
    // above the value at body size, which on a real screen looked like two
    // paragraphs of similar weight stacked with 6px between them — the flat
    // wall the owner's screenshot showed. Muted, slightly tracked out, and
    // given a little more room underneath, it recedes and the value leads.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
          ],
          child,
        ],
      ),
    );
  }
}
