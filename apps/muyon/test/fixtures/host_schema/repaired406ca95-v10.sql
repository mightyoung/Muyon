-- Frozen repaired406ca9567c5db7d7e02e5d2e312ea4b601c59bbc v10 schema and audit, no user data.
CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,scope_json TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE dream_proposals(
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  evidence_json TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('proposed','accepted','reverted'))
);
CREATE TABLE dream_runs(
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('running','done','interrupted','reverted','failed')),
  inputs_json TEXT NOT NULL,
  seen_json TEXT NOT NULL,
  outputs_json TEXT NOT NULL,
  snapshot_json TEXT NOT NULL,
  model_profile_id TEXT,
  outbound_ids_json TEXT NOT NULL,
  token_cost INTEGER,
  token_cost_estimated INTEGER NOT NULL DEFAULT 1,
  elapsed_ms INTEGER,
  started_at TEXT NOT NULL,
  finished_at TEXT
);
CREATE TABLE execution_records(id TEXT PRIMARY KEY,state TEXT NOT NULL,payload TEXT NOT NULL);
CREATE TABLE experiences(
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  source TEXT NOT NULL,
  scope_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('candidate','verified','retired')),
  evidence_json TEXT NOT NULL,
  revision INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE host_migration_compatibility(
 repair_id TEXT PRIMARY KEY CHECK(repair_id='reg2a-reserved9-v1'),
 source_version INTEGER NOT NULL CHECK(source_version IN (9,10)),
 source_definition_digest TEXT NOT NULL,
 source_structure_digest TEXT NOT NULL,
 source_history_json TEXT NOT NULL,
 canonical_migration_id TEXT NOT NULL CHECK(canonical_migration_id='outbound-tool-requests'),
 canonical_definition_digest TEXT NOT NULL CHECK(canonical_definition_digest='foundation-v9'),
 completed INTEGER NOT NULL CHECK(completed=1),
 repaired_at TEXT NOT NULL
);
CREATE TABLE host_schema_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),definition_digest TEXT NOT NULL,structure_digest TEXT NOT NULL);
CREATE TABLE import_intents(operation_id TEXT PRIMARY KEY,workspace_id TEXT NOT NULL REFERENCES workspaces(id),module_id TEXT NOT NULL,target_project_id TEXT NOT NULL,kind TEXT NOT NULL,input_digest TEXT NOT NULL,staging_token TEXT NOT NULL,status TEXT NOT NULL, last_error TEXT);
CREATE TABLE memories(id TEXT PRIMARY KEY,content TEXT NOT NULL,source TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,expires_at TEXT,scope_json TEXT NOT NULL,source_ref TEXT,verified INTEGER NOT NULL,revision INTEGER NOT NULL, disabled INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'fact', inference INTEGER NOT NULL DEFAULT 0, lineage_json TEXT NOT NULL DEFAULT '[]');
CREATE TABLE memory_tombstones(
  id TEXT NOT NULL,
  kind TEXT NOT NULL,
  revision INTEGER NOT NULL,
  reason TEXT NOT NULL,
  scope_json TEXT,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE messages(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id),role TEXT NOT NULL,content TEXT NOT NULL,references_json TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE module_grants(
  module_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  requested TEXT NOT NULL CHECK(requested IN ('required','optional')),
  reason TEXT NOT NULL,
  decision TEXT NOT NULL CHECK(decision IN ('granted','denied')),
  policy TEXT NOT NULL,
  decided_at TEXT NOT NULL,
  PRIMARY KEY(module_id, capability)
);
CREATE TABLE module_registry(module_id TEXT PRIMARY KEY,status TEXT NOT NULL,last_error TEXT);
CREATE TABLE notifications(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,task_id TEXT,read INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
CREATE TABLE object_catalog(module_id TEXT NOT NULL,project_id TEXT NOT NULL,object_type TEXT NOT NULL,object_id TEXT NOT NULL,summary TEXT NOT NULL,PRIMARY KEY(module_id,project_id,object_type,object_id));
CREATE TABLE outbound_requests(
  id TEXT PRIMARY KEY,
  caller TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  endpoint_identity TEXT NOT NULL,
  location TEXT NOT NULL,
  cloud_proxy INTEGER NOT NULL,
  model_id TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL,
  payload_bytes INTEGER NOT NULL,
  item_count INTEGER NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL CHECK(status IN ('sending','succeeded','failed','cancelled','timeout','interrupted')),
  http_status INTEGER,
  error TEXT
, request_digest TEXT, prompt_tokens INTEGER, completion_tokens INTEGER, first_byte_ms INTEGER, bytes_received INTEGER, streamed INTEGER);
CREATE TABLE outbound_tool_requests(
 id TEXT PRIMARY KEY, task_id TEXT, tool_id TEXT NOT NULL,
 channel TEXT NOT NULL CHECK(channel IN ('mcp','inquiry_web','inquiry_hub','transfer')),
 destination TEXT NOT NULL, payload_digest TEXT NOT NULL,
 bytes_sent INTEGER NOT NULL DEFAULT 0 CHECK(bytes_sent >= 0),
 state TEXT NOT NULL CHECK(state IN ('pending','succeeded','failed','cancelled')),
 error TEXT, created_at TEXT NOT NULL, finished_at TEXT
);
CREATE TABLE projection_cursors(module_id TEXT PRIMARY KEY,last_applied_seq INTEGER NOT NULL);
CREATE TABLE schema_catalog(module_id TEXT PRIMARY KEY,target_version INTEGER NOT NULL,target_digest TEXT NOT NULL,observed_version INTEGER,observed_digest TEXT,migration_status TEXT NOT NULL, last_error TEXT);
CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY,migration_id TEXT UNIQUE NOT NULL,definition_digest TEXT NOT NULL,applied_at TEXT NOT NULL);
CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE task_events(
  task_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  at TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY(task_id, seq)
);
CREATE TABLE task_objects(
  task_id TEXT NOT NULL,
  module_id TEXT NOT NULL,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  role TEXT NOT NULL,
  PRIMARY KEY(task_id, module_id, object_type, object_id, role)
);
CREATE TABLE tasks(
  id TEXT PRIMARY KEY,
  conversation_id TEXT,
  kind TEXT,
  state TEXT,
  goal TEXT,
  workspace_id TEXT,
  profile_id TEXT,
  device_id TEXT,
  created_at TEXT,
  updated_at TEXT,
  finished_at TEXT,
  previous_attempt_id TEXT
);
CREATE TABLE tool_approvals(
 id TEXT PRIMARY KEY, session_id TEXT NOT NULL, tool_id TEXT NOT NULL,
 identity_digest TEXT NOT NULL, scope_digest TEXT NOT NULL, input_digest TEXT NOT NULL,
 destination TEXT, issued_at TEXT NOT NULL, expires_at TEXT NOT NULL,
 state TEXT NOT NULL, consumed_at TEXT);
CREATE TABLE tool_invocation_receipts(
 replay_key TEXT PRIMARY KEY, invocation_id TEXT NOT NULL UNIQUE,
 identity_digest TEXT NOT NULL, tool_id TEXT NOT NULL,
 state TEXT NOT NULL, result_json TEXT);
CREATE TABLE transfer_tasks(
  task_id TEXT NOT NULL,
  input_revision TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  owner_device_id TEXT,
  result_seq INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(task_id, input_revision)
);
CREATE TABLE workspace_module_bindings(workspace_id TEXT REFERENCES workspaces(id),module_id TEXT NOT NULL,native_project_id TEXT NOT NULL,PRIMARY KEY(workspace_id,module_id),UNIQUE(module_id,native_project_id));
CREATE TABLE workspaces(id TEXT PRIMARY KEY,title TEXT NOT NULL);
CREATE UNIQUE INDEX active_create_intent ON import_intents(workspace_id,module_id) WHERE kind='create' AND status='pending';
CREATE INDEX messages_conversation ON messages(conversation_id,created_at);
CREATE INDEX task_objects_object ON task_objects(module_id, object_type, object_id);
CREATE INDEX tasks_conversation ON tasks(conversation_id);
CREATE TRIGGER host_compatibility_no_delete BEFORE DELETE ON host_migration_compatibility
BEGIN SELECT RAISE(ABORT,'Migration compatibility facts are immutable'); END;
CREATE TRIGGER host_compatibility_no_update BEFORE UPDATE ON host_migration_compatibility
BEGIN SELECT RAISE(ABORT,'Migration compatibility facts are immutable'); END;
INSERT INTO schema_migrations VALUES(1,'host-v1','muyon-host-v1','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(2,'foundation-v2','foundation-v2','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(3,'schema-catalog-errors','foundation-v3','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(4,'import-intent-errors','foundation-v4','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(5,'outbound-requests','foundation-v5','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(6,'dream-and-transfer-tasks','foundation-v6','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(7,'outbound-streaming-columns','foundation-v7','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(8,'task-events','foundation-v8','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(9,'reserved-reg-2a-outbound-tool-requests','foundation-v9','2026-10-07T00:00:00.000Z');
INSERT INTO schema_migrations VALUES(10,'module-grants','foundation-v10','2026-10-07T00:00:00.000Z');
INSERT INTO host_schema_state VALUES(1,'foundation-v10','a0be1c5a07eacb86c2a419979c8dd71905581493001bc807888899b34cff3c83');
INSERT INTO host_migration_compatibility VALUES('reg2a-reserved9-v1',10,'foundation-v10','b7ee3788ee14c435257b5be0b502fd3499e93401b5c6b7a66665c821574025fe','[[1,"host-v1","muyon-host-v1","2026-10-07T00:00:00.000Z"],[2,"foundation-v2","foundation-v2","2026-10-07T00:00:00.000Z"],[3,"schema-catalog-errors","foundation-v3","2026-10-07T00:00:00.000Z"],[4,"import-intent-errors","foundation-v4","2026-10-07T00:00:00.000Z"],[5,"outbound-requests","foundation-v5","2026-10-07T00:00:00.000Z"],[6,"dream-and-transfer-tasks","foundation-v6","2026-10-07T00:00:00.000Z"],[7,"outbound-streaming-columns","foundation-v7","2026-10-07T00:00:00.000Z"],[8,"task-events","foundation-v8","2026-10-07T00:00:00.000Z"],[9,"reserved-reg-2a-outbound-tool-requests","foundation-v9","2026-10-07T00:00:00.000Z"],[10,"module-grants","foundation-v10","2026-10-07T00:00:00.000Z"]]','outbound-tool-requests','foundation-v9',1,'2026-10-07T19:25:17.780054Z');
PRAGMA user_version=10;
