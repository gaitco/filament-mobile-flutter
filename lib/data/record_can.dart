import 'resource_record.dart';

/// Whether the user may perform [ability] on this specific record.
///
/// Typed against [ResourceRecord] on purpose: a `ResourceSchema`'s permissions
/// block means *capability* ("this resource supports deletion and you are not
/// categorically barred"), while a record's means *authorization* ("you may
/// delete THIS row"). Under an ownership policy the two disagree for most
/// records, and the class-level answer is permissive. Passing the wrong one is
/// now a compile error rather than a silent escalation.
bool recordCan(ResourceRecord record, String ability) => record.can(ability);
