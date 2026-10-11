/// Built-in parameter dictionary: typed properties and class templates for
/// the equipment the team buys. Structure follows IEC 61360 / ECLASS / ETIM
/// (see docs/design/2026-09-29-spec-matching-design.md). Codes never change
/// once released; team-defined codes start with "x.".
library;

part 'spec_dictionary_properties_a.dart';
part 'spec_dictionary_properties_b.dart';
part 'spec_dictionary_classes.dart';

/// Bumped whenever built-in properties or classes change.
const specDictionaryVersion = 1;

/// ETIM value types (A alphanumeric, L logical, N numeric, R range) plus
/// tolerance, multi-select, free text and three compound values.
enum ParamType {
  num,
  range,
  tol,
  enumOne,
  enumMany,
  bool,
  text,
  ip,
  ex,
  catalog,
}

/// Which way is better. Accuracy and response time are [lower]; "不低于" on
/// such a property means "no worse than", i.e. ≤.
enum Order { higher, lower, none }

class EnumValue {
  const EnumValue(this.code, this.label, {this.aliases = const [], this.rank});
  final String code, label;
  final List<String> aliases;

  /// Position in an ordered list (DDR3 < DDR4 < DDR5); null when unordered.
  final int? rank;
}

class SpecProperty {
  const SpecProperty(
    this.code,
    this.label,
    this.type, {
    this.aliases = const [],
    this.kind,
    this.unit,
    this.unitLabel,
    this.order = Order.none,
    this.values = const [],
    this.restrictive = false,
    this.help,
  });
  final String code, label;
  final ParamType type;
  final List<String> aliases;

  /// Quantity kind code ([quantityKinds]) for num / range / tol with units.
  final String? kind;

  /// Default unit code within [kind].
  final String? unit;

  /// Display word for counted things without a unit ("核", "路").
  final String? unitLabel;
  final Order order;
  final List<EnumValue> values;

  /// Only listed values allowed (ECLASS restrictive value list).
  final bool restrictive;
  final String? help;

  bool get ordered => values.any((v) => v.rank != null);

  EnumValue? value(String code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }
}

class ClassParam {
  const ClassParam(this.property, {this.key = false});
  final String property;

  /// Key parameter: counts toward completeness (ISO 22745 identification
  /// guide).
  final bool key;
}

class ParamBlock {
  const ParamBlock(this.label, this.params);
  final String label;
  final List<ClassParam> params;
}

class SpecClass {
  const SpecClass(
    this.code,
    this.label, {
    this.aliases = const [],
    this.parent,
    this.blocks = const [],
    this.refs = const {},
    this.help,
  });
  final String code, label;

  /// Synonyms used to recognize the class from names (ETIM synonyms).
  final List<String> aliases;
  final String? parent;
  final List<ParamBlock> blocks;

  /// Optional references to public classifications, e.g. {'etim': 'EC010378'}.
  final Map<String, String> refs;
  final String? help;
}

// ---------------------------------------------------------------- values --

const _origin = [
  EnumValue('domestic', '国产', aliases: ['国内', '国产品牌', '自主品牌']),
  EnumValue('joint', '合资'),
  EnumValue('imported', '进口', aliases: ['国外', '进口品牌', '外资']),
];

const _signals = [
  EnumValue(
    '4-20mA',
    '4-20mA',
    aliases: ['4~20mA', '4～20mA', '4-20ma', '4至20mA'],
  ),
  EnumValue('0-10V', '0-10V', aliases: ['0~10V', '0～10V']),
  EnumValue('0-5V', '0-5V', aliases: ['0~5V', '0～5V']),
  EnumValue('RS485', 'RS485', aliases: ['RS-485', '485', 'EIA-485']),
  EnumValue('RS232', 'RS232', aliases: ['RS-232', '232']),
  EnumValue('CAN', 'CAN', aliases: ['CAN总线', 'CANbus']),
  EnumValue(
    'PROFIBUS-DP',
    'PROFIBUS-DP',
    aliases: ['DP', 'Profibus', 'PROFIBUS'],
  ),
  EnumValue('Ethernet', '以太网', aliases: ['RJ45', '网口', '以太网口', 'LAN']),
  EnumValue('fiber', '光口', aliases: ['光纤', 'SFP']),
  EnumValue('4G', '4G', aliases: ['LTE', '4G全网通']),
  EnumValue('5G', '5G'),
  EnumValue('WiFi', 'WiFi', aliases: ['Wi-Fi', 'WLAN', '无线局域网']),
  EnumValue('LoRa', 'LoRa'),
  EnumValue('relay', '继电器', aliases: ['继电器输出', '开关量']),
];

