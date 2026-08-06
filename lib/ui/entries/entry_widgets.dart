import 'package:flutter/material.dart';

import '../semantic_badge.dart';

/// The tiles an infolist is built from. Every one of them is label-above-value,
/// so they share [_Labelled] and differ only in how the value is drawn.
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
    return _Labelled(
      label: label,
      child: Text(
        value ?? _emptyValue,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
    return _Labelled(
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

    return _Labelled(
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

    return _Labelled(
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
class _Labelled extends StatelessWidget {
  const _Labelled({required this.child, this.label});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(label!, style: Theme.of(context).textTheme.labelMedium),
          child,
        ],
      ),
    );
  }
}
