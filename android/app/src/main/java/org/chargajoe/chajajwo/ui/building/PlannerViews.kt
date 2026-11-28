package org.chargajoe.chajajwo.ui.building

import android.Manifest
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusClass
import org.chargajoe.chajajwo.data.CampusMinuteRange
import org.chargajoe.chajajwo.data.CampusPlanning
import org.chargajoe.chajajwo.data.CampusVisitTask
import org.chargajoe.chajajwo.data.DiningData
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceDirectory
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.data.seoulCalendar
import org.chargajoe.chajajwo.ui.BuildingDesign
import org.chargajoe.chajajwo.ui.BuildingEmptyCard
import org.chargajoe.chajajwo.ui.BuildingSurface
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.GroupRow
import org.chargajoe.chajajwo.ui.GroupSection
import org.chargajoe.chajajwo.ui.LabelText
import org.chargajoe.chajajwo.ui.LocalApp
import org.chargajoe.chajajwo.ui.LocalNavigator
import org.chargajoe.chajajwo.ui.SegmentedPicker
import org.chargajoe.chajajwo.ui.Sym
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.TextButton
import org.chargajoe.chajajwo.ui.Type
import org.chargajoe.chajajwo.ui.hex
import org.chargajoe.chajajwo.ui.tap
import org.chargajoe.chajajwo.ui.w
import java.util.Calendar

private fun formatDue(millis: Long): String {
    val c = seoulCalendar(millis)
    val ampm = if (c.get(Calendar.AM_PM) == 0) "오전" else "오후"
    val h = c.get(Calendar.HOUR).let { if (it == 0) 12 else it }
    return "${c.get(Calendar.MONTH) + 1}월 ${c.get(Calendar.DAY_OF_MONTH)}일 $ampm $h:%02d".format(c.get(Calendar.MINUTE))
}

/** 알림 권한 요청을 suspend 함수로 감싼다. */
@Composable
private fun rememberNotificationPermission(): suspend () -> Boolean {
    var pending by remember { mutableStateOf<CompletableDeferred<Boolean>?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> pending?.complete(granted); pending = null }
    return remember {
        suspend {
            val deferred = CompletableDeferred<Boolean>()
            pending = deferred
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            deferred.await()
        }
    }
}

@Composable
fun CampusTaskRow(task: CampusVisitTask) {
    val planner = LocalApp.current.planner
    val scope = rememberCoroutineScope()
    val requestPermission = rememberNotificationPermission()
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(36.dp).height(44.dp).tap { planner.toggleCompleted(task.id) }, contentAlignment = Alignment.Center) {
            SymbolIcon(if (task.completed) Sym.checkSquare else Sym.square, BuildingDesign.green, 26.dp, contentDescription = if (task.completed) "할 일 완료 취소" else "할 일 완료")
        }
        Column(Modifier.weight(1f).padding(vertical = 3.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(task.title, style = Type.subheadline.w(FontWeight.SemiBold).copy(textDecoration = if (task.completed) TextDecoration.LineThrough else null))
            if (task.location.isNotEmpty()) Text(task.location, style = Type.caption, color = Cj.secondary)
            Text(formatDue(task.due), style = Type.caption, color = Cj.secondary)
        }
        if (!task.completed) {
            Box(Modifier.size(44.dp).background(BuildingDesign.mint, CircleShape).tap { scope.launch { planner.toggleReminder(task.id, requestPermission) } },
                contentAlignment = Alignment.Center) {
                SymbolIcon(if (task.reminderEnabled) Sym.bellBadge else Sym.bell, BuildingDesign.green, 20.dp,
                    contentDescription = if (task.reminderEnabled) "방문 알림 해제" else "방문 알림 설정")
            }
        }
    }
}

