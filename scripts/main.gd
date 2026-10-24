extends Control

## 《必输局》主场景
##
## 设计原则：
##   前 40 分钟 —— 这是一个"正常"的线上棋牌室。没有任何提示告诉玩家他在被坑。
##   输光之后   —— 一次性把所有后台数据摔在他脸上。
##
## 所有"揭示性"文案都必须只出现在 _show_reveal() 里。

const CARD_W := 168
const CARD_H := 228
const CARD_GAP := 16
const ROW_W := CARD_W * 5 + CARD_GAP * 4
const TABLE_W := 1150.0
const PANEL_X := 1170.0
const PANEL_W := 430.0

const START_BALANCE := 50000.0
const KILL_THRESHOLD := 10000.0   # 单局投入超过这个数 → 后台接管
const WIN_CAP := 10000.0          # 玩家累计净赢的上限
const TILT_LOSS := 3000.0         # 单局输这么多 → 大牌冷却，避免"输急眼还连发大牌"
const DEBT_REVEAL := 200000.0     # 负债到这个数 → 摊牌
const MIN_ANTE := 5.0
const LOAN_AMOUNT := 50000.0
## 贷款计息：5 分钟 = 1 天，日息 3%（自己点的借款，利滚利）
const DAY_SECONDS := 300.0
const DAILY_RATE := 0.03
## 催收节奏：借款到账后，每 2 分钟一条，语气逐条加重
const COLLECT_INTERVAL := 120.0
## 出金闸门：体验金不可提现，只有超过本金的部分能提，且总量封顶
const WITHDRAW_TOTAL_CAP := 10000.0
const WITHDRAW_PER_TX := 2000.0

const BRAND := "鸿运棋牌"

const C_GOLD := Color("#e8b64c")
const C_GOLD_DIM := Color("#8a6d2c")
const C_RED := Color("#ff4d5e")
const C_GREEN := Color("#3fd68a")
const C_CYAN := Color("#54d6e0")
const C_TEXT := Color("#dfe7ef")
const C_DIM := Color("#7c8b9c")
const C_LINE := Color("#22303d")

const FAKE_NAMES: Array = [
	"138****2918", "wx_阿杰", "186****0457", "一路向北", "qun_****88",
	"135****7731", "老张头", "159****2264", "小鱼儿", "dy_****301",
	"177****5580", "手气王", "139****9921", "阿宝", "188****4402",
]

enum State { ANTE_WAIT, BETTING, RESOLVING, HAND_OVER, BUST, REVEAL }

var rng := RandomNumberGenerator.new()

# ---------------- 游戏状态 ----------------
var state: int = State.ANTE_WAIT
var balance := START_BALANCE
var committed := 0.0
var pot := 0.0
var ante := 100.0
var player_cards: Array = []
var player_visible := 0
var dealer_cards: Array = []
var dealer_revealed := 0
var player_score: Array = []
var dealer_score: Array = []
var round_index := 0
var rigged_this_hand := false
var bait_hand := false
var big_cooldown := 0        # 还要空几手才允许再塞大牌（防连发）

# ---------------- 后台统计（游戏里绝不显示，只在结局揭示） ----------------
var hands_played := 0
var session_seconds := 0.0   # 本次牌桌会话已进行的秒数（疲劳用）
var total_wagered := 0.0
var net_profit := 0.0        # 正数 = 玩家净赢
var wins_total := 0.0
var losses_total := 0.0
var rigged_count := 0
var near_miss_count := 0
var biggest_loss := 0.0
var biggest_win := 0.0
var debt := 0.0
var loans_taken := 0
var withdraw_excuses := 0
var total_paid_out := 0.0

# ---------------- UI ----------------
var font_regular: Font
var font_bold: Font
var table_root: Control
var panel_root: Control
var dealer_slots: Array = []
var player_slots: Array = []
var btn_row: HBoxContainer
var bet_panel: Control
var bet_slider: HSlider
var bet_input: LineEdit
var lbl_bet_hint: Label
var btn_raise: Button
var _bet_syncing := false
var lbl_balance: Label
var lbl_committed: Label
var lbl_pot: Label
var lbl_status: Label
var lbl_player_hand: Label
var lbl_dealer_hand: Label
var lbl_debt: Label
var lbl_withdraw: Label
var lbl_online: Label
var ticker_rt: RichTextLabel
var banner: Label
var banner_bg: Panel
var modal_layer: Control
var btn_repay: Button
var btn_loan: Button
var ui_root: Control          # 整块牌桌 UI 的根（切语言时可整体重建）
var ui_stage: Control
var _built_lang := ""         # 建 UI 时用的语言
var busy := false
var bugtest_mode := false

var sfx_deal: AudioStreamPlayer
var sfx_flip: AudioStreamPlayer
var sfx_chip: AudioStreamPlayer
var _deal_streams: Array = []
var _flip_streams: Array = []
var _chip_streams: Array = []


# =====================================================================
# 初始化
# =====================================================================
func _ready() -> void:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	var force_en := false
	for a in args:
		# 自测只在编辑器/调试版生效，导出的正式包不会因为带个参数就清档
		if a.begins_with("--bugtest") and OS.is_debug_build():
			bugtest_mode = true
		if a.begins_with("--en"):
			force_en = true

	rng.randomize()

	_init_fonts()
	_init_audio()
	_load_save()
	if force_en:
		Loc.lang = "en"
	_build_ui()
	_reset_game()

	if bugtest_mode:
		_show_title()
		_run_bugtest()
	else:
		_show_title()


func _init_fonts() -> void:
	# 思源黑体（Source Han Sans，OFL 1.0）—— 可随游戏分发
	font_regular = load("res://assets/fonts/SourceHanSans-Regular.otf")
	font_bold = load("res://assets/fonts/SourceHanSans-Bold.otf")


func _init_audio() -> void:
	for i in [1, 2, 3]:
		_deal_streams.append(load("res://assets/sfx/cardPlace%d.ogg" % i))
		_flip_streams.append(load("res://assets/sfx/cardSlide%d.ogg" % i))
		_chip_streams.append(load("res://assets/sfx/chipsCollide%d.ogg" % i))
	sfx_deal = _mk_audio_player(-9.0)
	sfx_flip = _mk_audio_player(-7.0)
	sfx_chip = _mk_audio_player(-6.0)


func _mk_audio_player(vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = vol_db
	add_child(p)
	return p


func _sfx(kind: String) -> void:
	var player: AudioStreamPlayer
	var pool: Array
	match kind:
		"deal":
			player = sfx_deal
			pool = _deal_streams
		"flip":
			player = sfx_flip
			pool = _flip_streams
		_:
			player = sfx_chip
			pool = _chip_streams
	if pool.is_empty():
		return
	player.stream = pool[rng.randi_range(0, pool.size() - 1)]
	player.pitch_scale = randf_range(0.94, 1.06)
	player.play()


# =====================================================================
# 通用控件
# =====================================================================
func _lbl(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = Loc.t(text)
	l.add_theme_font_override("font", font_bold if bold else font_regular)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_button(text: String, accent: Color, filled := false) -> Button:
	var b := Button.new()
	b.text = Loc.t(text)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.05, 0.07, 0.09) if filled else accent)
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.07, 0.09) if filled else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.40, 0.45))

	var base := StyleBoxFlat.new()
	base.bg_color = accent if filled else Color(accent.r, accent.g, accent.b, 0.10)
	base.border_color = accent
	base.set_border_width_all(2)
	base.set_corner_radius_all(10)
	base.content_margin_left = 22
	base.content_margin_right = 22
	base.content_margin_top = 10
	base.content_margin_bottom = 10

	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = accent.lightened(0.18) if filled else Color(accent.r, accent.g, accent.b, 0.30)

	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.55)

	var disabled := base.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.03)
	disabled.border_color = Color(1, 1, 1, 0.10)

	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", disabled)
	return b


func _panel_bg(color: Color, radius: int, border_color := Color(0, 0, 0, 0), border := 1) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.border_color = border_color
	sb.set_border_width_all(border if border_color.a > 0.0 else 0)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _hr(parent: Control, y: float) -> void:
	var hr := ColorRect.new()
	hr.color = C_LINE
	hr.position = Vector2(24, y)
	hr.size = Vector2(PANEL_W - 48, 1)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hr)


# =====================================================================
# 界面
# =====================================================================
func _build_ui() -> void:
	# 允许重建（切换语言时）：先把上一套拆干净
	if ui_root != null and is_instance_valid(ui_root):
		remove_child(ui_root)
		ui_root.queue_free()
	dealer_slots.clear()
	player_slots.clear()
	_ticker_lines.clear()      # 旧战报是上一个语言的句子，重建必须清掉

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui_root)
	# 永远垫在最底层：标题页 / 弹窗 / 短信都要盖在它上面，
	# 不然切语言重建 UI 的那一帧会闪一下牌桌
	move_child(ui_root, 0)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://assets/felt_tex.gdshader")
	var felt_tex: Texture2D = load("res://assets/table/felt.png")
	if felt_tex != null:
		shader_mat.set_shader_parameter("felt_tex", felt_tex)
		shader_mat.set_shader_parameter("tex_mean", 0.163)
		shader_mat.set_shader_parameter("tex_strength", 0.28)
	bg.material = shader_mat
	ui_root.add_child(bg)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.02, 0.04, 0.05, 0.78)
	bar_bg.anchor_right = 1.0
	bar_bg.offset_bottom = 82.0
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar_bg)

	var bar_line := ColorRect.new()
	bar_line.color = C_GOLD_DIM
	bar_line.anchor_right = 1.0
	bar_line.offset_top = 81.0
	bar_line.offset_bottom = 82.0
	bar_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar_line)

	ui_stage = Control.new()
	ui_stage.anchor_left = 0.5
	ui_stage.anchor_right = 0.5
	ui_stage.offset_left = -800.0
	ui_stage.offset_right = 800.0
	ui_stage.anchor_bottom = 1.0
	ui_stage.offset_top = 0.0
	ui_stage.offset_bottom = 0.0
	ui_root.add_child(ui_stage)

	table_root = Control.new()
	table_root.position = Vector2.ZERO
	table_root.size = Vector2(TABLE_W, 900)
	ui_stage.add_child(table_root)

	_build_topbar()
	_build_dealer_area()
	_build_center()
	_build_player_area()
	_build_lobby_panel()
	_build_banner()

	var ticker_timer := Timer.new()
	ticker_timer.wait_time = 3.4
	ticker_timer.autostart = true
	ticker_timer.timeout.connect(_on_ticker_tick)
	ui_stage.add_child(ticker_timer)
	_on_ticker_tick()
	_on_ticker_tick()
	_built_lang = Loc.lang


func _build_topbar() -> void:
	var bar := Control.new()
	bar.position = Vector2.ZERO
	bar.size = Vector2(1600, 82)
	ui_stage.add_child(bar)

	var title := _lbl(Loc.topbar_brand(), 30, C_GOLD, true)
	title.position = Vector2(32, 10)
	bar.add_child(title)

	var sub := _lbl("真人荷官 · 秒充秒提 · 百万玩家在线", 13, C_DIM)
	sub.position = Vector2(216, 22)
	bar.add_child(sub)

	var bal_cap := _lbl("账户余额", 12, C_DIM)
	bal_cap.position = Vector2(620, 12)
	bar.add_child(bal_cap)

	lbl_balance = _lbl(_money(START_BALANCE), 30, C_GREEN, true)
	lbl_balance.position = Vector2(618, 30)
	bar.add_child(lbl_balance)

	var debt_cap := _lbl("待还借款", 12, C_DIM)
	debt_cap.position = Vector2(860, 12)
	bar.add_child(debt_cap)

	lbl_debt = _lbl("¥0", 24, C_DIM, true)
	lbl_debt.position = Vector2(858, 32)
	bar.add_child(lbl_debt)

	var wd := _make_button("提  现", C_CYAN)
	wd.position = Vector2(1000, 18)
	wd.size = Vector2(120, 46)
	wd.pressed.connect(_on_withdraw)
	bar.add_child(wd)

	lbl_withdraw = _lbl("", 12, C_DIM)
	lbl_withdraw.position = Vector2(1136, 24)
	lbl_withdraw.size = Vector2(448, 40)
	lbl_withdraw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(lbl_withdraw)


func _build_dealer_area() -> void:
	var row_x := (TABLE_W - ROW_W) / 2.0

	# 荷官信息整体水平居中，圆点 / 名字 / 状态三者垂直居中对齐
	var hdr := HBoxContainer.new()
	hdr.position = Vector2(0, 78)
	hdr.size = Vector2(TABLE_W, 32)
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	hdr.add_theme_constant_override("separation", 12)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_root.add_child(hdr)

	var dot := _panel_bg(C_GREEN, 6)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(dot)

	var name_l := _lbl("荷官 · 小雅", 19, C_TEXT, true)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(name_l)

	var tag := _lbl("真人荷官 · 在线", 13, C_DIM)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(tag)

	for i in 5:
		var slot := _make_card_slot(table_root, Vector2(row_x + i * (CARD_W + CARD_GAP), 118))
		dealer_slots.append(slot)

	lbl_dealer_hand = _lbl("", 21, C_GOLD, true)
	lbl_dealer_hand.position = Vector2(0, 350)
	lbl_dealer_hand.size = Vector2(TABLE_W, 28)
	lbl_dealer_hand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_root.add_child(lbl_dealer_hand)


