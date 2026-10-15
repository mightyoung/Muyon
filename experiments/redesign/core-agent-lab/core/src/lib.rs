//! Experimental offline kernel; not a production authority or wire protocol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode { ReadOnly, AskEveryTime, Auto, FullAllow }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision { Permit, ConfirmationRequired, Denied }
pub fn authorize(_mode: Mode, _high: bool, _confirmed: bool, _hard_ok: bool) -> Decision {
    Decision::Denied
}
