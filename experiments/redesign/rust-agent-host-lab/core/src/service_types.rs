//! Private service DTO inventory. No live session or authority crosses threads.
#[macro_export]
macro_rules! define_agent_service_types {
    ($record:ident, $enumeration:ident) => {
        $record!(AgentReplyMeta { protocol:u32,build_identity:String,service_epoch:String,server_snapshot_revision:i64 });
        $record!(AgentConnectRequest { protocol:u32,platform_client_key:String });
        $record!(AgentClientRef { protocol:u32,expected_service_epoch:String,client_lease:String });
        $record!(AgentStartRequest { client:AgentClientRef,request_id:String,variant:AgentReadVariant });
        $record!(AgentRunRef { request_id:String,variant:AgentReadVariant,run_id:Option<String> });
        $record!(AgentStatusRequest { client:AgentClientRef,run:AgentRunRef });
        $record!(AgentLookupRequest { client:AgentClientRef,key:AgentLookupKey });
        $record!(AgentVisibilityRequest { client:AgentClientRef,observation_generation:i64,visible:bool });
        $record!(AgentReleaseRequest { client:AgentClientRef,observation_generation:i64 });
        $record!(AgentCancelRequest { client:AgentClientRef,run:AgentRunRef });
        $record!(AgentTaskIdentity { task_id:String,attempt_id:String });
        $record!(AgentRunIdentity { run_id:String,admitted_service_epoch:String,actual_task:Option<AgentTaskIdentity> });
        $record!(AgentReceiptSummary { opaque_id:Option<String>,outcome:AgentReceiptOutcome });
        $record!(AgentRunSummary { request_id:String,variant:AgentReadVariant,source_build_identity:String,identity:AgentRunIdentity,terminal:AgentTerminal,reason:AgentReason,receipt:AgentReceiptSummary });
        $record!(AgentIntentBinding { request_id:String,variant:AgentReadVariant,source_build_identity:String });
        $record!(AgentDurableRun { intent:AgentIntentBinding,identity:AgentRunIdentity });
        $record!(AgentNoAdmissionSettlement { intent:AgentIntentBinding,reason:AgentNoAdmissionReason });
        $record!(AgentUnresolvedObservation { intent:AgentIntentBinding,identity:Option<AgentRunIdentity>,receipt:AgentReceiptSummary });
        $record!(AgentSnapshot { meta:AgentReplyMeta,service_state:AgentServiceState,run:Option<AgentRunSnapshot> });
        $record!(AgentConnectReply { meta:AgentReplyMeta,outcome:AgentConnectOutcome });
        $record!(AgentStartReply { meta:AgentReplyMeta,outcome:AgentStartOutcome });
        $record!(AgentSnapshotReply { meta:AgentReplyMeta,outcome:AgentSnapshotOutcome });
        $record!(AgentControlReply { meta:AgentReplyMeta,outcome:AgentControlOutcome });
        $record!(AgentCloseReply { meta:AgentReplyMeta,outcome:AgentCloseOutcome });
        $enumeration!(AgentReadVariant { Equipment,Research,Inquiry,SeededEquipment });
        $enumeration!(AgentServiceState { Initializing,Ready,RecoveryRequired,Closing,Closed });
        $enumeration!(AgentLookupKey { RequestId{request_id:String},RunId{run_id:String} });
        $enumeration!(AgentTerminal { Completed,Cancelled,Failed,BudgetExhausted,OutcomeUnknown });
        $enumeration!(AgentReceiptOutcome { NotStarted,Unknown,RecordedSuccess,RecordedFailure });
        $enumeration!(AgentReason { None,Cancelled,AuthorityDenied,PurposeDenied,ContractRejected,StorageFailure,ProviderFailure,DeadlineExceeded,BudgetExceeded,Interrupted,InternalFailure });
        $enumeration!(AgentNoAdmissionReason { CancelledBeforeAdmission,QuotaExceeded,DirectoryRejected,IndexValidationRejected,StorageRejectedBeforeAdmission });
        $enumeration!(AgentRunSnapshot { QueuedVolatile{intent:AgentIntentBinding},DurablyAdmitted{run:AgentDurableRun},Running{run:AgentDurableRun},Terminal{summary:AgentRunSummary},SettledNoAdmission{settlement:AgentNoAdmissionSettlement},Unresolved{observation:AgentUnresolvedObservation} });
        $enumeration!(AgentServiceError { UnsupportedProtocol,InvalidRoot,InvalidRequestId,InvalidIdentity,InvalidGeneration,EpochMismatch,ClientUnavailable,ClientNotVisible,RequestConflict,Busy,Closed,TargetUnavailable,RecoveryRequired,BudgetExceeded,InternalFailure });
        $enumeration!(AgentConnectOutcome { Connected{client_lease:String,service_state:AgentServiceState},Busy,Rejected{error:AgentServiceError} });
        $enumeration!(AgentStartOutcome { QueuedVolatile{snapshot:AgentRunSnapshot},Existing{snapshot:AgentRunSnapshot},Busy,Rejected{error:AgentServiceError} });
        $enumeration!(AgentSnapshotOutcome { Snapshot{service_state:AgentServiceState,run:Option<AgentRunSnapshot>},Unresolved,Rejected{error:AgentServiceError} });
        $enumeration!(AgentControlOutcome { Applied,Requested,AlreadyTerminal,NotRunning,NotActive,Rejected{error:AgentServiceError} });
        $enumeration!(AgentCloseOutcome { Closing,Closed,Rejected{error:AgentServiceError} });
    };
}
macro_rules! service_record {
    ($name:ident { $($field:ident:$ty:ty),* }) => {
        #[derive(Clone, Debug, PartialEq, Eq)]
        pub struct $name { $(pub $field:$ty),* }
    };
}
macro_rules! service_enum {
    ($name:ident { $($variant:ident $( { $($field:ident:$ty:ty),* } )? ),* }) => {
        #[derive(Clone, Debug, PartialEq, Eq)]
        pub enum $name { $($variant $( { $($field:$ty),* } )?),* }
    };
}
define_agent_service_types!(service_record, service_enum);
impl std::fmt::Display for AgentServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("agent_service_error")
    }
}
impl std::error::Error for AgentServiceError {}

/// Trusted host composition input; bridge supplies compile-bound source identity.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AgentHostServiceConfig {
    pub protocol: u32,
    pub private_root: String,
    pub build_identity: String,
}
