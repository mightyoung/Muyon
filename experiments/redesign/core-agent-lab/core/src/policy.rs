#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode { ReadOnly, AskEveryTime, Auto, FullAllow }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision { Permit, ConfirmationRequired, Denied }
pub fn authorize(mode: Mode, high: bool, confirmed: bool, hard_ok: bool) -> Decision {
    if !hard_ok || mode == Mode::ReadOnly { return Decision::Denied; }
    if !confirmed && (mode == Mode::AskEveryTime || (mode == Mode::Auto && high)) { return Decision::ConfirmationRequired; }
    Decision::Permit
}
#[derive(Clone, Debug)]
pub struct HostFacts {
    pub mode: Mode, pub high: bool, pub hard_ok: bool, pub revoked: bool,
    pub scope_ok: bool, pub classification_ok: bool, pub confirmed: bool,
    pub tainted: bool, pub new_destination: bool,
}
impl Default for HostFacts {
    fn default() -> Self { Self { mode: Mode::Auto, high:false, hard_ok:true, revoked:false, scope_ok:true, classification_ok:true, confirmed:false, tainted:false, new_destination:false } }
}
pub trait Authorizer { fn check(&self, facts: &HostFacts) -> Decision; }
pub struct FixtureAuthorizer;
impl Authorizer for FixtureAuthorizer {
    fn check(&self, f: &HostFacts) -> Decision {
        authorize(f.mode, f.high, f.confirmed, f.hard_ok && !f.revoked && f.scope_ok && f.classification_ok)
    }
}
