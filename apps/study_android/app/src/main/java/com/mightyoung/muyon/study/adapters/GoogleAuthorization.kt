package com.mightyoung.muyon.study.adapters

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope

object GoogleAuthorization {
    fun authorize(activity: Activity, onResult: (AuthorizationResult?, String?) -> Unit) = authorizeScopes(activity, false, onResult)
    fun authorizeWrite(activity: Activity, onResult: (AuthorizationResult?, String?) -> Unit) = authorizeScopes(activity, true, onResult)
    private fun authorizeScopes(activity: Activity, write: Boolean, callback: (AuthorizationResult?, String?) -> Unit) {
        val scopes = mutableListOf(Scope("https://www.googleapis.com/auth/calendar.readonly"), Scope("https://www.googleapis.com/auth/drive.file"))
        if(write) { scopes.add(Scope("https://www.googleapis.com/auth/calendar.events")); scopes.add(Scope("https://www.googleapis.com/auth/calendar.calendars")) }
        Identity.getAuthorizationClient(activity).authorize(AuthorizationRequest.builder().setRequestedScopes(scopes).build())
            .addOnSuccessListener { callback(it, null) }.addOnFailureListener { callback(null, "Google 授权失败，请检查账号与 OAuth 配置") }
    }
    fun resultFromIntent(context: Context, data: Intent): AuthorizationResult = Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data)
}
