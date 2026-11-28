package org.chargajoe.chajajwo.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Apartment as OApartment
import androidx.compose.material.icons.outlined.CalendarMonth as OCalendarMonth
import androidx.compose.material.icons.outlined.Info as OInfo
import androidx.compose.material.icons.outlined.LocalCafe as OLocalCafe
import androidx.compose.material.icons.outlined.NearMe as ONearMe
import androidx.compose.material.icons.outlined.Notifications as ONotifications
import androidx.compose.material.icons.outlined.Phone as OPhone
import androidx.compose.material.icons.outlined.Schedule as OSchedule
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.outlined.Map as OMap
import androidx.compose.material.icons.outlined.People as OPeople
import androidx.compose.material.icons.outlined.WbSunny as OWbSunny
import androidx.compose.material.icons.outlined.DarkMode as ODarkMode
import androidx.compose.material.icons.outlined.WbTwilight as OWbTwilight
import androidx.compose.material.icons.outlined.Layers as OLayers
import androidx.compose.ui.graphics.vector.ImageVector
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.DiningMeal
import org.chargajoe.chajajwo.data.PlaceType

/** SF Symbols → Material 아이콘 대응표. */
object Sym {
    val search: ImageVector = Icons.Filled.Search
    val box: ImageVector = Icons.Filled.Inventory2
    val directionsFill: ImageVector = Icons.Filled.Directions
    val directions: ImageVector = Icons.Filled.Directions
    val xmarkCircle: ImageVector = Icons.Filled.Cancel
    val xmark: ImageVector = Icons.Filled.Close
    val grid: ImageVector = Icons.Filled.GridView
    val forkKnife: ImageVector = Icons.Filled.Restaurant
    val basket: ImageVector = Icons.Filled.ShoppingBasket
    val bus: ImageVector = Icons.Filled.DirectionsBus
    val building: ImageVector = Icons.Filled.Apartment
    val buildingOutline: ImageVector = OApartment
    val locationFill: ImageVector = Icons.Filled.NearMe
    val location: ImageVector = ONearMe
    val plus: ImageVector = Icons.Filled.Add
    val minus: ImageVector = Icons.Filled.Remove
    val layers: ImageVector = OLayers
    val crossCase: ImageVector = Icons.Filled.MedicalServices
    val cup: ImageVector = Icons.Filled.LocalCafe
    val cupOutline: ImageVector = OLocalCafe
    val card: ImageVector = Icons.Filled.CreditCard
    val books: ImageVector = Icons.AutoMirrored.Filled.MenuBook
    val booksOutline: ImageVector = Icons.AutoMirrored.Outlined.MenuBook
    val heartText: ImageVector = Icons.Filled.MonitorHeart
    val star: ImageVector = StarBorder
    val starFill: ImageVector = Icons.Filled.Star
    val map: ImageVector = OMap
    val chevronLeft: ImageVector = Icons.Filled.ChevronLeft
    val chevronRight: ImageVector = Icons.Filled.ChevronRight
    val chevronDown: ImageVector = Icons.Filled.ExpandMore
    val clock: ImageVector = OSchedule
    val circleFill: ImageVector = Icons.Filled.Circle
    val home: ImageVector = Icons.Filled.Home
    val checklist: ImageVector = Icons.Filled.Checklist
    val sparkles: ImageVector = Icons.Filled.AutoAwesome
    val pinEllipse: ImageVector = Icons.Filled.PinDrop
    val chart: ImageVector = Icons.Filled.BarChart
    val calendar: ImageVector = OCalendarMonth
    val bell: ImageVector = ONotifications
    val bellBadge: ImageVector = Icons.Filled.NotificationsActive
    val phone: ImageVector = OPhone
    val phoneFill: ImageVector = Icons.Filled.Phone
    val info: ImageVector = OInfo
    val calendarClock: ImageVector = Icons.Filled.EventAvailable
    val calendarPlus: ImageVector = Icons.Filled.EditCalendar
    val route: ImageVector = Icons.Filled.Route
    val arrowRight: ImageVector = Icons.AutoMirrored.Filled.ArrowForward
    val arrowDown: ImageVector = Icons.Filled.ArrowDownward
    val flask: ImageVector = Icons.Filled.Science
    val openExternal: ImageVector = Icons.AutoMirrored.Filled.OpenInNew
    val refresh: ImageVector = Icons.Filled.Refresh
    val wifiOff: ImageVector = Icons.Filled.WifiOff
    val originDot: ImageVector = Icons.Filled.RadioButtonChecked
    val destinationPin: ImageVector = Icons.Filled.Place
    val swap: ImageVector = Icons.Filled.SwapVert
    val check: ImageVector = Icons.Filled.Check
    val walk: ImageVector = Icons.AutoMirrored.Filled.DirectionsWalk
    val checkSquare: ImageVector = Icons.Filled.CheckBox
    val square: ImageVector = Icons.Filled.CheckBoxOutlineBlank
    val people: ImageVector = OPeople
    val clockQuestion: ImageVector = Icons.Filled.HelpOutline
    val mapPin: ImageVector = Icons.Filled.LocationOn

    fun meal(meal: DiningMeal): ImageVector = when (meal) {
        DiningMeal.BREAKFAST -> OWbTwilight
        DiningMeal.LUNCH -> OWbSunny
        DiningMeal.DINNER -> ODarkMode
    }

    fun place(type: PlaceType): ImageVector = when (type) {
        PlaceType.HUB -> check
        PlaceType.FOOD -> forkKnife
        PlaceType.STOP -> bus
    }

    fun amenity(kind: CampusAmenityKind): ImageVector = when (kind) {
        CampusAmenityKind.PHARMACY -> crossCase
        CampusAmenityKind.CONVENIENCE -> basket
        CampusAmenityKind.CAFE -> cup
        CampusAmenityKind.FOOD -> forkKnife
        CampusAmenityKind.BANK -> card
        CampusAmenityKind.BOOKS -> books
        CampusAmenityKind.HEALTH -> heartText
        CampusAmenityKind.OTHER -> building
    }
}
