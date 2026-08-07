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
    this.dashboardEmpty = 'Nothing to show yet.',
    this.chartUnavailable = 'No chart renderer supplied.',
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
    this.actionFailed = 'Could not run that action.',
    this.actionConfirm = 'Confirm',
    this.chooseFile = 'Choose file',
    this.uploading = 'Uploading…',
    this.uploadFailed = 'Could not upload the file',
    this.filePickerUnavailable = 'No file picker supplied.',
    this.fileFieldReadOnly = 'This file cannot be changed.',
    this.addItem = 'Add item',
    this.removeItem = 'Remove',
    this.repeaterReadOnly = 'These items cannot be changed.',
    this.tagHint = 'Add a tag',
    this.seeAll = 'See all',
    this.relationEmpty = 'Nothing here yet',
    this.relationFailed = 'Could not load',
  });

  final String retry;
  final String empty;

  /// Shown by `DashboardScreen` when a load succeeds with zero widgets.
  final String dashboardEmpty;

  /// Shown in place of a chart widget when the host passed no `chartBuilder`
  /// — see `DashboardScreen`'s class doc for why the package draws no charts
  /// of its own.
  final String chartUnavailable;

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

  /// Shown when an action's run fails and the server sent no message.
  ///
  /// There is deliberately no success counterpart: an action that declared no
  /// success notification is silent on the web panel, so it is silent here.
  /// See `ResourceViewScreen._runAction()` for why failure is not symmetric.
  final String actionFailed;

  /// The confirm button when an action requires confirmation but declared
  /// no submit label of its own.
  final String actionConfirm;

  /// The control that opens `filePicker` and starts an upload, and the same
  /// label used to replace an already-uploaded file.
  final String chooseFile;

  /// Shown on a file field while its upload is in flight.
  final String uploading;

  /// The field error shown when an upload fails with no server message.
  final String uploadFailed;

  /// Shown in place of a file field's choose control when `ResourceFormScreen`
  /// was given no `filePicker` — never a control the host cannot actually
  /// drive, the same principle as [chartUnavailable].
  final String filePickerUnavailable;

  /// Shown in place of a file field's choose control when the *server*
  /// marked it `readOnly` — distinct from [filePickerUnavailable], which is
  /// about a host capability gap, not a server rule. Shown even when the
  /// host did supply a picker: the server's word wins.
  final String fileFieldReadOnly;

  /// The control that appends a row to a repeater.
  final String addItem;

  /// The control that removes one row from a repeater.
  final String removeItem;

  /// Shown on a repeater the *server* marked `readOnly` — same story as
  /// [fileFieldReadOnly]: the server's rule, not a host capability gap, so
  /// it is shown even when the host's own gates would otherwise allow
  /// editing.
  final String repeaterReadOnly;

  /// The hint on a `tags` field's text input. A tag commits on submit only
  /// — `splitKeys` is not on the wire — so this has to say what to do, not
  /// merely name the field.
  final String tagHint;

  /// The affordance on a `RelationSectionWidget` that opens the full,
  /// paginated relation — shown only when there is more to see than the
  /// section's first page already rendered.
  final String seeAll;

  /// Shown by `RelationSectionWidget` when the relation loaded successfully
  /// but has zero rows. Distinct from the section being absent entirely —
  /// see that widget's class doc for why the two must not look the same.
  final String relationEmpty;

  /// Shown by `RelationSectionWidget` when its load fails, in place of the
  /// spinner — never left spinning forever. See the class doc for the
  /// incident this guards against.
  final String relationFailed;

  static String _defaultMin(num bound) => 'Must be at least $bound';
  static String _defaultMax(num bound) => 'Must be at most $bound';
}