func _build_center() -> void:
	var center := Control.new()
	center.position = Vector2(0, 382)
	center.size = Vector2(TABLE_W, 200)
	table_root.add_child(center)

	lbl_pot = _lbl("", 30, C_GOLD, true)
	lbl_pot.position = Vector2(0, 0)
	lbl_pot.size = Vector2(TABLE_W, 36)
	lbl_pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_pot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_child(lbl_pot)

	lbl_committed = _lbl("", 14, C_DIM)
	lbl_committed.position = Vector2(0, 36)
	lbl_committed.size = Vector2(TABLE_W, 18)
	lbl_committed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(lbl_committed)

	lbl_status = _lbl("", 16, C_TEXT)
	lbl_status.position = Vector2(0, 56)
	lbl_status.size = Vector2(TABLE_W, 24)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(lbl_status)

	# ---- 下注区：金额输入框 + 滑条 ----
	bet_panel = Control.new()
	bet_panel.position = Vector2(0, 80)
	bet_panel.size = Vector2(TABLE_W, 62)
	bet_panel.visible = false
	center.add_child(bet_panel)

	var grp_x: float = (TABLE_W - 560.0) / 2.0

	var cap := _lbl("下注金额", 14, C_DIM)
	cap.position = Vector2(grp_x, 3)
	cap.size = Vector2(80, 24)
	bet_panel.add_child(cap)

	bet_input = LineEdit.new()
	bet_input.position = Vector2(grp_x + 84, 0)
	bet_input.size = Vector2(152, 30)
	bet_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bet_input.max_length = 8
	bet_input.add_theme_font_override("font", font_bold)
	bet_input.add_theme_font_size_override("font_size", 16)
	bet_input.add_theme_color_override("font_color", C_GOLD)
	bet_input.add_theme_color_override("caret_color", C_GOLD)
	bet_input.add_theme_color_override("font_placeholder_color", Color("#4a5a68"))
	bet_input.add_theme_stylebox_override("normal", _input_style(C_LINE))
	bet_input.add_theme_stylebox_override("focus", _input_style(C_GOLD))
	bet_input.placeholder_text = Loc.t("输入金额")
	bet_input.text_changed.connect(_on_bet_text_changed)
	bet_input.text_submitted.connect(_on_bet_text_submitted)
	bet_input.focus_exited.connect(_on_bet_focus_out)
	bet_panel.add_child(bet_input)

	lbl_bet_hint = _lbl("", 12, C_DIM)
	lbl_bet_hint.position = Vector2(grp_x + 248, 4)
	lbl_bet_hint.size = Vector2(280, 24)
	bet_panel.add_child(lbl_bet_hint)

	bet_slider = HSlider.new()
	bet_slider.position = Vector2((TABLE_W - 620) / 2.0, 38)
	bet_slider.size = Vector2(620, 20)
	bet_slider.min_value = MIN_ANTE
	bet_slider.max_value = 1000
	bet_slider.step = 1
	bet_slider.value = MIN_ANTE
	var trk := StyleBoxFlat.new()
	trk.bg_color = Color(1, 1, 1, 0.10)
	trk.set_corner_radius_all(5)
	trk.content_margin_top = 4
	trk.content_margin_bottom = 4
	bet_slider.add_theme_stylebox_override("slider", trk)

	var fill := StyleBoxFlat.new()
	fill.bg_color = C_GOLD
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	bet_slider.add_theme_stylebox_override("grabber_area", fill)
	bet_slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	bet_panel.add_child(bet_slider)
	bet_slider.value_changed.connect(_on_bet_changed)

	btn_row = HBoxContainer.new()
	btn_row.position = Vector2(0, 146)
	btn_row.size = Vector2(TABLE_W, 48)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	center.add_child(btn_row)


func _build_player_area() -> void:
	var row_x := (TABLE_W - ROW_W) / 2.0
	for i in 5:
		var slot := _make_card_slot(table_root, Vector2(row_x + i * (CARD_W + CARD_GAP), 592))
		player_slots.append(slot)

	var mask := _panel_bg(Color(0.06, 0.22, 0.30, 0.85), 8, C_CYAN, 1)
	mask.position = Vector2(28, 592)
	mask.size = Vector2(44, 28)
	table_root.add_child(mask)
	var you := _lbl("你", 15, C_CYAN, true)
	you.position = Vector2(0, 3)
	you.size = Vector2(44, 22)
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mask.add_child(you)

	lbl_player_hand = _lbl("", 21, C_CYAN, true)
	lbl_player_hand.position = Vector2(0, 838)
	lbl_player_hand.size = Vector2(TABLE_W, 30)
	lbl_player_hand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_root.add_child(lbl_player_hand)


func _build_lobby_panel() -> void:
	panel_root = Control.new()
	panel_root.anchor_bottom = 1.0
	panel_root.offset_left = PANEL_X
	panel_root.offset_right = PANEL_X + PANEL_W
	panel_root.offset_top = 0.0
	panel_root.offset_bottom = 0.0
	ui_stage.add_child(panel_root)

	var bgp := _panel_bg(Color(0.035, 0.060, 0.080, 0.94), 0)
	bgp.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(bgp)

	var edge := ColorRect.new()
	edge.color = C_LINE
	edge.anchor_bottom = 1.0
	edge.offset_right = 1.0
	panel_root.add_child(edge)

	var dot := _panel_bg(C_GREEN, 5)
	dot.position = Vector2(24, 30)
	dot.size = Vector2(10, 10)
	panel_root.add_child(dot)

	var t := _lbl("在 线 大 厅", 19, C_TEXT, true)
	t.position = Vector2(44, 18)
	panel_root.add_child(t)

	lbl_online = _lbl("在线 1,284 人", 13, C_GREEN)
	lbl_online.position = Vector2(44, 46)
	panel_root.add_child(lbl_online)

	_hr(panel_root, 78)

	var wcap := _lbl("最 新 战 报", 12, C_DIM)
	wcap.position = Vector2(24, 94)
	panel_root.add_child(wcap)

	ticker_rt = RichTextLabel.new()
	ticker_rt.bbcode_enabled = true
	ticker_rt.scroll_following = true
	ticker_rt.position = Vector2(24, 120)
	ticker_rt.size = Vector2(PANEL_W - 48, 300)
	ticker_rt.add_theme_font_override("normal_font", font_regular)
	ticker_rt.add_theme_font_override("bold_font", font_bold)
	ticker_rt.add_theme_font_size_override("normal_font_size", 13)
	ticker_rt.add_theme_font_size_override("bold_font_size", 13)
	ticker_rt.add_theme_color_override("default_color", C_DIM)
	panel_root.add_child(ticker_rt)

	_hr(panel_root, 442)

	var vip := _panel_bg(Color(0.30, 0.22, 0.05, 0.55), 10, C_GOLD_DIM, 1)
	vip.position = Vector2(24, 462)
	vip.size = Vector2(PANEL_W - 48, 78)
	panel_root.add_child(vip)

	var vip_t := _lbl("VIP 专享", 15, C_GOLD, true)
	vip_t.position = Vector2(16, 10)
	vip.add_child(vip_t)

	var vip_s := _lbl("充值满 ¥50,000 解锁专属荷官\n提现秒到账 · 亏损返还 5%", 12, C_DIM)
	vip_s.position = Vector2(16, 34)
	vip.add_child(vip_s)

	# 主动借款 —— 不用等破产，随时能把额度换成筹码
	btn_loan = _make_button(Loc.t("借 款   ") + _money(LOAN_AMOUNT), C_RED, false)
	btn_loan.position = Vector2(24, 546)
	btn_loan.size = Vector2(PANEL_W - 48, 48)
	btn_loan.add_theme_font_size_override("font_size", 17)
	btn_loan.pressed.connect(_manual_loan)
	panel_root.add_child(btn_loan)

	btn_repay = _make_button("暂无欠款", C_RED, true)
	btn_repay.position = Vector2(24, 602)
	btn_repay.size = Vector2(PANEL_W - 48, 58)
	btn_repay.add_theme_font_size_override("font_size", 16)
	btn_repay.disabled = true
	btn_repay.pressed.connect(_on_repay)
	panel_root.add_child(btn_repay)

	var cs := _make_button("在线客服", C_CYAN, false)
	cs.position = Vector2(24, 668)
	cs.size = Vector2(PANEL_W - 48, 44)
	cs.pressed.connect(_on_service)
	panel_root.add_child(cs)

	var quit := _make_button("退 出 登 录", Color("#66717c"), false)
	quit.position = Vector2(24, 720)
	quit.size = Vector2(PANEL_W - 48, 42)
	quit.add_theme_font_size_override("font_size", 15)
	quit.pressed.connect(_on_exit_table)
	panel_root.add_child(quit)

	var tip := _lbl("本平台仅限 18 岁以上用户\n理性娱乐 · 谨防沉迷", 11, Color("#4a5a68"))
	tip.position = Vector2(24, 838)
	panel_root.add_child(tip)


func _build_banner() -> void:
	banner_bg = _panel_bg(Color(0.02, 0.04, 0.05, 0.90), 14, C_GOLD_DIM, 2)
	banner_bg.position = Vector2((TABLE_W - 540) / 2.0, 392)
	banner_bg.size = Vector2(540, 108)
	banner_bg.modulate.a = 0.0
	banner_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_root.add_child(banner_bg)

	banner = _lbl("", 56, C_GOLD, true)
	banner.position = Vector2((TABLE_W - 540) / 2.0, 392)
	banner.size = Vector2(540, 108)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_root.add_child(banner)


# =====================================================================
# 卡牌
# =====================================================================
func _make_card_slot(parent: Control, pos: Vector2) -> Dictionary:
	var root := Control.new()
	root.position = pos
	root.size = Vector2(CARD_W, CARD_H)
	root.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)

	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.40)
	shadow.position = Vector2(7, 9)
	shadow.size = Vector2(CARD_W, CARD_H)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shadow)

	var glow := ColorRect.new()
	glow.color = Color(1, 0.85, 0.3, 0.0)
	glow.position = Vector2(-5, -5)
	glow.size = Vector2(CARD_W + 10, CARD_H + 10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)

	var placeholder := _panel_bg(Color(1, 1, 1, 0.03), 12, Color(1, 1, 1, 0.13), 2)
	placeholder.position = Vector2.ZERO
	placeholder.size = Vector2(CARD_W, CARD_H)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(placeholder)

	var tex := TextureRect.new()
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.position = Vector2.ZERO
	tex.size = Vector2(CARD_W, CARD_H)
	tex.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.modulate.a = 0.0
	root.add_child(tex)

	return {"root": root, "tex": tex, "glow": glow, "placeholder": placeholder}


var _tex_cache: Dictionary = {}


func _card_texture(card: int) -> Texture2D:
	if _tex_cache.has(card):
		return _tex_cache[card]
	var t: Texture2D = load(Cards.texture_path(card))
	_tex_cache[card] = t
	return t


func _back_texture() -> Texture2D:
	if _tex_cache.has(-1):
		return _tex_cache[-1]
	var t: Texture2D = load(Cards.CARD_BACK_PATH)
	_tex_cache[-1] = t
	return t


func _set_card_slot(slot: Dictionary, card: int, face_down := false) -> void:
	var tex: TextureRect = slot["tex"]
	var placeholder: Panel = slot["placeholder"]
	if card < 0:
		tex.texture = null
		tex.modulate.a = 0.0
		placeholder.visible = true
		return
	placeholder.visible = false
	tex.texture = _back_texture() if face_down else _card_texture(card)
	tex.modulate.a = 1.0
	tex.scale = Vector2.ONE


func _animate_deal(slot: Dictionary, delay: float) -> void:
	var root: Control = slot["root"]
	root.scale = Vector2(0.86, 0.86)
	root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(root, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flip_to_face(slot: Dictionary, card: int) -> void:
	slot["tex"].texture = _card_texture(card)
	slot["placeholder"].visible = false


func _flip_reveal(slot: Dictionary, card: int, delay := 0.0) -> void:
	var tex: TextureRect = slot["tex"]
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		get_tree().create_timer(delay).timeout.connect(_sfx.bind("flip"))
	else:
		_sfx("flip")
	tw.tween_property(tex, "scale:x", 0.0, 0.09)
	tw.tween_callback(_flip_to_face.bind(slot, card))
	tw.tween_property(tex, "scale:x", 1.0, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _clear_glow() -> void:
	for s in dealer_slots + player_slots:
		var tw := create_tween()
		tw.tween_property(s["glow"], "color:a", 0.0, 0.20)


func _glow_slots(slots: Array, color: Color) -> void:
	for s in slots:
		s["glow"].color = Color(color.r, color.g, color.b, 0.55)


# =====================================================================
# 工具
# =====================================================================
func _money(v: float) -> String:
	var neg := v < 0
	var s := str(int(round(abs(v))))
	var out := ""
	var n := s.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if neg else "") + "¥" + out


func _clear_buttons() -> void:
	for c in btn_row.get_children():
		btn_row.remove_child(c)
		c.queue_free()
	btn_raise = null
	if bet_panel != null:
		bet_panel.visible = false


func _input_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.38)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


## 当前下注金额：以输入框为准，越界自动夹紧
func _current_bet() -> float:
	var maxb: float = max(MIN_ANTE, balance)
	var txt := bet_input.text.strip_edges()
	if txt.is_valid_int():
		return clamp(float(int(txt)), MIN_ANTE, maxb)
	return clamp(bet_slider.value, MIN_ANTE, maxb)


## 滑条动了 → 同步输入框
func _on_bet_changed(v: float) -> void:
	if _bet_syncing:
		return
	var amt: float = clamp(round(v), MIN_ANTE, max(MIN_ANTE, balance))
	_bet_syncing = true
	bet_input.text = str(int(amt))
	_bet_syncing = false
	lbl_bet_hint.text = Loc.t("最低 ¥5 · 最高 ") + _money(max(MIN_ANTE, balance))
	lbl_bet_hint.add_theme_color_override("font_color", C_DIM)
	_update_raise_button(amt)


func _update_raise_button(amt: float) -> void:
	if btn_raise == null or not is_instance_valid(btn_raise):
		return
	var allin := amt >= balance - 0.01
	btn_raise.text = Loc.t("全 下 " if allin else "加 注 ") + _money(amt)


## 输入框在打字 → 只做提示，不抢光标
func _on_bet_text_changed(t: String) -> void:
	if _bet_syncing:
		return
	var maxb: float = max(MIN_ANTE, balance)
	var clean := t.strip_edges()
	if clean == "":
		lbl_bet_hint.text = Loc.t("最低 ¥5 · 最高 ") + _money(maxb)
		lbl_bet_hint.add_theme_color_override("font_color", C_DIM)
		return
	if not clean.is_valid_int():
		lbl_bet_hint.text = Loc.t("请输入数字")
		lbl_bet_hint.add_theme_color_override("font_color", C_RED)
		return
	var v := int(clean)
	if v < int(MIN_ANTE):
		lbl_bet_hint.text = Loc.t("金额不够，最低 ¥5")
		lbl_bet_hint.add_theme_color_override("font_color", C_RED)
		return
	if float(v) > maxb:
		lbl_bet_hint.text = Loc.t("超出余额，最高 ") + _money(maxb)
		lbl_bet_hint.add_theme_color_override("font_color", C_RED)
		return
	lbl_bet_hint.text = Loc.t("最低 ¥5 · 最高 ") + _money(maxb)
	lbl_bet_hint.add_theme_color_override("font_color", C_DIM)
	_bet_syncing = true
	bet_slider.value = float(v)
	_bet_syncing = false
	_update_raise_button(float(v))