@Composable
fun CampusTaskListView(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    var completed by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            SegmentedPicker(listOf(false, true), completed, { if (it) "완료한 일" else "할 일 목록" }) { completed = it }
            val tasks = planner.tasks(building, completed)
            if (tasks.isEmpty()) {
                BuildingEmptyCard(Sym.checklist, if (completed) "완료한 일이 없어요" else "방문할 일을 기록해 보세요",
                    if (completed) "마친 일은 여기에 모아둘게요." else "식사, 서점 방문, 팀플 준비처럼 이 건물에서 할 일을 추가하세요.")
            }
            tasks.forEach { task ->
                BuildingSurface {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        CampusTaskRow(task)
                        Row(Modifier.heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("수정", style = Type.caption, color = Cj.tealText, modifier = Modifier.tap { nav?.push("할 일 수정") { CampusTaskEditorView(building, task) } }.padding(8.dp))
                            Spacer(Modifier.weight(1f))
                            Text("삭제", style = Type.caption, color = hex(0xFF3B30), modifier = Modifier.tap { planner.removeTask(task.id) }.padding(8.dp))
                        }
                    }
                }
            }
            BuildingSurface { LabelText("종 아이콘을 누르면 설정한 시간에 이 기기로 방문 알림을 보내드려요.", Sym.bell, Type.subheadline, Cj.secondary) }
        }
        Box(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.95f)).padding(16.dp)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).background(BuildingDesign.green, CircleShape)
                .tap { nav?.push("할 일 추가") { CampusTaskEditorView(building) } },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                LabelText("할 일 추가", Sym.plus, Type.headline, Color.White)
            }
        }
    }
}

@Composable
private fun FormTextField(value: String, onChange: (String) -> Unit, placeholder: String, keyboardType: KeyboardType = KeyboardType.Text) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
        if (value.isEmpty()) Text(placeholder, style = Type.body, color = hex(0x3C3C43).copy(alpha = 0.3f))
        BasicTextField(value, onChange, singleLine = true, textStyle = Type.body.copy(color = Color.Black), cursorBrush = SolidColor(Cj.teal),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType), modifier = Modifier.fillMaxWidth())
    }
}

/** DatePicker(.date / .hourAndMinute) 대응: 누르면 시스템 날짜·시간 선택 창을 띄운다. */
@Composable
private fun DateTimeRow(label: String, millis: Long, showDate: Boolean, onChange: (Long) -> Unit, showDivider: Boolean = true) {
    val context = LocalContext.current
    val c = seoulCalendar(millis)
    GroupRow(showDivider = showDivider) {
        Text(label, style = Type.body, modifier = Modifier.weight(1f))
        if (showDate) {
            Text("${c.get(Calendar.YEAR)}. ${c.get(Calendar.MONTH) + 1}. ${c.get(Calendar.DAY_OF_MONTH)}.", style = Type.body,
                modifier = Modifier.background(hex(0x767680).copy(alpha = 0.12f), RoundedCornerShape(6.dp)).tap {
                    DatePickerDialog(context, { _, y, m, d ->
                        onChange(seoulCalendar(millis).apply { set(y, m, d) }.timeInMillis)
                    }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).show()
                }.padding(horizontal = 10.dp, vertical = 6.dp))
            Spacer(Modifier.width(6.dp))
        }
        val ampm = if (c.get(Calendar.AM_PM) == 0) "오전" else "오후"
        val h = c.get(Calendar.HOUR).let { if (it == 0) 12 else it }
        Text("$ampm $h:%02d".format(c.get(Calendar.MINUTE)), style = Type.body,
            modifier = Modifier.background(hex(0x767680).copy(alpha = 0.12f), RoundedCornerShape(6.dp)).tap {
                TimePickerDialog(context, { _, hour, minute ->
                    onChange(seoulCalendar(millis).apply { set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute); set(Calendar.SECOND, 0) }.timeInMillis)
                }, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), false).show()
            }.padding(horizontal = 10.dp, vertical = 6.dp))
    }
}

@Composable
fun CampusTaskEditorView(building: CampusBuilding, task: CampusVisitTask? = null, presetTitle: String = "", presetLocation: String = "") {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    var title by remember { mutableStateOf(task?.title ?: presetTitle) }
    var location by remember { mutableStateOf(task?.location ?: presetLocation) }
    var due by remember { mutableLongStateOf(task?.due ?: (System.currentTimeMillis() + 3_600_000)) }
    val valid = title.isNotBlank() && title.length <= 120
    Column(Modifier.fillMaxSize().background(Cj.grouped).verticalScroll(rememberScrollState())) {
        GroupSection("무엇을 할까요?") {
            GroupRow { FormTextField(title, { title = it }, "예: 학생회관 식당에서 점심 먹기") }
            GroupRow { Text(building.displayTitle, style = Type.subheadline, color = Cj.secondary) }
            GroupRow { FormTextField(location, { location = it }, "층·공간 이름 (선택)") }
            DateTimeRow("방문 시간", due, showDate = true, onChange = { due = it }, showDivider = false)
        }
        GroupSection(footer = if (task?.reminderEnabled == true) "수정하면 기존 알림은 해제돼요. 저장한 뒤 종 아이콘을 눌러 다시 설정해 주세요."
            else "할 일은 이 기기에 저장돼요. 저장 후 종 아이콘을 누르면 방문 알림을 설정할 수 있어요.")
        GroupSection {
            GroupRow(onClick = if (valid) ({
                val base = task ?: CampusVisitTask(title = title, buildingID = building.id, location = location, due = due)
                planner.upsert(base.copy(title = title.trim(), location = location, due = due))
                nav?.pop()
            }) else null, showDivider = false) {
                Text("저장", style = Type.body, color = if (valid) Cj.tealText else Cj.tertiary)
            }
        }
    }
}

