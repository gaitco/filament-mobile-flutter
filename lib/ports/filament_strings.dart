/// The package's own user-facing strings.
///
/// Deliberately not an i18n package: depending on one would force every host
/// to initialise it a particular way and share an asset path. A host passes
/// its own translated values here in one place instead. Nearly all text on
/// screen comes from the server already translated, so this list stays short.
class FilamentStrings {
  const FilamentStrings({
    this.retry = 'Retry',
    this.empty = 'Nothing here yet',
    this.searchHint = 'Search',
    this.sortTitle = 'Sort by',
    this.updateRequired = 'Please update the app',
    this.loadFailed = 'Could not load',
    this.fieldRequired = 'This field is required',
    this.fieldEmail = 'Enter a valid email address',
    this.fieldUrl = 'Enter a valid URL',
    this.fieldPattern = 'This value is not in the expected format',
    this.fieldConfirmed = 'The confirmation does not match',
    this.fieldMin = _defaultMin,
    this.fieldMax = _defaultMax,
    this.save = 'Save',
    this.saveFailed = 'Could not save',
    this.deleteConfirmTitle = 'Delete this record?',
    this.deleteConfirmBody = 'This cannot be undone.',
    this.deleteConfirm = 'Delete',
    this.cancel = 'Cancel',
    this.create = 'Create',
    this.edit = 'Edit',
    this.actionDone = 'Done',
    this.actionFailed = 'Could not run that action.',
    this.actionConfirm = 'Confirm',
  });

  final String retry;
  final String empty;
  final String searchHint;
  final String sortTitle;
  final String updateRequired;
  final String loadFailed;

  // Client-side validation hints (see `form/client_validator.dart`) — feedback
  // only, never the last word: the server revalidates every submission and
  // its 422 is authoritative, already translated in the panel's locale.
  final String fieldRequired;
  final String fieldEmail;
  final String fieldUrl;
  final String fieldPattern;
  final String fieldConfirmed;

  /// Parameterised rather than a `'%s'` template: Arabic and English put the
  /// bound in different places in the sentence, so a fixed template can't
  /// carry both.
  final String Function(num) fieldMin;
  final String Function(num) fieldMax;

  final String save;
  final String saveFailed;
  final String deleteConfirmTitle;
  final String deleteConfirmBody;
  final String deleteConfirm;
  final String cancel;

  /// Tooltips for the create and edit affordances (`ResourceListScreen`,
  /// `ResourceViewScreen`) — icon-only controls need one for the same reason
  /// the delete affordance does: no accessible name otherwise.
  final String create;
  final String edit;

  /// Shown after an action that declared no success notification of its own.
  final String actionDone;

  /// Shown when an action's run fails and the server sent no message.
  final String actionFailed;

  /// The confirm button when an action requires confirmation but declared
  /// no submit label of its own.
  final String actionConfirm;

  static String _defaultMin(num bound) => 'Must be at least $bound';
  static String _defaultMax(num bound) => 'Must be at most $bound';
}
