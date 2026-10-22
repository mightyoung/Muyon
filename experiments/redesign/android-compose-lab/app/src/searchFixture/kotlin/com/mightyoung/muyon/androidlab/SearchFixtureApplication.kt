package com.mightyoung.muyon.androidlab

/** Isolated compile-time no-network tool installer; never included in debug/release. */
class SearchFixtureApplication:MuyonLabApplication() {override val syntheticRegisteredTools:Boolean get()=true}