@Composable
fun CampusTimetableView(building: CampusBuilding, initialRecommendations: Boolean = false) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    var recommendations by remember { mutableStateOf(initialRecommendations) }
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp), horizontalArrangement = Arrangement.End) {
            Row(Modifier.heightIn(min = 40.dp).tap { nav?.push("수업 추가") { CampusClassEditorView() } }, verticalAlignment = Alignment.CenterVertically) {
                LabelText("수업 추가", Sym.plus, Type.subheadline.w(FontWeight.SemiBold), Cj.tealText)
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            SegmentedPicker(listOf(false, true), recommendations, { if (it) "방문 추천 시간" else "주간 시간표" }) { recommendations = it }
            if (recommendations) CampusVisitRecommendations(building)
            else {
                val classes = planner.data.classes
                if (classes.isEmpty()) {
                    BuildingEmptyCard(Sym.calendarPlus, "내 수업을 추가해 보세요", "수업 사이의 공강을 찾아 방문할 수 있는 시간을 안내해 드려요.")
                    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).background(BuildingDesign.green, CircleShape).tap { nav?.push("수업 추가") { CampusClassEditorView() } },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        LabelText("첫 수업 추가", Sym.plus, Type.headline, Color.White)
                    }
                } else CampusWeekGrid(classes)
                classes.sortedWith(compareBy({ it.weekday }, { it.startMinute })).forEach { item ->
                    Box(Modifier.tap { nav?.push("수업 수정") { CampusClassEditorView(item) } }) {
                        BuildingSurface {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Box(Modifier.width(5.dp).height(52.dp).background(WeekColors[maxOf(0, item.colorIndex) % 5], RoundedCornerShape(3.dp)))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                    Text(item.title, style = Type.headline)
                                    Text("${CampusPlanning.dayName(item.weekday)} · ${CampusPlanning.time(item.startMinute)}–${CampusPlanning.time(item.endMinute)}",
                                        style = Type.subheadline, color = Cj.secondary)
                                    if (item.buildingNumber.isNotEmpty()) Text("${item.buildingNumber}동 ${item.room}", style = Type.caption, color = Cj.secondary)
                                }
                                SymbolIcon(Sym.chevronRight, Cj.secondary, 16.dp)
                            }
                        }
                    }
                }
            }
            Text("서울 시간 기준 · 직접 등록한 일정만 사용하며 이 기기에 저장돼요.", style = Type.caption, color = Cj.secondary)
        }
    }
}

private val WeekColors = listOf(hex(0xdce8ff), hex(0xffedbc), hex(0xcdebe1), hex(0xe6ddfa), hex(0xffdcbf))

