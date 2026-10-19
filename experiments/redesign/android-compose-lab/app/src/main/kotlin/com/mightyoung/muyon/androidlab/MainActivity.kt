package com.mightyoung.muyon.androidlab

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent

class MainActivity : ComponentActivity() {
    private lateinit var visibilityIdentity:String
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        visibilityIdentity=(application as MuyonLabApplication).newActivityIdentity()
        setContent { MuyonLabShell() }
        if(savedInstanceState==null)(application as MuyonLabApplication).openChatCredentialEntry(this)
    }
    override fun onStart(){super.onStart();(application as MuyonLabApplication).activityVisibility(visibilityIdentity,true)}
    override fun onStop(){(application as MuyonLabApplication).activityVisibility(visibilityIdentity,false);super.onStop()}
}
