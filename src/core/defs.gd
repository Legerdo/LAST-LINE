class_name Defs
extends RefCounted
## All static game data. Numbers here are the balance surface; tools/sim reads the same data.

# ---------------------------------------------------------------- train
const TRAIN_SPEED := 40.0
const TRAIN_ACCEL := 28.0
const TRAIN_BRAKE := 110.0
const LOCO_LEN := 32.0
const CAR_LEN := 28.0
const CAR_GAP := 3.0
const BASE_HULL := 80.0
const BASE_CREW_CAP := 4
const CREW_RATE_BONUS := 0.02
const HAND_MAX := 8
const BASE_MAX_CARS := 5  # cars behind the locomotive

const CARS := {
	"gun": {"name": "기관총차", "hull": 20, "desc": "가장 가까운 적에게 연사.",
		"weapon": {"kind": "gun", "dmg": 5.0, "rate": 2.5, "range": 68.0}},
	"flame": {"name": "화염방사차", "hull": 26, "desc": "근거리의 모든 적을 태운다. 떼거리에 강함.",
		"weapon": {"kind": "flame", "dmg": 2.4, "rate": 5.0, "range": 40.0, "burn": 2.0}},
	"mortar": {"name": "박격포차", "hull": 20, "desc": "먼 적 무리에 포탄 광역 피해. 근접 불가.",
		"weapon": {"kind": "mortar", "dmg": 15.0, "rate": 0.5, "range": 150.0, "min": 34.0, "radius": 20.0}},
	"tesla": {"name": "테슬라차", "hull": 20, "desc": "적 사이를 튀는 연쇄 전격.",
		"weapon": {"kind": "tesla", "dmg": 8.0, "rate": 0.9, "range": 74.0, "chains": 3}},
	"armor": {"name": "장갑차", "hull": 55, "armor": 1.0, "ram": 1, "desc": "선체 대폭 증가, 모든 피해 -1."},
	"repair": {"name": "정비차", "hull": 20, "regen": 1.4, "desc": "전투가 없으면 선체 자동 수리. 역 수리량 +50%."},
	"passenger": {"name": "객차", "hull": 25, "crew": 8, "desc": "생존자 탑승 한도 +8."},
	"cargo": {"name": "화물차", "hull": 30, "loot": 0.15, "keep": 0.05, "desc": "고철 획득 +15%, 파괴 시 보존 +5%."},
}
const CAR_BASE_UNLOCKED := ["gun", "passenger", "cargo"]

const MODULES := {
	"ap": {"name": "철갑탄", "desc": "기관총 피해 +2.", "icon": 12},
	"mag": {"name": "확장 탄창", "desc": "모든 무기 연사 +15%.", "icon": 12},
	"plate": {"name": "장갑판", "desc": "최대 선체 +30, 즉시 30 수리.", "icon": 13},
	"napalm": {"name": "네이팜", "desc": "화염 화상 +60%, 사거리 +6.", "icon": 14},
	"shrapnel": {"name": "파편탄", "desc": "박격포 폭발 반경 +40%, 피해 +4.", "icon": 14},
	"coil": {"name": "고압 축전기", "desc": "테슬라 연쇄 +2.", "icon": 11},
	"scope": {"name": "조준경", "desc": "모든 무기 사거리 +12%.", "icon": 12},
	"engine": {"name": "엔진 개조", "desc": "열차 속도 +10%.", "icon": 15},
	"plow": {"name": "충각", "desc": "들이받기 힘 +2, 충돌 피해 2배.", "icon": 13},
	"patch": {"name": "응급 수리", "desc": "선체 40% 즉시 수리.", "icon": 15},
	"drill": {"name": "사격 교범", "desc": "생존자 1명당 연사 보너스 +1%.", "icon": 3},
}