const _protocols = [
  EnumValue('Modbus RTU', 'Modbus RTU', aliases: ['ModbusRTU', 'Modbus-RTU']),
  EnumValue('Modbus TCP', 'Modbus TCP', aliases: ['ModbusTCP', 'Modbus-TCP']),
  EnumValue('OPC UA', 'OPC UA', aliases: ['OPCUA', 'OPC-UA']),
  EnumValue('OPC DA', 'OPC DA', aliases: ['OPCDA', 'OPC-DA']),
  EnumValue('MQTT', 'MQTT'),
  EnumValue('HTTP', 'HTTP'),
  EnumValue('HTTPS', 'HTTPS'),
  EnumValue('Siemens S7', 'Siemens S7', aliases: ['S7', '西门子S7', 'S7协议']),
  EnumValue('PROFINET', 'PROFINET', aliases: ['Profinet']),
  EnumValue('BACnet', 'BACnet'),
  EnumValue('SNMP', 'SNMP'),
  EnumValue('TCP/UDP', 'TCP/UDP 自定义', aliases: ['TCP', 'UDP', 'TCP/UDP']),
  EnumValue('IEC 104', 'IEC 60870-5-104', aliases: ['104规约', 'IEC104']),
];

const _videoPorts = [
  EnumValue('HDMI', 'HDMI'),
  EnumValue('DP', 'DisplayPort', aliases: ['DisplayPort', 'DP口']),
  EnumValue('VGA', 'VGA'),
  EnumValue('DVI', 'DVI'),
  EnumValue('USB-C', 'USB-C', aliases: ['Type-C', 'TypeC']),
];

const _power = [
  EnumValue('AC220V', 'AC 220V', aliases: ['220V', 'AC220', '交流220V', '市电']),
  EnumValue('DC24V', 'DC 24V', aliases: ['24V', 'DC24', '直流24V', '24VDC']),
  EnumValue('DC12V', 'DC 12V', aliases: ['12V', 'DC12', '直流12V', '12VDC']),
  EnumValue('PoE', 'PoE', aliases: ['POE']),
  EnumValue('battery', '电池', aliases: ['锂电池', '电池供电']),
];

const _shield = [
  EnumValue('none', '无屏蔽'),
  EnumValue('P', '铜丝编织屏蔽', aliases: ['编织屏蔽']),
  EnumValue('P2', '铜带屏蔽'),
  EnumValue('P3', '铝塑复合带屏蔽', aliases: ['铝箔屏蔽']),
];

const _insulation = [
  EnumValue('V', '聚氯乙烯', aliases: ['PVC']),
  EnumValue('YJ', '交联聚乙烯', aliases: ['XLPE']),
  EnumValue('Y', '聚乙烯', aliases: ['PE']),
  EnumValue('X', '橡胶'),
  EnumValue('F', '氟塑料'),
];

// ------------------------------------------------------------ properties --

const specProperties = <SpecProperty>[..._specPropertiesA, ..._specPropertiesB];

final _propertyByCode = {for (final p in specProperties) p.code: p};
final _classByCode = {for (final c in specClasses) c.code: c};

SpecProperty? specProperty(String code) => _propertyByCode[code];
SpecClass? specClass(String code) => _classByCode[code];

/// Parameters of [classCode] including inherited ones, parents first, each
/// property once.
List<ClassParam> classParams(String classCode) {
  final chain = <SpecClass>[];
  for (
    SpecClass? c = specClass(classCode);
    c != null;
    c = c.parent == null ? null : specClass(c.parent!)
  ) {
    chain.insert(0, c);
  }
  final seen = <String>{};
  return [
    for (final c in chain)
      for (final b in c.blocks)
        for (final p in b.params)
          if (seen.add(p.property)) p,
  ];
}

/// Blocks of [classCode] including inherited ones, parents first.
List<ParamBlock> classBlocks(String classCode) {
  final chain = <SpecClass>[];
  for (
    SpecClass? c = specClass(classCode);
    c != null;
    c = c.parent == null ? null : specClass(c.parent!)
  ) {
    chain.insert(0, c);
  }
  return [for (final c in chain) ...c.blocks];
}