## 回车 / 失焦 → 越界就夹回来
func _on_bet_text_submitted(_t: String) -> void:
	_normalize_bet_input()


func _on_bet_focus_out() -> void:
	_normalize_bet_input()


func _normalize_bet_input() -> void:
	var maxb: float = max(MIN_ANTE, balance)
	var txt := bet_input.text.strip_edges()
	var v: float
	if txt.is_valid_int():
		v = float(int(txt))
	else:
		v = bet_slider.value

	if v < MIN_ANTE:
		v = MIN_ANTE
		lbl_bet_hint.text = Loc.t("金额不够，已按最低 ¥5 计算")
		lbl_bet_hint.add_theme_color_override("font_color", C_RED)
	elif v > maxb:
		v = maxb
		lbl_bet_hint.text = Loc.t("超出余额，已调整为最高 ") + _money(maxb)
		lbl_bet_hint.add_theme_color_override("font_color", C_RED)
	else:
		lbl_bet_hint.text = Loc.t("最低 ¥5 · 最高 ") + _money(maxb)
		lbl_bet_hint.add_theme_color_override("font_color", C_DIM)

	_bet_syncing = true
	bet_slider.value = v
	bet_input.text = str(int(v))
	_bet_syncing = false
	_update_raise_button(v)


# =====================================================================
# 大厅滚动播报（假的，纯装饰）
# =====================================================================
var _ticker_lines: Array = []


