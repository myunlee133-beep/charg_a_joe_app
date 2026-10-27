"""Source URL inventory and independently curated campus location labels.

Location mappings are editable hints, not assertions about exact room coordinates.
"""
SOURCES = {
    "snuco": "https://snuco.snu.ac.kr/foodmenu/",
    "snudorm": "https://snudorm.snu.ac.kr/foodmenu/",
    "vet": "https://vet.snu.ac.kr/cafe_menu/",
}

# Extend manually when new dining facilities appear; unknown restaurants are retained.
LOCATIONS = {
    "학생회관식당": ("63동", "학생회관"),
    "자하연식당 3층": ("109동", "자하연"),
    "자하연식당 2층": ("109동", "자하연"),
    "예술계식당": ("74동", "예술계"),
    "두레미담": ("75-1동", "두레미담"),
    "3식당": ("75-1동", None),
    "제3식당": ("75-1동", None),
    "동원관식당": ("113동", "동원관"),
    "302동식당": ("302동", None),
    "301동식당": ("301동", None),
    "공대간이식당": ("30-2동", "공대간이식당"),
    "버거운버거": ("101동", "아시아연구소"),
    "75-1동 4층 푸드코트": ("75-1동", None),
    "220동식당": ("220동", None),
    "아워홈(901동)": ("901동", "관악학생생활관"),
    "생협기숙사(919동)": ("919동", "관악학생생활관"),
    "수의대식당": ("85동", "수의과대학"),
}
