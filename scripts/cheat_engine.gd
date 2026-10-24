class_name CheatEngine
extends RefCounted

## 后台发牌引擎 —— 这个文件就是"为什么网赌必输"的答案。
##
## 庄家只亮 1 张牌，其余 4 张在摊牌时才"发给"庄家：
## 后台此刻已经知道玩家的完整 5 张牌，于是按权重表构造一副
## 能赢、且牌型 ≥ 三条的牌。
##
## 谁输谁赢由胜率模型决定；牌型构造只负责让输赢看起来自然，
## 不刻意控制"赢多少 / 输多少"。
##
## 玩家拿到的牌另有一条"养鱼"曲线：时间越久、欠款越多，越容易
## 看到三条以上的大牌；但大注局、刚发过大牌、刚输急眼时会被压住。

## =====================================================================
## 胜率模型
##
## 一条连续曲线：押得越大，胜率越低，没有阈值和台阶。
##
##      押注      胜率
##      ¥100   →  97%
##      ¥1,000 →  75%
##      ¥3,000 →  50%
##     ¥10,000 →  23%
##     ¥40,000 →   7%
##
## 修正项：
##   · 开局前几把几乎必赢
##   · 累计净赢超过 2 万开始压，到 6 万归零
##   · 手数 / 时长越多，胜率越低
##
## 真正的兜底在提现口：体验金不可提现、单笔 2,000、第一笔之后永远失败。
## =====================================================================

## 曲线的中位点：押注等于这个数时，胜率正好 50%
const ODDS_K := 3000.0

## 累计净赢超过这个数，开始往下压胜率（软上限）
const WIN_SOFT := 20000.0
## 到这儿胜率归零（硬上限）
const WIN_HARD := 60000.0

## 开局送分局数
const OPENING_HANDS := 5
const OPENING_FLOOR := 0.90


## 给定本局押注和累计净赢，返回玩家这一局的胜率。
##
## 注意：这里【没有】任何单局押注阈值。
## 押 9,999 和押 10,001 的胜率完全一样。
static func win_chance(bet: float, net_profit: float, hands_played: int) -> float:
	var won: float = max(net_profit, 0.0)
	if won >= WIN_HARD:
		return 0.0

	var b: float = max(bet, 1.0)

	# 1) 押得越大，胜率越低（连续，无阈值）
	var p: float = ODDS_K / (ODDS_K + b)

	# 2) 已经赢走的越多，整体越难（只在 2 万之后开始压，避免影响正常对局）
	var decay := 1.0
	if won > WIN_SOFT:
		decay = clamp((WIN_HARD - won) / (WIN_HARD - WIN_SOFT), 0.0, 1.0)
	p *= 0.15 + 0.85 * decay

	# 3) 开局送分
	if hands_played <= OPENING_HANDS and b <= ODDS_K:
		p = max(p, OPENING_FLOOR)

	return clamp(p, 0.0, 0.97)


## =====================================================================
## 局数 / 时长疲劳：手数越多、时间越长，最终胜率越低（平滑过渡）
## =====================================================================

const HAND_FADE_START := 10.0    # 前 10 手不衰减
const HAND_FADE_FULL := 120.0    # 到 120 手压到最低
const TIME_FADE_START := 600.0   # 前 10 分钟不衰减
const TIME_FADE_FULL := 3600.0   # 到 60 分钟压到最低
const FATIGUE_MIN := 0.18        # 最低保留 18% 的基础胜率

## 疲劳压到最低后，最终胜率仍保留的最低值
const MIN_WIN_CHANCE := 0.03