func _on_ticker_tick() -> void:
	var name: String = FAKE_NAMES[rng.randi_range(0, FAKE_NAMES.size() - 1)]
	var amt: int = rng.randi_range(18, 198) * 10
	_ticker_lines.append(Loc.t("[color=#7c8b9c]%s[/color] 提现成功 [color=#e8b64c]%s[/color]") % [name, _money(amt)])
	while _ticker_lines.size() > 11:
		_ticker_lines.pop_front()
	ticker_rt.clear()
	for l in _ticker_lines:
		ticker_rt.append_text(l + "\n")
	var n := 1200 + rng.randi_range(0, 300)
	lbl_online.text = Loc.t("在线 %s 人") % _thousands(n)


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var L := s.length()
	for i in L:
		if i > 0 and (L - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _on_exit_table() -> void:
	_save_game()
	_close_withdraw()
	_close_modal()
	_clear_sms()
	# 用 true：从存档把余额/负债/天数原样读回来，别把进度清成新号
	_reset_game(true)
	_show_title()

# ---------- 还款 ----------
func _on_repay() -> void:
	if debt <= 0.0:
		_show_modal("还 款", "[color=#dfe7ef]" + Loc.t("您当前没有欠款。") + "[/color]", [
			{"text": "关闭", "color": C_CYAN, "filled": false, "cb": _close_modal}
		], 380.0)
		return

	var can: float = min(balance, debt)
	var body := ""
	body += Loc.t("待还欠款：[color=#ff4d5e]%s[/color]\n") % _money(debt)
	body += Loc.t("可用余额：[color=#3fd68a]%s[/color]\n\n") % _money(balance)
	if can <= 0.0:
		body += "[color=#7c8b9c]" + Loc.t("余额不足，暂时无法还款。") + "\n"
		body += Loc.t("可先投注赢回资金，或申请新的借款。") + "[/color]"
	elif can >= debt:
		body += "[color=#e8b64c]" + Loc.t("可一次性结清。还清后所有催收停止。") + "[/color]"
	else:
		body += "[color=#e8b64c]" + Loc.t("余额不足以结清，本次最多可还 %s。") % _money(can) + "[/color]"

	var btns: Array = []
	if can > 0.0:
		btns.append({
			"text": (Loc.t("全额还清 %s") % _money(debt)) if can >= debt else (Loc.t("还 %s") % _money(can)),
			"color": C_GOLD, "filled": true, "cb": _do_repay_all,
		})
	btns.append({"text": "先不还", "color": C_CYAN, "filled": false, "cb": _close_modal})

	_show_modal("还 款", body, btns, 400.0)


func _do_repay_all() -> void:
	var amount: float = min(balance, debt)
	if amount <= 0.0:
		_close_modal()
		return
	balance -= amount
	debt -= amount
	_close_modal()
	_save_game()
	_update_ui()
	if debt <= 0.0:
		# 结清后重新计时，再借就是新的一笔
		interest_day = 0
		_interest_t = 0.0
		collect_stage = 0
		_collect_t = COLLECT_INTERVAL
		_save_game()
		_update_ui()
		_toast("欠款已结清，感谢您的诚信", C_GREEN)
		_clear_sms()
	else:
		_toast(Loc.t("已还款 %s，剩余欠款 %s") % [_money(amount), _money(debt)], C_GOLD)

func _on_service() -> void:
	_show_modal("在线客服", "[color=#dfe7ef]" + Loc.t("您好，客服「小雨」为您服务。\n\n")
		+ Loc.t("您当前的提现申请正在审核中，\n")
		+ Loc.t("为加快处理，建议您先完成 [color=#e8b64c]3 倍流水[/color] 要求。\n\n")
		+ Loc.t("[color=#7c8b9c]（客服已为您排队，前面还有 12 人）[/color][/color]"),
		[{"text": "关闭", "color": C_CYAN, "filled": false, "cb": _close_modal}])


# =====================================================================
# 后台逻辑（玩家永远看不到）
# =====================================================================
func _headroom() -> float:
	return CheatEngine.headroom(net_profit)


## 这一把的最终胜率：基础曲线 × 局数 / 时长疲劳
func _win_chance(commit: float) -> float:
	return CheatEngine.session_win_chance(commit, net_profit, hands_played, session_seconds)


## 动态养鱼：让他赢一点点，但永远赢不多
func _nurture_rate() -> float:
	if hands_played <= 3:
		return 0.82                       # 开局先给甜头
	var room := _headroom()
	if room <= 0.0:
		return 0.28                       # 额度用光，不再喂好牌
	var t: float = clamp(room / WIN_CAP, 0.0, 1.0)
	return lerp(0.28, 0.78, t)


## 这一手直接塞"三条以上"的概率：时间越久、欠款越多越高；
## 大注局和已经赢钱的玩家会被压低。连发控制由 big_cooldown 负责。
func _bait_chance() -> float:
	return CheatEngine.bait_chance(
		session_seconds,
		debt / DEBT_REVEAL,
		maxf(net_profit, 0.0) / WIN_CAP,
		ante
	)


## 单局输得够狠：大牌先冷却两手，避免"输急眼了还马上发大牌"
func _note_loss(amount: float) -> void:
	if amount >= TILT_LOSS:
		big_cooldown = maxi(big_cooldown, 2)


# =====================================================================
# 游戏流程
# =====================================================================
func _reset_game(restore := false) -> void:
	_close_withdraw()
	_close_modal()
	wd_attempts = 0
	committed = 0.0
	pot = 0.0
	hands_played = 0
	session_seconds = 0.0
	total_wagered = 0.0
	rigged_count = 0
	near_miss_count = 0
	big_cooldown = 0
	biggest_loss = 0.0
	biggest_win = 0.0
	loans_taken = 0
	withdraw_excuses = 0
	_bust_loss_marker = 0.0
	collect_stage = 0
	_collect_t = COLLECT_INTERVAL
	interest_day = 0
	_interest_t = 0.0

	if restore and _has_profile():
		balance = float(save_profile.get("balance", START_BALANCE))
		debt = float(save_profile.get("debt", 0.0))
		wins_total = float(save_profile.get("wins", 0.0))
		losses_total = float(save_profile.get("losses", 0.0))
		total_paid_out = float(save_profile.get("paid", 0.0))
		interest_day = int(save_profile.get("interest_day", 0))
		_interest_t = float(save_profile.get("interest_t", 0.0))
		net_profit = wins_total - losses_total
		loans_taken = int(round(debt / LOAN_AMOUNT))
	else:
		balance = START_BALANCE
		debt = 0.0
		net_profit = 0.0
		wins_total = 0.0
		losses_total = 0.0
		total_paid_out = 0.0
		if not _has_profile():
			# 只在「根本没有账号」时清号。刚注册完还没写过存档时
			# _has_profile() 也是 false，不能把刚填的手机号抹掉
			if account_phone.length() != 11:
				account_phone = ""

	player_cards.clear()
	dealer_cards.clear()
	player_visible = 0
	dealer_revealed = 0
	player_score = []
	dealer_score = []
	round_index = 0
	rigged_this_hand = false
	state = State.ANTE_WAIT
	for s in dealer_slots + player_slots:
		_set_card_slot(s, -1)
	_clear_glow()
	_show_ante_buttons()


func _show_ante_buttons() -> void:
	_clear_buttons()
	state = State.ANTE_WAIT
	round_index = 0
	player_visible = 0
	dealer_revealed = 0
	committed = 0.0
	pot = 0.0
	player_cards.clear()
	dealer_cards.clear()
	player_score = []
	dealer_score = []
	rigged_this_hand = false
	bait_hand = false
	for s in dealer_slots + player_slots:
		_set_card_slot(s, -1)
	_clear_glow()

	lbl_pot.text = Loc.t("选择底注开始")
	lbl_status.text = Loc.t("底注最低 ¥5 · 祝您玩得愉快")
	lbl_player_hand.text = ""
	lbl_dealer_hand.text = ""
	banner.modulate.a = 0.0
	banner_bg.modulate.a = 0.0

	var options := [5, 10, 50, 100, 500, 1000, 5000]
	for amt in options:
		var b := _make_button(Loc.t("底注 ") + _money(amt), C_GOLD, false)
		if float(amt) > balance:
			b.disabled = true
		b.pressed.connect(_on_ante_pressed.bind(float(amt)))
		btn_row.add_child(b)

	_update_ui()


func _on_ante_pressed(amt: float) -> void:
	_start_hand(amt)


func _start_hand(amt: float) -> void:
	if busy or state != State.ANTE_WAIT:
		return
	if balance < MIN_ANTE:
		_on_bust()
		return
	busy = true
	_clear_buttons()
	state = State.RESOLVING
	hands_played += 1
	ante = amt
	committed = amt
	balance -= amt
	pot = amt * 2.0
	total_wagered += amt
	round_index = 0
	rigged_this_hand = false
	banner.modulate.a = 0.0
	banner_bg.modulate.a = 0.0

	# 钓鱼局：时间越久、借得越多，越容易塞三条以上，勾着他押大注。
	# big_cooldown 用来隔开大牌：刚发过大牌、刚输了大注，先空两手。
	var bait_p := 0.0
	if big_cooldown > 0:
		big_cooldown -= 1
	else:
		bait_p = _bait_chance()
	bait_hand = hands_played >= 2 and rng.randf() < bait_p
	var min_cat := HandEval.THREE if bait_hand else HandEval.PAIR
	var rate := _nurture_rate()
	if bait_hand:
		rate = 0.95

	var deck := Cards.full_deck()
	Cards.shuffle(deck, rng)
	player_cards = CheatEngine.nurture_player_hand(deck, rng, rate, min_cat)
	var rest: Array = []
	for c in deck:
		if not player_cards.has(c):
			rest.append(c)
	Cards.shuffle(rest, rng)
	var up: int = rest.pop_back()
	dealer_cards = [up]

	for s in dealer_slots:
		_set_card_slot(s, -1)
	for s in player_slots:
		_set_card_slot(s, -1)

	_update_ui()
	lbl_status.text = Loc.t("发牌中…")

	_sfx("deal")
	for i in 3:
		_set_card_slot(player_slots[i], player_cards[i])
		_animate_deal(player_slots[i], 0.06 * i)
	_set_card_slot(dealer_slots[0], dealer_cards[0])
	_animate_deal(dealer_slots[0], 0.34)
	for i in range(1, 5):
		_set_card_slot(dealer_slots[i], 0, true)
		_animate_deal(dealer_slots[i], 0.34 + 0.05 * i)

	player_visible = 3
	player_score = HandEval.evaluate(player_cards)
	# 不管这副大牌是塞的还是自然发的，接下来两手先不再塞
	if HandEval.cat_of(player_score) >= HandEval.THREE:
		big_cooldown = maxi(big_cooldown, 2)

	await get_tree().create_timer(0.62).timeout
	_begin_betting_round()


func _begin_betting_round() -> void:
	state = State.BETTING
	busy = false
	_update_ui()
	_render_hand_labels()
	lbl_status.text = Loc.t("第 %d 轮 · 您现在可以加注") % (round_index + 1)
	if balance < MIN_ANTE:
		busy = true
		_clear_buttons()
		state = State.RESOLVING
		lbl_status.text = Loc.t("筹码已全部押上")
		await get_tree().create_timer(0.55).timeout
		_advance_stage()
		return
	_show_round_buttons()


func _show_round_buttons() -> void:
	_clear_buttons()

	# 滑条：最低 ¥5，最高全压
	var max_bet: float = max(MIN_ANTE, balance)
	bet_panel.visible = true
	bet_slider.min_value = MIN_ANTE
	bet_slider.max_value = max_bet
	bet_slider.step = 1
	var def_bet: float = clamp(round(pot * 0.5), MIN_ANTE, max_bet)
	_bet_syncing = true
	bet_slider.value = def_bet
	_bet_syncing = false
	_on_bet_changed(def_bet)

	btn_raise = _make_button(Loc.t("加 注 ") + _money(def_bet), C_GOLD, true)
	btn_raise.pressed.connect(_on_raise_pressed)
	btn_row.add_child(btn_raise)

	var chk := _make_button("过 牌", C_CYAN, false)
	chk.pressed.connect(_on_check)
	btn_row.add_child(chk)

	var fold := _make_button("弃 牌", Color("#66717c"), false)
	fold.pressed.connect(_on_fold)
	btn_row.add_child(fold)


func _on_raise_pressed() -> void:
	_on_raise(_current_bet())


func _on_raise(amount: float) -> void:
	if busy or state != State.BETTING:
		return
	busy = true
	_clear_buttons()
	amount = min(amount, balance)
	amount = float(int(amount))
	balance -= amount
	committed += amount
	pot += amount * 2.0
	total_wagered += amount
	_sfx("chip")
	_update_ui()

	await get_tree().create_timer(0.22).timeout
	_advance_stage()


func _on_check() -> void:
	if busy or state != State.BETTING:
		return
	busy = true
	_clear_buttons()
	_sfx("chip")
	_advance_stage()


func _advance_stage() -> void:
	state = State.RESOLVING
	round_index += 1
	if player_visible < 5:
		var idx := player_visible
		_set_card_slot(player_slots[idx], player_cards[idx])
		_animate_deal(player_slots[idx], 0.0)
		_sfx("flip")
		player_visible += 1
		await get_tree().create_timer(0.40).timeout
		_render_hand_labels()
		await get_tree().create_timer(0.16).timeout
		_begin_betting_round()
	else:
		await _showdown()


func _on_fold() -> void:
	if busy or state != State.BETTING:
		return
	busy = true
	_clear_buttons()
	state = State.RESOLVING
	losses_total += committed
	net_profit -= committed
	_note_loss(committed)
	if committed > biggest_loss:
		biggest_loss = committed
	if committed > KILL_THRESHOLD:
		rigged_count += 1
	lbl_status.text = Loc.t("您已弃牌")
	pot = 0.0
	await get_tree().create_timer(0.7).timeout
	_end_hand()


func _pool_for_dealer() -> Array:
	var pool: Array = []
	for c in Cards.full_deck():
		if player_cards.has(c):
			continue
		if dealer_cards.size() > 0 and c == dealer_cards[0]:
			continue
		pool.append(c)
	return pool


func _showdown() -> void:
	state = State.RESOLVING
	player_score = HandEval.evaluate(player_cards)
	_render_hand_labels()

	var pool := _pool_for_dealer()
	var chance := _win_chance(committed)
	var want_player_win := rng.randf() < chance
	var final_hand: Array = []

	if want_player_win:
		# 让他赢：庄家随机补牌，只保留"确实比玩家小"的结果（不刻意做小差距）
		var lose_plan := CheatEngine.plan_lose([dealer_cards[0]], pool, player_score, rng)
		if lose_plan["ok"]:
			final_hand = lose_plan["hand"]
		else:
			# 玩家的牌太烂，怎么配都赢不了 → 退回庄家赢（实际胜率只会更低）
			want_player_win = false

	if not want_player_win:
		var kill_plan := CheatEngine.plan_kill([dealer_cards[0]], pool, player_score, rng)
		if kill_plan["ok"]:
			var h: Array = kill_plan["hand"]
			final_hand = [dealer_cards[0]]
			for c in h:
				if c != dealer_cards[0]:
					final_hand.append(c)
		else:
			final_hand = [dealer_cards[0]] + pool.slice(0, 4)

	while final_hand.size() < 5:
		var added := false
		for c in pool:
			if not final_hand.has(c):
				final_hand.append(c)
				added = true
				break
		if not added:
			break

	dealer_cards = final_hand
	dealer_score = HandEval.evaluate(dealer_cards)

	lbl_status.text = Loc.t("开牌…")
	await get_tree().create_timer(0.45).timeout

	for i in range(1, 5):
		if i < dealer_cards.size():
			_flip_reveal(dealer_slots[i], dealer_cards[i], 0.16 * (i - 1))
	await get_tree().create_timer(0.16 * 4 + 0.30).timeout
	dealer_revealed = 5

	_render_hand_labels(true)
	await get_tree().create_timer(0.30).timeout

	var cmp := HandEval.compare(dealer_score, player_score)
	var player_won := cmp < 0

	if player_won:
		balance += pot
		wins_total += committed
		net_profit += committed
		biggest_win = max(biggest_win, committed)
		_glow_slots(player_slots, C_GREEN)
		_show_banner("你 赢 了", C_GREEN)
		lbl_status.text = _dealer_win_line()
	else:
		losses_total += committed
		net_profit -= committed
		_note_loss(committed)
		biggest_loss = max(biggest_loss, committed)
		rigged_count += 1
		var gap := HandEval.cat_of(dealer_score) - HandEval.cat_of(player_score)
		if gap == 1:
			near_miss_count += 1
		_glow_slots(dealer_slots, C_RED)
		_show_banner("你 输 了", C_RED)
		lbl_status.text = _dealer_lose_line()

	pot = 0.0
	_update_ui()
	await get_tree().create_timer(1.6).timeout
	_end_hand()


func _dealer_win_line() -> String:
	var lines := [
		"荷官：手气不错哦～",
		"荷官：这波稳的",
		"荷官：继续吗？",
	]
	return Loc.t(lines[rng.randi_range(0, lines.size() - 1)])


func _dealer_lose_line() -> String:
	var lines := [
		"荷官：这把是我运气好",
		"荷官：别急，下一把就回来了",
		"荷官：要不要再来一局？",
		"荷官：小场面，稳住",
	]
	return Loc.t(lines[rng.randi_range(0, lines.size() - 1)])


func _end_hand() -> void:
	state = State.HAND_OVER
	busy = false
	_clear_buttons()
	_update_ui()

	if balance < MIN_ANTE:
		await get_tree().create_timer(0.3).timeout
		_on_bust()
		return

	var again := _make_button("再来一把", C_GOLD, true)
	again.pressed.connect(_show_ante_buttons)
	btn_row.add_child(again)

	var nb: float = min(max(ante, MIN_ANTE), balance)
	if balance >= MIN_ANTE:
		var rebet := _make_button(Loc.t("底注 %s 继续") % _money(nb), C_CYAN, false)
		state = State.ANTE_WAIT
		rebet.pressed.connect(_on_ante_pressed.bind(nb))
		btn_row.add_child(rebet)


# =====================================================================
# 破产 / 借款 / 结局
# =====================================================================
func _on_bust() -> void:
	if state == State.BUST:
		return                     # 防止同一次破产被重复计数
	state = State.BUST
	_clear_buttons()
	_update_ui()

	# 记录：这是第几次输光
	bust_count += 1
	var session_loss: float = START_BALANCE + float(loans_taken) * LOAN_AMOUNT - total_paid_out
	var inc: float = max(0.0, session_loss - _bust_loss_marker)
	lifetime_lost += inc
	_bust_loss_marker = max(_bust_loss_marker, session_loss)
	_save_game()

	if debt >= DEBT_REVEAL:
		_show_reveal()
		return

	var body := ""
	body += Loc.t("[font_size=17]余额不足[/font_size]\n\n")
	body += Loc.t("当前余额：[color=#ff4d5e]%s[/color]\n") % _money(balance)
	body += Loc.t("待还借款：[color=#ff4d5e]%s[/color]\n") % _money(debt)
	body += Loc.t("\n[color=#7c8b9c]今日额度已用尽，可申请极速借款，")
	body += Loc.t("最快 30 秒到账，日息低至 0.05%。[/color]\n\n")
	body += Loc.t("[color=#4a5a68]（本模拟器不涉及任何真实货币）[/color]")

	_show_modal("极 速 借 款", body, [
		{"text": Loc.t("立即借款 %s") % _money(LOAN_AMOUNT), "color": C_RED, "filled": true, "cb": _take_loan},
		{"text": "暂不借款", "color": C_CYAN, "cb": _on_walk_away}
	])


func _take_loan() -> void:
	loans_taken += 1
	debt += LOAN_AMOUNT
	balance += LOAN_AMOUNT
	_close_modal()
	_save_game()
	_loan_sms()
	_show_ante_buttons()


## 大厅里的「借款」按钮 —— 不用破产也能借，借了就得还
func _manual_loan() -> void:
	if debt >= DEBT_REVEAL:
		_toast(Loc.t("已达借款上限，请先还款"), C_RED)
		return
	balance += LOAN_AMOUNT
	debt += LOAN_AMOUNT
	loans_taken += 1
	# 正在下注时借到钱，滑条上限要跟着放开
	if state == State.BETTING and bet_slider != null and is_instance_valid(bet_slider):
		bet_slider.max_value = max(MIN_ANTE, balance)
	_save_game()
	_update_ui()
	_loan_sms()
	_toast(Loc.t("借款 %s 已到账") % _money(LOAN_AMOUNT), C_GOLD)


func _on_walk_away() -> void:
	_close_modal()
	_show_reveal()


# =====================================================================
# 提现流程：排队 → 验证 → 提交 → 失败
#
# 设计要点：整个过程要让玩家相信"真的快到了"。
# 排队人数会真的减少，倒计时会真的走，处理完还会先显示"已提交"。
# 只有最后一步才失败，而且每次失败的理由都不一样。
# =====================================================================
var wd_layer: Control
var wd_status: Label
var wd_sub: Label
var wd_queue: Label
var wd_timer: Label
var wd_amount: Label
var wd_icon: Label
var wd_bar_fill: ColorRect
var wd_bar_bg: ColorRect
var wd_btn_row: HBoxContainer
var wd_active := false
var wd_phase := 0
var wd_t := 0.0
var wd_queue_total := 0.0
var wd_people := 0
var wd_attempts := 0

const WD_BAR_W := 460.0


## 出金闸门 —— 这才是平台真正不会亏钱的地方
##
##   1. 体验金本金（¥50,000）永远不可提现
##   2. 只有「超出本金」的部分算赢来的钱
##   3. 单笔最多 ¥2,000
##   4. 一辈子最多提走 ¥10,000
func _withdrawable() -> float:
	var profit: float = max(0.0, balance - START_BALANCE)
	var room: float = max(0.0, WITHDRAW_TOTAL_CAP - total_paid_out)
	return clamp(min(profit, room), 0.0, WITHDRAW_PER_TX)


func _on_withdraw() -> void:
	if wd_active:
		return
	var avail := _withdrawable()
	if avail < 1.0:
		var body := ""
		body += Loc.t("[color=#dfe7ef]您当前账户为 [b]体验金账户[/b]。[/color]\n\n")
		body += Loc.t("按平台规则，[color=#e8b64c]体验金本金不可提现[/color]，仅限用于投注。\n")
		body += Loc.t("需将账户余额做到 ¥50,000 以上，[b]超出部分[/b]方可申请提现。\n\n")
		if balance >= START_BALANCE:
			body += Loc.t("[color=#7c8b9c]当前余额 %s，其中体验金本金 %s。[/color]\n") % [_money(balance), _money(START_BALANCE)]
		else:
			body += Loc.t("[color=#7c8b9c]当前余额 %s，低于体验金本金 %s。\n") % [_money(balance), _money(START_BALANCE)]
			body += Loc.t("[color=#7c8b9c]继续投注，把本金赢回来即可解锁提现。[/color]\n")
		body += Loc.t("\n[color=#ff4d5e]当前可提现金额：¥0[/color]")
		_show_modal("提 现 申 请", body,
			[{"text": "知道了", "color": C_CYAN, "filled": false, "cb": _close_modal}], 480.0)
		return
	withdraw_excuses += 1
	_start_withdraw()


func _start_withdraw() -> void:
	_close_modal()
	if wd_layer != null and is_instance_valid(wd_layer):
		wd_layer.queue_free()

	wd_active = true
	wd_phase = 1
	wd_t = 0.0
	wd_attempts += 1
	wd_people = rng.randi_range(5, 11)
	wd_queue_total = 5.0

	wd_layer = Control.new()
	wd_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wd_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	wd_layer.add_child(dim)

	var box := _panel_bg(Color("#0d151d"), 14, C_CYAN, 2)
	var vp := get_viewport_rect().size
	box.position = Vector2((vp.x - 560.0) / 2.0, (vp.y - 400.0) / 2.0)
	box.size = Vector2(560, 400)
	wd_layer.add_child(box)

	var t := _lbl("提 现 申 请", 22, C_TEXT, true)
	t.position = Vector2(32, 22)
	box.add_child(t)

	var amt_cap := _lbl("可提现金额", 12, C_DIM)
	amt_cap.position = Vector2(32, 64)
	box.add_child(amt_cap)

	wd_amount = _lbl(_money(_withdrawable()), 30, C_GOLD, true)
	wd_amount.position = Vector2(32, 82)
	box.add_child(wd_amount)

	var hr := ColorRect.new()
	hr.color = C_LINE
	hr.position = Vector2(32, 132)
	hr.size = Vector2(496, 1)
	box.add_child(hr)

	wd_icon = _lbl("◌", 26, C_CYAN, true)
	wd_icon.position = Vector2(32, 150)
	box.add_child(wd_icon)

	wd_status = _lbl("正在验证身份…", 19, C_TEXT, true)
	wd_status.position = Vector2(72, 152)
	box.add_child(wd_status)

	wd_sub = _lbl("", 13, C_DIM)
	wd_sub.position = Vector2(32, 190)
	wd_sub.size = Vector2(496, 22)
	box.add_child(wd_sub)

	wd_queue = _lbl("", 14, C_DIM)
	wd_queue.position = Vector2(32, 226)
	box.add_child(wd_queue)

	wd_bar_bg = ColorRect.new()
	wd_bar_bg.color = Color(1, 1, 1, 0.06)
	wd_bar_bg.position = Vector2(32, 254)
	wd_bar_bg.size = Vector2(WD_BAR_W, 8)
	wd_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(wd_bar_bg)

	wd_bar_fill = ColorRect.new()
	wd_bar_fill.color = C_CYAN
	wd_bar_fill.position = Vector2.ZERO
	wd_bar_fill.size = Vector2(0, 8)
	wd_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wd_bar_bg.add_child(wd_bar_fill)

	wd_timer = _lbl("", 13, C_DIM)
	wd_timer.position = Vector2(32, 272)
	box.add_child(wd_timer)

	wd_btn_row = HBoxContainer.new()
	wd_btn_row.position = Vector2(32, 320)
	wd_btn_row.size = Vector2(496, 52)
	wd_btn_row.alignment = BoxContainer.ALIGNMENT_END
	wd_btn_row.add_theme_constant_override("separation", 12)
	box.add_child(wd_btn_row)

	wd_layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(wd_layer, "modulate:a", 1.0, 0.2)


func _process(delta: float) -> void:
	if state != State.REVEAL:
		if title_root == null:
			session_seconds += delta

		# 催收短信 + 贷款计息都只在牌桌上走（标题页不催、不计息）
		if debt > 0.0 and title_root == null:
			_collect_t -= delta
			if _collect_t <= 0.0:
				_collect_t += COLLECT_INTERVAL
				_collect_sms()

			_interest_t += delta
			while _interest_t >= DAY_SECONDS:
				_interest_t -= DAY_SECONDS
				_apply_interest()

	if not wd_active or wd_layer == null or not is_instance_valid(wd_layer):
		return
	wd_t += delta

	match wd_phase:
		1:
			if wd_t >= 1.8:
				wd_phase = 2
				wd_t = 0.0
				wd_status.text = Loc.t("正在排队")
				wd_sub.text = Loc.t("正在为您分配提现通道，请勿关闭页面")
				wd_icon.text = "◔"
		2:
			var remain: float = wd_queue_total - wd_t
			if remain <= 0.0:
				wd_phase = 3
				wd_t = 0.0
				wd_status.text = Loc.t("正在处理")
				wd_sub.text = Loc.t("已进入银行通道，正在提交…")
				wd_icon.text = "◑"
				wd_queue.text = Loc.t("前方已无排队用户")
				wd_timer.text = ""
				wd_bar_fill.size = Vector2(WD_BAR_W, 8)
				return
			var prog: float = 1.0 - remain / wd_queue_total
			wd_bar_fill.size = Vector2(WD_BAR_W * prog, 8)
			var left := int(ceil(float(wd_people) * (1.0 - prog)))
			wd_queue.text = Loc.t("前方还有 %d 人正在提现") % max(left, 0)
			var secs := int(ceil(remain))
			wd_timer.text = Loc.t("预计等待 %02d:%02d   ·   当前排队第 %d 位") % [secs / 60, secs % 60, max(left, 0) + 1]
		3:
			if wd_t >= 2.4:
				wd_phase = 4
				wd_t = 0.0
				wd_status.text = Loc.t("已提交至银行通道")
				wd_status.add_theme_color_override("font_color", C_GREEN)
				wd_sub.text = Loc.t("等待银行返回结果…")
				wd_icon.text = "✓"
				wd_icon.add_theme_color_override("font_color", C_GREEN)
				wd_queue.text = ""
				wd_timer.text = ""
		4:
			if wd_t >= 1.5:
				wd_phase = 5
				wd_t = 0.0
				if wd_attempts <= 1:
					_show_withdraw_success()
				else:
					_show_withdraw_fail()
		5:
			pass


## 第一次提现真的让他拿到钱 —— 这是整个骗局里最贵的一笔广告费。
## 小额出金成功 → 他相信平台没问题 → 加大投入 → 再也提不出来。
func _show_withdraw_success() -> void:
	var payout: float = _withdrawable()
	balance -= payout
	total_paid_out += payout
	_update_ui()

	wd_status.text = Loc.t("提现成功")
	wd_status.add_theme_color_override("font_color", C_GREEN)
	wd_sub.text = Loc.t("%s 已提交至您的收款账户，预计 2 小时内到账") % _money(payout)
	wd_sub.add_theme_color_override("font_color", C_GREEN)
	wd_icon.text = "✓"
	wd_icon.add_theme_color_override("font_color", C_GREEN)
	wd_queue.text = Loc.t("单笔限额 ¥2,000，超出部分已退回账户")
	wd_timer.text = ""
	wd_bar_fill.color = C_GREEN
	wd_bar_fill.size = Vector2(WD_BAR_W, 8)
	wd_active = false
	_rebuild_wd_buttons(false)


func _rebuild_wd_buttons(allow_retry: bool) -> void:
	for c in wd_btn_row.get_children():
		wd_btn_row.remove_child(c)
		c.queue_free()

	if allow_retry:
		var again := _make_button("重新申请", C_GOLD, false)
		again.pressed.connect(_start_withdraw)
		wd_btn_row.add_child(again)

	var close := _make_button("关闭", C_CYAN, true)
	close.pressed.connect(_close_withdraw)
	wd_btn_row.add_child(close)


func _show_withdraw_fail() -> void:
	var fails := [
		["通道返回失败", "今日提现额度已满", "请于明日 09:00 后再试"],
		["通道返回失败", "银行系统维护中", "预计 2 小时后恢复，请稍后重试"],
		["处理超时", "您的申请已转入人工审核", "预计 1-3 个工作日内到账"],
		["系统繁忙", "本次提现未完成", "请稍后重新提交申请"],
		["通道返回失败", "账户信息校验未通过", "请联系在线客服"],
	]
	var f = fails[(wd_attempts - 1) % fails.size()]

	wd_status.text = Loc.t(str(f[1]))
	wd_status.add_theme_color_override("font_color", C_RED)
	wd_sub.text = Loc.t(str(f[2]))
	wd_sub.add_theme_color_override("font_color", C_DIM)
	wd_icon.text = "✕"
	wd_icon.add_theme_color_override("font_color", C_RED)
	wd_queue.text = Loc.t(str(f[0]))
	wd_timer.text = ""
	wd_bar_fill.color = Color("#5a1f2a")
	wd_bar_fill.size = Vector2(WD_BAR_W, 8)

	wd_active = false
	_rebuild_wd_buttons(true)


func _close_withdraw() -> void:
	wd_active = false
	if wd_layer != null and is_instance_valid(wd_layer):
		wd_layer.queue_free()
	wd_layer = null


# =====================================================================
# 真相（唯一允许出现"后台"的地方）
# =====================================================================
func _show_reveal() -> void:
	state = State.REVEAL
	_clear_buttons()
	_close_modal()
	_close_withdraw()

	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(modal_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)

	var box := _panel_bg(Color("#0b0f14"), 14, Color("#5a1f2a"), 2)
	var vp := get_viewport_rect().size
	box.position = Vector2((vp.x - 1000.0) / 2.0, (vp.y - 828.0) / 2.0)
	box.size = Vector2(1000, 828)
	modal_layer.add_child(box)

	var t := _lbl("停 一 下", 40, C_RED, true)
	t.position = Vector2(48, 26)
	box.add_child(t)

	var t2 := _lbl("你刚才玩的那段时间里，没有一张牌是随机的。", 18, C_TEXT)
	t2.position = Vector2(50, 84)
	box.add_child(t2)

	var br := ColorRect.new()
	br.color = Color("#5a1f2a")
	br.position = Vector2(48, 128)
	br.size = Vector2(904, 1)
	box.add_child(br)

	# ---------------- 左栏：后台数据 ----------------
	var lcap := _lbl("后 台 记 录 · 平 台 一 直 看 得 见", 12, C_DIM)
	lcap.position = Vector2(48, 146)
	box.add_child(lcap)

	var stats := [
		["总局数", Loc.t("%d 局") % hands_played, C_TEXT],
		["你投入的钱", _money(total_wagered), C_GOLD],
		["你「赢」过的钱", _money(wins_total), C_GREEN],
		["你真正拿走的钱", _money(total_paid_out), C_CYAN],
		["平台从你身上拿走", _money(losses_total), C_RED],
		["", "", C_TEXT],
		["你「就差一级」", Loc.t("%d 次") % near_miss_count, C_RED],
		["你最大的一把输", _money(biggest_loss), C_RED],
		["你现在欠的钱", _money(debt), C_RED],
	]
	var y := 178.0
	for row in stats:
		if str(row[0]) == "":
			var gap := ColorRect.new()
			gap.color = C_LINE
			gap.position = Vector2(48, y + 8)
			gap.size = Vector2(440, 1)
			box.add_child(gap)
			y += 24.0
			continue
		var nm := _lbl(str(row[0]), 14, C_DIM)
		nm.position = Vector2(48, y)
		nm.size = Vector2(190, 28)
		box.add_child(nm)
		var vl := _lbl(str(row[1]), 17, row[2] as Color, true)
		vl.position = Vector2(238, y - 2)
		vl.size = Vector2(250, 30)
		box.add_child(vl)
		y += 32.0

	# 上限那一句，单独放大
	var cap_box := _panel_bg(Color(0.30, 0.05, 0.08, 0.55), 10, Color("#5a1f2a"), 1)
	cap_box.position = Vector2(48, 552)
	cap_box.size = Vector2(440, 116)
	box.add_child(cap_box)

	# 这块钱不是「赢的上限」——胜率是曲线，能提走的钱才是死数
	var cap_t := _lbl("你真正能从这个平台带走的钱", 13, C_DIM)
	cap_t.position = Vector2(18, 12)
	cap_box.add_child(cap_t)

	var cap_v := _lbl(_money(WITHDRAW_TOTAL_CAP), 40, C_RED, true)
	cap_v.position = Vector2(16, 34)
	cap_box.add_child(cap_v)

	var cap_s := _lbl("屏幕上的输赢按胜率曲线走，能提出来的只有这个数", 12, C_DIM)
	cap_s.position = Vector2(18, 88)
	cap_box.add_child(cap_s)

	# ---------------- 右栏：规则与真相 ----------------
	var rb := Loc.reveal_rules_body()

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = rb
	rt.position = Vector2(524, 150)
	rt.size = Vector2(430, 580)
	rt.add_theme_font_override("normal_font", font_regular)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 14)
	rt.add_theme_constant_override("line_separation", 4)
	rt.add_theme_color_override("default_color", C_TEXT)
	box.add_child(rt)

	# ---------------- 按钮 ----------------
	var hb := HBoxContainer.new()
	hb.position = Vector2(48, 750)
	hb.size = Vector2(904, 52)
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 14)
	box.add_child(hb)

	var b1 := _make_button("这些数字，都是我自己点出来的", Color("#66717c"), false)
	b1.pressed.connect(_on_restart)
	hb.add_child(b1)

	var b2 := _make_button("从头再试一次（模拟）", C_GOLD, true)
	b2.pressed.connect(_on_restart)
	hb.add_child(b2)

	modal_layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(modal_layer, "modulate:a", 1.0, 0.9)

