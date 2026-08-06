/// The house pattern: an explicit status rather than a bool, so `loading` and
/// `failure` are never both plausible at once.
enum LoadStatus {
  initial,
  loading,
  success,
  failure;

  bool get isInitial => this == LoadStatus.initial;
  bool get isLoading => this == LoadStatus.loading;
  bool get isSuccess => this == LoadStatus.success;
  bool get isFailure => this == LoadStatus.failure;
}
