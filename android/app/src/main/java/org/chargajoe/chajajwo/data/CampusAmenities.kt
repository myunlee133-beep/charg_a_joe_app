package org.chargajoe.chajajwo.data

import kotlinx.serialization.Serializable

enum class CampusAmenityKind(val raw: String, val title: String) {
    PHARMACY("pharmacy", "약국"),
    CONVENIENCE("convenience", "편의점"),
    CAFE("cafe", "카페"),
    FOOD("food", "식당"),
    BANK("bank", "은행·ATM"),
    BOOKS("books", "서점·문구"),
    HEALTH("health", "건강·의료"),
    OTHER("other", "기타 시설");

    companion object {
        val everyday = listOf(PHARMACY, CONVENIENCE, CAFE)
        val highlights = listOf(PHARMACY, CONVENIENCE, CAFE, FOOD)
        fun fromCategory(category: String): CampusAmenityKind = when (category) {
            "약국" -> PHARMACY
            "편의점" -> CONVENIENCE
            "카페" -> CAFE
            "식당", "채식식당" -> FOOD
            "은행", "ATM" -> BANK
            "서점", "문구", "기념품" -> BOOKS
            "건강", "병원" -> HEALTH
            else -> OTHER
        }
    }
}

@Serializable
data class CampusAmenityInfo(
    val facilityID: String,
    val buildingNumber: String,
    val displayName: String? = null,
    val aliases: List<String> = emptyList(),
    val phone: String? = null,
    val weekdayHours: String? = null,
    val saturdayHours: String? = null,
    val holidayHours: String? = null,
    val items: List<String> = emptyList(),
    val note: String? = null,
    val sourceURL: String = "",
    val checkedAt: String = "",
)

/** 위치는 건물 좌표. 실내·매장 좌표를 추측하지 않는다. */
data class CampusAmenity(
    val building: CampusBuilding,
    val facility: CampusBuildingFacility,
    val info: CampusAmenityInfo?,
    val venue: CampusVenue?,
) {
    val id: String get() = facility.id
    val kind: CampusAmenityKind get() = CampusAmenityKind.fromCategory(facility.category)
    val name: String get() = info?.displayName ?: venue?.name ?: facility.name
    val floor: String get() = venue?.floor ?: PlaceDirectory.floorName(facility.floor)
    val shortFloor: String get() = floor.replace("지상", "")
    val location: String get() = building.name + " · " + building.buildingNumberLabel + " " + shortFloor
    val phone: String? get() = info?.phone ?: venue?.phone
    val weekdayHours: String? get() = info?.weekdayHours ?: venue?.weekdayHours
    val sourceURL: String get() = info?.sourceURL ?: venue?.sourceURL ?: "https://map.snu.ac.kr/"
    val checkedAt: String get() = info?.checkedAt ?: venue?.checkedAt ?: building.details?.checkedAt ?: ""
    val searchFields: List<String>
        get() = listOf(name, facility.name, facility.category, kind.title, building.name, building.number ?: "",
            building.buildingNumberLabel, shortFloor) + (info?.aliases ?: emptyList()) + (venue?.aliases ?: emptyList())
}

data class CampusAmenityMapGroup(val building: CampusBuilding, val amenities: List<CampusAmenity>) {
    val id: String get() = building.id
}

object CampusAmenities {
    @Serializable private data class InfoFile(val facilities: List<CampusAmenityInfo> = emptyList())

    val information: List<CampusAmenityInfo> by lazy {
        PlaceResources.decode<InfoFile>("campus_amenity_details")?.facilities ?: emptyList()
    }

    val all: List<CampusAmenity> by lazy {
        val supplements = LinkedHashMap<String, CampusAmenityInfo>()
        information.forEach { supplements.putIfAbsent(it.facilityID, it) }
        CampusBuildingCatalog.all.flatMap { building ->
            (building.details?.facilities ?: emptyList()).map { facility ->
                val info = supplements[facility.id]?.takeIf { it.buildingNumber == building.number }
                val venue = PlaceDirectory.venues(building).firstOrNull { venue ->
                    (listOf(venue.name) + venue.aliases).any { it.compactKey() == facility.name.compactKey() }
                }
                CampusAmenity(building, facility, info, venue)
            }
        }
    }

    private val ordered: Comparator<CampusAmenity> = Comparator { lhs, rhs ->
        if (lhs.building.id != rhs.building.id) return@Comparator naturalOrder.compare(lhs.building.displayTitle, rhs.building.displayTitle)
        val a = PlaceDirectory.floorOrder(lhs.floor)
        val b = PlaceDirectory.floorOrder(rhs.floor)
        if (a != b) a.compareTo(b) else naturalOrder.compare(lhs.name, rhs.name)
    }

    fun inBuilding(building: CampusBuilding, kind: CampusAmenityKind? = null): List<CampusAmenity> =
        all.filter { it.building.id == building.id && (kind == null || it.kind == kind) }.sortedWith(ordered)

    fun search(query: String, kind: CampusAmenityKind? = null): List<CampusAmenity> {
        if (query.isBlank()) return emptyList()
        val key = query.compactKey()
        fun exact(a: CampusAmenity) = (listOf(a.name, a.facility.name) + (a.info?.aliases ?: emptyList())).any { it.compactKey() == key }
        return all.filter { (kind == null || it.kind == kind) && PlaceDirectory.matches(query, it.searchFields) }
            .sortedWith { lhs, rhs ->
                val a = exact(lhs)
                val b = exact(rhs)
                if (a == b) ordered.compare(lhs, rhs) else if (a) -1 else 1
            }
    }

    fun mapGroups(kind: CampusAmenityKind? = null): List<CampusAmenityMapGroup> {
        val amenities = all.filter { if (kind == null) it.kind in CampusAmenityKind.everyday else it.kind == kind }
        return amenities.groupBy { it.building.id }.values.mapNotNull { items ->
            val first = items.firstOrNull() ?: return@mapNotNull null
            CampusAmenityMapGroup(first.building, items.sortedWith(ordered))
        }.sortedWith { a, b -> naturalOrder.compare(a.building.displayTitle, b.building.displayTitle) }
    }
}