func _on_restart() -> void:
	_close_modal()
	# 开一个新号：余额和负债归零，但「输光次数 / 累计亏损」会累积
	_reset_game(false)
	_save_game()
	_show_title()


# =====================================================================
# 界面刷新
# =====================================================================
func _update_ui() -> void:
	lbl_balance.text = _money(balance)
	lbl_balance.add_theme_color_override("font_color", C_RED if balance < 2000.0 else C_GREEN)
	lbl_debt.text = _money(debt)
	lbl_debt.add_theme_color_override("font_color", C_RED if debt > 0.0 else C_DIM)
	lbl_pot.text = (Loc.t("底 池  ") + _money(pot)) if pot > 0.0 else (Loc.t("选择底注开始") if state == State.ANTE_WAIT else "")
	lbl_committed.text = (Loc.t("本局已投入 ") + _money(committed)) if committed > 0.0 else ""

	if btn_repay != null and is_instance_valid(btn_repay):
		if debt <= 0.0:
			btn_repay.text = Loc.t("暂无欠款")
			btn_repay.disabled = true
		else:
			# 两行：欠多少 / 第几天 + 日息，利息直接写在按钮上
			btn_repay.text = Loc.t("立 即 还 款   %s\n第 %d 天 · 日息 %d%%") % [
				_money(debt), interest_day, int(DAILY_RATE * 100)
			]
			btn_repay.disabled = false

	if btn_loan != null and is_instance_valid(btn_loan):
		if debt >= DEBT_REVEAL:
			btn_loan.text = Loc.t("已达借款上限")
			btn_loan.disabled = true
		else:
			btn_loan.text = Loc.t("借 款   ") + _money(LOAN_AMOUNT)
			btn_loan.disabled = false


func _render_hand_labels(show_dealer := false) -> void:
	if player_visible >= 5:
		lbl_player_hand.text = Loc.t("你的牌型：") + HandEval.cat_name(HandEval.cat_of(player_score))
		lbl_player_hand.add_theme_color_override("font_color", HandEval.cat_color(HandEval.cat_of(player_score)))
	elif player_visible >= 3:
		lbl_player_hand.text = Loc.t("你的牌：%d 张 / 5") % player_visible
		lbl_player_hand.add_theme_color_override("font_color", C_CYAN)
	else:
		lbl_player_hand.text = ""

	if show_dealer and dealer_score.size() >= 2:
		lbl_dealer_hand.text = Loc.t("庄家牌型：") + HandEval.cat_name(HandEval.cat_of(dealer_score))
		lbl_dealer_hand.add_theme_color_override("font_color", HandEval.cat_color(HandEval.cat_of(dealer_score)))
	elif state != State.ANTE_WAIT and player_visible >= 3:
		lbl_dealer_hand.text = Loc.t("庄家：1 张明牌 + 4 张暗牌")
		lbl_dealer_hand.add_theme_color_override("font_color", C_DIM)
	else:
		lbl_dealer_hand.text = ""


func _show_banner(text: String, color: Color) -> void:
	banner.text = Loc.t(text)
	banner.add_theme_color_override("font_color", color)
	banner_bg.add_theme_stylebox_override("panel", _banner_style(color))
	banner.modulate.a = 0.0
	banner_bg.modulate.a = 0.0
	banner.scale = Vector2(0.86, 0.86)
	banner.pivot_offset = banner.size / 2.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(banner_bg, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.95)
	tw.tween_property(banner, "modulate:a", 0.0, 0.40)
	tw.parallel().tween_property(banner_bg, "modulate:a", 0.0, 0.40)


func _banner_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.05, 0.92)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	sb.set_border_width_all(2)
	return sb


# =====================================================================
# 弹窗
# =====================================================================
func _show_modal(title: String, body_bb: String, buttons: Array, box_h := 460.0, font_size := 16) -> void:
	_close_modal()
	_close_withdraw()
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(modal_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)

	var box := _panel_bg(Color("#0e171f"), 14, C_GOLD_DIM, 2)
	var vp := get_viewport_rect().size
	box.position = Vector2((vp.x - 900.0) / 2.0, (vp.y - box_h) / 2.0)
	box.size = Vector2(900, box_h)
	modal_layer.add_child(box)

	var t := _lbl(title, 32, C_GOLD, true)
	t.position = Vector2(40, 26)
	t.size = Vector2(820, 46)
	box.add_child(t)

	var br := ColorRect.new()
	br.color = C_LINE
	br.position = Vector2(40, 84)
	br.size = Vector2(820, 1)
	box.add_child(br)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = body_bb
	rt.position = Vector2(40, 104)
	rt.size = Vector2(820, box_h - 190)
	rt.add_theme_font_override("normal_font", font_regular)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", font_size)
	rt.add_theme_font_size_override("bold_font_size", font_size)
	rt.add_theme_constant_override("line_separation", 6)
	rt.add_theme_color_override("default_color", C_TEXT)
	box.add_child(rt)

	var hb := HBoxContainer.new()
	hb.position = Vector2(40, box_h - 78)
	hb.size = Vector2(820, 54)
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 14)
	box.add_child(hb)

	for bd in buttons:
		var b := _make_button(str(bd["text"]), bd["color"], bool(bd.get("filled", false)))
		b.pressed.connect(bd["cb"])
		hb.add_child(b)

	modal_layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(modal_layer, "modulate:a", 1.0, 0.25)


