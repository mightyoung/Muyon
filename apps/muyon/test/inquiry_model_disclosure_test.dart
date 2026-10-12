import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/inquiry_model_disclosure.dart';

/// C6-REDO: registration is an allowlist. Free text, sensitive and unknown
/// fields are withheld whatever the local display shows.
void main() {
  test('free text fields are never registered', () {
    for (final entry in {
      'project_item': ['requirement', 'notes'],
      'quotation': ['award_note', 'notes'],
      'inquiry': ['notes'],
    }.entries) {
      for (final field in entry.value) {
        expect(
          inquiryFieldDisclosedToModel(entry.key, field, masked: false),
          isFalse,
          reason: '${entry.key}.$field',
        );
      }
    }
  });

  test('unknown fields and unknown types default to withheld', () {
    expect(
      inquiryFieldDisclosedToModel(
        'quotation',
        'x_unregistered',
        masked: false,
      ),
      isFalse,
    );
    expect(
      inquiryFieldDisclosedToModel('contact', 'name', masked: false),
      isFalse,
    );
    expect(inquiryFieldDisclosedToModel('', '', masked: false), isFalse);
  });

  test('masked fields stay withheld even when their name is registered', () {
    expect(
      inquiryFieldDisclosedToModel('project_item', 'name', masked: true),
      isFalse,
    );
    expect(
      inquiryFieldDisclosedToModel('project_item', 'name', masked: false),
      isTrue,
    );
  });

  test('sensitive commercial and personal fields are not registered', () {
    for (final field in ['price', 'unit_cost', 'inquirer_name', 'contact']) {
      for (final type in inquiryModelDisclosedFields.keys) {
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: false),
          isFalse,
          reason: '$type.$field',
        );
      }
    }
  });

  test('the registration table cannot be edited at runtime', () {
    expect(
      () => inquiryModelDisclosedFields['quotation']!.add('notes'),
      throwsUnsupportedError,
    );
  });
}