const RELICS := {
	"watch": {"name": "기관사의 회중시계", "desc": "차량기지 보급 선택지 +1.", "icon": 0},
	"bell": {"name": "녹슨 종", "desc": "역에 정차할 때 주변 적을 기절시키고 밀쳐낸다.", "icon": 1},
	"blackbox": {"name": "블랙박스", "desc": "선체 35% 이하일 때 연사 +40%.", "icon": 2},
	"ledger": {"name": "생존자 명부", "desc": "탑승 한도 +4. 귀환 시 생존자 1.5배 기록.", "icon": 3},
	"oldmap": {"name": "낡은 노선도", "desc": "시설 변이가 1바퀴 빨라진다.", "icon": 4},
	"token": {"name": "행운의 토큰", "desc": "카드 획득 확률 +6%.", "icon": 5},
	"gasmask": {"name": "방독면", "desc": "감염체와 포자 피해 -30%.", "icon": 6},
	"trophy": {"name": "약탈자의 트로피", "desc": "약탈자 처치 시 고철 +3, 약탈자 피해 -20%.", "icon": 7},
	"jammer": {"name": "신호 교란기", "desc": "군세 게이지 상승 -25%.", "icon": 8},
	"lantern": {"name": "광부의 등불", "desc": "스토커가 항상 보인다. 기관차 주변 적 받는 피해 +20%.", "icon": 9},
	"coupler": {"name": "강화 연결기", "desc": "연결 가능 차량 +1.", "icon": 10},
	"fuelcell": {"name": "연료전지", "desc": "바퀴마다 보급품 +2, 속도 +5%.", "icon": 11},
}

# ---------------------------------------------------------------- enemies
# faction: infected / raider / dark / neutral
# ai: walker, ranged, bloater, static, rig, horror, brood
const ENEMIES := {
	"shambler": {"name": "좀비", "faction": "infected", "ai": "walker", "hp": 14.0, "spd": 11.0,
		"dmg": 3.0, "cd": 1.0, "mass": 1, "r": 5.0, "scrap": 2, "card": 0.18},
	"runner": {"name": "러너", "faction": "infected", "ai": "walker", "hp": 9.0, "spd": 34.0,
		"dmg": 2.0, "cd": 0.7, "mass": 1, "r": 4.0, "scrap": 2, "card": 0.13},
	"dog": {"name": "감염견", "faction": "infected", "ai": "walker", "hp": 12.0, "spd": 42.0,
		"dmg": 3.0, "cd": 0.8, "mass": 1, "r": 4.0, "scrap": 3, "card": 0.13},
	"bloater": {"name": "부푼자", "faction": "infected", "ai": "bloater", "hp": 32.0, "spd": 8.0,
		"dmg": 14.0, "cd": 1.0, "mass": 2, "r": 7.0, "scrap": 6, "card": 0.30, "blast": 24.0},
	"brood": {"name": "브루드 마더", "faction": "infected", "ai": "brood", "hp": 140.0, "spd": 9.0,
		"dmg": 6.0, "cd": 1.2, "mass": 5, "r": 10.0, "scrap": 30, "card": 1.0, "relic": 0.30, "elite": true},
	"stalker": {"name": "스토커", "faction": "dark", "ai": "walker", "hp": 20.0, "spd": 16.0,
		"dmg": 6.0, "cd": 1.3, "mass": 1, "r": 5.0, "scrap": 4, "card": 0.18, "stealth": true, "lunge": 60.0},
	"rat": {"name": "쥐떼", "faction": "dark", "ai": "walker", "hp": 5.0, "spd": 28.0,
		"dmg": 1.0, "cd": 0.5, "mass": 0, "r": 3.0, "scrap": 1, "card": 0.04},
	"horror": {"name": "터널 괴물", "faction": "dark", "ai": "horror", "hp": 120.0, "spd": 0.0,
		"dmg": 6.0, "cd": 1.6, "mass": 9, "r": 11.0, "scrap": 40, "card": 1.0, "relic": 0.30, "elite": true},
	"raider": {"name": "약탈자", "faction": "raider", "ai": "ranged", "hp": 16.0, "spd": 18.0,
		"dmg": 2.0, "cd": 2.0, "mass": 1, "r": 5.0, "scrap": 7, "card": 0.15, "range": 62.0},
	"bomber": {"name": "화염병 투척자", "faction": "raider", "ai": "ranged", "hp": 14.0, "spd": 16.0,
		"dmg": 5.0, "cd": 3.0, "mass": 1, "r": 5.0, "scrap": 8, "card": 0.16, "range": 52.0, "splash": 16.0},
	"barricade": {"name": "바리케이드", "faction": "raider", "ai": "static", "hp": 70.0, "spd": 0.0,
		"dmg": 0.0, "cd": 1.0, "mass": 9, "r": 8.0, "scrap": 10, "card": 0.20},
	"warrig": {"name": "전투 트럭", "faction": "raider", "ai": "rig", "hp": 160.0, "spd": 50.0,
		"dmg": 12.0, "cd": 0.5, "mass": 9, "r": 11.0, "scrap": 60, "card": 1.0, "relic": 0.30,
		"range": 70.0, "gun": 2.0, "elite": true},
}
const ENEMY_HP_GROWTH := 1.10
const ENEMY_DMG_GROWTH := 1.045
const ENEMY_SCRAP_GROWTH := 0.05

