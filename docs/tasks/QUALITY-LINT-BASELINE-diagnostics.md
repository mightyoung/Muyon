# 首次配置诊断清单

固定 source `5fbc6ce83d569614cd9fd8497f68acc60c495201`，[push CI 38022202677](https://github.com/mightyoung/Muyon/actions/runs/38022202677) failure。

294 条 info；analyze 4/8、test 8/8，gate 9/9、doctor 23/23。Laya 后续步骤被门禁失败跳过。原始日志不入库。此表是按文件、规则、位置整理的修复清单，位置针对首次配置源。

`owner` 文件未修改，具体候选补丁见 [owner.patch](QUALITY-LINT-BASELINE-owner.patch)，须由父任务交对应 owner 在其最新源适配、验证；该 patch 不是已测修复。`local` 是本任务局部修复范围，最终以新精确 CI 为准。

| 文件 | 规则 | 原位置 line:column | 归属 |
| --- | --- | --- | --- |
| `packages/muyon_module_api/lib/src/context.dart` | `use_null_aware_elements` | 33:7 | local |
| `packages/muyon_module_api/lib/src/ui/state.dart` | `curly_braces_in_flow_control_structures` | 53:11, 70:7, 73:7, 75:7, 104:7, 122:7, 136:7, 139:7, 150:7, 155:7, 159:9, 173:11 | owner |
| `packages/muyon_module_api/lib/src/ui/stream_compiler.dart` | `curly_braces_in_flow_control_structures` | 228:11, 288:7, 297:7 | owner |
| `packages/muyon_module_api/lib/src/ui/stream_protocol.dart` | `curly_braces_in_flow_control_structures` | 160:9, 180:13 | owner |
| `packages/muyon_module_api/lib/src/ui/validation.dart` | `curly_braces_in_flow_control_structures` | 69:5, 76:7, 117:7, 140:5, 143:7, 148:7, 152:7, 157:7, 162:11, 168:11, 171:13, 176:11, 183:11, 197:11, 218:9, 227:9, 232:9, 237:9, 240:9, 258:9 | owner |
| `packages/muyon_module_api/lib/src/ui/workspace.dart` | `curly_braces_in_flow_control_structures` | 65:7 | owner |
| `packages/muyon_module_api/test/ui_stream_test.dart` | `curly_braces_in_flow_control_structures` | 408:9, 415:37, 424:33, 516:7, 531:67 | owner |
| `packages/muyon_module_api/test/ui_stream_test.dart` | `use_null_aware_elements` | 750:5 | owner |
| `packages/muyon_ui/lib/src/confirmation.dart` | `curly_braces_in_flow_control_structures` | 324:7 | owner |
| `packages/muyon_ui/lib/src/dynamic/patch.dart` | `curly_braces_in_flow_control_structures` | 54:5, 60:5, 100:5, 105:5 | owner |
| `packages/muyon_ui/lib/src/dynamic/surface.dart` | `curly_braces_in_flow_control_structures` | 106:7, 130:7, 131:9, 171:7, 179:7, 188:9, 229:7, 364:11, 401:11, 499:13, 503:13, 564:7 | owner |
| `packages/muyon_ui/lib/src/dynamic/workspace.dart` | `curly_braces_in_flow_control_structures` | 93:11, 102:13, 128:17, 182:7, 192:13 | owner |
| `packages/muyon_ui/lib/src/navigation_layout.dart` | `curly_braces_in_flow_control_structures` | 256:9 | owner |
| `packages/muyon_ui/lib/src/tokens.dart` | `prefer_initializing_formals` | 36:8, 37:8, 38:8 | owner |
| `packages/muyon_ui/lib/src/ui_components/layout.dart` | `prefer_is_empty` | 163:11 | owner |
| `packages/muyon_ui/lib/src/ui_components/layout.dart` | `unnecessary_brace_in_string_interps` | 311:37 | owner |
| `packages/muyon_ui/test/catalog_release_guard_test.dart` | `curly_braces_in_flow_control_structures` | 8:7, 10:7 | owner |
| `packages/muyon_ui/test/catalog_test.dart` | `curly_braces_in_flow_control_structures` | 15:7, 17:7, 19:7, 21:7 | owner |
| `packages/muyon_ui/test/confirmation_test.dart` | `curly_braces_in_flow_control_structures` | 43:11, 64:11, 126:13 | owner |
| `packages/prototype_module/test/scheme_loader_test.dart` | `prefer_function_declarations_over_variables` | 123:11, 124:11 | local |
| `packages/supplier_core/lib/src/agent_tools.dart` | `curly_braces_in_flow_control_structures` | 218:11, 222:11, 236:7, 239:5, 244:5, 246:5, 250:5, 259:9, 277:11, 286:11, 288:11, 290:11, 743:5 | local |
| `packages/supplier_core/lib/src/ai_jobs.dart` | `curly_braces_in_flow_control_structures` | 149:7, 168:7, 195:7 | local |
| `packages/supplier_core/lib/src/ai_runtime.dart` | `curly_braces_in_flow_control_structures` | 37:49, 126:7 | local |
| `packages/supplier_core/lib/src/assistant_actions.dart` | `curly_braces_in_flow_control_structures` | 331:7 | local |
| `packages/supplier_core/lib/src/assistant_actions.dart` | `use_null_aware_elements` | 202:16 | local |
| `packages/supplier_core/lib/src/assistant_context.dart` | `curly_braces_in_flow_control_structures` | 78:11, 87:11, 158:11, 246:9, 275:11 | local |
| `packages/supplier_core/lib/src/assistant_evidence.dart` | `curly_braces_in_flow_control_structures` | 246:11, 252:11, 415:5, 428:33, 445:11, 453:9 | local |
| `packages/supplier_core/lib/src/assistant_evidence.dart` | `unnecessary_brace_in_string_interps` | 378:33, 389:33 | local |
| `packages/supplier_core/lib/src/assistant_procurement.dart` | `curly_braces_in_flow_control_structures` | 67:7, 94:7, 112:7, 188:7, 193:9, 200:7, 246:7, 264:9, 266:9, 278:11, 290:11, 326:7, 332:7, 338:7, 395:7, 433:7, 435:7, 455:7, 465:7, 467:7, 471:7, 477:27, 497:9, 502:13, 524:9, 532:9, 572:7, 577:7, 591:7, 596:7, 599:7, 602:9, 607:7, 609:11, 628:11, 636:11, 643:11, 645:11, 651:7, 654:9, 657:7, 660:7, 664:11, 680:7, 683:9, 685:9, 689:7, 692:7, 697:7, 723:7, 731:11, 743:11, 775:11, 814:7, 835:7, 888:9, 890:9, 893:9, 918:11, 930:9, 1023:11, 1038:7 | local |
| `packages/supplier_core/lib/src/assistant_web_catalog.dart` | `curly_braces_in_flow_control_structures` | 44:7, 56:7, 140:7, 193:7, 197:9, 381:7, 401:7, 403:7, 449:9, 507:11, 512:11, 532:9, 561:5 | local |
| `packages/supplier_core/lib/src/assistant_web_tools.dart` | `curly_braces_in_flow_control_structures` | 118:9, 217:11, 231:11, 364:11, 428:11, 445:15, 450:13, 470:17, 593:7, 618:9, 626:7, 629:7, 683:5, 689:5, 795:9, 837:7 | local |
| `packages/supplier_core/lib/src/assistant_web_tools.dart` | `prefer_initializing_formals` | 90:8 | local |
| `packages/supplier_core/lib/src/assistant_web_tools.dart` | `unnecessary_underscores` | 535:42 | local |
| `packages/supplier_core/lib/src/bounded_zip.dart` | `curly_braces_in_flow_control_structures` | 109:7, 116:7, 130:5 | local |
| `packages/supplier_core/lib/src/budget.dart` | `use_null_aware_elements` | 163:9 | local |
| `packages/supplier_core/lib/src/conflicts.dart` | `curly_braces_in_flow_control_structures` | 75:7 | local |
| `packages/supplier_core/lib/src/crypto_file.dart` | `curly_braces_in_flow_control_structures` | 43:7 | local |
| `packages/supplier_core/lib/src/entities.dart` | `curly_braces_in_flow_control_structures` | 185:5 | local |
| `packages/supplier_core/lib/src/hub.dart` | `curly_braces_in_flow_control_structures` | 177:11, 318:11, 406:11 | owner |
| `packages/supplier_core/lib/src/hub.dart` | `unnecessary_underscores` | 385:42 | owner |
| `packages/supplier_core/lib/src/inquiries.dart` | `curly_braces_in_flow_control_structures` | 374:7 | local |
| `packages/supplier_core/lib/src/lan.dart` | `curly_braces_in_flow_control_structures` | 266:11, 786:11 | owner |
| `packages/supplier_core/lib/src/lan_identity.dart` | `prefer_initializing_formals` | 18:8 | owner |
| `packages/supplier_core/lib/src/llm.dart` | `curly_braces_in_flow_control_structures` | 141:13 | local |
| `packages/supplier_core/lib/src/llm.dart` | `prefer_initializing_formals` | 36:7 | local |
| `packages/supplier_core/lib/src/material_import.dart` | `curly_braces_in_flow_control_structures` | 204:7, 447:9 | local |
| `packages/supplier_core/lib/src/pricing.dart` | `curly_braces_in_flow_control_structures` | 69:5, 130:5, 133:5 | local |
| `packages/supplier_core/lib/src/product_params.dart` | `curly_braces_in_flow_control_structures` | 60:7 | local |
| `packages/supplier_core/lib/src/product_params.dart` | `use_null_aware_elements` | 121:7 | local |
| `packages/supplier_core/lib/src/project.dart` | `curly_braces_in_flow_control_structures` | 23:5 | local |
| `packages/supplier_core/lib/src/quote_excel.dart` | `curly_braces_in_flow_control_structures` | 302:9 | local |
| `packages/supplier_core/lib/src/record_query.dart` | `use_null_aware_elements` | 147:5 | local |
| `packages/supplier_core/lib/src/spec_ai.dart` | `curly_braces_in_flow_control_structures` | 211:7 | local |
| `packages/supplier_core/lib/src/spec_compare.dart` | `curly_braces_in_flow_control_structures` | 194:5, 270:7, 282:7, 295:7 | local |
| `packages/supplier_core/lib/src/spec_match.dart` | `curly_braces_in_flow_control_structures` | 90:9 | local |
| `packages/supplier_core/lib/src/spec_parse.dart` | `curly_braces_in_flow_control_structures` | 787:7, 865:9 | local |
| `packages/supplier_core/lib/src/spec_request.dart` | `curly_braces_in_flow_control_structures` | 83:7, 85:7, 88:7, 107:7, 111:7, 113:7, 276:7 | local |
| `packages/supplier_core/lib/src/spec_response.dart` | `curly_braces_in_flow_control_structures` | 300:11 | local |
| `packages/supplier_core/lib/src/store.dart` | `curly_braces_in_flow_control_structures` | 276:7, 452:7, 519:7, 598:7 | local |
| `packages/supplier_core/lib/src/xlsx.dart` | `curly_braces_in_flow_control_structures` | 71:7 | local |
| `packages/supplier_core/test/ai_runtime_test.dart` | `prefer_interpolation_to_compose_strings` | 31:20 | local |
| `packages/supplier_core/test/assistant_capabilities_test.dart` | `curly_braces_in_flow_control_structures` | 92:13, 104:13, 303:13 | local |
| `packages/supplier_core/test/assistant_context_test.dart` | `curly_braces_in_flow_control_structures` | 76:13 | local |
| `packages/supplier_core/test/assistant_context_test.dart` | `prefer_interpolation_to_compose_strings` | 8:22 | local |
| `packages/supplier_core/test/assistant_procurement_test.dart` | `curly_braces_in_flow_control_structures` | 499:7, 512:7 | local |
| `packages/supplier_core/test/assistant_procurement_test.dart` | `unnecessary_string_escapes` | 676:39, 676:53 | local |
| `packages/supplier_core/test/assistant_procurement_test.dart` | `use_null_aware_elements` | 117:13 | local |
| `packages/supplier_core/test/assistant_web_tools_test.dart` | `curly_braces_in_flow_control_structures` | 232:13 | local |
| `packages/supplier_core/test/data_quality_scale_test.dart` | `avoid_print` | 84:7 | local |
| `packages/supplier_core/test/lan_security_test.dart` | `curly_braces_in_flow_control_structures` | 239:36 | owner |
| `packages/supplier_core/test/lan_trust_test.dart` | `prefer_iterable_wheretype` | 220:33 | owner |
| `packages/supplier_core/test/migration_test.dart` | `collection_methods_unrelated_type` | 26:76 | local |
| `packages/supplier_core/test/product_source_provenance_test.dart` | `depend_on_referenced_packages` | 4:8 | local |
| `packages/supplier_core/test/spec_parse_test.dart` | `curly_braces_in_flow_control_structures` | 31:11 | local |
| `packages/supplier_core/tool/assistant_eval.dart` | `curly_braces_in_flow_control_structures` | 63:7, 67:7 | local |
| `packages/supplier_core/tool/assistant_live_eval.dart` | `curly_braces_in_flow_control_structures` | 155:7, 221:11, 229:11, 249:11, 252:11, 289:11, 301:11 | local |
| `packages/supplier_core/tool/bench.dart` | `avoid_print` | 7:3, 95:3, 98:3, 103:3, 111:3, 115:3, 123:5, 179:3, 181:5 | local |
