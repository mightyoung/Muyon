import android.system.Os
import android.system.OsConstants
fun directorySync(root:String) {
    val directory=Os.open(root,OsConstants.O_RDONLY or OsConstants.O_DIRECTORY or OsConstants.O_NOFOLLOW,0)
    try { Os.fsync(directory) } finally { Os.close(directory) }
}
