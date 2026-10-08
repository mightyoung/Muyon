# Frozen host histories

`legacy-v8.sql`, `legacy-v9.sql`, `legacy-v10.sql` freeze the schema and exact
migration identifiers from `review/REG-2b` commit
`e61a1db220cfb158b751b768e9593509f4be208d`. Version 9 is its explicit historical
placeholder prefix, not an interrupted v8→v10 transaction. Version 10 includes
module-grants while retaining that placeholder. These are empty schema fixtures;
only timestamps were normalized to a fixed UTC value.

`canonical-v9.sql` adds the real outbound ledger DDL from REG-2a commit
`7c59b579f97b96f8144df6e43c59e8e8a1927638` to the frozen v8 prefix.

Fingerprints use SHA-256 of JSON rows `(type,name,tbl_name,sql)` from
`sqlite_master`, excluding `sqlite_%`, ordered by type/name. Literal independently
captured fingerprints are in `HostSchemaCompatibility`; database metadata alone
is never sufficient to recognize an old placeholder schema. Repair fingerprints
include the frozen real ledger, module-grants and immutable compatibility DDL;
v11 additionally includes the already defined AUTH grant library DDL. AUTH-1b registers the unchanged v11 grant migration and adds v12 authorization
linkage; all previous DDL and applied history remain frozen.

Do not regenerate these fixtures from the schema under test. Tests install them
into real on-disk SQLite databases, add user records, and verify the original
applied migration rows survive success and transaction rollback.

`repaired406ca95-v10.sql` and `repaired406ca95-v11.sql` freeze the exact repaired
schema and audit row produced by commit 406ca9567c5db7d7e02e5d2e312ea4b601c59bbc,
before the insert guard. They verify an additive guard upgrade preserves original
facts/history and rolls back atomically. The new BEFORE INSERT guard is needed
because REPLACE skips DELETE triggers when recursive_triggers is off; no global
SQLite setting is changed. Old audit timestamps cannot be retroactively
authenticated; the upgrade preserves them and prevents subsequent replacement.

`canonical-v12.sql` and `repaired-v12.sql` freeze AUTH-1b linkage DDL. They
were captured independently by applying the immutable approved baseline
`b95d6f9de1f1b50cadcd8c8092cd3edf9beeef72` v10/v11 DDL and the separately
written v12 SQL to the existing frozen fixtures, not by invoking the schema
under test. The repaired fixture also includes the immutable insert guard.
Canonical v12 fingerprint: `684ec7c8d50704ede272245aec25c11ffc5b1c069e1b25ef49fd12488d6c526e`.
Repaired v12 fingerprint: `12a312b608fe9a95a18d5113a4361acb7f552fb9702fb4b3bcca41559e737d81`.
Review decisions are separate records; both transport state CHECK constraints
are unchanged. A blocked review does not manufacture a sent request.
