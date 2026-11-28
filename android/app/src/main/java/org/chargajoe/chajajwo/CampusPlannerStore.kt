package org.chargajoe.chajajwo

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.serialization.encodeToString
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingCatalog
import org.chargajoe.chajajwo.data.CampusClass
import org.chargajoe.chajajwo.data.CampusPlannerData
import org.chargajoe.chajajwo.data.CampusVisitTask
import org.chargajoe.chajajwo.data.PlaceResources

/** 시간표·할 일·즐겨찾기 건물. 이 기기에만 저장한다. */
class CampusPlannerStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("cj_campus_planner", Context.MODE_PRIVATE)
    private val key = "cj_campus_planner_v1"

    var data by mutableStateOf(load())
        private set
    var message by mutableStateOf<String?>(null)

    private fun load(): CampusPlannerData {
        val saved = prefs.getString(key, null) ?: return CampusPlannerData()
        return try {
            val decoded = PlaceResources.json.decodeFromString<CampusPlannerData>(saved)
            decoded.copy(classes = decoded.classes.filter { it.isValid }, tasks = decoded.tasks.filter { it.isValid })
        } catch (e: Exception) {
            CampusPlannerData()
        }
    }

    private fun save() {
        prefs.edit().putString(key, PlaceResources.json.encodeToString(data)).apply()
    }

    fun toggleFavorite(building: CampusBuilding) {
        val favorites = data.favoriteBuildings.toMutableSet()
        if (!favorites.add(building.id)) favorites.remove(building.id)
        data = data.copy(favoriteBuildings = favorites); save()
    }

    fun upsert(item: CampusClass) {
        if (!item.isValid) return
        data = data.copy(classes = data.classes.filter { it.id != item.id } + item); save()
    }

    fun removeClass(id: String) { data = data.copy(classes = data.classes.filter { it.id != id }); save() }

    fun upsert(task: CampusVisitTask) {
        if (!task.isValid) return
        // 시간을 바꾸면 예전 알림을 조용히 남겨 두지 않는다.
        cancelReminder(task.id)
        val updated = task.copy(reminderEnabled = false)
        data = data.copy(tasks = data.tasks.filter { it.id != task.id } + updated); save()
    }

    fun toggleCompleted(id: String) {
        data = data.copy(tasks = data.tasks.map {
            if (it.id != id) it
            else {
                val completed = !it.completed
                if (completed) cancelReminder(id)
                it.copy(completed = completed, reminderEnabled = if (completed) false else it.reminderEnabled)
            }
        })
        save()
    }

    fun removeTask(id: String) { cancelReminder(id); data = data.copy(tasks = data.tasks.filter { it.id != id }); save() }

    fun tasks(building: CampusBuilding, completed: Boolean = false): List<CampusVisitTask> =
        data.tasks.filter { it.buildingID == building.id && it.completed == completed }.sortedBy { it.due }

    private fun pendingIntent(task: CampusVisitTask?, id: String, create: Boolean): PendingIntent? {
        val intent = Intent(context, VisitReminderReceiver::class.java).apply {
            action = "campus-visit-$id"
            if (task != null) {
                putExtra("taskID", task.id)
                putExtra("buildingID", task.buildingID)
                putExtra("title", task.title)
                putExtra("location", task.location)
            }
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(context, id.hashCode(), intent, flags)
    }

    private fun cancelReminder(id: String) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        pendingIntent(null, id, create = false)?.let { alarm.cancel(it); it.cancel() }
        NotificationManagerCompat.from(context).cancel(id.hashCode())
    }

    /** 알림 권한이 필요하면 requestPermission을 불러 허용 여부를 받는다. */
    suspend fun toggleReminder(id: String, requestPermission: suspend () -> Boolean) {
        val task = data.tasks.firstOrNull { it.id == id } ?: return
        if (task.completed) return
        if (task.reminderEnabled) {
            cancelReminder(id)
            data = data.copy(tasks = data.tasks.map { if (it.id == id) it.copy(reminderEnabled = false) else it }); save()
            return
        }
        if (task.due <= System.currentTimeMillis() + 60_000) { message = "알림은 1분 이후 시간으로 설정해 주세요."; return }
        val granted = if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermission()
        } else NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (!granted) { message = "알림이 꺼져 있어요. 휴대폰 설정에서 찾아줘 알림을 허용해 주세요."; return }
        try {
            val alarm = context.getSystemService(AlarmManager::class.java)
            val pending = pendingIntent(task, id, create = true) ?: throw IllegalStateException()
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, task.due, pending)
            val current = data.tasks.firstOrNull { it.id == id }
            if (current == null || current.completed || current.due != task.due) { cancelReminder(id); return }
            data = data.copy(tasks = data.tasks.map { if (it.id == id) it.copy(reminderEnabled = true) else it }); save()
        } catch (e: Exception) {
            message = "알림을 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

/** 방문 알림 시간이 되면 알림을 띄운다. 누르면 그 건물 시트의 할 일 화면을 연다. */
class VisitReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskID = intent.getStringExtra("taskID") ?: return
        val buildingID = intent.getStringExtra("buildingID") ?: return
        val title = intent.getStringExtra("title") ?: ""
        val location = intent.getStringExtra("location") ?: ""
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "방문 알림", NotificationManager.IMPORTANCE_HIGH))
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_VISIT_BUILDING, buildingID)
        }
        val content = PendingIntent.getActivity(context, taskID.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentTitle("방문할 시간이에요")
            .setContentText(title + if (location.isEmpty()) "" else " · $location")
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(content)
            .build()
        if (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            NotificationManagerCompat.from(context).notify(taskID.hashCode(), notification)
        }
    }

    companion object {
        const val CHANNEL = "campus-visit"
        const val EXTRA_VISIT_BUILDING = "cj_pending_visit_building"
        fun isKnownBuilding(id: String) = CampusBuildingCatalog.all.any { it.id == id }
    }
}
