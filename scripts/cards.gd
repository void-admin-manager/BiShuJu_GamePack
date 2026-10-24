class_name Cards
extends RefCounted

## 牌面模型。
## 一张牌编码为 4 位花色 + 4 位点数： (suit << 4) | rank
## rank 取值 2..14（14 = A），suit 取值 0..3。
##
## 花色大小严格按需求：黑桃 > 红桃 > 梅花 > 方块
## 所以 suit 数值越大越强。

const DIAMONDS := 0
const CLUBS := 1
const HEARTS := 2
const SPADES := 3

const SUIT_NAMES: Array = ["方块", "梅花", "红桃", "黑桃"]
const SUIT_SYMBOLS: Array = ["♦", "♣", "♥", "♠"]
const SUIT_CAMEL: Array = ["Diamonds", "Clubs", "Hearts", "Spades"]
const CARD_DIR := "res://assets/cards2/"
const CARD_BACK_PATH := CARD_DIR + "cardBack_blue4.png"

const RANKS: Array = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]

static func make(suit: int, rank: int) -> int:
	return (suit << 4) | rank

static func suit_of(card: int) -> int:
	return (card >> 4) & 3

static func rank_of(card: int) -> int:
	return card & 15

static func is_red(card: int) -> bool:
	var s := suit_of(card)
	return s == DIAMONDS or s == HEARTS

static func rank_label(rank: int) -> String:
	match rank:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
		_:
			return str(rank)

static func name_of(card: int) -> String:
	return SUIT_NAMES[suit_of(card)] + rank_label(rank_of(card))

static func file_name(card: int) -> String:
	return "card%s%s.png" % [SUIT_CAMEL[suit_of(card)], rank_label(rank_of(card))]

static func texture_path(card: int) -> String:
	return CARD_DIR + file_name(card)

static func full_deck() -> Array:
	var d: Array = []
	for s in 4:
		for r in RANKS:
			d.append(make(s, r))
	return d

static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
