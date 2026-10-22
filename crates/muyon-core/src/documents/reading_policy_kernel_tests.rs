//! First real kernel slice: no claim D/E/F/G exists yet.
use super::{reading_policy::*,reader_tests::{setup,pins},*};
use crate::contract::*;
fn scope()->PolicyScope{PolicyScope{service_session:"service".into(),generation:Revision::new(1),project:"project".into()}}
fn surface()->ReadingSurfaceBinding{ReadingSurfaceBinding{surface_id:"surface".into(),lifecycle_epoch:"lifecycle".into(),selection_sequence:Revision::new(1)}}
#[test]
fn observe_reads_real_rows_without_opening_bytes_or_issuing_grants(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();let request=PolicyObserveRequest{scope:scope(),access};
 assert_eq!(host.observe(&mut reader,&request).unwrap().availability,PolicyAvailability::Valid);
 reader.store().database().exec("UPDATE document_grants SET expires_at_ms='0'",&[]).unwrap();
 assert_eq!(host.observe(&mut reader,&request).unwrap().availability,PolicyAvailability::NaturallyExpired);
 reader.store().database().exec("UPDATE document_grants SET active=0",&[]).unwrap();
 assert_eq!(host.observe(&mut reader,&request).unwrap().availability,PolicyAvailability::Revoked);
 assert_eq!(pins(reader.store()),0);
}
#[test]
fn real_initial_render_begins_once_and_prepares_original_challenge_without_issuance(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 let info=reader.open_presentation(&access).unwrap();
 let request=PolicyBeginRequest{scope:scope(),access:access.clone(),source_digest:info.session.metadata.blob.digest.clone(),presentation_id:"initial".into(),frame_generation:info.status.ticket.generation().clone(),surface_binding:surface(),original_attempt_id:"begin".into()};
 let begun=host.begin(&mut reader,&request,&info.status.ticket,&Revision::new(1)).unwrap();assert_eq!(begun.status,PolicyOutcomeStatus::Begun);
 let again=host.begin(&mut reader,&request,&info.status.ticket,&Revision::new(1)).unwrap();assert_eq!(begun.outcome_id,again.outcome_id);assert!(again.historical);
 let p=PolicyPrepareRequest{scope:scope(),root_id:begun.root_id.unwrap(),expected_root_revision:Revision::new(1),expected_grant_id:access.authority.grant_id.clone(),expected_grant_generation:access.authority.generation.clone(),original_attempt_id:"renew".into(),surface_binding:surface(),expected_presentation_id:"initial".into(),expected_frame_generation:Revision::new(1)};
 let prepared=host.prepare(&mut reader,&p).unwrap();let duplicate=host.prepare(&mut reader,&p).unwrap();assert_eq!(prepared.challenge_id,duplicate.challenge_id);assert!(duplicate.historical);
 assert_eq!(reader.store().database().query("SELECT grant_id FROM document_grants",&[]).unwrap().len(),1);
 host.selection_changed(&mut reader,&scope(),&Revision::new(2)).unwrap();
 let mut late=p;late.original_attempt_id="late".into();assert!(host.prepare(&mut reader,&late).is_err());
 assert_eq!(pins(reader.store()),0);
}
#[test]
fn explicit_revoke_and_reactivation_cannot_unfence_an_established_root(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 let info=reader.open_presentation(&access).unwrap();let request=PolicyBeginRequest{scope:scope(),access:access.clone(),source_digest:info.session.metadata.blob.digest,presentation_id:"initial".into(),frame_generation:Revision::new(1),surface_binding:surface(),original_attempt_id:"begin".into()};
 let root=host.begin(&mut reader,&request,&info.status.ticket,&Revision::new(1)).unwrap();
 reader.store().revoke_document_grant_trusted(&access.authority).unwrap();reader.store().database().exec("UPDATE document_grants SET active=1",&[]).unwrap();
 let p=PolicyPrepareRequest{scope:scope(),root_id:root.root_id.unwrap(),expected_root_revision:Revision::new(1),expected_grant_id:access.authority.grant_id,expected_grant_generation:access.authority.generation,original_attempt_id:"late".into(),surface_binding:surface(),expected_presentation_id:"initial".into(),expected_frame_generation:Revision::new(1)};
 assert!(host.prepare(&mut reader,&p).is_err());
}
