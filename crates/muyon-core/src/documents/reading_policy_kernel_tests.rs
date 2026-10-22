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

fn request(access:&DocumentAccess, info:&reader::DocumentPresentationInfo, id:&str)->PolicyBeginRequest {
 PolicyBeginRequest{scope:scope(),access:access.clone(),source_digest:info.session.metadata.blob.digest.clone(),presentation_id:id.into(),frame_generation:info.status.ticket.generation().clone(),surface_binding:surface(),original_attempt_id:id.into()}
}
fn prepare_request(access:&DocumentAccess, begun:&OriginalPolicyOutcome,id:&str)->PolicyPrepareRequest {
 PolicyPrepareRequest{scope:scope(),root_id:begun.root_id.clone().unwrap(),expected_root_revision:Revision::new(1),expected_grant_id:access.authority.grant_id.clone(),expected_grant_generation:access.authority.generation.clone(),original_attempt_id:id.into(),surface_binding:surface(),expected_presentation_id:begun.presentation_id.clone().unwrap(),expected_frame_generation:Revision::new(1)}
}
#[test]
fn presentation_created_before_native_selection_cannot_be_adopted(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();
 let old=reader.open_presentation(&access).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 assert!(host.begin(&mut reader,&request(&access,&old,"old"),&old.status.ticket,&Revision::new(1)).is_err());
 assert_eq!(pins(reader.store()),0);
}
#[test]
fn late_old_selection_begin_cannot_adopt_or_close_new_selection(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();
 host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();let old=reader.open_presentation(&access).unwrap();
 host.selection_changed(&mut reader,&scope(),&Revision::new(2)).unwrap();let next=reader.open_presentation(&access).unwrap();
 assert!(host.begin(&mut reader,&request(&access,&old,"late"),&old.status.ticket,&Revision::new(2)).is_err());
 reader.check_presentation(&next.status.ticket).unwrap();assert_eq!(pins(reader.store()),1);
 host.begin(&mut reader,&request(&access,&next,"new"),&next.status.ticket,&Revision::new(2)).unwrap();
}
#[test]
fn explicit_close_after_natural_session_cleanup_terminates_root(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 let info=reader.open_presentation(&access).unwrap();let begun=host.begin(&mut reader,&request(&access,&info,"begin"),&info.status.ticket,&Revision::new(1)).unwrap();
 reader.expire_for_test(info.status.ticket.session_id(),false);assert!(reader.check_presentation(&info.status.ticket).is_err());
 reader.close_presentation(&info.status.ticket).unwrap();reader.close_presentation(&info.status.ticket).unwrap();
 assert!(host.prepare(&mut reader,&prepare_request(&access,&begun,"late")).is_err());
}
#[test]
fn close_all_after_natural_session_cleanup_terminates_root(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 let info=reader.open_presentation(&access).unwrap();let begun=host.begin(&mut reader,&request(&access,&info,"begin"),&info.status.ticket,&Revision::new(1)).unwrap();
 reader.expire_for_test(info.status.ticket.session_id(),false);assert!(reader.check_presentation(&info.status.ticket).is_err());reader.close_all().unwrap();
 assert!(host.prepare(&mut reader,&prepare_request(&access,&begun,"late")).is_err());
}
#[test]
fn lost_pin_failure_cannot_be_reclassified_by_later_grant_expiry(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();host.selection_changed(&mut reader,&scope(),&Revision::new(1)).unwrap();
 let info=reader.open_presentation(&access).unwrap();let begun=host.begin(&mut reader,&request(&access,&info,"begin"),&info.status.ticket,&Revision::new(1)).unwrap();
 reader.store().database().exec("DELETE FROM blob_pins WHERE kind='reader'",&[]).unwrap();assert!(reader.check_presentation(&info.status.ticket).is_err());
 reader.store().database().exec("UPDATE document_grants SET expires_at_ms='0'",&[]).unwrap();
 assert!(host.prepare(&mut reader,&prepare_request(&access,&begun,"late")).is_err());
}
#[test]
fn observe_does_not_disclose_other_document_generation(){
 let(_f,mut reader,access)=setup();let mut host=ReadingPolicyHost::open(&mut reader).unwrap();
 let mut foreign=access.document.scope().clone();foreign.project_id=Some("other-project".into());
 let foreign=DocumentRef::new(foreign,"other-document",Revision::new(1),DocumentFormat::Pdf).unwrap();
 reader.store().database().exec("UPDATE document_grants SET document_json=?",&[&serde_json::to_string(&foreign).unwrap()]).unwrap();
 let mut wanted=access;wanted.authority.generation=wanted.authority.generation.next().unwrap();
 assert_eq!(host.observe(&mut reader,&PolicyObserveRequest{scope:scope(),access:wanted}).unwrap().availability,PolicyAvailability::Unavailable);
}