@Composable
fun CampusWeekGrid(classes: List<CampusClass>) {
    val days = if (classes.any { it.weekday == 1 || it.weekday == 7 }) listOf(2, 3, 4, 5, 6, 7, 1) else listOf(2, 3, 4, 5, 6)
    val firstHour = minOf(8, classes.minOfOrNull { it.startMinute / 60 } ?: 8)
    val lastHour = minOf(24, maxOf(21, classes.maxOfOrNull { (it.endMinute + 59) / 60 } ?: 21))
    val shape = RoundedCornerShape(12.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(Color.White).border(1.dp, BuildingDesign.line, shape)) {
        Row(Modifier.fillMaxWidth().height(34.dp).background(Color.White), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(30.dp))
            days.forEach { Text(CampusPlanning.dayName(it), style = Type.caption.w(FontWeight.SemiBold), modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
        }
        Row {
            Column(Modifier.width(30.dp)) {
                for (hour in firstHour until lastHour) Text("${hour}시", fontSize = 10.sp, color = Cj.secondary, modifier = Modifier.height(48.dp))
            }
            BoxWithConstraints(Modifier.weight(1f).height((48 * (lastHour - firstHour)).dp)) {
                val width = maxWidth / days.size
                Canvas(Modifier.fillMaxSize()) {
                    val w = size.width / days.size
                    for (i in 0..days.size) drawLine(BuildingDesign.line, Offset(i * w, 0f), Offset(i * w, size.height), 0.6.dp.toPx())
                    for (h in firstHour..lastHour) {
                        val y = (h - firstHour) * 48.dp.toPx()
                        drawLine(BuildingDesign.line, Offset(0f, y), Offset(size.width, y), 0.6.dp.toPx())
                    }
                }
                classes.filter { it.isValid }.forEach { item ->
                    val day = days.indexOf(item.weekday)
                    if (day >= 0) {
                        Text(item.title + if (item.room.isEmpty()) "" else "\n" + item.room, fontSize = 10.sp, fontWeight = FontWeight.Medium, lineHeight = 12.sp,
                            modifier = Modifier.offset(x = width * day + 1.dp, y = ((item.startMinute - firstHour * 60) / 60f * 48).dp + 1.dp)
                                .width(maxOf(1.dp, width - 3.dp)).height(maxOf(4.dp, ((item.endMinute - item.startMinute) / 60f * 48).dp - 2.dp))
                                .background(WeekColors[maxOf(0, item.colorIndex) % 5], RoundedCornerShape(4.dp)).clip(RoundedCornerShape(4.dp)).padding(4.dp))
                    }
                }
            }
        }
    }
    Text("주간 미리보기 · 아래 수업을 선택하면 수정할 수 있어요.", style = Type.caption, color = Cj.secondary)
}

private fun minuteMillis(minute: Int): Long = DiningData.startOfDay(System.currentTimeMillis()) + minute * 60_000L

@Composable
fun CampusClassEditorView(item: CampusClass? = null) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    var title by remember { mutableStateOf(item?.title ?: "") }
    var weekday by remember { mutableStateOf(item?.weekday ?: CampusPlanning.weekdayOf(System.currentTimeMillis())) }
    var start by remember { mutableLongStateOf(minuteMillis(item?.startMinute ?: 540)) }
    var end by remember { mutableLongStateOf(minuteMillis(item?.endMinute ?: 600)) }
    var buildingNumber by remember { mutableStateOf(item?.buildingNumber ?: "") }
    var room by remember { mutableStateOf(item?.room ?: "") }
    val startMinute = CampusPlanning.minuteOf(start)
    val endRaw = CampusPlanning.minuteOf(end)
    val candidate = (item ?: CampusClass(title = title, weekday = weekday, startMinute = 0, endMinute = 0, colorIndex = planner.data.classes.size % 5)).copy(
        title = title, weekday = weekday, startMinute = startMinute,
        endMinute = if (endRaw == 0 && startMinute > 0) 1440 else endRaw,
        buildingNumber = buildingNumber.trim().replace("동", ""), room = room,
    )
    val conflicts = CampusPlanning.conflicts(candidate, planner.data.classes)
    var weekdayMenu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(Cj.grouped).verticalScroll(rememberScrollState())) {
        GroupSection("수업 정보") {
            GroupRow { FormTextField(title, { title = it }, "수업명") }
            GroupRow {
                Text("요일", style = Type.body, modifier = Modifier.weight(1f))
                Box {
                    Text(CampusPlanning.dayName(weekday) + "요일", style = Type.body, color = Cj.secondary, modifier = Modifier.tap { weekdayMenu = true }.padding(6.dp))
                    DropdownMenu(weekdayMenu, onDismissRequest = { weekdayMenu = false }) {
                        listOf(2, 3, 4, 5, 6, 7, 1).forEach { d ->
                            DropdownMenuItem(text = { Text(CampusPlanning.dayName(d) + "요일") }, onClick = { weekday = d; weekdayMenu = false })
                        }
                    }
                }
            }
            DateTimeRow("시작", start, showDate = false, onChange = { start = it })
            DateTimeRow("종료", end, showDate = false, onChange = { end = it })
            GroupRow { FormTextField(buildingNumber, { buildingNumber = it }, "건물 번호 (선택)", KeyboardType.Number) }
            GroupRow(showDivider = false) { FormTextField(room, { room = it }, "호실 (선택)") }
        }
        if (title.isNotEmpty() && !candidate.isValid) Text("수업명과 시작·종료 시간을 확인해 주세요. 자정을 넘는 수업은 요일별로 나눠 등록하세요.",
            style = Type.caption, color = hex(0xFF3B30), modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp))
        if (conflicts) Text("등록된 수업과 시간이 겹쳐요.", style = Type.caption, color = hex(0xFF3B30), modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp))
        GroupSection {
            val enabled = candidate.isValid && !conflicts
            GroupRow(onClick = if (enabled) ({ planner.upsert(candidate); nav?.pop() }) else null, showDivider = item != null) {
                Text("저장", style = Type.body, color = if (enabled) Cj.tealText else Cj.tertiary)
            }
            if (item != null) GroupRow(onClick = { planner.removeClass(item.id); nav?.pop() }, showDivider = false) {
                Text("수업 삭제", style = Type.body, color = hex(0xFF3B30))
            }
        }
    }
}

