package com.tjearn.tj_earn

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * Manifest-registered receiver for DownloadManager.ACTION_DOWNLOAD_COMPLETE.
 *
 * Fires the system install intent directly when the updater's download
 * finishes while the app process is dead (Jaani, 3 Nov 2026): the Dart
 * poll loop can't run then, but the user still gets the install prompt.
 * Only acts on the download id the updater last enqueued (stored in the
 * "tj_earn_updater" prefs by MainActivity.downloadApk); every other
 * download is ignored.
 *
 * When the app IS alive, the Dart side also shows its install dialog on
 * success — the system installer simply takes the foreground first; the
 * dialog behind it is harmless (tapping Install re-fires the same APK).
 */
class DownloadCompleteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (id == -1L) return
        val prefs = context.getSharedPreferences("tj_earn_updater", Context.MODE_PRIVATE)
        val expected = prefs.getLong("last_download_id", -1L)
        if (id != expected) return
        // Claim it: a later Dart-side poll must not treat this as new.
        prefs.edit().remove("last_download_id").apply()
        try {
            val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
            if (!cursor.moveToFirst()) {
                cursor.close()
                return
            }
            val status = cursor.getInt(
                cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            )
            val localUri = cursor.getString(
                cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
            ) ?: ""
            cursor.close()
            if (status != DownloadManager.STATUS_SUCCESSFUL) return
            // Our destination (setDestinationInExternalFilesDir) always
            // yields a file:// URI.
            val path = if (localUri.startsWith("file://")) {
                Uri.parse(localUri).path
            } else {
                null
            }
            val apkFile = if (path != null) File(path) else null
            if (apkFile == null || !apkFile.exists()) return
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                apkFile,
            )
            val install = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(install)
        } catch (_: Exception) {
            // Never crash the broadcast; the system notification and the
            // next cold start remain as fallbacks.
        }
    }
}
