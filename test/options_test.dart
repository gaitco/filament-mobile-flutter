import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';

/// The remote option source, from the client's side.
///
/// `/schema` publishes `config.optionsUrl` instead of inline options when the
/// list is not knowable at publish time or has outgrown the wire, and this is
/// what the client does about it.
void main() {
  const acme = SelectOption(value: 3, label: 'Acme Ltd');

  test('a stale options response never replaces a fresh one', () async {
    // P1 shipped this bug in ResourceListProvider and the form provider has
    // guarded it twice since. A search box types fast; the first response
    // resolving last must be dropped.
    final source = FakeSource(
      components: formWith(),
      optionsResponse: const OptionsPage(options: [acme], hasMore: false),
    );
    final provider = providerFor(source);
    await provider.load();

    source.holdNextOptions();
    final stale = provider.searchOptions('company_id', 'ac');
    final fresh = provider.searchOptions('company_id', 'acme');

    // The FRESH one resolves first, then the held stale one completes with a
    // different payload. Without the guard the stale answer lands last and wins.
    await fresh;
    source.completeHeldOptions(const OptionsPage(options: [], hasMore: false));
    await stale;

    expect(provider.optionsFor('company_id'), [acme]);
  });

  test('the request carries the form values, not an empty map', () async {
    // Options depend on siblings — a pilot measured a dependent picker
    // narrowing 6 -> 2 -> 1 as its parent changed. Sending {} would make every
    // dependent select wrong.
    final source = FakeSource(components: formWith());
    final provider = providerFor(source);
    await provider.load();
    provider.change('name', 'Sara');

    await provider.searchOptions('company_id', '');

    expect(source.lastOptionsValues['name'], 'Sara');
  });

  test('the query reaches the server verbatim', () async {
    final source = FakeSource(components: formWith());
    final provider = providerFor(source);
    await provider.load();

    await provider.searchOptions('company_id', 'acme');

    expect(source.lastOptionsQuery, 'acme');
  });

  test('two fields search independently', () async {
    // One counter per field. A shared sequence would let a search in one
    // picker silently cancel the answer already showing in another.
    final source = FakeSource(
      components: formWith(),
      optionsResponse: const OptionsPage(options: [acme], hasMore: false),
    );
    final provider = providerFor(source);
    await provider.load();

    // CONCURRENT, not sequential. Awaited one after the other, a single shared
    // counter still works — each search finishes before the next begins — so
    // the test would pass against an implementation that has no per-field
    // sequencing at all. Overlapping them is what makes it discriminate.
    source.holdNextOptions();
    final first = provider.searchOptions('company_id', 'a');
    await provider.searchOptions('tag_ids', 'b');
    source.completeHeldOptions(
      const OptionsPage(options: [acme], hasMore: false),
    );
    await first;

    expect(provider.optionsFor('company_id'), [acme]);
    expect(provider.optionsFor('tag_ids'), [acme]);
  });

  test('a transport failure leaves the form usable', () async {
    // Degrade, never block. A picker that cannot reach the server shows what
    // it already had; it does not take the form down.
    final source = FakeSource(
      components: formWith(),
      optionsError: const FilamentTransportException('لا يوجد اتصال'),
    );
    final provider = providerFor(source);
    await provider.load();

    final page = await provider.searchOptions('company_id', 'x');

    expect(page.options, isEmpty);
    expect(provider.components, isNotEmpty);
    expect(provider.formError, isNull);
  });

  test('a failed search keeps the options already shown', () async {
    // The stronger half of the rule above: losing the list on a dropped
    // connection is how a user concludes the record does not exist.
    final source = FakeSource(
      components: formWith(),
      optionsResponse: const OptionsPage(options: [acme], hasMore: false),
    );
    final provider = providerFor(source);
    await provider.load();
    await provider.searchOptions('company_id', 'ac');

    final failing = FakeSource(
      components: formWith(),
      optionsError: const FilamentTransportException('لا يوجد اتصال'),
    );
    final second = providerFor(failing);
    await second.load();
    await second.searchOptions('company_id', 'x');

    expect(provider.optionsFor('company_id'), [acme]);
    expect(second.optionsFor('company_id'), isEmpty);
  });

  test('optionsFor is empty before anything is fetched', () {
    final provider = providerFor(FakeSource(components: formWith()));

    expect(provider.optionsFor('company_id'), isEmpty);
  });

  test('hasMore travels back to the caller', () async {
    // The client says "keep typing" rather than implying the list ended.
    final source = FakeSource(
      components: formWith(),
      optionsResponse: const OptionsPage(options: [acme], hasMore: true),
    );
    final provider = providerFor(source);
    await provider.load();

    expect((await provider.searchOptions('company_id', 'a')).hasMore, isTrue);
  });
}
