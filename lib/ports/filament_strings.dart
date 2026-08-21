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
    this.fieldColor = 'Enter a valid color in the expected format',
    this.fieldMin = _defaultMin,
    this.fieldMax = _defaultMax,
    this.timeFieldRange = _defaultTimeRange,
    this.save = 'Save',
    this.saveFailed = 'Could not save',
    this.saved = 'Saved',
    this.deleteConfirmTitle = 'Delete this record?',
    this.deleteConfirmBody = 'This cannot be undone.',
    this.deleteConfirm = 'Delete',
    this.cancel = 'Cancel',
    this.create = 'Create',
    this.edit = 'Edit',
    this.actions = 'Actions',
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
    this.keepTypingToNarrowList = 'Keep typing to narrow the list',
    this.reorderRecords = 'Reorder',
    this.doneReordering = 'Done',
    this.reorderFailed = 'Could not save the new order',
    this.cancelReordering = 'Cancel reordering',
    this.noRecordSelected = 'Select a record',
    this.dashboardTitle = 'Dashboard',
    this.logOut = 'Log out',
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

  /// Shown by a `color` field when its text does not match the format the
  /// panel declared (hex/hsl/rgb/rgba) — a malformed value blocks submission
  /// rather than being silently coerced into something the panel never
  /// declared. See `ColorComponent.isValid`, the single check both this
  /// message and the field's live swatch are driven from.
  final String fieldColor;

  /// Parameterised rather than a `'%s'` template: Arabic and English put the
  /// bound in different places in the sentence, so a fixed template can't
  /// carry both.
  final String Function(num) fieldMin;
  final String Function(num) fieldMax;

  /// The helper line on a bounded `time` field that declared no helper text
  /// of its own, e.g. "Between 9:00 AM and 5:00 PM".
  ///
  /// `showTimePicker` cannot restrict its dial, so `TimeFieldWidget` pulls an
  /// out-of-range pick to the nearest bound. Without this the user simply sees
  /// a different time than the one they chose, with nothing said. Either bound
  /// may be null — a field may declare only one — and both are already
  /// formatted in the device's 12/24-hour setting.
  final String Function(String? min, String? max) timeFieldRange;

  final String save;
  final String saveFailed;

  /// Toast after a successful save, shown on the screen the form returns to.
  final String saved;
  final String deleteConfirmTitle;
  final String deleteConfirmBody;
  final String deleteConfirm;
  final String cancel;

  /// Tooltips for the create and edit affordances (`ResourceListScreen`,
  /// `ResourceViewScreen`) — icon-only controls need one for the same reason
  /// the delete affordance does: no accessible name otherwise.
  final String create;
  final String edit;

  /// Tooltip on the record screen's overflow menu, which holds the actions
  /// the server published for this record. Icon-only, so it needs an
  /// accessible name for the same reason `edit` and `create` do.
  final String actions;

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

  /// The footnote on a remote select's search sheet when the server said
  /// the page it returned is not the whole list — says the list was cut
  /// short rather than implying it ended, so a user who cannot find their
  /// record keeps typing instead of concluding it does not exist.
  final String keepTypingToNarrowList;

  /// Tooltip on `ResourceListScreen`'s reorder toggle (P18) — icon-only, so
  /// it needs an accessible name for the same reason [create]/[edit] do.
  /// Shown only when `resource.reorder != null` — see that screen's class
  /// doc.
  final String reorderRecords;

  /// The AppBar action that commits the current drag order and closes
  /// reorder mode — `ResourceListProvider.saveReorder()`'s trigger.
  final String doneReordering;

  /// Shown when `saveReorder()`'s POST fails and the server sent no message
  /// — the drag order is rolled back to the last server-confirmed one when
  /// this is shown, same as every other write's failure in this package.
  final String reorderFailed;

  /// Tooltip on the AppBar's exit-without-saving control, shown only while
  /// reordering — `ResourceListProvider.exitReorderMode()`'s trigger.
  /// Icon-only, so it needs an accessible name for the same reason
  /// [reorderRecords] does.
  final String cancelReordering;

  /// `PanelShell`'s detail-pane placeholder at the expanded form factor,
  /// shown while no master row is selected (P23).
  final String noRecordSelected;

  /// `PanelShell`'s home AppBar title and sidebar entry for the dashboard.
  final String dashboardTitle;

  /// `PanelShell`'s profile-menu item, shown only when the host wired
  /// `onLogout`.
  final String logOut;

  static String _defaultMin(num bound) => 'Must be at least $bound';
  static String _defaultMax(num bound) => 'Must be at most $bound';

  static String _defaultTimeRange(String? min, String? max) =>
      switch ((min, max)) {
        (final min?, final max?) => 'Between $min and $max',
        (final min?, null) => 'From $min',
        (null, final max?) => 'Until $max',
        _ => '',
      };

  /// A fully Arabic-translated instance — Modern Standard Arabic, matching
  /// Flutter's own Material localisations where it has a canonical word
  /// (Cancel = إلغاء, Delete = حذف, Save = حفظ, Retry = إعادة المحاولة,
  /// Search = بحث).
  ///
  /// A factory, not a `const`: the parameterised strings are closures, and
  /// a closure capturing its bound is not a compile-time constant. The
  /// closures keep the `String Function(...)` shape the constructor
  /// established — Arabic puts the bound where English cannot, so no fixed
  /// `'%s'` template carries both.
  factory FilamentStrings.arabic() => FilamentStrings(
    retry: 'إعادة المحاولة',
    empty: 'لا يوجد شيء هنا بعد',
    dashboardEmpty: 'لا يوجد ما يمكن عرضه بعد.',
    chartUnavailable: 'لم يتم توفير أداة عرض للرسوم البيانية.',
    searchHint: 'بحث',
    sortTitle: 'ترتيب حسب',
    updateRequired: 'يُرجى تحديث التطبيق',
    loadFailed: 'تعذّر التحميل',
    fieldRequired: 'هذا الحقل مطلوب',
    fieldEmail: 'أدخل عنوان بريد إلكتروني صالحًا',
    fieldUrl: 'أدخل رابطًا صالحًا',
    fieldPattern: 'هذه القيمة ليست بالتنسيق المتوقع',
    fieldConfirmed: 'التأكيد غير متطابق',
    fieldColor: 'أدخل لونًا صالحًا بالتنسيق المتوقع',
    fieldMin: (bound) => 'يجب ألا تقل القيمة عن $bound',
    fieldMax: (bound) => 'يجب ألا تزيد القيمة عن $bound',
    timeFieldRange: (min, max) => switch ((min, max)) {
      (final min?, final max?) => 'بين $min و$max',
      (final min?, null) => 'من $min',
      (null, final max?) => 'حتى $max',
      _ => '',
    },
    save: 'حفظ',
    saveFailed: 'تعذّر الحفظ',
    saved: 'تم الحفظ',
    deleteConfirmTitle: 'هل تريد حذف هذا السجل؟',
    deleteConfirmBody: 'لا يمكن التراجع عن هذا الإجراء.',
    deleteConfirm: 'حذف',
    cancel: 'إلغاء',
    create: 'إنشاء',
    edit: 'تعديل',
    actions: 'الإجراءات',
    actionFailed: 'تعذّر تنفيذ هذا الإجراء.',
    actionConfirm: 'تأكيد',
    chooseFile: 'اختر ملفًا',
    uploading: 'جارٍ الرفع…',
    uploadFailed: 'تعذّر رفع الملف',
    filePickerUnavailable: 'لم يتم توفير أداة اختيار الملفات.',
    fileFieldReadOnly: 'لا يمكن تغيير هذا الملف.',
    addItem: 'إضافة عنصر',
    removeItem: 'إزالة',
    repeaterReadOnly: 'لا يمكن تغيير هذه العناصر.',
    tagHint: 'أضف علامة',
    seeAll: 'عرض الكل',
    relationEmpty: 'لا يوجد شيء هنا بعد',
    relationFailed: 'تعذّر التحميل',
    keepTypingToNarrowList: 'واصل الكتابة لتضييق القائمة',
    reorderRecords: 'إعادة ترتيب',
    doneReordering: 'تم',
    reorderFailed: 'تعذّر حفظ الترتيب الجديد',
    cancelReordering: 'إلغاء إعادة الترتيب',
    noRecordSelected: 'اختر سجلًا',
    dashboardTitle: 'لوحة التحكم',
    logOut: 'تسجيل الخروج',
  );

  /// The one resolver the common case needs: a locale in, strings out.
  ///
  /// Covers Arabic — the locale this package's RTL support already targets —
  /// and nothing else. A host serving any other language still constructs
  /// its own instance and passes it, exactly as before; this method exists
  /// so the overwhelmingly common `panel.locale`-to-strings wiring is one
  /// call rather than a hand-rolled switch in every host.
  ///
  /// Matching is a case-insensitive prefix check on `ar` (`ar`, `ar-SA`,
  /// `AR` all resolve Arabic) because the translations are Modern Standard
  /// Arabic, not a regional variant. Anything else — `en`, null, or a
  /// language this package does not ship — falls back to the English
  /// defaults rather than leaving a host with nothing.
  static FilamentStrings forLocale(String? locale) =>
      locale != null && locale.toLowerCase().startsWith('ar')
      ? FilamentStrings.arabic()
      : const FilamentStrings();
}
