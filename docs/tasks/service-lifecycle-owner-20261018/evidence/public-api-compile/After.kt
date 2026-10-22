import android.system.Os
import android.system.OsConstants
import android.os.Process
fun directorySync(root:String) {
    val directory=Os.open(root,OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW,0)
    try {
        val stat=Os.fstat(directory)
        check((stat.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFDIR &&
            stat.st_uid==Process.myUid() && (stat.st_mode and 4095)==448){"fixture_schedule_root_invalid"}
        Os.fsync(directory)
    } finally { Os.close(directory) }
}
