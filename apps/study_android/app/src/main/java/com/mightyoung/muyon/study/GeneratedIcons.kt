package com.mightyoung.muyon.study

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

/** Original GPT image assets. Runtime tint preserves the generated alpha silhouette. */
@Composable fun GeneratedIcon(@DrawableRes resource:Int,description:String?,compact:Boolean=false){
    Icon(painterResource(resource),description,Modifier.size(if(compact)24.dp else 32.dp),tint=LocalContentColor.current)
}

@Composable fun ActionLabel(@DrawableRes resource:Int,label:String){
    GeneratedIcon(resource,null,compact=true)
    Spacer(Modifier.width(6.dp))
    Text(label)
}
