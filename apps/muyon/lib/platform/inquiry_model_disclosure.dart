/// Model-only registration of the saved-record fields the planning source may
/// send. Registration is necessary, never permission: scope, pins, owner
/// authority and the existing sensitive-field masking still apply, and local
/// pages keep showing every field. Free text (requirement, notes, award_note)
/// and anything not listed here are withheld; a new field needs a reviewed
/// entry below before the model can see its value.
const inquiryModelDisclosedFields = <String, Set<String>>{
  'project_item': {
    'project_id',
    'category',
    'product_id',
    'name',
    'qty',
    'unit',
    'quotation_id',
  },
  'quotation': {
    'supplier_id',
    'product_id',
    'currency',
    'tax_mode',
    'unit_snapshot',
    'min_qty',
    'quoted_on',
    'tax_rate',
    'lead_time_days',
    'valid_until',
    'project_id',
    'inquiry_precision',
    'inquiry_date',
    'inquired_at',
    'inquiry_utc_offset_minutes',
    'capture_mode',
    'includes',
    'warranty_months',
    'awarded_on',
    'inquiry_id',
    'price_basis',
  },
  'inquiry': {
    'project_id',
    'title',
    'item_ids',
    'supplier_ids',
    'due_date',
    'status',
  },
};

bool inquiryFieldDisclosedToModel(
  String objectType,
  String field, {
  required bool masked,
}) =>
    !masked &&
    (inquiryModelDisclosedFields[objectType]?.contains(field) ?? false);