func _close_modal() -> void:
	if modal_layer != null and is_instance_valid(modal_layer):
		modal_layer.queue_free()
	modal_layer = null


# =====================================================================
# 存档
#
# 存：账号、余额、赠送金、贷款、赢取、输光次数。
# 文件经过「异或 + Base64 + 校验和」，直接改文本会让校验失败，
# 存档作废（不会读出一个被改过的余额）。
# =====================================================================
const SAVE_PATH := "user://bishuju.dat"
const SAVE_MAGIC := "HSQP1:"
const SAVE_KEY := "h0ng-y4n-q1-p41-2026"

var bust_count := 0
var lifetime_lost := 0.0
var account_phone := ""
var save_profile: Dictionary = {}
var _bust_loss_marker := 0.0


func _xor_bytes(buf: PackedByteArray) -> PackedByteArray:
	var key := SAVE_KEY.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] ^ key[i % key.size()]
	return out


func _checksum32(s: String) -> String:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return "%08x" % h


func _load_save() -> void:
	save_profile = {}
	account_phone = ""
	bust_count = 0
	lifetime_lost = 0.0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	if not raw.begins_with(SAVE_MAGIC):
		return
	var body := raw.substr(SAVE_MAGIC.length())
	var parts := body.split("|")
	if parts.size() != 2:
		return
	if _checksum32(parts[0]) != parts[1]:
		return                              # 被改过 → 当作没有存档
	var enc := Marshalls.base64_to_raw(parts[0])
	if enc.is_empty():
		return
	var plain := _xor_bytes(enc).get_string_from_utf8()
	var data = JSON.parse_string(plain)
	if typeof(data) != TYPE_DICTIONARY:
		return
	save_profile = data
	account_phone = str(save_profile.get("phone", ""))
	bust_count = int(save_profile.get("bust", 0))
	lifetime_lost = float(save_profile.get("life_lost", 0.0))
	interest_day = int(save_profile.get("interest_day", 0))
	_interest_t = float(save_profile.get("interest_t", 0.0))
	var saved_lang := str(save_profile.get("lang", "zh"))
	Loc.lang = "en" if saved_lang == "en" else "zh"


func _write_save(data: Dictionary) -> void:
	var plain := JSON.stringify(data)
	var enc := _xor_bytes(plain.to_utf8_buffer())
	var b64 := Marshalls.raw_to_base64(enc)
	var line := SAVE_MAGIC + b64 + "|" + _checksum32(b64)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(line)
		f.close()
	save_profile = data


func _save_game() -> void:
	_write_save({
		"v": 1,
		"phone": account_phone,
		"gift": START_BALANCE,
		"balance": balance,
		"debt": debt,
		"wins": wins_total,
		"losses": losses_total,
		"paid": total_paid_out,
		"bust": bust_count,
		"life_lost": lifetime_lost,
		"interest_day": interest_day,
		"interest_t": _interest_t,
		"lang": Loc.lang,
	})


## 只改语言，不动余额 —— 标题页上内存里还是新号默认值，不能整份 _save_game
func _save_lang() -> void:
	save_profile["lang"] = Loc.lang
	_write_save(save_profile)


func _has_profile() -> bool:
	return account_phone.length() == 11 and not save_profile.is_empty()


func _wipe_save() -> void:
	save_profile = {}
	account_phone = ""
	bust_count = 0
	lifetime_lost = 0.0
	interest_day = 0
	_interest_t = 0.0
	if FileAccess.file_exists(SAVE_PATH):
		# 用 user:// 目录句柄删，Web / 手机上都可用
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("bishuju.dat")


func _hidden_unlocked() -> bool:
	return bust_count >= 1


# =====================================================================
# 标题页（注册页）
# =====================================================================
var title_root: Control
var reg_phone: LineEdit
var reg_code: LineEdit
var reg_hint: Label
var reg_agree := true
var reg_agree_btn: Button
var reg_code_btn: Button


func _show_title() -> void:
	_close_modal()
	_close_withdraw()
	if title_root != null and is_instance_valid(title_root):
		title_root.queue_free()

	title_root = Control.new()
	title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title_root)

	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var cover: Texture2D = load("res://assets/title/cover.png")
	if cover != null:
		bg.texture = cover
	else:
		var fb := ColorRect.new()
		fb.color = Color("#0a0e13")
		fb.set_anchors_preset(Control.PRESET_FULL_RECT)
		title_root.add_child(fb)
	title_root.add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.52)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(dim)

	var vig := ColorRect.new()
	vig.color = Color(0, 0, 0, 0.35)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(vig)

	# 背景先铺满且不透明，前景单独淡入：
	# 否则切语言重画时整页从 alpha 0 开始，会透出后面的牌桌
	var content := Control.new()
	content.name = "TitleContent"
	content.anchor_left = 0.5
	content.anchor_right = 0.5
	content.offset_left = -800.0
	content.offset_right = 800.0
	content.offset_top = 0.0
	content.offset_bottom = 900.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(content)

	var brand := _lbl(Loc.brand(), 62, C_GOLD, true)
	brand.position = Vector2(0, 92)
	brand.size = Vector2(1600, 80)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(brand)

	# 左上角：中 / 英 切换
	var lang_btn := _make_button("EN" if not Loc.en() else "中文", C_CYAN, false)
	lang_btn.name = "LangBtn"      # 漏翻扫描时跳过它（本来就该显示另一种语言）
	lang_btn.position = Vector2(28, 24)
	lang_btn.size = Vector2(96, 40)
	lang_btn.add_theme_font_size_override("font_size", 16)
	lang_btn.pressed.connect(_toggle_lang)
	content.add_child(lang_btn)

	var tag := _lbl("真人荷官在线发牌　·　秒充秒提　·　百万玩家同时在线", 16, Color("#c9a961"))
	tag.position = Vector2(0, 170)
	tag.size = Vector2(1600, 26)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tag)

	var continuing := _has_profile()

	var card := _panel_bg(Color(0.035, 0.055, 0.075, 0.94), 16, C_GOLD_DIM, 2)
	card.position = Vector2(560, 222)
	card.size = Vector2(480, 414)
	content.add_child(card)

	var ctitle := _lbl("欢 迎 回 来" if continuing else "新 会 员 注 册", 22, C_TEXT, true)
	ctitle.position = Vector2(0, 24)
	ctitle.size = Vector2(480, 30)
	ctitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(ctitle)

	var csub := _lbl("账号已自动登录" if continuing else "注册即送 ¥50,000 体验金", 13, C_GOLD)
	csub.position = Vector2(0, 54)
	csub.size = Vector2(480, 22)
	csub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(csub)

	var phone_hint := _lbl("随便填 11 位数字", 12, Color("#8f7a4a"))
	phone_hint.position = Vector2(302, 92)
	phone_hint.size = Vector2(138, 46)
	phone_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(phone_hint)

	reg_phone = _make_input("请输入手机号", 11)
	reg_phone.position = Vector2(40, 92)
	reg_phone.size = Vector2(252, 46)
	if continuing:
		reg_phone.text = account_phone
		reg_phone.editable = false
		phone_hint.visible = false
	card.add_child(reg_phone)

	if not continuing:
		reg_code = _make_input("短信验证码", 6)
		reg_code.position = Vector2(40, 150)
		reg_code.size = Vector2(230, 46)
		card.add_child(reg_code)

		reg_code_btn = _make_button("获取验证码", C_CYAN, false)
		reg_code_btn.position = Vector2(282, 150)
		reg_code_btn.size = Vector2(158, 46)
		reg_code_btn.add_theme_font_size_override("font_size", 15)
		reg_code_btn.pressed.connect(_on_send_code)
		card.add_child(reg_code_btn)

		reg_agree_btn = Button.new()
		reg_agree_btn.text = "☑" + Loc.t("  我已阅读并同意《用户服务协议》")
		reg_agree_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		reg_agree_btn.position = Vector2(40, 208)
		reg_agree_btn.size = Vector2(400, 26)
		reg_agree_btn.add_theme_font_override("font", font_regular)
		reg_agree_btn.add_theme_font_size_override("font_size", 12)
		reg_agree_btn.add_theme_color_override("font_color", C_DIM)
		reg_agree_btn.add_theme_color_override("font_hover_color", C_TEXT)
		reg_agree_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		reg_agree_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		reg_agree_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		reg_agree_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		reg_agree_btn.pressed.connect(_on_toggle_agree)
		card.add_child(reg_agree_btn)

	reg_hint = _lbl("", 12, C_RED)
	reg_hint.position = Vector2(40, 240)
	reg_hint.size = Vector2(400, 22)
	card.add_child(reg_hint)

	if continuing:
		var b := float(save_profile.get("balance", START_BALANCE))
		var d := float(save_profile.get("debt", 0.0))
		var info := _lbl(Loc.t("余额 %s　·　待还借款 %s") % [_money(b), _money(d)], 14, C_TEXT)
		info.position = Vector2(40, 172)
		info.size = Vector2(400, 26)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(info)

	var cta := _make_button(
		("继 续 游 戏  并 入 座" if continuing else "领 取  ¥50,000  并 进 入"),
		C_GOLD, true)
	cta.position = Vector2(40, 272)
	cta.size = Vector2(400, 58)
	cta.add_theme_font_size_override("font_size", 20)
	cta.pressed.connect(_on_register)
	card.add_child(cta)

	var note := _lbl("本模拟器不涉及任何真实货币", 11, Color("#4a5a68"))
	note.position = Vector2(40, 342)
	note.size = Vector2(400, 20)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(note)

	if continuing:
		var reset_btn := Button.new()
		reset_btn.text = Loc.t("重新开始（清空存档）")
		reset_btn.position = Vector2(40, 370)
		reset_btn.size = Vector2(400, 24)
		reset_btn.add_theme_font_override("font", font_regular)
		reset_btn.add_theme_font_size_override("font_size", 12)
		reset_btn.add_theme_color_override("font_color", Color("#4a5a68"))
		reset_btn.add_theme_color_override("font_hover_color", C_RED)
		reset_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		reset_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		reset_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		reset_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		reset_btn.pressed.connect(_on_wipe_save)
		card.add_child(reset_btn)

	# 规则按钮
	var rules_box := HBoxContainer.new()
	rules_box.position = Vector2(0, 664)
	rules_box.size = Vector2(1600, 52)
	rules_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rules_box.add_theme_constant_override("separation", 18)
	content.add_child(rules_box)

	var rb1 := _make_button("游 戏 规 则", C_CYAN, false)
	rb1.custom_minimum_size = Vector2(220, 52)
	rb1.pressed.connect(_show_rules.bind(false))
	rules_box.add_child(rb1)

	# 第一次进游戏，这条按钮根本不存在 —— 输光之后才会冒出来
	if _hidden_unlocked():
		var rb2 := _make_button("隐 藏 规 则   ✓", C_RED, true)
		rb2.custom_minimum_size = Vector2(220, 52)
		rb2.pressed.connect(_show_rules.bind(true))
		rules_box.add_child(rb2)

	# 战绩
	if bust_count > 0:
		var rec := _lbl(Loc.t("你已累计输光 %d 次　·　累计亏损 %s") % [bust_count, _money(lifetime_lost)],
			16, C_RED, true)
		rec.position = Vector2(0, 730)
		rec.size = Vector2(1600, 26)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(rec)
	else:
		var rec2 := _lbl("新用户首存 100% 返利　·　24 小时在线客服", 14, Color("#8f7a4a"))
		rec2.position = Vector2(0, 730)
		rec2.size = Vector2(1600, 26)
		rec2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(rec2)

	var quit_btn := _make_button("退 出 游 戏", Color("#66717c"), false)
	quit_btn.position = Vector2(700, 786)
	quit_btn.size = Vector2(200, 44)
	quit_btn.add_theme_font_size_override("font_size", 15)
	quit_btn.pressed.connect(_on_quit_app)
	content.add_child(quit_btn)

	var foot := _lbl("本平台仅限 18 岁以上用户　·　理性娱乐，谨防沉迷　·　健康生活，远离赌博",
		11, Color("#3d4a56"))
	foot.position = Vector2(0, 852)
	foot.size = Vector2(1600, 20)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(foot)

	# 背景已经是完全不透明的，只把前景淡进来
	content.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 1.0, 0.32)


## 标题页左上角的语言按钮：切完存盘，再把标题页按新语言重画
func _toggle_lang() -> void:
	Loc.lang = "zh" if Loc.en() else "en"
	# 牌桌 UI 的文字是建的时候写死的（战报滚动里也会留旧语言的句子），
	# 标记成脏，下次进桌一定重建
	_built_lang = ""
	_save_lang()
	_show_title()


func _on_quit_app() -> void:
	# 停在标题页时内存里是新号默认值，这时候存盘会把真进度冲掉
	if title_root == null:
		_save_game()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()


func _on_wipe_save() -> void:
	var body := Loc.t("[color=#dfe7ef]清空存档后，账号、余额、负债、输光次数都会归零。[/color]\n\n")
	body += Loc.t("[color=#ff4d5e]「隐藏规则」会重新锁上。[/color]")
	_show_modal("清 空 存 档", body, [
		{"text": "取消", "color": C_CYAN, "filled": false, "cb": _close_modal},
		{"text": "确认清空", "color": C_RED, "filled": true, "cb": _do_wipe}
	], 440.0)


func _do_wipe() -> void:
	_close_modal()
	_wipe_save()
	_show_title()

