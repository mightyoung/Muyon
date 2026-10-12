/// Model-only field registration for the bounded saved-record planning source.
/// This is not permission: callers must also check scope, pins, owner authority
/// and the existing sensitive-field masking. Local pages retain their fields.
/// New fields and free-text documents are denied until explicitly reviewed.
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
