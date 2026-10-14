//! Bounded synthetic phase invariants. Capture and compare while BEGIN IMMEDIATE
//! owns the writer lock, so legitimate concurrent commits cannot enter the comparison.
use crate::sqlite::{Db, Result};

type Rows = Vec<Vec<Option<String>>>;

#[derive(PartialEq, Eq)]
pub struct Facts {
    meta: Rows,
    pub suppliers: Rows,
    pub intents: Rows,
    pub history: Rows,
    pub receipts: Rows,
}

impl Facts {
    pub fn capture(db: &Db) -> Result<Self> {
        Ok(Self {
            meta: db.query("SELECT domain,format FROM meta ORDER BY domain", &[])?,
            suppliers: db.query(
                "SELECT id,scope,name,revision,untouched FROM suppliers ORDER BY id",
                &[],
            )?,
            intents: db.query(
                "SELECT intent,binding,status,rejection FROM intents ORDER BY intent",
                &[],
            )?,
            history: db.query(
                "SELECT intent,supplier,old_name,new_name,old_revision,new_revision,binding FROM history ORDER BY intent",
                &[],
            )?,
            receipts: db.query("SELECT intent,body FROM receipts ORDER BY intent", &[])?,
        })
    }

    pub fn add_pending(&mut self, intent: &str, binding: &str) {
        self.intents.push(vec![
            Some(intent.into()),
            Some(binding.into()),
            Some("pending".into()),
            None,
        ]);
        self.intents.sort();
    }

    pub fn finish_intent(
        &mut self,
        intent: &str,
        binding: &str,
        status: &str,
        rejection: Option<&str>,
    ) -> Result<()> {
        let mut changed = 0;
        for row in &mut self.intents {
            if row[0].as_deref() == Some(intent) {
                if row[1].as_deref() != Some(binding)
                    || row[2].as_deref() != Some("pending")
                    || row[3].is_some()
                {
                    return Err("phase expected bound pending ownership".into());
                }
                row[2] = Some(status.into());
                row[3] = rejection.map(str::to_owned);
                changed += 1;
            }
        }
        if changed != 1 {
            return Err("phase expected exactly one bound intent".into());
        }
        Ok(())
    }

    pub fn verify(&self, db: &Db, phase: &str) -> Result<()> {
        if *self != Self::capture(db)? {
            return Err(format!("{phase} consistency mismatch"));
        }
        Ok(())
    }
}
