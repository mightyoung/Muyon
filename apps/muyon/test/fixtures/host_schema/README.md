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
v11 additionally includes the already defined AUTH grant library DDL. Production
continues registering only through v10.

Do not regenerate these fixtures from the schema under test. Tests install them
into real on-disk SQLite databases, add user records, and verify the original
applied migration rows survive success and transaction rollback.