# ---------------------------------------------------------------- facilities
# cat: civil / industry / hostile / military / special
const FACILITIES := {
	"station": {"name": "역", "cat": "civil", "tags": ["civil", "transit"], "noise": 0.5, "card": true,
		"desc": "정차 시 선체 12% 수리, 보급품 +1.\n인접 병원마다 수리 +5%.",
		"evo": "시장 인접 → 환승역"},
	"transfer": {"name": "환승역", "cat": "civil", "tags": ["civil", "transit"], "noise": 1.0,
		"desc": "정차 시 선체 12% 수리, 보급품 +2.\n바퀴마다 1회 보급 선택."},
	"ruin": {"name": "폐역", "cat": "hostile", "tags": ["hostile", "dark", "transit"], "noise": 0.5, "card": true,
		"desc": "통과 시 고철 수색, 카드 25%.\n스토커가 숨어든다.",
		"evo": "4바퀴 방치 → 망령역 / 피난처 인접 → 역 복구",
		"spawn": {"types": ["stalker"], "period": 13.0, "cap": 3}},
	"ghost": {"name": "망령역", "cat": "hostile", "tags": ["hostile", "dark"], "noise": 1.5,
		"desc": "통과 시 많은 고철, 유물 12%.\n스토커와 쥐떼, 2바퀴마다 터널 괴물.",
		"spawn": {"types": ["stalker", "rat", "rat"], "period": 9.0, "cap": 5}, "elite": "horror", "elite_every": 2},
	"market": {"name": "시장", "cat": "civil", "tags": ["civil", "trade"], "noise": 1.0, "card": true,
		"desc": "통과 시 고철 +6.\n인접 공장 +3, 인접 역 +2.\n약탈자를 끌어들인다.",
		"evo": "약탈자 거점 인접 → 암시장"},
	"blackmarket": {"name": "암시장", "cat": "civil", "tags": ["civil", "trade", "raider"], "noise": 1.5,
		"desc": "통과 시 고철 +8.\n바퀴마다 유물을 고철로 거래."},
	"hospital": {"name": "병원", "cat": "civil", "tags": ["civil", "medical"], "noise": 0.5, "card": true,
		"desc": "통과 시 선체 10% 수리.\n회복한 환자가 생존자로 합류.\n감염 인접 시 감염병동 위험.",
		"evo": "역 인접 → 의료 거점"},
	"medhub": {"name": "의료 거점", "cat": "civil", "tags": ["civil", "medical"], "noise": 1.0,
		"desc": "통과 시 선체 20% 수리.\n환자가 생존자로 합류."},
	"ward": {"name": "감염병동", "cat": "hostile", "tags": ["hostile", "infected"], "noise": 1.5,
		"desc": "부푼자와 좀비가 쏟아진다.",
		"spawn": {"types": ["bloater", "shambler"], "period": 10.0, "cap": 4}},
	"factory": {"name": "공장", "cat": "industry", "tags": ["industry"], "noise": 1.5, "card": true,
		"desc": "바퀴마다 보급품 +3.\n2바퀴마다 차량 개조 카드.\n오염: 인접 감염 확산 가속.",
		"evo": "발전소 인접 → 조립공장"},
	"assembly": {"name": "조립공장", "cat": "industry", "tags": ["industry"], "noise": 2.0,
		"desc": "바퀴마다 보급품 +3,\n차량 또는 개조 카드 생산."},
	"checkpoint": {"name": "검문소", "cat": "military", "tags": ["military"], "noise": 0.5, "card": true, "upkeep": 1,
		"desc": "민병대가 주변 적을 사격.\n인접 민간 시설을 감염·약탈에서 보호.\n유지비: 보급품 1",
		"evo": "약탈자 인접 → 용병 초소 / 무기고 인접 → 포대",
		"turret": {"kind": "gun", "dmg": 5.0, "rate": 1.2, "range": 76.0}},
	"mercpost": {"name": "용병 초소", "cat": "military", "tags": ["military"], "noise": 0.5, "upkeep": 2,
		"desc": "강력한 용병 사격.\n인접 약탈자 출현 절반.\n유지비: 보급품 2",
		"turret": {"kind": "gun", "dmg": 8.0, "rate": 1.6, "range": 84.0}},
	"bastion": {"name": "포대", "cat": "military", "tags": ["military"], "noise": 1.0, "upkeep": 1,
		"desc": "먼 적 무리에 포격.\n유지비: 보급품 1",
		"turret": {"kind": "mortar", "dmg": 22.0, "rate": 0.4, "range": 130.0, "radius": 22.0}},
	"infection": {"name": "감염구역", "cat": "hostile", "tags": ["hostile", "infected"], "noise": 1.0, "card": true,
		"desc": "좀비가 계속 몰려온다.\n처치 시 카드를 잘 준다.\n인접 민간 시설을 감염시킨다.",
		"evo": "4바퀴 → 둥지 (공장 인접 시 3바퀴)",
		"spawn": {"types": ["shambler", "shambler", "runner"], "period": 7.0, "cap": 5}},
	"hive": {"name": "둥지", "cat": "hostile", "tags": ["hostile", "infected"], "noise": 2.0,
		"desc": "감염체가 끝없이 쏟아진다.\n2바퀴마다 브루드 마더.",
		"spawn": {"types": ["shambler", "runner", "dog"], "period": 5.0, "cap": 7}, "elite": "brood", "elite_every": 2},
	"raiders": {"name": "약탈자 거점", "cat": "hostile", "tags": ["hostile", "raider"], "noise": 1.0, "card": true,
		"desc": "총잡이 약탈자와 선로 바리케이드.\n처치 시 고철이 많다.\n인접 시장·피난처를 약탈.",
		"evo": "4바퀴 또는 시장 2곳 인접 → 요새",
		"spawn": {"types": ["raider", "raider", "bomber"], "period": 11.0, "cap": 3}},
	"fortress": {"name": "약탈자 요새", "cat": "hostile", "tags": ["hostile", "raider"], "noise": 2.0,
		"desc": "약탈자 대군, 2바퀴마다 전투 트럭.",
		"spawn": {"types": ["raider", "bomber"], "period": 8.0, "cap": 5}, "elite": "warrig", "elite_every": 2},
	"shelter": {"name": "피난처", "cat": "civil", "tags": ["civil", "survivors"], "noise": 0.5, "card": true,
		"desc": "바퀴마다 생존자 1명이 모인다.\n통과 시 탑승 (한도 내).\n감염에 약하다.",
		"evo": "온실 인접 → 공동체"},
	"commune": {"name": "공동체", "cat": "civil", "tags": ["civil", "survivors"], "noise": 0.5,
		"desc": "바퀴마다 생존자 2명, 보급품 +2."},
	"power": {"name": "발전소", "cat": "industry", "tags": ["industry", "power"], "noise": 2.0, "card": true, "unlock": true,
		"desc": "주변 선로에 전류: 적에게 지속 피해.\n그 구간 열차 가속.\n테슬라 피해 +30%."},
	"radio": {"name": "무선탑", "cat": "special", "tags": ["special"], "noise": 5.0, "card": true, "unlock": true,
		"desc": "매 바퀴 무전 사건 발생.\n차량기지 카드 +1.\n방송이 검은 열차를 부른다."},
	"greenhouse": {"name": "온실", "cat": "civil", "tags": ["civil", "nature"], "noise": 0.0, "card": true, "unlock": true,
		"desc": "바퀴마다 보급품 +3.\n인접 공장 소음 -2.\n감염되면 포자농장."},
	"sporefarm": {"name": "포자농장", "cat": "hostile", "tags": ["hostile", "infected"], "noise": 1.0,
		"desc": "바퀴마다 보급품 +4.\n통과하는 열차에 포자 피해.",
		"spawn": {"types": ["shambler"], "period": 15.0, "cap": 2}},
	"armory": {"name": "무기고", "cat": "military", "tags": ["military"], "noise": 1.0, "card": true, "unlock": true,
		"desc": "통과 시 이번 바퀴 무기 피해 +25%.\n인접 약탈자도 무장한다."},
	"purge": {"name": "소각 작전", "cat": "special", "tags": [], "noise": 0.0, "card": true, "action": true,
		"desc": "시설 하나를 소각한다.\n군세 -4."},
}
const FAC_BASE_CARDS := ["station", "ruin", "market", "hospital", "factory", "checkpoint",
	"infection", "raiders", "shelter"]
