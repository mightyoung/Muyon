package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import org.junit.Assert.*
import org.junit.Test

/** Metadata-only callback tests. No native controller, source, secret or transport. */
class ServiceHostBindingsTest {
    private open class UnconfiguredOwner:ServiceHostOwnerSource {
        override fun currentScope():ServiceOwnerScope?=null
        override fun currentProviderMetadata():ServiceOwnerProvider?=null
        override fun credentialHandleExists(profileId:String,credentialRef:String)=false
    }
    private fun binding()=ServiceOwnerAdmissionBinding(
        profile=ServiceOwnerProfile(
            id="fixture-profile",endpoint="https://provider.example/v1",endpointIdentity="fixture-endpoint",
            provider="fixture",model="fixture-chat",location=ServiceOwnerLocation.OWN_DEVICE,
            purpose=ServiceOwnerPurpose.CHAT,credentialRef="existing-ref",
            declared=ServiceOwnerCapabilities(toolCalls=false,streaming=true),
            tested=ServiceOwnerCapabilities(toolCalls=true,streaming=true)),
        profileRevision="profile-r",policyRevision="policy-r",grantRevision="grant-r",
        authorizationOwner="fixture-owner",modelAllowed=true,outboundAllowed=true,
        budget=ServiceOwnerBudget(revision="budget-r",quotaProof="quota-proof",remainingCalls=1uL,
            remainingTokens=13uL,remainingMicros=17uL))
    private fun budget()=ServiceOwnerCallBudget(maxTokens=7uL,maxMicros=11uL,requiresTools=false,requiresStreaming=true)

    @Test fun unavailable_owner_defaults_deny_all_admission_operations() {
        val callback=ServiceHostBindings.callback(UnconfiguredOwner())
        val b=binding();val payload=byteArrayOf(0,1,127,-1)
        assertFalse(callback.reviewPayload(b,payload))
        assertNull(callback.reserveBudget(b,"request",payload,budget()))
        assertNull(callback.commitAdmission("reservation",b,"request",payload,"fixture-profile","existing-ref"))
    }

    @Test fun owner_exceptions_fail_closed_for_each_admission_operation() {
        val callback=ServiceHostBindings.callback(object:UnconfiguredOwner() {
            override fun reviewPayload(binding:ServiceOwnerAdmissionBinding,payload:ByteArray):Boolean=error("fixture failure")
            override fun reserveBudget(binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,budget:ServiceOwnerCallBudget):String?=error("fixture failure")
            override fun commitAdmission(reservation:String,binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,credentialProfileId:String,credentialRef:String):String?=error("fixture failure")
        })
        val b=binding();val payload=byteArrayOf(0,1,127,-1)
        assertFalse(callback.reviewPayload(b,payload))
        assertNull(callback.reserveBudget(b,"request",payload,budget()))
        assertNull(callback.commitAdmission("reservation",b,"request",payload,"fixture-profile","existing-ref"))
    }

    @Test fun trusted_owner_receives_exact_objects_and_correlating_metadata() {
        val b=binding();val payload=byteArrayOf(0,1,127,-1);val callBudget=budget()
        val calls=mutableListOf<String>()
        val callback=ServiceHostBindings.callback(object:UnconfiguredOwner() {
            override fun reviewPayload(binding:ServiceOwnerAdmissionBinding,payload:ByteArray):Boolean {
                assertSame(b,binding);assertArrayEquals(byteArrayOf(0,1,127,-1),payload)
                calls.add("review");return true
            }
            override fun reserveBudget(binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,budget:ServiceOwnerCallBudget):String? {
                assertSame(b,binding);assertEquals("exact-request",requestId)
                assertArrayEquals(byteArrayOf(0,1,127,-1),payload);assertSame(callBudget,budget)
                calls.add("reserve");return "owner-reservation"
            }
            override fun commitAdmission(reservation:String,binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,credentialProfileId:String,credentialRef:String):String? {
                assertEquals("owner-reservation",reservation);assertSame(b,binding)
                assertEquals("exact-request",requestId);assertArrayEquals(byteArrayOf(0,1,127,-1),payload)
                assertEquals("fixture-profile",credentialProfileId);assertEquals("existing-ref",credentialRef)
                calls.add("commit");return "admission-row"
            }
        })
        assertTrue(callback.reviewPayload(b,payload))
        assertEquals("owner-reservation",callback.reserveBudget(b,"exact-request",payload,callBudget))
        assertEquals("admission-row",callback.commitAdmission("owner-reservation",b,"exact-request",payload,"fixture-profile","existing-ref"))
        assertEquals(listOf("review","reserve","commit"),calls)
        assertArrayEquals(byteArrayOf(0,1,127,-1),payload)
    }
}
