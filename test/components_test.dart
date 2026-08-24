import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

T parse<T extends SchemaComponent>(Map<String, dynamic> json) =>
    SchemaComponent.fromJson(json, 'form[0]') as T;

void main() {
  group('common component direction', () {
    test('parses the closed ltr and rtl values', () {
      expect(
        parse<TextComponent>(const {
          'type': 'text',
          'name': 'arabic',
          'direction': 'rtl',
        }).direction,
        ComponentDirection.rtl,
      );
      expect(
        parse<TextComponent>(const {
          'type': 'text',
          'name': 'english',
          'direction': 'ltr',
        }).direction,
        ComponentDirection.ltr,
      );
    });

    test('absent or unknown direction inherits instead of guessing', () {
      expect(
        parse<TextComponent>(const {
          'type': 'text',
          'name': 'absent',
        }).direction,
        isNull,
      );
      expect(
        parse<TextComponent>(const {
          'type': 'text',
          'name': 'automatic',
          'direction': 'auto',
        }).direction,
        isNull,
      );
    });
  });

  group('NumberComponent', () {
    test('parses default, prefix, suffix and numeric bounds', () {
      final component = parse<NumberComponent>(const {
        'type': 'number',
        'name': 'price',
        'default': 10,
        'config': {'prefix': 'ج.م', 'suffix': null},
        'rules': {'min': 0, 'max': 9999},
      });

      expect(component.defaultValue, 10);
      expect(component.prefix, 'ج.م');
      expect(component.suffix, isNull);
      expect(component.rules.min, 0);
      expect(component.rules.max, 9999);
    });
  });

  group('SelectComponent', () {
    test('parses inline options', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'role_id',
        'config': {
          'options': [
            {'value': 1, 'label': 'مدير'},
            {'value': 2, 'label': 'محرر'},
          ],
          'searchable': true,
        },
      });

      expect(component.options, hasLength(2));
      expect(component.options.first.value, 1);
      expect(component.options.first.label, 'مدير');
      expect(component.searchable, isTrue);
      expect(component.multiple, isFalse);
      expect(component.optionsUrl, isNull);
    });

    test('parses a remote options url with no inline options', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'city_id',
        'config': {'optionsUrl': '/api/mobile-panel/users/options/city_id'},
      });

      expect(component.options, isEmpty);
      expect(component.optionsUrl, '/api/mobile-panel/users/options/city_id');
    });

    test('multiselect sets multiple', () {
      final component = parse<SelectComponent>(const {
        'type': 'multiselect',
        'name': 'tags',
      });
      expect(component.multiple, isTrue);
    });

    test('parses config.placeholder, and leaves it null when absent', () {
      final withPlaceholder = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'trashed',
        'config': {
          'options': [
            {'value': '1', 'label': 'With trashed'},
          ],
          'placeholder': 'Without trashed',
        },
      });
      final without = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'status',
        'config': {
          'options': [
            {'value': 'draft', 'label': 'Draft'},
          ],
        },
      });

      expect(withPlaceholder.placeholder, 'Without trashed');
      expect(without.placeholder, isNull);
    });

    test('config.multiple can force multiple on a plain select', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'tags',
        'config': {'multiple': true},
      });
      expect(component.multiple, isTrue);
    });
  });

  group('ToggleButtonsComponent', () {
    test('parses flattened options and a scalar default', () {
      final component = parse<ToggleButtonsComponent>(const {
        'type': 'toggle_buttons',
        'name': 'status',
        'default': 'draft',
        'rules': {'required': true},
        'config': {
          'multiple': false,
          'options': [
            {'value': 'draft', 'label': 'مسودة'},
            {'value': 'active', 'label': 'نشط'},
          ],
        },
      });

      expect(component.options, hasLength(2));
      expect(component.options.first.value, 'draft');
      expect(component.options.first.label, 'مسودة');
      expect(component.multiple, isFalse);
      expect(component.defaultValue, 'draft');
      expect(component.rules.required, isTrue);
    });

    test('parses a multiple field with a list default', () {
      final component = parse<ToggleButtonsComponent>(const {
        'type': 'toggle_buttons',
        'name': 'flags',
        'default': ['featured'],
        'config': {
          'multiple': true,
          'options': [
            {'value': 'featured', 'label': 'Featured'},
          ],
        },
      });

      expect(component.multiple, isTrue);
      expect(component.defaultValue, ['featured']);
    });

    test('a boolean() preset arrives as int options', () {
      final component = parse<ToggleButtonsComponent>(const {
        'type': 'toggle_buttons',
        'name': 'active',
        'config': {
          'multiple': false,
          'options': [
            {'value': 1, 'label': 'Yes'},
            {'value': 0, 'label': 'No'},
          ],
        },
      });

      expect(component.options.map((o) => o.value), [1, 0]);
    });

    test('absent or wrong-typed config keys read as their defaults', () {
      // The spec's degradation rule: absence is never an error, so a pre-P10
      // server (or a hand-rolled one) can never blank the form here.
      final absent = parse<ToggleButtonsComponent>(const {
        'type': 'toggle_buttons',
        'name': 'status',
      });
      expect(absent.multiple, isFalse);
      expect(absent.options, isEmpty);
      expect(absent.defaultValue, isNull);

      final wrongTyped = parse<ToggleButtonsComponent>(const {
        'type': 'toggle_buttons',
        'name': 'status',
        'config': {'multiple': 'yes'},
      });
      expect(wrongTyped.multiple, isFalse);
    });
  });

  group('SliderComponent', () {
    test('parses bounds, step and a scalar default', () {
      final component = parse<SliderComponent>(const {
        'type': 'slider',
        'name': 'rating',
        'default': 0,
        'rules': {'required': true, 'numeric': true, 'min': 0, 'max': 10},
        'config': {'min': 0, 'max': 10, 'step': 1, 'multiple': false},
      });

      expect(component.min, 0);
      expect(component.max, 10);
      expect(component.step, 1);
      expect(component.multiple, isFalse);
      expect(component.defaultValue, 0);
      expect(component.rules.numeric, isTrue);
      expect(component.rules.min, 0);
      expect(component.rules.max, 10);
    });

    test('parses a range slider with a two-element default', () {
      final component = parse<SliderComponent>(const {
        'type': 'slider',
        'name': 'price_range',
        'default': [20, 40],
        'config': {'min': 0, 'max': 100, 'step': 5, 'multiple': true},
      });

      expect(component.multiple, isTrue);
      expect(component.defaultValue, [20, 40]);
    });

    test('absent bounds read as 0/100, absent step as no constraint', () {
      // Filament's own accessor defaults (getMinValue/getMaxValue), mirrored
      // for a server that omits the keys.
      final component = parse<SliderComponent>(const {
        'type': 'slider',
        'name': 'rating',
      });

      expect(component.min, 0);
      expect(component.max, 100);
      expect(component.step, isNull);
      expect(component.multiple, isFalse);
      expect(component.defaultValue, isNull);
    });

    test('a non-numeric step reads as no step constraint, never an error', () {
      // Filament allows a STRING step; the walker publishes `step` only when
      // it is numeric, so a string must not be reinterpreted client-side.
      final component = parse<SliderComponent>(const {
        'type': 'slider',
        'name': 'rating',
        'config': {'step': 'any', 'multiple': 'yes'},
      });

      expect(component.step, isNull);
      expect(component.multiple, isFalse);
    });
  });

  group('BooleanComponent', () {
    test('maps toggle and checkbox onto a kind', () {
      expect(
        parse<BooleanComponent>(const {'type': 'toggle', 'name': 'a'}).kind,
        BooleanKind.toggle,
      );
      expect(
        parse<BooleanComponent>(const {'type': 'checkbox', 'name': 'a'}).kind,
        BooleanKind.checkbox,
      );
    });

    test('defaults to false when no default is given', () {
      expect(
        parse<BooleanComponent>(const {
          'type': 'toggle',
          'name': 'a',
        }).defaultValue,
        isFalse,
      );
    });
  });

  group('FileComponent', () {
    test('parses a read-only file field', () {
      final component = parse<FileComponent>(const {
        'type': 'file',
        'name': 'avatar',
        'label': 'الصورة',
        'config': {'readOnly': true},
      });

      expect(component.name, 'avatar');
      expect(component.readOnly, isTrue);
    });

    test('defaults readOnly to true when config is absent', () {
      // P2 never emits a writable file field. Defaulting to false would let a
      // renderer offer an upload the server cannot accept.
      expect(
        parse<FileComponent>(const {'type': 'file', 'name': 'avatar'}).readOnly,
        isTrue,
      );
    });

    test('parses a multiple field with its count bounds', () {
      final component = parse<FileComponent>(const {
        'type': 'file',
        'name': 'attachments',
        'config': {
          'readOnly': false,
          'multiple': true,
          'accept': ['image/png', 'image/jpeg'],
          'maxSize': 1024,
          'maxFiles': 3,
          'minFiles': 1,
        },
      });

      expect(component.readOnly, isFalse);
      expect(component.multiple, isTrue);
      expect(component.accept, ['image/png', 'image/jpeg']);
      expect(component.maxSizeKb, 1024);
      expect(component.maxFiles, 3);
      expect(component.minFiles, 1);
    });

    test('an absent multiple reads as false', () {
      // Absent means a server predating P12 — the client must never invent a
      // capability the server did not declare, so it reads as single.
      expect(
        parse<FileComponent>(const {'type': 'file', 'name': 'avatar'}).multiple,
        isFalse,
      );
    });

    test('absent or wrong-typed count bounds read as null', () {
      final absent = parse<FileComponent>(const {
        'type': 'file',
        'name': 'attachments',
        'config': {'multiple': true},
      });
      expect(absent.maxFiles, isNull);
      expect(absent.minFiles, isNull);

      // Same licence `opt` gives every scalar hint: a wrong type reads as
      // absent rather than failing the whole field's parse.
      final wrongTyped = parse<FileComponent>(const {
        'type': 'file',
        'name': 'attachments',
        'config': {'multiple': true, 'maxFiles': 'three', 'minFiles': 1.5},
      });
      expect(wrongTyped.maxFiles, isNull);
      expect(wrongTyped.minFiles, isNull);
    });

    test('a wrong-typed whole config throws', () {
      // `object()`'s deliberate strictness, pinned for this component too:
      // a container arriving as a scalar is a server bug, not a widening.
      expect(
        () => parse<FileComponent>(const {
          'type': 'file',
          'name': 'avatar',
          'config': 'readOnly',
        }),
        throwsA(isA<SchemaFormatException>()),
      );
    });
  });

  group('DateComponent', () {
    test('maps date, datetime and time onto a kind', () {
      // Genuinely three-way. `_fromJson` used to derive the kind with
      // `type == 'datetime' ? datetime : date`, under which a third type
      // silently reads as `date` — a two-way test could never see it.
      expect(
        parse<DateComponent>(const {'type': 'date', 'name': 'd'}).kind,
        DateKind.date,
      );
      expect(
        parse<DateComponent>(const {'type': 'datetime', 'name': 'd'}).kind,
        DateKind.datetime,
      );
      expect(
        parse<DateComponent>(const {'type': 'time', 'name': 'd'}).kind,
        DateKind.time,
      );
    });

    test('parses a time bound DateTime.tryParse alone reads as null', () {
      // The trap this task exists for: `DateTime.tryParse('09:00')` is null,
      // so the date path would discard a bound the panel really declared and
      // then offer the user times the server rejects.
      expect(
        DateTime.tryParse('09:00'),
        isNull,
        reason: 'premise of this test',
      );

      final component = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'minDate': '09:00', 'maxDate': '17:30:45'},
      });

      expect(component.minDate, DateTime.utc(1970, 1, 1, 9));
      expect(component.maxDate, DateTime.utc(1970, 1, 1, 17, 30, 45));
    });

    test('normalises a Carbon-shaped time bound onto the same day', () {
      // A panel writing `->minDate(Carbon::parse(...))` publishes
      // "2026-01-01 09:00:00" — measured on the server, see TimeTest.php. For
      // a `time` field only the clock reading is meaningful, so both wire
      // shapes have to land on one comparable value.
      final component = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'minDate': '2026-01-01 09:00:00'},
      });

      expect(component.minDate, DateTime.utc(1970, 1, 1, 9));
    });

    test('rejects an out-of-range time rather than rolling it over', () {
      // DateTime.utc(1970, 1, 1, 25) is a valid DateTime — the next day at
      // 01:00 — so an unchecked parse would turn a nonsense bound into a
      // plausible one.
      final component = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'minDate': '25:00', 'maxDate': '09:75'},
      });

      expect(component.minDate, isNull);
      expect(component.maxDate, isNull);
    });

    test('a time value is not read with the date parse', () {
      // The mirror of the bound trap: `date`/`datetime` must keep reading
      // "09:00" as no bound, because for them it genuinely is malformed.
      final asDate = parse<DateComponent>(const {
        'type': 'date',
        'name': 'd',
        'config': {'minDate': '09:00'},
      });

      expect(asDate.minDate, isNull);
    });

    test('distinguishes a bound it could not read from one never declared', () {
      // A malformed bound still reads as "no bound" — a crashed form is an
      // outage — but it is a contract violation, not the ordinary case, and
      // the client says which.
      final unreadable = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'minDate': 'half past nine', 'maxDate': '17:00'},
      });
      final absent = parse<DateComponent>(const {
        'type': 'time',
        'name': 'closes_at',
        'config': {'minDate': null, 'maxDate': null},
      });

      expect(unreadable.minDate, isNull);
      expect(unreadable.unreadableBounds, {'minDate'});
      expect(absent.minDate, isNull);
      expect(absent.unreadableBounds, isEmpty);
    });

    test('an unparseable bound reads as absent rather than throwing', () {
      final component = parse<DateComponent>(const {
        'type': 'date',
        'name': 'born_at',
        'config': {'minDate': 'yesterday'},
      });

      expect(component.minDate, isNull);
      expect(component.unreadableBounds, {'minDate'});
    });

    test('parses ISO 8601 bounds', () {
      final component = parse<DateComponent>(const {
        'type': 'date',
        'name': 'born_at',
        'config': {'minDate': '1900-01-01', 'maxDate': '2026-08-02'},
      });

      expect(component.minDate, DateTime.utc(1900, 1, 1));
      expect(component.maxDate, DateTime.utc(2026, 8, 2));
    });

    test('parses seconds true and false, not just its default', () {
      // Two fields, not one: a fixture that never sets `seconds` cannot
      // distinguish "the walker publishes the real value" from "this field
      // defaults false" — the same trap the Laravel-side fixture documents
      // (DateTimePicker's own `$hasSeconds` defaults to `true` in vendor).
      final withSeconds = parse<DateComponent>(const {
        'type': 'datetime',
        'name': 'a',
        'config': {'seconds': true},
      });
      final withoutSeconds = parse<DateComponent>(const {
        'type': 'datetime',
        'name': 'b',
        'config': {'seconds': false},
      });

      expect(withSeconds.seconds, isTrue);
      expect(withoutSeconds.seconds, isFalse);
    });

    test('defaults seconds to false when config is absent', () {
      expect(
        parse<DateComponent>(const {'type': 'date', 'name': 'd'}).seconds,
        isFalse,
      );
    });

    test('parses the three step keys when the server publishes them', () {
      // P13. The walker publishes a step only when it is > 1, so all three
      // present at once is the fully-declared case.
      final component = parse<DateComponent>(const {
        'type': 'datetime',
        'name': 'booked_at',
        'config': {'hoursStep': 2, 'minutesStep': 30, 'secondsStep': 15},
      });

      expect(component.hoursStep, 2);
      expect(component.minutesStep, 30);
      expect(component.secondsStep, 15);
    });

    test('an absent step key reads as 1, the vendor default', () {
      // Absent means 1 — the walker leaves the key off rather than
      // publishing the default, so "no key" must not read as "no grid".
      final component = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'minutesStep': 15},
      });

      expect(component.hoursStep, 1);
      expect(component.minutesStep, 15);
      expect(component.secondsStep, 1);
    });

    test('a wrong-typed step key reads as 1, not a crash', () {
      // `opt`'s licence: the server may widen a scalar without breaking older
      // clients, and an advisory hint is not worth a thrown form.
      final component = parse<DateComponent>(const {
        'type': 'time',
        'name': 'opens_at',
        'config': {'hoursStep': '2', 'minutesStep': 15.5, 'secondsStep': true},
      });

      expect(component.hoursStep, 1);
      expect(component.minutesStep, 1);
      expect(component.secondsStep, 1);
    });
  });

  group('ColorComponent', () {
    // Four fixtures, one per format — a single-format fixture cannot show
    // the format is READ off `config.format` rather than assumed, the same
    // reasoning DateComponent's bounded/unbounded pair documents.
    test('parses each of the four declared formats', () {
      ColorComponent color(String format) => parse<ColorComponent>({
        'type': 'color',
        'name': 'c',
        'config': {'format': format},
      });

      expect(color('hex').format, ColorFormat.hex);
      expect(color('hsl').format, ColorFormat.hsl);
      expect(color('rgb').format, ColorFormat.rgb);
      expect(color('rgba').format, ColorFormat.rgba);
    });

    test('defaults to hex when config is absent, filament\'s own default', () {
      expect(
        parse<ColorComponent>(const {'type': 'color', 'name': 'c'}).format,
        ColorFormat.hex,
      );
    });

    test('throws on a format outside the closed set', () {
      // The server already normalises a nonsense override to 'hex'
      // (ColorTest.php) — this client trusts that promise the way it trusts
      // `direction`'s, and a value that breaks it is a contract violation,
      // not a value to silently reinterpret.
      expect(
        () => parse<ColorComponent>(const {
          'type': 'color',
          'name': 'c',
          'config': {'format': 'sideways'},
        }),
        throwsA(isA<SchemaFormatException>()),
      );
    });

    group('match', () {
      test('reads a 6-digit and a 3-digit hex value', () {
        expect(ColorComponent.isValid('#aabbcc', ColorFormat.hex), isTrue);
        expect(ColorComponent.isValid('#abc', ColorFormat.hex), isTrue);
        expect(ColorComponent.isValid('aabbcc', ColorFormat.hex), isFalse);
        expect(ColorComponent.isValid('#ggg', ColorFormat.hex), isFalse);
      });

      test('reads rgb and rgba', () {
        expect(
          ColorComponent.isValid('rgb(10, 20, 30)', ColorFormat.rgb),
          isTrue,
        );
        expect(
          ColorComponent.isValid('rgba(10, 20, 30, 0.5)', ColorFormat.rgba),
          isTrue,
        );
        expect(
          ColorComponent.isValid('rgb(10, 20, 30)', ColorFormat.rgba),
          isFalse,
          reason:
              'an rgb string is not a valid rgba one — no cross-format '
              'leniency',
        );
      });

      test('reads hsl', () {
        expect(
          ColorComponent.isValid('hsl(200, 50%, 60%)', ColorFormat.hsl),
          isTrue,
        );
        expect(
          ColorComponent.isValid('hsl(200, 50, 60)', ColorFormat.hsl),
          isFalse,
          reason: 'hsl requires the % suffix on saturation/lightness',
        );
      });

      test('rejects a blank or malformed value for every format', () {
        for (final format in ColorFormat.values) {
          expect(
            ColorComponent.isValid('', format),
            isFalse,
            reason: format.name,
          );
          expect(
            ColorComponent.isValid('not a color', format),
            isFalse,
            reason: format.name,
          );
        }
      });
    });
  });
}
