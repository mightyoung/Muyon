# Toolchain recovery independent evidence review

Reviewed TOOLCHAIN-RECOVERY.md and its packages JSON, online Gradle log and info
Gradle log. Product baseline: `043bed97e218bc25202a803aff3c0de1a5da031f`.
No production source diff against baseline under apps/. Only this review written;
no installation, license acceptance, network request or repeated pure test run.

## Findings and verified boundaries

The report correctly records incomplete recovery, no new runtime or Compose
preview screenshots, no Library file IDs and no candidate Android acceptance.

Online log terminates BUILD FAILED in1m39s with AGP8.11.1 unresolved, before source
compilation. Info log terminates BUILD FAILED in1m40s, with SocketException:
Network is unreachable for the configured repositories. Its intermediate
“Resolved plugin” line does not override the final plugin-resolution failure.
Parent confirmed both command exits1 after terminal completion; raw logs themselves
contain the terminal failure but do not embed shell exit codes. These are failed
commands, not automatic approval denials. No independent Gradle rerun performed.

Read-only local XML checks confirmed:

- repository file SHA256 `29b31c17e49aa3e79c1c248dc35efc23fa60bbd0fa5ccc5a8e8f2c316435b6e1`;
- android-sdk-license actual text SHA256
  `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`,
  containing January16,2019;
- all seven listed candidate archive size/checksum/URL and license refs match
  the local official-repository snapshot;
- AOSP API26 default x86_64 image is revision1 under android-sdk-license;
- emulator37.3.5 refers to android-sdk-preview-license;37.2.12 refers to
  android-sdk-license. Only the latter is in the proposed stable install plan.

The2026-04-28 download-page date is a prior research assertion in the reviewed
report/JSON, not a freshly fetched page in this review. No archived page body was
provided among these four evidence inputs. It must not be equated with the
separately verified2019 repository text/hash or treated as accepted. The proposed
install remains explicitly pending applicable agreement acceptance.

Local Gradle8.13 zip hashes to its exact pinned value
`20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`.
Existing AGP POM identifies com.android.tools.build:gradle8.11.1; one cached POM
does not establish dependency or SDK recovery. No SDK licenses directory and no
/dev/kvm exist at review time. The proposed software-emulation trial remains
NOT_ATTEMPTED, performance unknown. No emulator process was started by the reviewer
and no security/network/hardware settings changed. Local software option prose
was reviewed for honest status; external current documentation was not fetched.

## Review comments

Two metadata clarity comments sent to the author before sealing: candidate catalog
included excluded preview/extension entries under the misleading name
required_packages; license_official_url next to the2019 hash pointed to the2026
page. The human-readable stable-only plan and separate dates were already explicit,
but machine-readable metadata should also keep catalog/selection and license
provenance distinct. Final disposition and evidence hashes follow below.


## Final disposition and sealed input hashes

Author corrected both metadata comments before final review: the catalog is now
`catalog_candidates_NOT_install_input`, each item explicitly records selection
and `action_now="NONE; acceptance pending"`; extension and preview entries are not selected. Repository
license URL/hash are separated from current download-page URL. Report now states
both terminal exit1 results. These corrections were independently reread.
No remaining blocking finding in this evidence-only report; recovery and actual
Android/screenshot acceptance remain incomplete, agreement acceptance pending.

Final SHA256 of reviewed inputs:

- `TOOLCHAIN-RECOVERY.md`: `bfbbf1a4323321757260a889f88f9bdf80f7f4932f1a5a371021e91f58ffa6f9`
- `evidence/toolchain-recovery-packages.json`: `623e4297cf689c7314dd81354a0a8f429f2d6ab381432342ca7648bf7d09943c`
- `evidence/toolchain-recovery-gradle-online.log`: `fdc98f7dd0e35d8a587fb842e520d4ec341237abf30684401fc51a2a5b7ce969`
- `evidence/toolchain-recovery-gradle-info.log`: `8d78e931f55494168b174990037d48a0b5ff4a69548274935ece7e0788d58b84`
