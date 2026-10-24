class_name HandEval
extends RefCounted

## 牌型判定 + 比较。
##
## 牌型大小（从大到小）：
##   同花顺 > 四条 > 葫芦（三条带一对）> 同花 > 顺子 > 三条 > 两对 > 一对 > 高牌
##
## 平局时按花色决胜：黑桃 > 红桃 > 梅花 > 方块
## 比较结果编码成一个数组，直接按字典序比较即可：
##   [牌型等级, 主牌点..., 副牌点..., 对应花色...]
## 因为同牌型时点数数组长度固定，所以字典序比较是安全的。

const HIGH := 0
const PAIR := 1
const TWO_PAIR := 2
const THREE := 3
const STRAIGHT := 4
const FLUSH := 5
const FULL_HOUSE := 6
const FOUR := 7
const STRAIGHT_FLUSH := 8

const CAT_NAMES: Array = [
	"高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"
]

const CAT_NAMES_EN: Array = [
	"High Card", "One Pair", "Two Pair", "Three of a Kind", "Straight",
	"Flush", "Full House", "Four of a Kind", "Straight Flush"
]

const CAT_COLORS: Array = [
	Color("#9aa7b4"), # 高牌
	Color("#a8c0d8"), # 一对
	Color("#8fd6a8"), # 两对
	Color("#6fd0e0"), # 三条
	Color("#7fb2ff"), # 顺子
	Color("#b48cff"), # 同花
	Color("#ffb648"), # 葫芦
	Color("#ff6b6b"), # 四条
	Color("#ff3ea5"), # 同花顺
]

# 每种牌型在真随机发牌中的出现概率（52 选 5，共 2,598,960 种组合）
const CAT_ODDS_TEXT: Array = [
	"50.12%",   # 高牌
	"42.26%",   # 一对
	"4.75%",    # 两对
	"2.11%",    # 三条
	"0.392%",   # 顺子
	"0.197%",   # 同花
	"0.144%",   # 葫芦
	"0.0240%",  # 四条
	"0.00154%", # 同花顺
]


static func straight_high_of(ranks_desc: Array) -> int:
	var uniq: Array = []
	for r in ranks_desc:
		if not uniq.has(r):
			uniq.append(r)
	if uniq.size() != 5:
		return 0
	# A-2-3-4-5 的最小顺子，A 记作 5
	if uniq[0] == 14 and uniq[1] == 5 and uniq[2] == 4 and uniq[3] == 3 and uniq[4] == 2:
		return 5
	for i in range(4):
		if uniq[i] - 1 != uniq[i + 1]:
			return 0
	return uniq[0]


static func evaluate(hand: Array) -> Array:
	if hand.size() < 5:
		return [-1]

	var ranks: Array = []
	for c in hand:
		ranks.append(Cards.rank_of(c))
	ranks.sort()
	ranks.reverse()

	var counts: Dictionary = {}
	for r in ranks:
		counts[r] = int(counts.get(r, 0)) + 1

	var groups: Array = counts.keys()
	groups.sort_custom(func(a, b):
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		return a > b
	)

	var is_flush := true
	var first_suit := Cards.suit_of(hand[0])
	for c in hand:
		if Cards.suit_of(c) != first_suit:
			is_flush = false
			break

	var s_high := straight_high_of(ranks)
	var cat := HIGH
	var order: Array = []

	var top_count: int = counts[groups[0]]
	var has_pair2: bool = groups.size() >= 2 and counts[groups[1]] == 2

	if is_flush and s_high > 0:
		cat = STRAIGHT_FLUSH
		order = [s_high]
	elif top_count == 4:
		cat = FOUR
		order = [groups[0], groups[1]]
	elif top_count == 3 and has_pair2:
		cat = FULL_HOUSE
		order = [groups[0], groups[1]]
	elif is_flush:
		cat = FLUSH
		order = ranks.duplicate()
	elif s_high > 0:
		cat = STRAIGHT
		order = [s_high]
	elif top_count == 3:
		cat = THREE
		order = [groups[0]]
		var ks: Array = []
		for i in range(1, groups.size()):
			ks.append(groups[i])
		ks.sort()
		ks.reverse()
		order.append_array(ks)
	elif groups.size() >= 3 and top_count == 2 and counts[groups[1]] == 2:
		cat = TWO_PAIR
		var pr: Array = [groups[0], groups[1]]
		pr.sort()
		pr.reverse()
		order = pr.duplicate()
		order.append(groups[2])
	elif top_count == 2:
		cat = PAIR
		order = [groups[0]]
		var ks2: Array = []
		for i in range(1, groups.size()):
			ks2.append(groups[i])
		ks2.sort()
		ks2.reverse()
		order.append_array(ks2)
	else:
		cat = HIGH
		order = ranks.duplicate()

	# 花色决胜序列：按上面确定的顺序，取对应牌的最大花色
	var pool: Array = hand.duplicate()
	var suit_seq: Array = []
	for r in order:
		var best := -1
		for c in pool:
			if Cards.rank_of(c) == r:
				if best == -1 or Cards.suit_of(c) > Cards.suit_of(best):
					best = c
		if best != -1:
			suit_seq.append(Cards.suit_of(best))
			pool.erase(best)

	var out: Array = [cat]
	out.append_array(order)
	out.append_array(suit_seq)
	return out


## 返回 1 / 0 / -1
static func compare(a: Array, b: Array) -> int:
	var n: int = mini(a.size(), b.size())
	for i in range(n):
		if a[i] > b[i]:
			return 1
		if a[i] < b[i]:
			return -1
	return 0


static func cat_of(score: Array) -> int:
	return int(score[0])


static func cat_name(cat: int) -> String:
	if cat < 0 or cat >= CAT_NAMES.size():
		return Loc.t("未知")
	if Loc.en():
		return CAT_NAMES_EN[cat]
	return CAT_NAMES[cat]


static func cat_color(cat: int) -> Color:
	if cat < 0 or cat >= CAT_COLORS.size():
		return Color.WHITE
	return CAT_COLORS[cat]


static func beats(a: Array, b: Array) -> bool:
	return compare(a, b) > 0


static func score_text(score: Array) -> String:
	var cat := cat_of(score)
	if cat < 0:
		return "—"
	var txt := cat_name(cat)
	var tail: Array = []
	for i in range(1, score.size()):
		# 只保留点数部分（花色序列长度与点数相同，跳过）
		pass
	return txt
