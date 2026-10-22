# Evidence source resolver continuation

Base 65fb35c6195a03b48dc476a0917527aa310d02c5; fixed inherited Evidence
78cdff32dee68b664c4fe71b4bbd6b81251af5e7 and core aec085fa.
Only artifacts/** and own docs change. No canonical body or document schema copy.

1. Test first using actual UTF8 DocumentFormat::Text, BusinessStore and StoreEvidence.
2. New artifacts/local_sources.rs owns a separate explicit metadata-only source
   namespace. Resolver calls actual StoreEvidence::open and discards quote; private
   proof cannot be fabricated/deserialized. Evidence revision is source document
   revision, not a display-index revision. Initial binding requires real proof;
   generic issue only renews already resolved same immutable source.
3. Every local binding check uses core document_access_in_transaction(ReadText)
   on original exact document+grant and metadata, including after receipt UPDATE.
   Source publication/revocation denies frozen preview immediately, regardless TTL.
4. Source invalidation hook runs in caller's same BusinessStore transaction;
   returns exact invalidated object identities for trusted owner notification.
   Parent must wire core publication/revocation callback; no fake push integration.
5. Message disabled until authoritative Runtime message/request/side/revision
   snapshot and transactional authorization contract exist. AgentOwner request rows
   do not establish a stable Message identity. PDF/OCR unsupported by Evidence.
6. Preserve four local grant purposes, CAS, sticky human fields, original unknown
   journal. Run actual 15+17 plus new source cases if toolchain is available;
   retain all failures/NOT_RUN. Independent review before fixed-SHA handoff.