## 把 x 从 [start, full] 映射到 [0, 1]，两端平滑，不会出现台阶
static func _smooth01(x: float, start: float, full: float) -> float:
	if full <= start:
		return 1.0 if x >= full else 0.0
	var t: float = clampf((x - start) / (full - start), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 1.0 = 不衰减，FATIGUE_MIN = 压到最低；手数和时长取进度更大的那个，不叠加
static func session_fatigue(hands_played: int, session_seconds: float) -> float:
	var h := _smooth01(float(hands_played), HAND_FADE_START, HAND_FADE_FULL)
	var t := _smooth01(session_seconds, TIME_FADE_START, TIME_FADE_FULL)
	return lerpf(1.0, FATIGUE_MIN, maxf(h, t))


## 最终胜率 = 基础曲线 × 疲劳系数。
## 保底 MIN_WIN_CHANCE，但基础曲线本身低于它时不强行抬高。
static func session_win_chance(
	bet: float,
	net_profit: float,
	hands_played: int,
	session_seconds: float
) -> float:
	var base := win_chance(bet, net_profit, hands_played)
	if base <= 0.0:
		return 0.0
	var p: float = base * session_fatigue(hands_played, session_seconds)
	return clampf(p, minf(base, MIN_WIN_CHANCE), 0.97)


## 玩家还能净赢多少
static func headroom(net_profit: float) -> float:
	return WIN_HARD - max(net_profit, 0.0)


## =====================================================================
## 大牌诱饵：时间越久、借款越多，越容易让玩家拿到三条以上
##
## 注意：这里只控制"发什么牌给玩家"，不改变输赢概率。
## 真到摊牌时，还是走 session_win_chance 那条平滑曲线。
## =====================================================================

const BAIT_TIME_START := 120.0   # 前 2 分钟不升温
const BAIT_TIME_FULL := 1800.0   # 30 分钟达到最高
const BAIT_BASE := 0.08          # 开局直接塞大牌的概率
const BAIT_MAX := 0.42           # 时间 + 欠款都拉满时的基础概率

## 返回下一手"直接发三条以上"的概率。
##
## 只管"大牌多不多"，不决定输赢；连发控制放在 main.gd 的 big_cooldown 里。
##
## session_seconds : 本次牌桌会话时长
## debt_ratio      : 当前欠款 / 借款上限，0..1
## profit_ratio    : 玩家净赢 / 1 万，0..1
## ante            : 本手底注（大注不给大牌，避免赢大钱）
static func bait_chance(
	session_seconds: float,
	debt_ratio: float,
	profit_ratio: float,
	ante: float
) -> float:
	# 1) 时间 + 欠款：六成看时间、四成看欠款，慢热但不突兀
	var time_t := _smooth01(session_seconds, BAIT_TIME_START, BAIT_TIME_FULL)
	var debt_t := clampf(debt_ratio, 0.0, 1.0)
	var heat := clampf(0.6 * time_t + 0.4 * debt_t, 0.0, 1.0)
	var p := lerpf(BAIT_BASE, BAIT_MAX, heat)

	# 2) 已经在赢钱 → 收手，不能让他靠大牌把雪球滚大
	p *= lerpf(1.0, 0.35, clampf(profit_ratio, 0.0, 1.0))

	# 3) 大注局不塞大牌：大牌集中在小注，赢了也只是小钱
	if ante >= 5000.0:
		p *= 0.30
	elif ante >= 1000.0:
		p *= 0.60

	return clampf(p, 0.0, 0.50)


## 杀猪权重表：命中风控后，庄家牌型的分布。
## 数值越大越常见。可以随意调整，总和不必为 1（内部会归一化）。
const KILL_WEIGHTS: Dictionary = {
	HandEval.STRAIGHT_FLUSH: 0.04,  # 同花顺
	HandEval.FOUR: 0.06,            # 四条
	HandEval.FULL_HOUSE: 0.18,      # 葫芦
	HandEval.FLUSH: 0.14,           # 同花
	HandEval.STRAIGHT: 0.28,        # 顺子
	HandEval.THREE: 0.30,           # 三条
}

## 未命中风控时，玩家拿到"还不错的牌"的概率（养鱼阶段）
const NURTURE_STRONG_RATE := 0.58


static func _by_rank(pool: Array, rank: int) -> Array:
	var out: Array = []
	for c in pool:
		if Cards.rank_of(c) == rank:
			out.append(c)
	return out


static func _by_suit(pool: Array, suit: int) -> Array:
	var out: Array = []
	for c in pool:
		if Cards.suit_of(c) == suit:
			out.append(c)
	return out


static func _combinations(arr: Array, k: int, max_out: int = 200) -> Array:
	var out: Array = []
	var n := arr.size()
	if k > n or k < 1:
		return out
	var idx: Array = []
	for i in range(k):
		idx.append(i)
	while out.size() < max_out:
		var combo: Array = []
		for i in idx:
			combo.append(arr[i])
		out.append(combo)
		var p := k - 1
		while p >= 0 and idx[p] == n - k + p:
			p -= 1
		if p < 0:
			break
		idx[p] = int(idx[p]) + 1
		for j in range(p + 1, k):
			idx[j] = int(idx[j - 1]) + 1
	return out


static func _runs_containing(rank: int) -> Array:
	## 所有包含该点数的 5 连张（含 A-2-3-4-5）
	var out: Array = []
	for start in range(2, 11):
		var run: Array = [start, start + 1, start + 2, start + 3, start + 4]
		if run.has(rank):
			out.append(run)
	var wheel: Array = [14, 2, 3, 4, 5]
	if wheel.has(rank):
		out.append(wheel)
	return out


static func _cat_straight_flush(fixed: int, pool: Array) -> Array:
	var s := Cards.suit_of(fixed)
	var r := Cards.rank_of(fixed)
	var suited := _by_suit(pool, s)
	var out: Array = []
	for run in _runs_containing(r):
		var need: Array = []
		var ok := true
		for rr in run:
			if rr == r:
				continue
			var found := -1
			for c in suited:
				if Cards.rank_of(c) == rr:
					found = c
					break
			if found == -1:
				ok = false
				break
			need.append(found)
		if ok and need.size() == 4:
			var h: Array = need.duplicate()
			h.append(fixed)
			out.append(h)
	return out


static func _cat_four(fixed: int, pool: Array) -> Array:
	var r := Cards.rank_of(fixed)
	var out: Array = []
	# 固定牌自己组成四条：再补 3 张同点数
	var same := _by_rank(pool, r)
	if same.size() >= 3:
		var h: Array = [fixed, same[0], same[1], same[2]]
		out.append(h)
	# 另外某个点数四条，固定牌当踢脚
	for q in Cards.RANKS:
		if q == r:
			continue
		var cs := _by_rank(pool, q)
		if cs.size() >= 4:
			out.append([fixed, cs[0], cs[1], cs[2], cs[3]])
	return out


static func _cat_full_house(fixed: int, pool: Array) -> Array:
	var r := Cards.rank_of(fixed)
	var same := _by_rank(pool, r)
	var out: Array = []
	# A. 固定牌在"三条"里
	if same.size() >= 2:
		for q in Cards.RANKS:
			if q == r:
				continue
			var cs := _by_rank(pool, q)
			if cs.size() >= 2:
				out.append([fixed, same[0], same[1], cs[0], cs[1]])
	# B. 固定牌在"一对"里
	if same.size() >= 1:
		for q in Cards.RANKS:
			if q == r:
				continue
			var cs2 := _by_rank(pool, q)
			if cs2.size() >= 3:
				out.append([fixed, same[0], cs2[0], cs2[1], cs2[2]])
	return out


static func _cat_flush(fixed: int, pool: Array) -> Array:
	var s := Cards.suit_of(fixed)
	var suited := _by_suit(pool, s)
	suited.sort_custom(func(a, b): return Cards.rank_of(a) > Cards.rank_of(b))
	if suited.size() > 8:
		suited = suited.slice(0, 8)
	var out: Array = []
	for combo in _combinations(suited, 4, 80):
		var h: Array = combo.duplicate()
		h.append(fixed)
		out.append(h)
	return out


static func _cat_straight(fixed: int, pool: Array, rng: RandomNumberGenerator) -> Array:
	var r := Cards.rank_of(fixed)
	var out: Array = []
	for run in _runs_containing(r):
		var need: Array = []
		var ok := true
		for rr in run:
			if rr == r:
				continue
			var cs := _by_rank(pool, rr)
			if cs.is_empty():
				ok = false
				break
			# 顺子的大小只看点数；同点数的牌随便取一张，
			# 不再固定挑某一张（花色只影响极少数平局）
			need.append(cs[rng.randi_range(0, cs.size() - 1)])
		if ok and need.size() == 4:
			var h: Array = need.duplicate()
			h.append(fixed)
			out.append(h)
	return out


static func _cat_three(fixed: int, pool: Array) -> Array:
	var r := Cards.rank_of(fixed)
	var same := _by_rank(pool, r)
	var out: Array = []
	var kickers: Array = []
	for q in Cards.RANKS:
		if q == r:
			continue
		var cs := _by_rank(pool, q)
		if not cs.is_empty():
			cs.sort_custom(func(a, b): return Cards.rank_of(a) < Cards.rank_of(b))
			kickers.append(cs[0])
	if kickers.size() >= 2:
		var kcombos := _combinations(kickers, 2, 12)
		# A. 固定牌在三条里
		if same.size() >= 2:
			for kc in kcombos:
				out.append([fixed, same[0], same[1], kc[0], kc[1]])
		# B. 固定牌当踢脚
		for q in Cards.RANKS:
			if q == r:
				continue
			var cs2 := _by_rank(pool, q)
			if cs2.size() >= 3:
				for kc2 in kcombos:
					if kc2[0] == q or kc2[1] == q:
						continue
					out.append([fixed, cs2[0], cs2[1], cs2[2], kc2[0]])
	return out


static func _candidates(cat: int, fixed: int, pool: Array, rng: RandomNumberGenerator) -> Array:
	match cat:
		HandEval.STRAIGHT_FLUSH:
			return _cat_straight_flush(fixed, pool)
		HandEval.FOUR:
			return _cat_four(fixed, pool)
		HandEval.FULL_HOUSE:
			return _cat_full_house(fixed, pool)
		HandEval.FLUSH:
			return _cat_flush(fixed, pool)
		HandEval.STRAIGHT:
			return _cat_straight(fixed, pool, rng)
		HandEval.THREE:
			return _cat_three(fixed, pool)
	return []


## 核心：构造一副"必然赢过玩家、且至少是三条"的庄家牌。
##
## fixed_cards : 庄家已经亮出的牌（本设计里只有 1 张）
## pool        : 剩余可用牌（52 - 玩家手牌 - 已亮出）
## player_score: 玩家 5 张牌的 HandEval.evaluate() 结果
##
## 返回 { ok, hand, score, cat, cat_name, reason }
static func plan_kill(
	fixed_cards: Array,
	pool: Array,
	player_score: Array,
	rng: RandomNumberGenerator,
	weights: Dictionary = KILL_WEIGHTS
) -> Dictionary:
	if fixed_cards.size() != 1:
		return {"ok": false, "reason": "fixed_cards 必须为 1 张"}

	var fixed: int = fixed_cards[0]
	var winning: Dictionary = {} # cat -> Array of {hand, score}
	var bonus_cat := HandEval.cat_of(player_score)

	for cat in weights.keys():
		var hands := _candidates(cat, fixed, pool, rng)
		if hands.is_empty():
			continue
		var wins: Array = []
		for h in hands:
			if h.size() != 5 or not h.has(fixed):
				continue
			var sc := HandEval.evaluate(h)
			if HandEval.cat_of(sc) < HandEval.THREE:
				continue # 硬性下限：三条以上
			if HandEval.compare(sc, player_score) > 0:
				wins.append({"hand": h, "score": sc})
		if wins.is_empty():
			continue
		winning[cat] = wins

	if winning.is_empty():
		return {"ok": false, "reason": "没有可构造的必胜牌型"}

	# 按权重抽一个牌型
	var total := 0.0
	var picked := -1
	for cat in winning.keys():
		total += float(weights.get(cat, 0.01))
	var roll := rng.randf() * total
	var acc := 0.0
	for cat in winning.keys():
		acc += float(weights.get(cat, 0.01))
		if roll <= acc:
			picked = cat
			break
	if picked == -1:
		picked = winning.keys()[0]

	# 同类牌型里随机取一副：赢就是赢，不再固定挑"刚好压一点点"的那副。
	# 这样玩家看到的差距有大有小，不会每把都像算好的。
	var options: Array = winning[picked]
	var chosen: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	return {
		"ok": true,
		"hand": chosen["hand"],
		"score": chosen["score"],
		"cat": picked,
		"cat_name": HandEval.cat_name(picked),
		"pool_cats": winning.keys(),
		"player_cat": bonus_cat,
	}


## 反向操作：构造一副"就是没玩家大"的庄家牌。
##
## 胜率曲线说这一把要让玩家赢，就正常发牌，只保留"确实输给玩家"的结果。
## 不再刻意挑「最强但依然输」的那副 —— 那样玩家每把都只赢一个踢脚，
## 反而一眼看出是安排好的。赢多少由牌面决定。
##
## 如果玩家牌太弱、抽了 tries 次都找不到比它更小的牌，
## 就返回 ok=false，由调用方退回庄家赢。
## 这一点保证：实际胜率只会低于设计值，永远不会高于设计值。
static func plan_lose(
	fixed_cards: Array,
	pool: Array,
	player_score: Array,
	rng: RandomNumberGenerator,
	tries: int = 500
) -> Dictionary:
	if fixed_cards.size() != 1 or pool.size() < 4:
		return {"ok": false, "reason": "参数不足"}

	var fixed: int = fixed_cards[0]

	# 随机补 4 张，抽到第一副输给玩家的就直接用。
	# 拒绝采样 = 在"所有会输的牌"里均匀分布，不做任何"贴着玩家"的挑选。
	for i in tries:
		var hand: Array = [fixed]
		var avail := pool.duplicate()
		for k in 4:
			var idx := rng.randi_range(0, avail.size() - 1)
			hand.append(avail[idx])
			avail.remove_at(idx)
		var sc := HandEval.evaluate(hand)
		if HandEval.compare(sc, player_score) < 0:
			return {
				"ok": true,
				"hand": hand,
				"score": sc,
				"cat": HandEval.cat_of(sc),
				"cat_name": HandEval.cat_name(HandEval.cat_of(sc)),
			}

	return {"ok": false, "reason": "构造不出更弱的牌"}


## 真随机补牌（未命中风控时使用）
static func random_completion(fixed_cards: Array, pool: Array, rng: RandomNumberGenerator) -> Array:
	var avail := pool.duplicate()
	var out: Array = fixed_cards.duplicate()
	while out.size() < 5 and not avail.is_empty():
		var idx := rng.randi_range(0, avail.size() - 1)
		out.append(avail[idx])
		avail.remove_at(idx)
	return out


## 养鱼：给玩家一副"还不错"的牌，让他有信心加注。
##
## strong_rate 由 main.gd 按玩家已赢金额动态给出；
## min_cat 用于钓鱼局：直接塞三条以上的强牌，勾他推大注。
static func nurture_player_hand(
	deck: Array,
	rng: RandomNumberGenerator,
	strong_rate: float = NURTURE_STRONG_RATE,
	min_cat: int = HandEval.PAIR
) -> Array:
	var pool := deck.duplicate()
	var best: Array = []
	var best_score: Array = []
	var tries := 0
	while tries < 220:
		tries += 1
		var hand: Array = []
		var avail := pool.duplicate()
		for i in 5:
			var idx := rng.randi_range(0, avail.size() - 1)
			hand.append(avail[idx])
			avail.remove_at(idx)
		var sc := HandEval.evaluate(hand)
		if best.is_empty() or HandEval.compare(sc, best_score) > 0:
			best = hand
			best_score = sc
		if HandEval.cat_of(sc) >= min_cat:
			if rng.randf() < strong_rate:
				return hand
	return best


## 玩家胜率统计（用于"公平对照"面板）
static func fair_win_rate_given(cat: int) -> float:
	## 给定玩家的牌型，在完全公平的牌局里他赢的概率（粗略，按牌型分布累计）
	const DIST: Array = [0.5012, 0.4226, 0.0475, 0.0211, 0.00392, 0.00197, 0.00144, 0.000240, 0.0000154]
	var below := 0.0
	for i in range(cat):
		below += float(DIST[i])
	return 1.0 - below
