/// Multi-step task evaluation of the current assistant (E-1): the
/// "before phase 2" baseline.
///
/// Drives the existing [PersonalAgent] on a fresh [MuyonHost] per task, seeded
/// with the inquiry North Star data, and confirms like the person would: every
/// model round with the digest the host showed, every expected write once.
/// A write the task does not expect is rejected (the person says no), which
/// ends the task and scores as an extra write. Per task it records success,
/// manual confirmations (model requests and tool approvals counted
/// separately), rounds, total time, time to the first complete model response
/// and token usage.
///
/// Tasks: `agent_task_set.json` beside this file. Scoring is [judgeTask], a
/// pure function of what was observed.
///
/// Evidence: normal `flutter test` runs only a loopback fixture model scripted
/// by the test. A fixture run proves the harness and the scoring, never model
/// quality, and [agentEvalReport] refuses to write one. The real run needs
/// `MUYON_EVAL_REAL=1` plus `MUYON_EVAL_MODEL_ENDPOINT` and
/// `MUYON_EVAL_MODEL_ID` (a non-loopback endpoint also needs HTTPS and
/// `MUYON_EVAL_MODEL_KEY`, visible ASCII only). Optional:
/// `MUYON_EVAL_MODEL_TIMEOUT_SECONDS` (per request, default 45) and
/// `MUYON_WRITE_EVAL_REPORT=1`, which writes
/// `docs/implementation/agent-task-eval-<model slug>.md`; without it nothing
/// is written. The key is read from the environment only and is never printed
/// or written.
///
/// ```bash
/// cd apps/muyon
/// env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
///   NO_PROXY=localhost,127.0.0.1,::1 \
///   MUYON_EVAL_REAL=1 \
///   MUYON_EVAL_MODEL_ENDPOINT=https://api.deepseek.com \
///   MUYON_EVAL_MODEL_ID=deepseek-chat \
///   MUYON_EVAL_MODEL_KEY="$DEEPSEEK_API_KEY" \
///   MUYON_WRITE_EVAL_REPORT=1 \
///   flutter test --no-pub test/agent_eval_test.dart --plain-name 'real model'
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../app/bootstrap.dart';
import '../../platform/business_tools.dart';
import '../../platform/foundation_repository.dart';
import '../../services/models/credential_redaction.dart';
import '../../services/models/model_gateway.dart';
import '../../services/models/model_provider.dart';
import '../personal_agent.dart';
import '../selection_eval/llm_selection_eval.dart'
    show llmReportSlug, reportEndpoint;

export '../selection_eval/llm_selection_eval.dart'
    show llmReportSlug, reportEndpoint;

part 'agent_eval_tasks.dart';
part 'agent_eval_judge.dart';
part 'agent_eval_gateway.dart';
part 'agent_eval_run.dart';
part 'agent_eval_report.dart';
part 'agent_eval_environment.dart';