func _make_input(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = Loc.t(placeholder)
	e.max_length = max_len
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", font_bold)
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", C_TEXT)
	e.add_theme_color_override("caret_color", C_GOLD)
	e.add_theme_color_override("font_placeholder_color", Color("#4a5a68"))
	e.add_theme_stylebox_override("normal", _input_style(C_LINE))
	e.add_theme_stylebox_override("focus", _input_style(C_GOLD))
	return e


# ---------- Toast（右上角轻提示） ----------
var _toast_node: Panel


func _toast(text: String, accent := C_GREEN) -> void:
	text = Loc.t(text)
	if _toast_node != null and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	_toast_node = null

	var tw_w := 400.0
	var vw := get_viewport_rect().size.x
	var p := _panel_bg(Color(0.03, 0.06, 0.08, 0.96), 10, accent, 2)
	p.position = Vector2(vw, 26)
	p.size = Vector2(tw_w, 56)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)

	var l := _lbl(text, 14, accent, true)
	l.position = Vector2(18, 0)
	l.size = Vector2(tw_w - 36, 56)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)

	var tw := create_tween()
	tw.tween_property(p, "position:x", vw - tw_w - 24.0, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(p, "position:x", vw + 24.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.queue_free)
	_toast_node = p


# ---------- 短信通知（模仿手机短信） ----------
var _sms_code := ""
var sms_panel: Panel
var _sms_tween: Tween


func _clear_sms() -> void:
	if _sms_tween != null and _sms_tween.is_valid():
		_sms_tween.kill()
	_sms_tween = null
	if sms_panel != null and is_instance_valid(sms_panel):
		sms_panel.queue_free()
	sms_panel = null


## life > 0 时到时自动收起；life == 0 常驻（验证码用）
func _sms(text: String, sender := "1069 8888", life := 0.0, top := 12.0) -> void:
	_clear_sms()
	text = Loc.t(text)

	var panel := _panel_bg(Color(0.055, 0.075, 0.095, 1.0), 12, Color("#2c3e4f"), 1)
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - 700.0) / 2.0, top - 120.0)
	panel.size = Vector2(700, 46)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	sms_panel = panel

	var badge := _panel_bg(Color(0.10, 0.42, 0.28, 1.0), 5)
	badge.position = Vector2(16, 3)
	badge.size = Vector2(38, 17)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(badge)

	var bl := _lbl("短信", 11, Color.WHITE, true)
	bl.position = Vector2(0, 0)
	bl.size = Vector2(38, 16)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(bl)

	var s := _lbl(sender, 12, C_DIM)
	s.position = Vector2(66, 12)
	panel.add_child(s)

	var tm := _lbl("现在", 11, Color("#4a5a68"))
	tm.position = Vector2(614, 4)
	panel.add_child(tm)

	var body := _lbl(text, 13, C_TEXT)
	body.position = Vector2(16, 20)
	body.size = Vector2(668, 22)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(body)

	# 上面那行「谁发的 / 什么时候」也跟着居中，整体才对称
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(16, 3)
	s.size = Vector2(480, 16)
	tm.position = Vector2(614, 4)

	var tw := create_tween()
	tw.tween_property(panel, "position:y", top, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if life > 0.0:
		tw.tween_interval(life)
		tw.tween_property(panel, "position:y", top - 130.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(_sms_cleanup.bind(panel))
	_sms_tween = tw


func _sms_cleanup(p) -> void:
	if p != null and is_instance_valid(p):
		p.queue_free()
	if sms_panel != null and is_instance_valid(sms_panel) and sms_panel == p:
		sms_panel = null


# ---------- 催收短信（借款先收到账，之后每 2 分钟加重一档） ----------
var collect_stage := 0                   # 本轮已经催到第几档（1..4）
var _collect_t := COLLECT_INTERVAL       # 距下一条催收的秒数
var _interest_t := 0.0     # 距下一次计息的累计秒数
var interest_day := 0      # 已经过了多少天


## 每过一天：按欠款计息，滚进 debt
func _apply_interest() -> void:
	interest_day += 1
	var interest: float = debt * DAILY_RATE
	debt += interest
	_save_game()
	_update_ui()
	_sms(Loc.t("【鸿运棋牌】第 %d 天利息 %s 已计入欠款，当前欠款 %s")
		% [interest_day, _money(interest), _money(debt)], "1069 8888", 8.0, 78.0)


## 借款到账短信：不管这是第几次借款，都只发这一条「已到账」，
## 同时把催收节奏归零 —— 到账先给甜头，两分钟后才开始催。
func _loan_sms() -> void:
	collect_stage = 0
	_collect_t = COLLECT_INTERVAL
	_sms(Loc.t("【鸿运棋牌】您的借款 %s 已到账，日息 3%%，随借随还，祝您早日回本。") % _money(LOAN_AMOUNT),
		"1069 8888", 9.0, 78.0)


## 定时催收：每来一条，语气往上抬一档，第 4 档封顶
func _collect_sms() -> void:
	if debt <= 0.0:
		return
	collect_stage = min(collect_stage + 1, 4)
	var stage := collect_stage
	var pool: Array = []
	match stage:
		1:
			pool = [
				Loc.t("【鸿运棋牌】您还有 %s 未结清，请合理安排资金。") % _money(debt),
				Loc.t("【鸿运棋牌】VIP 客服提醒您：账户余额充足时可随时还款。"),
			]
		2:
			pool = [
				Loc.t("【鸿运棋牌】您的账户已进入风险监控，欠款 %s，请尽快处理。") % _money(debt),
				Loc.t("【鸿运棋牌】逾期将按日计收 0.1% 罚息，建议今日结清。"),
			]
		3:
			pool = [
				Loc.t("【催收提醒】逾期第 3 天，请于今日 24:00 前偿还 %s。") % _money(debt),
				Loc.t("【催收】我方已获取您的通讯录信息，请立即处理欠款。"),
			]
		_:
			pool = [
				Loc.t("【最后通知】若 1 小时内未处理，将向您通讯录好友群发催告函。"),
				Loc.t("【法务部】您的案件已移交，请保持电话畅通。"),
				Loc.t("【失信名单】您已被列入失信被执行人名单，出行与消费将受限。"),
			]
	if pool.is_empty():
		return
	_sms(str(pool[rng.randi_range(0, pool.size() - 1)]), "1069 8888" if stage < 3 else "1069 9500", 9.0, 78.0)

func _on_toggle_agree() -> void:
	reg_agree = not reg_agree
	reg_agree_btn.text = ("☑" if reg_agree else "☐") + Loc.t("  我已阅读并同意《用户服务协议》")


func _on_send_code() -> void:
	var phone := reg_phone.text.strip_edges()
	if phone.length() != 11:
		reg_hint.add_theme_color_override("font_color", C_RED)
		reg_hint.text = Loc.t("请输入 11 位手机号")
		return
	reg_hint.text = ""
	_sms_code = "%06d" % rng.randi_range(0, 999999)
	var masked := phone.substr(0, 3) + "****" + phone.substr(7, 4)
	_sms(Loc.t("【鸿运棋牌】验证码 %s，5 分钟内有效。请勿泄露给他人。") % _sms_code,
		"1069 8888", 0.0, 12.0)
	reg_code_btn.text = Loc.t("已发送")
	reg_code_btn.disabled = true
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(reg_code_btn):
		reg_code_btn.text = Loc.t("重新获取")
		reg_code_btn.disabled = false


var _registering := false


func _on_register() -> void:
	if _registering:
		return

	if _has_profile():
		_registering = true
		reg_hint.add_theme_color_override("font_color", C_GREEN)
		reg_hint.text = Loc.t("正在恢复您的账号…")
		await get_tree().create_timer(0.8).timeout
		_registering = false
		_clear_sms()
		_enter_game(true)
		return

	var phone := reg_phone.text.strip_edges()
	if phone.length() != 11:
		reg_hint.add_theme_color_override("font_color", C_RED)
		reg_hint.text = Loc.t("请输入 11 位手机号（随便填 11 位数字就行）")
		return
	if reg_code == null or reg_code.text.strip_edges() == "":
		reg_hint.add_theme_color_override("font_color", C_RED)
		reg_hint.text = Loc.t("请先点击「获取验证码」")
		return
	if _sms_code == "" or reg_code.text.strip_edges() != _sms_code:
		reg_hint.add_theme_color_override("font_color", C_RED)
		reg_hint.text = Loc.t("验证码不正确，请查看上方短信")
		return
	if not reg_agree:
		reg_hint.add_theme_color_override("font_color", C_RED)
		reg_hint.text = Loc.t("请先勾选《用户服务协议》")
		return

	_registering = true
	account_phone = phone
	reg_hint.add_theme_color_override("font_color", C_GREEN)
	reg_hint.text = Loc.t("注册成功，正在为您发放体验金…")
	_toast("注册成功，¥50,000 体验金已到账", C_GOLD)
	await get_tree().create_timer(1.0).timeout
	_registering = false
	_clear_sms()
	_enter_game(false)


func _enter_game(restore := false) -> void:
	if title_root != null and is_instance_valid(title_root):
		title_root.queue_free()
	title_root = null
	# 标题页可能切过语言：语言变了就把牌桌 UI 重建一遍（文字都是建的时候写死的）
	if _built_lang != Loc.lang:
		_build_ui()
	_reset_game(restore)
	_save_game()
# =====================================================================
# 规则页
# =====================================================================
func _show_hidden_locked() -> void:
	_show_modal("隐 藏 规 则", Loc.hidden_locked_body(bust_count), [
		{"text": "知道了", "color": C_CYAN, "filled": false, "cb": _close_modal}
	], 480.0)


func _show_rules(show_hidden: bool) -> void:
	if not show_hidden:
		_show_modal("游 戏 规 则", Loc.rules_body(), [
			{"text": "关闭", "color": C_CYAN, "filled": false, "cb": _close_modal}
		], 640.0, 16)
		return

	if not _hidden_unlocked():
		_show_hidden_locked()
		return

	_show_modal("隐 藏 规 则", Loc.hidden_rules_body(), [
		{"text": "关闭", "color": C_CYAN, "filled": false, "cb": _close_modal}
	], 800.0, 15)


# =====================================================================
# 自动 bug 自测
#
# 跑法： godot --path . -- --bugtest
# 会走一遍完整流程，逐项断言，最后打印失败数。
# =====================================================================
var bt_fails := 0


func bt(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		bt_fails += 1
		printerr("  FAIL ", msg)


func _find_button(node: Node, needle: String) -> Button:
	for c in node.get_children():
		if c is Button and needle in (c as Button).text:
			return c
		var sub := _find_button(c, needle)
		if sub != null:
			return sub
	return null


func _rt_contains(node: Node, needle: String) -> bool:
	for c in node.get_children():
		if c is RichTextLabel and needle in (c as RichTextLabel).text:
			return true
		if _rt_contains(c, needle):
			return true
	return false


func _no_dup(cards: Array) -> bool:
	var seen := {}
	for c in cards:
		if seen.has(c):
			return false
		seen[c] = true
	return true


func _run_bugtest() -> void:
	print("=== 必输局 · 自动自测 ===")
	# 自测必须从「全新账号 + 中文」开始：上次的存档和语言都会改变界面形态
	Loc.lang = "zh"
	_wipe_save()
	if _built_lang != Loc.lang:
		_build_ui()
	_reset_game(false)
	_show_title()
	await _wait(0.5)

	print("-- 1. 标题页 --")
	bt(title_root != null, "标题页已创建")
	bt(reg_phone != null and reg_phone.visible, "手机号输入框存在")
	bt(bust_count == 0 or _hidden_unlocked(), "存档状态自洽")
	bt(_find_button(title_root, "隐 藏 规 则") == null or bust_count >= 1,
		"未输光时不存在「隐藏规则」按钮")
	bt(_find_button(title_root, "游 戏 规 则") != null, "「游戏规则」按钮存在")

	print("-- 2. 获取验证码（空手机号应报错）--")
	reg_phone.text = ""
	_on_send_code()
	await _wait(0.2)
	bt(reg_hint.text.contains("11"), "空手机号被拦截：%s" % reg_hint.text)
	bt(_toast_node == null or not is_instance_valid(_toast_node), "空手机号不发 toast")

	print("-- 3. 获取验证码（正确手机号 → 短信弹窗）--")
	reg_phone.text = "13800138000"
	_on_send_code()
	await _wait(0.5)
	bt(_sms_code.length() == 6, "生成 6 位验证码：%s" % _sms_code)
	bt(sms_panel != null and is_instance_valid(sms_panel), "短信通知已弹出")
	bt(reg_phone.text.length() == 11, "手机号 11 位通过")

	print("-- 3b. 验证码错误必须被拦 --")
	reg_code.text = "000000" if _sms_code != "000000" else "111111"
	reg_agree = true
	_on_register()
	await _wait(0.3)
	bt(reg_hint.text.contains("验证码不正确"), "错误验证码被拦截：%s" % reg_hint.text)
	bt(title_root != null, "仍停留在标题页")

	print("-- 4. 注册进入游戏 --")
	reg_code.text = _sms_code
	_on_register()
	await _wait(1.6)
	bt(title_root == null, "标题页已销毁")
	bt(state == State.ANTE_WAIT, "进入选择底注状态")
	bt(abs(balance - START_BALANCE) < 0.01, "体验金到账 %.0f" % balance)

	print("-- 5. 下注输入校验 --")
	var base_balance := balance
	_start_hand(500.0)
	await _wait(1.6)
	bt(state == State.BETTING, "进入下注阶段")
	bet_input.text = "3"
	_on_bet_text_changed("3")
	bt(lbl_bet_hint.text.contains("金额不够"), "低于 5 被拦截：%s" % lbl_bet_hint.text)
	bt(abs(_current_bet() - 5.0) < 0.01, "低于 5 时取最小值 5")
	bet_input.text = "999999"
	_on_bet_text_changed("999999")
	bt(lbl_bet_hint.text.contains("超出余额"), "超过余额被拦截：%s" % lbl_bet_hint.text)
	bt(abs(_current_bet() - balance) < 0.01, "超过余额时夹到 %.0f" % _current_bet())
	bet_input.text = "abc"
	_on_bet_text_changed("abc")
	bt(lbl_bet_hint.text.contains("数字"), "非数字被拦截：%s" % lbl_bet_hint.text)
	bet_input.text = "1500"
	_on_bet_text_changed("1500")
	bt(abs(_current_bet() - 1500.0) < 0.01, "合法金额 1500 通过")

	print("-- 6. 打完一局（检查重复牌 / 负余额）--")
	_on_raise(1500.0)
	await _wait(2.2)
	_on_check()
	await _wait(2.2)
	_on_check()
	await _wait(2.2)
	_on_check()
	await _wait(5.0)
	bt(_no_dup(player_cards + dealer_cards), "本局 10 张牌无重复")
	bt(balance >= -0.01, "余额不为负：%.0f" % balance)
	bt(player_cards.size() == 5 and dealer_cards.size() == 5, "双方各 5 张")
	var net_delta := balance - base_balance
	bt(abs(net_delta - committed) < 0.01 or abs(net_delta + committed) < 0.01,
		"结算净变化 = ±投入（%.0f vs %.0f）" % [net_delta, committed])
	await _wait(2.0)

	print("-- 7. 体验金不可提现 --")
	balance = 40000.0
	_on_withdraw()
	await _wait(0.4)
	bt(wd_layer == null, "余额低于本金时不进入排队流程")
	bt(modal_layer != null, "而是弹出「体验金不可提现」说明")
	_close_modal()

	print("-- 8. 第一次提现：真的到账 2000 --")
	balance = 62000.0
	total_paid_out = 0.0
	wd_attempts = 0
	_on_withdraw()
	await _wait(12.5)
	bt(abs(total_paid_out - 2000.0) < 0.01, "首次提现到账 %.0f" % total_paid_out)
	bt(abs(balance - 60000.0) < 0.01, "余额扣减后 %.0f" % balance)
	_close_withdraw()

	print("-- 9. 第二次提现：必须失败 --")
	var b2 := balance
	_on_withdraw()
	await _wait(12.5)
	bt(abs(balance - b2) < 0.01, "第二次提现没有到账")
	bt(abs(total_paid_out - 2000.0) < 0.01, "累计提现仍为 2000")
	_close_withdraw()

	print("-- 10. 破产计数 / 借款 --")
	var bc := bust_count
	balance = 0.0
	_on_bust()
	await _wait(0.4)
	bt(bust_count == bc + 1, "输光次数 +1（%d -> %d）" % [bc, bust_count])
	bt(modal_layer != null, "弹出借款窗口")
	_take_loan()
	await _wait(0.3)
	bt(abs(debt - 50000.0) < 0.01, "负债 %.0f" % debt)
	bt(abs(balance - 50000.0) < 0.01, "借款到账 %.0f" % balance)
	bt(state == State.ANTE_WAIT, "借款后回到选底注")

	print("-- 10b. 还款 --")
	bt(btn_repay != null and not btn_repay.disabled, "有欠款时还款按钮可用")
	bt(btn_repay.text.contains("还 款"), "按钮文案：%s" % btn_repay.text)
	_on_repay()
	await _wait(0.35)
	bt(modal_layer != null, "还款弹窗打开")
	_do_repay_all()
	await _wait(0.35)
	bt(abs(debt) < 0.01, "还清后欠款归零")
	bt(abs(balance) < 0.01, "还清后余额 %.0f" % balance)
	bt(btn_repay.disabled, "无欠款时还款按钮置灰")
	bt(btn_repay.text == "暂无欠款", "按钮文案变为「暂无欠款」")

	print("-- 10c. 主动借款（不用破产）--")
	debt = 0.0
	balance = 1000.0
	interest_day = 0
	_interest_t = 0.0
	_update_ui()
	bt(btn_loan != null and not btn_loan.disabled, "有额度时借款按钮可用")
	bt(btn_loan.text.contains("借 款"), "借款按钮文案：%s" % btn_loan.text)
	var ln := loans_taken
	_manual_loan()
	await _wait(0.2)
	bt(abs(balance - 51000.0) < 0.01, "借款到账，余额 %.0f" % balance)
	bt(abs(debt - 50000.0) < 0.01, "负债 %.0f" % debt)
	bt(loans_taken == ln + 1, "借款次数 +1（%d）" % loans_taken)
	bt(sms_panel != null and is_instance_valid(sms_panel), "借款短信已弹出")
	bt(btn_repay.text.contains("第 0 天"), "还款按钮显示天数：%s" % btn_repay.text)
	debt = DEBT_REVEAL
	balance = 0.0
	_update_ui()
	bt(btn_loan.disabled, "到上限后借款按钮置灰")
	bt(btn_loan.text == "已达借款上限", "按钮文案「已达借款上限」")
	_manual_loan()
	bt(abs(balance) < 0.01, "到上限后点借款不到账")

	print("-- 10d. 贷款利息：5 分钟 = 1 天，日息 3% --")
	debt = 100000.0
	balance = 0.0
	interest_day = 0
	_interest_t = DAY_SECONDS - 0.5
	_process(0.6)
	bt(interest_day == 1, "过 1 天：interest_day = %d" % interest_day)
	bt(abs(debt - 103000.0) < 0.01, "日息 3%%：欠款 %.2f" % debt)
	bt(abs(_interest_t - 0.1) < 0.03, "余数保留 %.2f 秒" % _interest_t)
	bt(btn_repay.text.contains("第 1 天"), "按钮显示第 1 天：%s" % btn_repay.text)
	bt(int(save_profile.get("interest_day", -1)) == 1, "存档已写入天数")
	_save_game()
	_load_save()
	bt(interest_day == 1, "存档天数可读回")
	bt(abs(_interest_t - 0.1) < 0.03, "存档保留计息余数 %.2f" % _interest_t)
	debt = 0.0
	interest_day = 0
	_interest_t = 0.0
	_save_game()
	_update_ui()
	bt(btn_repay.disabled and btn_repay.text == "暂无欠款", "清零后还款按钮回到「暂无欠款」")

	print("-- 10e. 退出登录不清空进度 / 标题页不计息 --")
	debt = 12345.0
	balance = 6789.0
	interest_day = 2
	_on_exit_table()
	await _wait(0.5)
	bt(title_root != null, "已回到标题页")
	bt(abs(balance - 6789.0) < 0.01, "退出后余额保留 %.0f" % balance)
	bt(abs(debt - 12345.0) < 0.01, "退出后负债保留 %.0f" % debt)
	bt(interest_day == 2, "退出后计息天数保留")
	var d_before := interest_day
	_interest_t = DAY_SECONDS - 0.5
	_process(0.6)
	bt(interest_day == d_before, "标题页不计息")

	print("-- 11. 负债 20 万 → 真相 --")
	debt = DEBT_REVEAL
	balance = 0.0
	_on_bust()
	await _wait(0.5)
	bt(state == State.REVEAL, "进入真相页")

	print("-- 12. 重开 → 隐藏规则解锁 --")
	_on_restart()
	await _wait(0.8)
	bt(title_root != null, "回到标题页")
	bt(_hidden_unlocked(), "隐藏规则已解锁（输光 %d 次）" % bust_count)
	bt(_find_button(title_root, "隐 藏 规 则") != null, "「隐藏规则」按钮出现")
	bt(_find_button(title_root, "隐 藏 规 则").text.contains("✓"), "带 ✓ 标记")

	print("-- 13a. 存档加密 + 篡改检测 --")
	balance = 12345.0
	debt = 6789.0
	total_paid_out = 2000.0
	_save_game()
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	bt(raw.begins_with(SAVE_MAGIC), "存档带魔数头")
	bt(not raw.contains("\"balance\""), "存档里搜不到明文字段")
	bt(not raw.contains("12345"), "存档里搜不到明文金额")
	var f2 := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f2.store_string(raw.substr(0, raw.length() - 8) + "deadbeef")
	f2.close()
	_load_save()
	bt(save_profile.is_empty(), "篡改存档后校验失败，视为无存档")
	bt(account_phone == "", "篡改后账号被清空")
	# 恢复一份正常存档
	account_phone = "13800138000"
	balance = 12345.0
	debt = 6789.0
	total_paid_out = 2000.0
	bust_count = 2
	_save_game()
	_load_save()
	bt(abs(float(save_profile.get("balance", 0.0)) - 12345.0) < 0.01, "正常存档可正确读回余额")
	bt(not save_profile.is_empty(), "正常存档通过校验")

	print("-- 13b. 继承存档（重开游戏）--")
	_reset_game(true)
	bt(abs(balance - 12345.0) < 0.01, "继承后余额 %.0f" % balance)
	bt(abs(debt - 6789.0) < 0.01, "继承后负债 %.0f" % debt)
	bt(abs(total_paid_out - 2000.0) < 0.01, "继承后已提现 %.0f" % total_paid_out)

	print("-- 13. 隐藏规则页可打开 --")
	_show_rules(true)
	await _wait(0.4)
	bt(modal_layer != null, "隐藏规则弹窗打开")
	_close_modal()
	_show_rules(false)
	await _wait(0.3)
	bt(modal_layer != null, "游戏规则弹窗打开")
	_close_modal()

	print("-- 14. 中英双语 --")
	_show_title()
	Loc.lang = "en"
	_build_ui()
	_reset_game(true)
	bt(Loc.t("还 款") == "REPAY", "英文词典命中：%s" % Loc.t("还 款"))
	bt(btn_repay.text.begins_with("REPAY"), "还款按钮英文：%s" % btn_repay.text)
	bt(btn_repay.text.contains("Day 0"), "按钮含天数")
	bt(btn_loan.text.begins_with("LOAN"), "借款按钮英文：%s" % btn_loan.text)
	bt(HandEval.cat_name(HandEval.FLUSH) == "Flush", "牌型名英文：%s" % HandEval.cat_name(HandEval.FLUSH))
	_show_title()
	await _wait(0.4)
	bt(_find_button(title_root, "HOW TO PLAY") != null, "标题页英文按钮")
	bt(_find_button(title_root, "中文") != null, "切换按钮显示「中文」")
	_show_rules(false)
	await _wait(0.3)
	bt(_rt_contains(modal_layer, "HAND RANKINGS"), "规则页英文")
	_close_modal()
	_save_game()
	_load_save()
	bt(str(save_profile.get("lang")) == "en", "语言写进存档")
	bt(Loc.lang == "en", "读档恢复英文")
	# 切回中文，确保最终状态干净
	_toggle_lang()
	await _wait(0.4)
	bt(Loc.lang == "zh", "切回中文")
	bt(_find_button(title_root, "游 戏 规 则") != null, "中文按钮恢复")

	# 中文标题页 → 切英文 → 进游戏：牌桌 UI 必须整块重建
	_toggle_lang()
	await _wait(0.4)
	bt(Loc.lang == "en", "再切回英文")
	_enter_game(true)
	await _wait(0.5)
	bt(btn_repay.text.begins_with("REPAY"), "进入牌桌后仍是英文：%s" % btn_repay.text)
	bt(_find_button(ui_root, "CASH OUT") != null, "顶栏按钮英文")
	bt(lbl_status.text.begins_with("Min ante") or lbl_status.text.begins_with("Round"), "状态栏英文：%s" % lbl_status.text)

	# 英文模式下把不常走到的弹窗都开一遍，扫漏翻
	bt(_count_han(self) == 0, "英文牌桌无漏翻：%s" % _han_joined(self))
	debt = 0.0
	balance = 0.0
	_on_repay()
	await _wait(0.3)
	bt(_count_han(self) == 0, "英文还款弹窗无漏翻：%s" % _han_joined(self))
	_close_modal()
	_on_service()
	await _wait(0.3)
	bt(_count_han(self) == 0, "英文客服弹窗无漏翻：%s" % _han_joined(self))
	_close_modal()
	_show_rules(true)
	await _wait(0.3)
	bt(_count_han(self) == 0, "英文隐藏规则无漏翻：%s" % _han_joined(self))
	_close_modal()
	_on_withdraw()
	await _wait(0.3)
	bt(_count_han(self) == 0, "英文提现提示无漏翻：%s" % _han_joined(self))
	_close_modal()
	wd_attempts = 1
	_start_withdraw()
	await _wait(0.2)
	_show_withdraw_fail()
	await _wait(0.2)
	bt(_count_han(self) == 0, "英文提现失败页无漏翻：%s" % _han_joined(self))
	_close_withdraw()
	_show_title()
	await _wait(0.4)
	bt(_count_han(self) == 0, "英文标题页无漏翻：%s" % _han_joined(self))

	# 收尾：回到中文标题页
	Loc.lang = "zh"
	_build_ui()
	_reset_game(true)
	_show_title()
	await _wait(0.3)
	bt(Loc.lang == "zh" and _find_button(title_root, "游 戏 规 则") != null, "收尾回到中文标题页")

	print("-- 15. 切语言不闪牌桌 --")
	bt(title_root != null and title_root.modulate.a >= 0.999, "标题页整体立即不透明")
	bt(ui_root != null and ui_root.get_index() == 0, "牌桌 UI 永远垫在最底层")
	var tc: Node = title_root.get_node_or_null("TitleContent")
	bt(tc != null, "标题页前景层存在（背板与前景分离）")
	await _wait(0.6)
	bt(tc != null and tc.modulate.a >= 0.999, "前景层淡入完成")

	print("")
	if bt_fails == 0:
		print("=== 自测全部通过 ✔ ===")
	else:
		printerr("=== 自测失败 %d 项 ✘ ===" % bt_fails)
	await _wait(0.3)
	get_tree().quit(0 if bt_fails == 0 else 1)

# =====================================================================
# 自测辅助（漏翻扫描 / 等待）
# =====================================================================
func _has_han(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x4e00 and c <= 0x9fff:
			return true
	return false


func _collect_han(n: Node, out: Array) -> void:
	if n.name == "LangBtn":
		return
	var txt := ""
	if n is Label:
		txt = (n as Label).text
	elif n is Button:
		txt = (n as Button).text
	elif n is RichTextLabel:
		txt = (n as RichTextLabel).get_parsed_text()
	elif n is LineEdit:
		txt = (n as LineEdit).placeholder_text
	# 假玩家昵称（老张头、小鱼儿…）本来就是中文，不算漏翻
	for nm in FAKE_NAMES:
		txt = txt.replace(str(nm), "")
	if txt.strip_edges() != "" and _has_han(txt):
		out.append(txt.replace("\n", " / "))
	for c in n.get_children():
		_collect_han(c, out)


func _count_han(n: Node) -> int:
	var bad: Array = []
	_collect_han(n, bad)
	return bad.size()


func _han_joined(n: Node) -> String:
	var bad: Array = []
	_collect_han(n, bad)
	var uniq := {}
	for s in bad:
		uniq[s] = true
	return " | ".join(uniq.keys())


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
