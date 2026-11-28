package org.chargajoe.chajajwo.data

import kotlinx.serialization.Serializable

@Serializable
data class ResearchLab(
    val id: String,
    val name: String,
    val buildingNumber: String,
    val room: String = "",
    val rooms: List<String> = emptyList(),
    val floor: String = "",
    val floorDerived: Boolean = false,
    val professor: String = "",
    val professorURL: String = "",
    val phone: String = "",
    val url: String = "",
    val checkedAt: String = "",
    val topics: List<String> = emptyList(),
    val field: String = "",
    val summary: String = "",
) {
    val searchFields: List<String> get() = listOf(name, professor, field, summary, room) + topics
}

@Serializable
data class CampusVenue(
    val id: String,
    val buildingNumber: String,
    val name: String,
    val aliases: List<String> = emptyList(),
    val category: String = "",
    val floor: String = "",
    val phone: String = "",
    val weekdayHours: String = "",
    val checkedAt: String = "",
    val sourceURL: String = "",
    val menuSourceURL: String = "",
    val menuNote: String = "",
    val menus: List<VenueMenu> = emptyList(),
    val photoAsset: String? = null,
    val photoSourceURL: String? = null,
    val photoCaption: String? = null,
    val photoCredit: String? = null,
) {
    val featuredMenu: VenueMenu? get() = menus.firstOrNull { it.featured == true }
    val searchFields: List<String> get() = listOf(name, buildingNumber, buildingNumber + "동") + aliases + menus.map { it.name }
}

@Serializable
data class VenueMenu(
    val name: String,
    val category: String = "",
    val description: String = "",
    val priceWon: Int? = null,
    val photoAsset: String? = null,
    val photoSourceURL: String? = null,
    val photoCredit: String? = null,
    val featured: Boolean? = null,
) {
    val priceLabel: String get() = priceWon?.let { "${it.won()}원" } ?: "가격은 매장에서 확인"
}

object PlaceDirectory {
    @Serializable private data class LabFile(val labs: List<ResearchLab> = emptyList())
    @Serializable private data class VenueFile(val venues: List<CampusVenue> = emptyList())

    // 건물 번호로만 연결한다. 좌표로 추측하지 않는다.
    val labs: List<ResearchLab> by lazy {
        val numbers = CampusBuildingCatalog.all.mapNotNull { it.number }.toSet()
        (PlaceResources.decode<LabFile>("research_labs")?.labs ?: emptyList()).filter { it.buildingNumber in numbers }
    }
    val venues: List<CampusVenue> by lazy {
        val numbers = CampusBuildingCatalog.all.mapNotNull { it.number }.toSet()
        (PlaceResources.decode<VenueFile>("campus_venues")?.venues ?: emptyList()).filter { it.buildingNumber in numbers }
    }

    fun labs(building: CampusBuilding): List<ResearchLab> = labs.filter { it.buildingNumber == building.number }
    fun venues(building: CampusBuilding): List<CampusVenue> = venues.filter { it.buildingNumber == building.number }

    fun floors(building: CampusBuilding): List<String> {
        val values = (building.details?.facilities?.map { floorName(it.floor) } ?: emptyList()) +
            labs(building).map { it.floor } + venues(building).map { it.floor }
        return values.toSet().sortedWith(floorComparator)
    }

    val floorComparator: Comparator<String> = Comparator { lhs, rhs ->
        val a = floorOrder(lhs)
        val b = floorOrder(rhs)
        if (a == b) naturalOrder.compare(lhs, rhs) else a.compareTo(b)
    }

    fun floorName(value: String?): String = if (value.isNullOrEmpty()) "층 정보 미등록" else value

    fun floorOrder(floor: String): Int {
        val n = floor.filter { it.isDigit() }.toIntOrNull() ?: return Int.MAX_VALUE
        return if (floor.contains("지하") || floor.uppercase().startsWith("B")) -n else n
    }

    fun matches(query: String, fields: List<String>): Boolean {
        val terms = query.split(Regex("\\s+")).map { it.compactKey() }.filter { it.isNotEmpty() }
        val text = fields.map { it.compactKey() }
        return terms.all { term -> text.any { it.contains(term) } }
    }

    fun phoneURL(phone: String): String? {
        val digits = phone.filter { it.isDigit() }
        return if (digits.length in 8..12) "tel:$digits" else null
    }

    fun sourceURL(value: String): String? {
        val uri = try { android.net.Uri.parse(value) } catch (e: Exception) { return null }
        return if (uri.scheme == "https" && uri.host != null) value else null
    }

    /** menu_photos/pascucci-latte.png → PlaceMenu-pascucci-latte 에셋 */
    fun imageName(asset: String?): String? {
        if (asset == null || !asset.startsWith("menu_photos/") || asset.contains("..")) return null
        val last = asset.substringAfterLast('/')
        return "PlaceMenu-" + last.substringBeforeLast('.')
    }
}
