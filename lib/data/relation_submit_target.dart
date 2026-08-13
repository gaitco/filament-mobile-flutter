import '../schema/relation_descriptor.dart';

/// Where a form's submission goes when it edits a relation ROW instead of a
/// record of the form's own resource (P9): the relation endpoint on the
/// PARENT, not the child resource's own endpoint.
///
/// The form itself renders the CHILD resource's `ResourceSchema` — only the
/// write target changes, which is the whole point of the type: one small
/// value carried into `ResourceFormProvider`, rather than a forked form
/// screen. Create vs update is decided by the provider's own `recordId`
/// (null = create), exactly as the resource write path already decides it;
/// the update URL's `{child}` segment is that same id.
class RelationSubmitTarget {
  const RelationSubmitTarget({
    required this.resourceKey,
    required this.recordId,
    required this.relation,
  });

  /// The PARENT resource's key — deliberately not named `parentResourceKey`
  /// at the call sites, but documented here because the form's own resource
  /// (the child) is the one a reader expects this to be.
  final String resourceKey;

  /// The PARENT record's id — the `{record}` segment of the relation URL.
  final Object recordId;

  /// The relation being written. Carried whole rather than as a bare key so
  /// the data source methods keep the same shape as the `relation()` read.
  final RelationDescriptor relation;
}
