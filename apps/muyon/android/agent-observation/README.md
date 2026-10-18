# Private receipt observation dependency slice

This module adds a default-disabled production-host consumer of the existing private
Agent Service run/receipt summary protocol. It is an independently testable dependency,
not a connected production capability. No production UI route or Android transport
adapter constructs it yet. It cannot submit/start a run or make a lease visible.

`ReceiptObserver` serializes explicit connect/current/lookup reconciliation on a
caller-owned background worker. It reuses `AgentServiceClientState` and
`AgentServiceWire` validation without copying or replacing their rules. Unknown,
stale/conflicting snapshots, and failed release/unbind retain the original receipt
and mark observation uncertainty. An unbind failure retains the port owner until
explicit same-port cleanup succeeds. Each port must own a stable liveness identity;
its disconnect must retire/unbind that identity. No automatic retry is scheduled.

The module compiles the three original private state/protocol files in place under
`experiments/redesign/android-compose-lab/state`. Their package names and bytes stay
unchanged because existing checker manifests pin them. This is an explicit temporary
source dependency. A later shared-source extraction must migrate those checker and
lab-build references together; this fragment does not duplicate those implementations.

Run the module checks using Kotlin 2.2.20 and a JVM supporting target 17:

```sh
MUYON_UI_KOTLINC=/path/to/kotlinc ./check-observation.sh
```

The fixture transport tests real shared presentation/identity policy. They do not
exercise Android, Binder, generated FFI, a physical business read, or ART. Existing
Rust `service_controller` and `service_oracle` integration targets corroborate the
underlying controller/physical synthetic read/original receipt without new Rust code
or a changed formal test inventory. This is not a Kotlin-to-Rust integration test.

## Remaining production dependencies

- The shipping Android host is still `apps/muyon/android/app/.../MainActivity.kt`,
  a FlutterActivity with only its secrets MethodChannel. No agent UI route is enabled.
- Service, AIDL, bounded proxy/Parcel adapter, generated controller, liveness registry
  and settlement ownership remain under `experiments/redesign/android-compose-lab`.
  A real production adapter must preserve the private ordinary `:agent` process;
  the UI cannot construct the native Agent controller or bypass it with a subprocess.
- The shipping app does not package verified native inputs/JNA/generated bindings or
  implement the Service bootstrap/root owner. Flutter/Android SDK and full app build,
  API24/ABI/native-package and device runtime verification remain pending work.
- `rust-agent-host-lab/core/src/service_runtime.rs::run_builtin_admitted` writes a
  synthetic `source.db`, installs `BuiltinAuthority`/`BuiltinReview`, and uses an
  offline `BuiltinEndpoint`. It is not a real production store/authority adapter.
  A current trusted business-store selection, permission/revision source, and physical
  domain read registration are still needed for the originally requested real-store loop.
- `B-SERVICE-ABI.md` forbids answer/current-business-projection/sourcefacts/history
  payloads. Its `current` and `lookup` return original run/receipt summaries. A business
  value projection cannot be added under the guise of this existing private ABI.
  The v1.3.2 recovery contract keeps original receipt and currently permitted values
  separate; their production projection dependency remains unresolved here.

No INTERNET permission was added or removed (the shipping app already requests it).
No live model, business write, new runtime, budget/permission change, replay or ABI
expansion was introduced. This fragment does not retry the separately blocked I04 action.
