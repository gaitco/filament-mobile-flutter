import 'package:equatable/equatable.dart';

import '../schema/schema_component.dart';

/// One page of a select's options, fetched rather than inlined.
///
/// `/schema` publishes `config.optionsUrl` instead of `config.options` when the
/// options are not knowable at publish time — a searchable relationship select,
/// which Filament deliberately declines to enumerate — or when the list outgrew
/// the wire. This is what comes back from that endpoint.
class OptionsPage extends Equatable {
  const OptionsPage({required this.options, required this.hasMore});

  const OptionsPage.empty() : options = const [], hasMore = false;

  final List<SelectOption> options;

  /// The server hit its own ceiling, so there may be more behind a narrower
  /// query. A client says "keep typing" rather than implying the list ended —
  /// implying a truncated list is complete is how a user concludes their
  /// record does not exist.
  final bool hasMore;

  @override
  List<Object?> get props => [options, hasMore];
}