const FAC_UNLOCK_CARDS := ["greenhouse", "armory", "power", "radio"]

# card draw weights by id (only unlocked ids are drawn)
const CARD_WEIGHTS := {
	"station": 9, "ruin": 8, "market": 9, "hospital": 8, "factory": 7, "checkpoint": 7,
	"infection": 10, "raiders": 9, "shelter": 8, "greenhouse": 6, "armory": 5,
	"power": 4, "radio": 3, "purge": 2,
}

# ---------------------------------------------------------------- horde / boss
const HORDE_BASE_PER_LOOP := 4.0
const HORDE_PER_PLACE := 0.5
const BOSS := {
	"name": "검은 열차",
	"head_hp": 1200.0, "car_hp": 400.0, "hp_per_loop": 0.07,
	"armor_mult": 0.5,  # head damage taken while any car survives
	"ram_dmg": 16.0, "shell_dmg": 3.0, "mortar_dmg": 6.0, "dmg_per_loop": 0.06,
}

# ---------------------------------------------------------------- radio events
const EVENTS := {
	"sos": {"title": "피난민 구조 요청", "text": "\"여기는... 생존자 셋. 제발 태워줘요.\"\n근처에 감염체 무리가 있다.",
		"choices": ["구조한다 (생존자 +3, 러너 출현)", "무시한다"]},
	"drop": {"title": "보급 투하 신호", "text": "낡은 군용 주파수. 보급 상자가 떨어진다.\n신호는 다른 것도 부른다.",
		"choices": ["수령 (보급품 +12, 군세 +8)", "무시한다"]},
	"toll": {"title": "약탈자의 통행세", "text": "\"고철 내놔. 아니면 선로에서 보자.\"",
		"choices": ["지불 (고철 -30)", "거절 (약탈자 습격)"]},
	"signal": {"title": "기묘한 신호", "text": "터널 깊은 곳에서 반복되는 모스 부호.\n무언가 빛나고 있다.",
		"choices": ["추적한다 (유물 또는 괴물)", "무시한다"]},
	"crew": {"title": "떠돌이 정비반", "text": "\"보급품만 나눠주면 차를 손봐주지.\"",
		"choices": ["초청 (보급품 -5, 선체 30% 수리)", "거절한다"]},
	"sighting": {"title": "검은 열차 목격담", "text": "\"붉은 등이 네 개... 선로를 따라 오고 있어.\"",
		"choices": ["선로 교란 (고철 -20, 군세 -15)", "무시한다"]},
	"merchant": {"title": "떠돌이 상인", "text": "\"좋은 물건 있어. 싸게 줄게.\"",
		"choices": ["거래 (고철 -35, 개조 부품)", "거절한다"]},
	"outbreak": {"title": "감염 경보", "text": "피난처 방향에서 비명이 들린다.",
		"choices": ["구출 작전 (선체 -12, 생존자 +2)", "외면한다 (감염 확산)"]},
}