@Composable
fun CampusVisitRecommendations(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val app = LocalApp.current
    val planner = app.planner
    var weekday by remember { mutableStateOf(CampusPlanning.weekdayOf(System.currentTimeMillis())) }
    var menu by remember { mutableStateOf(false) }
    val hours: List<CampusMinuteRange> = run {
        val places = Place.all.filter { it.type == PlaceType.FOOD && it.building == building.buildingNumberLabel }
        // 오늘 이후 처음 오는 그 요일
        var next = DiningData.startOfDay(System.currentTimeMillis())
        while (CampusPlanning.weekdayOf(next) != weekday) next = DiningData.addDays(next, 1)
        val restaurantHours = places.flatMap { CampusPlanning.parseHours(app.store.dining.hours(it, next + 12 * 3_600_000L)) }
        val cafeHours = if (weekday in 2..6) PlaceDirectory.venues(building).flatMap { CampusPlanning.parseHours(it.weekdayHours) } else emptyList()
        restaurantHours + cafeHours
    }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Box {
            Row(Modifier.heightIn(min = 40.dp).tap { menu = true }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(CampusPlanning.dayName(weekday) + "요일", style = Type.body, color = Cj.tealText)
                SymbolIcon(Sym.chevronDown, Cj.tealText, 18.dp)
            }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                listOf(2, 3, 4, 5, 6, 7, 1).forEach { d -> DropdownMenuItem(text = { Text(CampusPlanning.dayName(d) + "요일") }, onClick = { weekday = d; menu = false }) }
            }
        }
        if (planner.data.classes.isEmpty()) {
            BuildingEmptyCard(Sym.calendar, "수업을 먼저 등록해 주세요", "등록한 수업의 빈 시간과 공개 운영시간을 함께 확인할게요.")
            TextButton("수업 추가") { nav?.push("수업 추가") { CampusClassEditorView() } }
        } else {
            val sourceHours = if (hours.isEmpty()) listOf(CampusMinuteRange(540, 1080)) else hours
            val after = if (weekday == CampusPlanning.weekdayOf(System.currentTimeMillis())) CampusPlanning.minuteOf(System.currentTimeMillis()) else 0
            val ranges = CampusPlanning.visitRanges(planner.data.classes, weekday, sourceHours, after)
            Text(if (hours.isEmpty()) "이 요일의 공개 운영 구간 없음 · 09–18시 공강만 표시해요" else "등록한 수업과 식당·카페의 공개 운영시간 기준이에요",
                style = Type.footnote, color = Cj.secondary)
            ranges.take(4).forEach { range ->
                BuildingSurface {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        LabelText(range.label, Sym.clock, Type.headline, BuildingDesign.green)
                        Text("${range.duration}분의 공강 · 이동시간은 길찾기에서 확인해 주세요.", style = Type.subheadline, color = Cj.secondary)
                        Text("이 시간에 둘러볼 공간", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText,
                            modifier = Modifier.heightIn(min = 44.dp).tap { nav?.push("공강 공간 추천") { CampusSpaceRecommendationsView(building) } }.padding(vertical = 12.dp))
                    }
                }
            }
            if (ranges.isEmpty()) BuildingEmptyCard(Sym.calendarClock, "조건에 맞는 공강이 없어요", "다른 요일을 선택해 보세요. 30분 이상의 빈 시간을 안내해요.")
            Text("방문 추천은 혼잡도 예측이 아니에요. 휴일·방학·임시 휴무와 실제 좌석 상황은 매장에 확인해 주세요.", style = Type.caption, color = Cj.secondary)
        }
    }
}

