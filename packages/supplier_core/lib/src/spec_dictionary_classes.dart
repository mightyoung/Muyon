part of 'spec_dictionary.dart';

// --------------------------------------------------------------- classes --

const _environment = ParamBlock('环境与防护', [
  ClassParam('env.op_temp'),
  ClassParam('env.op_rh'),
  ClassParam('prot.ip'),
  ClassParam('prot.ex'),
]);

const specClasses = <SpecClass>[
  SpecClass(
    'computer',
    '计算机',
    aliases: ['计算机', '主机', '电脑'],
    blocks: [
      ParamBlock('处理器', [
        ClassParam('cpu.arch', key: true),
        ClassParam('cpu.vendor'),
        ClassParam('cpu.model'),
        ClassParam('cpu.cores', key: true),
        ClassParam('cpu.threads'),
        ClassParam('cpu.base_freq', key: true),
        ClassParam('cpu.boost_freq'),
      ]),
      ParamBlock('内存', [
        ClassParam('mem.type', key: true),
        ClassParam('mem.total', key: true),
        ClassParam('mem.speed'),
        ClassParam('mem.dimm_size'),
        ClassParam('mem.dimm_count'),
        ClassParam('mem.max'),
      ]),
      ParamBlock('存储', [
        ClassParam('disk.total', key: true),
        ClassParam('disk.type'),
      ]),
      ParamBlock('图形与显示', [
        ClassParam('gpu.discrete'),
        ClassParam('gpu.mem'),
        ClassParam('gpu.outputs'),
        ClassParam('gpu.ports'),
      ]),
      ParamBlock('网络', [ClassParam('nic.ports'), ClassParam('nic.speed')]),
      ParamBlock('软件与合规', [
        ClassParam('os.name'),
        ClassParam('sw.licensed'),
        ClassParam('comp.catalog'),
        ClassParam('gen.brand_origin'),
      ]),
    ],
  ),
  SpecClass(
    'computer.server',
    '服务器',
    parent: 'computer',
    aliases: ['服务器', '机架式服务器', '塔式服务器', '存储服务器'],
    blocks: [
      ParamBlock('服务器', [
        ClassParam('cpu.sockets'),
        ClassParam('mem.slots'),
        ClassParam('disk.bays'),
        ClassParam('disk.raid'),
        ClassParam('psu.redundant'),
        ClassParam('form.factor', key: true),
      ]),
    ],
  ),
  SpecClass(
    'computer.ipc',
    '工控机',
    parent: 'computer',
    aliases: ['工控机', '工业计算机', '工业控制计算机', 'IPC', '工业电脑'],
    blocks: [
      ParamBlock('结构与环境', [
        ClassParam('form.factor'),
        ClassParam('pwr.supply'),
        ClassParam('env.op_temp'),
      ]),
    ],
  ),
  SpecClass(
    'computer.pc',
    '台式计算机',
    parent: 'computer',
    aliases: ['台式机', '台式计算机', 'PC', '办公电脑', '工作站'],
  ),
  SpecClass(
    'display.monitor',
    '显示器',
    aliases: ['显示器', '液晶显示器', '监视器', '显示屏'],
    blocks: [
      ParamBlock('显示', [
        ClassParam('disp.size', key: true),
        ClassParam('disp.res', key: true),
        ClassParam('disp.aspect'),
        ClassParam('disp.refresh'),
        ClassParam('disp.response'),
        ClassParam('disp.ports', key: true),
        ClassParam('disp.psu_internal'),
      ]),
      ParamBlock('其他', [ClassParam('gen.brand_origin')]),
    ],
  ),
  SpecClass(
    'sensor.th',
    '温湿度传感器',
    aliases: ['温湿度传感器', '温湿度变送器', '温湿度探头', '温湿度计', '温度传感器', '温度变送器'],
    blocks: [
      ParamBlock('测量', [
        ClassParam('th.temp_range', key: true),
        ClassParam('th.rh_range', key: true),
        ClassParam('th.temp_accuracy', key: true),
        ClassParam('th.rh_accuracy', key: true),
        ClassParam('th.temp_resolution'),
        ClassParam('th.rh_resolution'),
      ]),
      ParamBlock('信号与通信', [
        ClassParam('io.output', key: true),
        ClassParam('io.protocol'),
        ClassParam('pwr.supply'),
      ]),
      _environment,
    ],
  ),
  SpecClass(
    'sensor.gas',
    '气体检测探头',
    aliases: [
      '气体检测探头',
      '气体探测器',
      '气体检测仪',
      '气体浓度检测探头',
      '可燃气体探测器',
      '有毒气体探测器',
      '氧浓度检测探头',
      '氧气探测器',
      '气体报警器',
    ],
    refs: {'etim': 'EC010378'},
    help: 'ETIM EC010378 为便携式气体检测仪，本类以固定式探头为主，仅作近似参考',
    blocks: [
      ParamBlock('检测', [
        ClassParam('gas.target', key: true),
        ClassParam('gas.principle'),
        ClassParam('gas.range', key: true),
        ClassParam('gas.resolution'),
        ClassParam('gas.accuracy', key: true),
        ClassParam('gas.t90', key: true),
        ClassParam('gas.recovery'),
      ]),
      ParamBlock('信号与通信', [
        ClassParam('io.output', key: true),
        ClassParam('io.protocol'),
        ClassParam('pwr.supply'),
      ]),
      ParamBlock('环境与防护', [
        ClassParam('prot.ex', key: true),
        ClassParam('prot.ip'),
        ClassParam('env.op_temp'),
        ClassParam('env.op_rh'),
      ]),
    ],
  ),
  SpecClass(
    'comm.gateway',
    '网关 / 数据采集器',
    aliases: ['网关', '数据采集器', '采集器', '协议转换器', '通讯管理机', '数据分流装置', '物联网网关'],
    blocks: [
      ParamBlock('接口与协议', [
        ClassParam('gw.south_ports', key: true),
        ClassParam('gw.north_ports'),
        ClassParam('io.protocol', key: true),
        ClassParam('gw.channels'),
        ClassParam('gw.baud'),
      ]),
      ParamBlock('其他', [
        ClassParam('gen.industrial'),
        ClassParam('gen.brand_origin'),
        ClassParam('pwr.supply'),
        ClassParam('env.op_temp'),
      ]),
    ],
  ),
  SpecClass(
    'control.plc',
    'PLC 控制系统',
    aliases: ['PLC', '可编程控制器', '控制系统', 'PLC控制系统'],
    blocks: [
      ParamBlock('I/O', [
        ClassParam('plc.di', key: true),
        ClassParam('plc.do', key: true),
        ClassParam('plc.ai', key: true),
        ClassParam('plc.ao', key: true),
      ]),
      ParamBlock('其他', [
        ClassParam('io.protocol'),
        ClassParam('plc.chips_domestic'),
        ClassParam('gen.brand_origin'),
        ClassParam('comp.catalog'),
      ]),
    ],
  ),
  SpecClass(
    'alarm.av',
    '声光报警器',
    aliases: ['声光报警器', '声光报警', '报警器', '警报器'],
    blocks: [
      ParamBlock('报警', [
        ClassParam('alarm.spl', key: true),
        ClassParam('alarm.light'),
        ClassParam('alarm.flash'),
        ClassParam('alarm.voice'),
        ClassParam('alarm.programmable'),
      ]),
      _environment,
    ],
  ),
  SpecClass(
    'cable',
    '电缆',
    aliases: ['电缆', '控制电缆', '电力电缆', '信号电缆', '软电缆', '线缆'],
    blocks: [
      ParamBlock('电缆', [
        ClassParam('cable.use', key: true),
        ClassParam('cable.cores', key: true),
        ClassParam('cable.csa', key: true),
        ClassParam('cable.conductor'),
        ClassParam('cable.insulation'),
        ClassParam('cable.sheath'),
        ClassParam('cable.shield'),
        ClassParam('cable.flame', key: true),
        ClassParam('cable.fire_resistant'),
      ]),
    ],
  ),
  SpecClass(
    'service.software',
    '软件开发服务',
    aliases: ['软件开发', '软件', '应用软件', '系统开发'],
    help: '方案和功能描述不适合参数化匹配，按文字条款人工判断',
    blocks: [
      ParamBlock('软件', [
        ClassParam('sw.arch'),
        ClassParam('sw.third_party_test'),
      ]),
    ],
  ),
];
