class_name Loc
extends RefCounted

## 中英双语。
##
## 约定：**以中文原文为 key**，不另外发明 key 名。
##   - 不用维护 key 表
##   - 漏翻的字符串直接回退中文，不会出现 KEY_NOT_FOUND
##   - 改中文文案时同步改 DICT 的 key 即可
##
## 用法：
##   Loc.t("还 款")                      # 短文案
##   Loc.t("已还款 %s") % _money(x)       # 带格式化的：先翻模板再套
##
## 规则页 / 真相页这种整段 bbcode 太长，不适合塞进 DICT，
## 由下面的 xxx_body() 函数各排一版中英文，调用方直接取整段。

static var lang := "zh"

const BRAND_ZH := "鸿运棋牌"
const BRAND_EN := "HONGYUN CASINO"


static func en() -> bool:
	return lang == "en"


static func t(s: String) -> String:
	if lang == "en":
		var v = DICT.get(s)
		if v != null:
			return str(v)
	return s


## 顶栏用短名（中文 4 字 / 英文 1 个词），不然会压到右边的副标题
static func topbar_brand() -> String:
	return "HONGYUN" if en() else BRAND_ZH


static func brand() -> String:
	return BRAND_EN if en() else BRAND_ZH


static var DICT: Dictionary = {
	# ---------------- 品牌 / 顶栏 / 荷官 ----------------
	"鸿运棋牌": "HONGYUN CASINO",
	"真人荷官 · 秒充秒提 · 百万玩家在线": "Live dealers · Instant payouts · 1M online",
	"账户余额": "BALANCE",
	"待还借款": "DEBT",
	"提  现": "CASH OUT",
	"荷官 · 小雅": "Dealer · Xiaoya",
	"真人荷官 · 在线": "Live dealer · Online",
	"荷官：手气不错哦～": "Dealer: Nice run!",
	"荷官：这波稳的": "Dealer: Solid hand",
	"荷官：继续吗？": "Dealer: Again?",
	"荷官：这把是我运气好": "Dealer: Lucky me",
	"荷官：别急，下一把就回来了": "Dealer: Easy — the next one is yours",
	"荷官：要不要再来一局？": "Dealer: One more round?",
	"荷官：小场面，稳住": "Dealer: Small stakes, stay calm",

	# ---------------- 牌桌 ----------------
	"选择底注开始": "Choose an ante to start",
	"底注最低 ¥5 · 祝您玩得愉快": "Min ante ¥5 · Good luck",
	"底 池  ": "POT  ",
	"本局已投入 ": "In this hand: ",
	"下注金额": "Bet amount",
	"输入金额": "Enter amount",
	"最低 ¥5 · 最高 ": "Min ¥5 · Max ",
	"全 下 ": "ALL IN ",
	"加 注 ": "RAISE ",
	"过 牌": "CHECK",
	"弃 牌": "FOLD",
	"请输入数字": "Enter a number",
	"金额不够，最低 ¥5": "Below the ¥5 minimum",
	"超出余额，最高 ": "Above your balance — max ",
	"金额不够，已按最低 ¥5 计算": "Too low — using the ¥5 minimum",
	"超出余额，已调整为最高 ": "Too high — lowered to ",
	"发牌中…": "Dealing…",
	"第 %d 轮 · 您现在可以加注": "Round %d · You can raise",
	"筹码已全部押上": "All-in",
	"您已弃牌": "You folded",
	"开牌…": "Showdown…",
	"你 赢 了": "YOU WIN",
	"你 输 了": "YOU LOSE",
	"你的牌型：": "Your hand: ",
	"你的牌：%d 张 / 5": "Your cards: %d / 5",
	"庄家牌型：": "Dealer hand: ",
	"庄家：1 张明牌 + 4 张暗牌": "Dealer: 1 up, 4 down",
	"你": "YOU",
	"底注 ": "Ante ",
	"再来一把": "One more hand",
	"底注 %s 继续": "Ante %s",
	"未知": "Unknown",

	# ---------------- 大厅 ----------------
	"在 线 大 厅": "ONLINE LOBBY",
	"在线 1,284 人": "1,284 players online",
	"在线 %s 人": "%s players online",
	"最 新 战 报": "LATEST WINS",
	"[color=#7c8b9c]%s[/color] 提现成功 [color=#e8b64c]%s[/color]":
		"[color=#7c8b9c]%s[/color] cashed out [color=#e8b64c]%s[/color]",
	"VIP 专享": "VIP ONLY",
	"充值满 ¥50,000 解锁专属荷官\n提现秒到账 · 亏损返还 5%":
		"Deposit ¥50,000 to unlock your own dealer\nInstant cash-out · 5% loss rebate",
	"借 款   ": "LOAN   ",
	"暂无欠款": "NO DEBT",
	"立 即 还 款   %s\n第 %d 天 · 日息 %d%%": "REPAY   %s\nDay %d · %d%% daily",
	"已达借款上限": "LOAN LIMIT REACHED",
	"已达借款上限，请先还款": "Loan limit reached — repay first",
	"借款 %s 已到账": "Loan of %s received",
	"在线客服": "SUPPORT",
	"退 出 登 录": "LOG OUT",
	"本平台仅限 18 岁以上用户\n理性娱乐 · 谨防沉迷": "18+ only\nPlay responsibly",

	# ---------------- 还款 ----------------
	"还 款": "REPAY",
	"您当前没有欠款。": "You have no debt.",
	"待还欠款：[color=#ff4d5e]%s[/color]\n": "Debt: [color=#ff4d5e]%s[/color]\n",
	"可用余额：[color=#3fd68a]%s[/color]\n\n": "Balance: [color=#3fd68a]%s[/color]\n\n",
	"余额不足，暂时无法还款。": "Not enough balance to repay right now.",
	"可先投注赢回资金，或申请新的借款。": "Win some back first, or take another loan.",
	"可一次性结清。还清后所有催收停止。": "You can settle it in full. All collection stops.",
	"余额不足以结清，本次最多可还 %s。": "Balance too low to settle — you can pay up to %s.",
	"全额还清 %s": "PAY OFF %s",
	"还 %s": "PAY %s",
	"先不还": "NOT NOW",
	"欠款已结清，感谢您的诚信": "Debt cleared. Thank you.",
	"已还款 %s，剩余欠款 %s": "Paid %s · remaining %s",

	# ---------------- 通用弹窗 ----------------
	"关闭": "CLOSE",
	"知道了": "GOT IT",
	"取消": "CANCEL",

	# ---------------- 客服 ----------------
	"您好，客服「小雨」为您服务。\n\n": "Hi, this is Xiaoyu from support.\n\n",
	"您当前的提现申请正在审核中，\n": "Your withdrawal is still under review.\n",
	"为加快处理，建议您先完成 [color=#e8b64c]3 倍流水[/color] 要求。\n\n":
		"To speed it up, please complete the [color=#e8b64c]3x wagering[/color] requirement.\n\n",
	"[color=#7c8b9c]（客服已为您排队，前面还有 12 人）[/color][/color]":
		"[color=#7c8b9c](You are queued — 12 people ahead)[/color][/color]",

	# ---------------- 破产 / 借款 ----------------
	"极 速 借 款": "INSTANT LOAN",
	"[font_size=17]余额不足[/font_size]\n\n": "[font_size=17]INSUFFICIENT BALANCE[/font_size]\n\n",
	"当前余额：[color=#ff4d5e]%s[/color]\n": "Balance: [color=#ff4d5e]%s[/color]\n",
	"待还借款：[color=#ff4d5e]%s[/color]\n": "Debt: [color=#ff4d5e]%s[/color]\n",
	"\n[color=#7c8b9c]今日额度已用尽，可申请极速借款，":
		"\n[color=#7c8b9c]Today's limit is used up. Apply for an instant loan — ",
	"最快 30 秒到账，日息低至 0.05%。[/color]\n\n":
		"cash in 30 seconds, from 0.05% daily.[/color]\n\n",
	"[color=#4a5a68]（本模拟器不涉及任何真实货币）[/color]":
		"[color=#4a5a68](This simulator involves no real money)[/color]",
	"立即借款 %s": "BORROW %s",
	"暂不借款": "NOT NOW",

	# ---------------- 提现 ----------------
	"提 现 申 请": "CASH OUT",
	"可提现金额": "AVAILABLE TO WITHDRAW",
	"正在验证身份…": "Verifying identity…",
	"正在排队": "In queue",
	"正在为您分配提现通道，请勿关闭页面": "Assigning a payout channel — keep this page open",
	"正在处理": "Processing",
	"已进入银行通道，正在提交…": "Sent to the banking channel…",
	"前方已无排队用户": "No one ahead of you",
	"前方还有 %d 人正在提现": "%d people ahead of you",
	"预计等待 %02d:%02d   ·   当前排队第 %d 位": "Est. wait %02d:%02d   ·   position %d",
	"已提交至银行通道": "Sent to the bank",
	"等待银行返回结果…": "Waiting for the bank…",
	"提现成功": "WITHDRAWAL SUCCESSFUL",
	"%s 已提交至您的收款账户，预计 2 小时内到账":
		"%s has been sent to your account. ETA 2 hours.",
	"单笔限额 ¥2,000，超出部分已退回账户":
		"Limit ¥2,000 per withdrawal. The rest was returned.",
	"重新申请": "TRY AGAIN",
	"通道返回失败": "CHANNEL ERROR",
	"今日提现额度已满": "Daily withdrawal limit reached",
	"请于明日 09:00 后再试": "Please try again after 09:00 tomorrow",
	"银行系统维护中": "Bank system under maintenance",
	"预计 2 小时后恢复，请稍后重试": "Back in about 2 hours. Try again later.",
	"处理超时": "PROCESSING TIMEOUT",
	"您的申请已转入人工审核": "Your request was sent to manual review",
	"预计 1-3 个工作日内到账": "Funds expected in 1-3 business days",
	"系统繁忙": "SYSTEM BUSY",
	"本次提现未完成": "Withdrawal not completed",
	"请稍后重新提交申请": "Please submit your request again later",
	"账户信息校验未通过": "Account verification failed",
	"请联系在线客服": "Please contact support",
	"[color=#dfe7ef]您当前账户为 [b]体验金账户[/b]。[/color]\n\n":
		"[color=#dfe7ef]This is a [b]trial balance account[/b].[/color]\n\n",
	"按平台规则，[color=#e8b64c]体验金本金不可提现[/color]，仅限用于投注。\n":
		"Under platform rules, [color=#e8b64c]the trial balance cannot be withdrawn[/color]. Betting only.\n",
	"需将账户余额做到 ¥50,000 以上，[b]超出部分[/b]方可申请提现。\n\n":
		"Raise your balance above ¥50,000 — only the [b]excess[/b] can be withdrawn.\n\n",
	"[color=#7c8b9c]当前余额 %s，其中体验金本金 %s。[/color]\n":
		"[color=#7c8b9c]Balance %s, of which trial funds are %s.[/color]\n",
	"[color=#7c8b9c]当前余额 %s，低于体验金本金 %s。\n":
		"[color=#7c8b9c]Balance %s is below the trial funds of %s.\n",
	"[color=#7c8b9c]继续投注，把本金赢回来即可解锁提现。[/color]\n":
		"[color=#7c8b9c]Keep playing — win the principal back to unlock withdrawals.[/color]\n",
	"\n[color=#ff4d5e]当前可提现金额：¥0[/color]":
		"\n[color=#ff4d5e]Available to withdraw: ¥0[/color]",

	# ---------------- 真相页 ----------------
	"停 一 下": "STOP.",
	"你刚才玩的那段时间里，没有一张牌是随机的。":
		"Not a single card in that session was random.",
	"后 台 记 录 · 平 台 一 直 看 得 见": "BACKEND LOG · THE HOUSE SEES EVERYTHING",
	"总局数": "Hands",
	"你投入的钱": "Wagered",
	"你「赢」过的钱": "Won (on paper)",
	"你真正拿走的钱": "Actually cashed out",
	"平台从你身上拿走": "The house took",
	"你「就差一级」": "Near misses",
	"你最大的一把输": "Biggest loss",
	"你现在欠的钱": "Debt now",
	"%d 局": "%d",
	"%d 次": "%d",
	"你真正能从这个平台带走的钱": "What you can actually walk away with",
	"屏幕上的输赢按胜率曲线走，能提出来的只有这个数":
		"The odds are a curve — only this much can ever be cashed out",
	"这些数字，都是我自己点出来的": "All those numbers — I clicked them myself",
	"从头再试一次（模拟）": "Try again from scratch (simulation)",

	# ---------------- 标题页 ----------------
	"真人荷官在线发牌　·　秒充秒提　·　百万玩家同时在线":
		"Live dealers · Instant payouts · 1M players online",
	"欢 迎 回 来": "WELCOME BACK",
	"新 会 员 注 册": "NEW MEMBER",
	"账号已自动登录": "Auto-logged in",
	"注册即送 ¥50,000 体验金": "Sign up and get a ¥50,000 trial balance",
	"随便填 11 位数字": "Any 11 digits",
	"请输入手机号": "Phone number",
	"短信验证码": "SMS code",
	"获取验证码": "Send code",
	"已发送": "Sent",
	"重新获取": "Resend",
	"  我已阅读并同意《用户服务协议》": "  I agree to the Terms of Service",
	"余额 %s　·　待还借款 %s": "Balance %s　·　Debt %s",
	"继 续 游 戏  并 入 座": "CONTINUE TO TABLE",
	"领 取  ¥50,000  并 进 入": "CLAIM ¥50,000 & ENTER",
	"本模拟器不涉及任何真实货币": "This simulator uses no real money",
	"重新开始（清空存档）": "Start over (wipe save)",
	"游 戏 规 则": "HOW TO PLAY",
	"隐 藏 规 则   ✓": "HIDDEN RULES   ✓",
	"隐 藏 规 则": "HIDDEN RULES",
	"你已累计输光 %d 次　·　累计亏损 %s": "Busted %d times　·　Total lost %s",
	"新用户首存 100% 返利　·　24 小时在线客服": "100% first-deposit bonus　·　24/7 support",
	"退 出 游 戏": "QUIT",
	"本平台仅限 18 岁以上用户　·　理性娱乐，谨防沉迷　·　健康生活，远离赌博":
		"18+ only　·　Play responsibly　·　Gambling ruins lives",
	"清 空 存 档": "WIPE SAVE",
	"[color=#dfe7ef]清空存档后，账号、余额、负债、输光次数都会归零。[/color]\n\n":
		"[color=#dfe7ef]Wiping the save clears your account, balance, debt and bust count.[/color]\n\n",
	"[color=#ff4d5e]「隐藏规则」会重新锁上。[/color]":
		"[color=#ff4d5e]The HIDDEN RULES page will be locked again.[/color]",
	"确认清空": "WIPE",

	# ---------------- 注册 / 验证码 ----------------
	"请输入 11 位手机号": "Enter an 11-digit phone number",
	"请输入 11 位手机号（随便填 11 位数字就行）":
		"Enter an 11-digit phone number (any 11 digits will do)",
	"请先点击「获取验证码」": "Tap \"Send code\" first",
	"验证码不正确，请查看上方短信": "Wrong code — check the SMS above",
	"请先勾选《用户服务协议》": "Please accept the Terms of Service",
	"注册成功，正在为您发放体验金…": "Registered — issuing your trial balance…",
	"注册成功，¥50,000 体验金已到账": "Registered. ¥50,000 trial balance credited",
	"正在恢复您的账号…": "Restoring your account…",

	# ---------------- 短信 ----------------
	"短信": "SMS",
	"现在": "now",
	"【鸿运棋牌】验证码 %s，5 分钟内有效。请勿泄露给他人。":
		"[Hongyun] Code %s, valid for 5 minutes. Do not share it.",
	"【鸿运棋牌】第 %d 天利息 %s 已计入欠款，当前欠款 %s":
		"[Hongyun] Day %d interest %s added. Debt now %s.",
	"【鸿运棋牌】您的借款 %s 已到账，日息 0.05%%，随借随还，祝您早日回本。":
		"[Hongyun] Loan of %s received. 0.05%% daily, repay anytime.",
	"【鸿运棋牌】您的账户已进入风险监控，当前欠款 %s，请尽快处理，逾期将产生罚息。":
		"[Hongyun] Account under risk review. Debt %s. Late fees apply.",
	"【催收提醒】您已逾期，请于今日 24:00 前偿还 %s，否则将联系您的紧急联系人。":
		"[Collection] Overdue. Repay %s by 24:00 today or we call your contacts.",
	"【最后通知】您的案件已移交法务，若 1 小时内未处理，将向您通讯录好友群发催告函。":
		"[Final notice] Case sent to legal. Unpaid in 1 hour, letters go to all contacts.",
	"【鸿运棋牌】您还有 %s 未结清，请合理安排资金。":
		"[Hongyun] %s still outstanding. Please arrange funds.",
	"【鸿运棋牌】VIP 客服提醒您：账户余额充足时可随时还款。":
		"[Hongyun] VIP support: repay anytime your balance allows.",
	"【鸿运棋牌】您的账户已进入风险监控，欠款 %s，请尽快处理。":
		"[Hongyun] Account under risk review. Debt %s. Please settle soon.",
	"【鸿运棋牌】逾期将按日计收 0.1% 罚息，建议今日结清。":
		"[Hongyun] Overdue balances incur 0.1% daily penalty. Settle today.",
	"【催收提醒】逾期第 3 天，请于今日 24:00 前偿还 %s。":
		"[Collection] Day 3 overdue. Repay %s by 24:00 today.",
	"【催收】我方已获取您的通讯录信息，请立即处理欠款。":
		"[Collection] We have your contact list. Settle now.",
	"【最后通知】若 1 小时内未处理，将向您通讯录好友群发催告函。":
		"[Final notice] Unpaid in 1 hour, demand letters go to all your contacts.",
	"【法务部】您的案件已移交，请保持电话畅通。":
		"[Legal] Your case has been transferred. Keep your phone reachable.",
	"【失信名单】您已被列入失信被执行人名单，出行与消费将受限。":
		"[Blacklist] Added to the defaulter list. Travel and spending restricted.",
}


# =====================================================================
# 长文案：规则页 / 隐藏规则 / 真相页右栏
# =====================================================================

static func rules_body() -> String:
	if en():
		var b := ""
		b += "[color=#e8b64c][font_size=17]HAND RANKINGS[/font_size][/color]\n\n"
		b += "  Straight Flush > Four of a Kind > Full House > Flush > Straight\n"
		b += "  > Three of a Kind > Two Pair > One Pair > High Card\n\n"
		b += "[color=#e8b64c][font_size=17]TIES GO BY SUIT[/font_size][/color]\n\n"
		b += "  Spades ♠  >  Hearts ♥  >  Clubs ♣  >  Diamonds ♦\n\n"
		b += "[color=#e8b64c][font_size=17]HOW TO PLAY[/font_size][/color]\n\n"
		b += "  · Pick an ante (min ¥5). You and the dealer put in the same amount.\n"
		b += "  · You see 3 cards first, then one more per round — raise after each card.\n"
		b += "  · The dealer shows only 1 card; the other 4 stay hidden until showdown.\n"
		b += "  · After three betting rounds, showdown: the better hand takes the pot.\n\n"
		b += "[color=#7c8b9c]Drag the slider to bet, or type an amount directly.[/color]"
		return b

	var body := ""
	body += "[color=#e8b64c][font_size=17]牌 型 大 小[/font_size][/color]\n\n"
	body += "　同花顺  >  四条  >  葫芦  >  同花  >  顺子\n"
	body += "　>  三条  >  两对  >  一对  >  高牌\n\n"
	body += "[color=#e8b64c][font_size=17]平 局 比 花 色[/font_size][/color]\n\n"
	body += "　黑桃 ♠  >  红桃 ♥  >  梅花 ♣  >  方块 ♦\n\n"
	body += "[color=#e8b64c][font_size=17]玩 法[/font_size][/color]\n\n"
	body += "　· 选底注（最低 ¥5），你和庄家各出同样多进底池\n"
	body += "　· 你先亮 3 张，之后每轮再开 1 张，每开一次都能加注\n"
	body += "　· 庄家只亮 1 张，其余 4 张到摊牌才翻开\n"
	body += "　· 三轮加注结束后摊牌，牌大的一方赢走底池\n\n"
	body += "[color=#7c8b9c]下注可以拖动滑条，也可以直接输入金额。[/color]"
	return body


static func hidden_locked_body(bust: int) -> String:
	if en():
		var b := ""
		b += "[color=#ff4d5e][font_size=18]This part, the house will never tell you.[/font_size][/color]\n\n"
		b += "After you [b]lose your whole balance for the first time[/b], this page shows the platform's real odds formula —\n"
		b += "the rule behind \"why online gambling can never be beaten\".\n\n"
		b += "[color=#7c8b9c]Status:[/color]\n"
		b += "  Busted [color=#ff4d5e]%d[/color] time(s)\n" % bust
		b += "  Unlocks after: 1 bust\n\n"
		b += "[color=#4a5a68](This is not a game mechanic. Real online casinos only let you see it after you have lost.)[/color]"
		return b

	var body := ""
	body += "[color=#ff4d5e][font_size=18]这一条平台不会告诉你。[/font_size][/color]\n\n"
	body += "在你[b]第一次把本金输光[/b]之后，这里会显示平台真正的赔率算法 ——\n"
	body += "也就是「为什么在网上赌，永远赢不了」的那条规则。\n\n"
	body += "[color=#7c8b9c]当前状态：[/color]\n"
	body += "　已输光 [color=#ff4d5e]%d[/color] 次\n" % bust
	body += "　解锁条件：输光 1 次\n\n"
	body += "[color=#4a5a68]（这不是游戏设定。真实的网赌平台，也是在你输完之后才会被你看见。）[/color]"
	return body


static func hidden_rules_body() -> String:
	if en():
		var b := ""
		b += "[color=#ff4d5e][font_size=17]THE REAL ODDS[/font_size][/color]\n\n"
		b += "  Bet ¥100     →  97% win\n"
		b += "  Bet ¥1,000   →  75% win\n"
		b += "  Bet ¥5,000   →  38% win\n"
		b += "  Bet ¥10,000  →  23% win\n"
		b += "  Bet ¥40,000  →   7% win\n\n"
		b += "[color=#e8b64c]The more you bet, the worse your odds. Smooth all the way — no thresholds.[/color]\n"
		b += "So you blame your luck. There is no number you can catch.\n\n"
		b += "[color=#ff4d5e][font_size=17]DECAY OVER TIME[/font_size][/color]\n\n"
		b += "  Past ¥20,000 in winnings the odds start to decay; at ¥60,000 they hit zero.\n\n"
		b += "[color=#ff4d5e][font_size=17]THE PAYOUT GATE[/font_size][/color]\n\n"
		b += "  · The ¥50,000 trial balance can never be withdrawn\n"
		b += "  · Only the part above the principal counts as winnings\n"
		b += "  · Max ¥2,000 per withdrawal, ¥10,000 in a lifetime\n"
		b += "  · The first one really arrives. Every one after that fails\n\n"
		b += "[color=#e8b64c][font_size=17]CONCLUSION[/font_size][/color]\n\n"
		b += "  That number on the screen was never your money.\n"
		b += "  You were just watching it grow, then watching it hit zero."
		return b

	var body := ""
	body += "[color=#ff4d5e][font_size=17]平 台 真 正 的 赔 率[/font_size][/color]\n\n"
	body += "　押 ¥100     →  胜率 97%\n"
	body += "　押 ¥1,000   →  胜率 75%\n"
	body += "　押 ¥5,000   →  胜率 38%\n"
	body += "　押 ¥10,000  →  胜率 23%\n"
	body += "　押 ¥40,000  →  胜率  7%\n\n"
	body += "[color=#e8b64c]你押得越大，胜率越低。全程平滑，没有任何阈值。[/color]\n"
	body += "所以你会觉得是运气不好 —— 因为没有哪个数字能让你抓住。\n\n"
	body += "[color=#ff4d5e][font_size=17]累 计 衰 减[/font_size][/color]\n\n"
	body += "　赢超 ¥20,000 开始衰减，到 ¥60,000 归零。\n\n"
	body += "[color=#ff4d5e][font_size=17]出 金 闸 门[/font_size][/color]\n\n"
	body += "　· 体验金本金 ¥50,000 永久不可提现\n"
	body += "　· 只有超出本金的部分才算赢来的钱\n"
	body += "　· 单笔上限 ¥2,000，一生最多 ¥10,000\n"
	body += "　· 第一笔真的到账，之后永远失败\n\n"
	body += "[color=#e8b64c][font_size=17]结 论[/font_size][/color]\n\n"
	body += "　屏幕上的那个数字，从来不是你的钱。\n"
	body += "　你只是在看它变大，然后再看它归零。"
	return body


static func reveal_rules_body() -> String:
	if en():
		var b := ""
		b += "[color=#7c8b9c]THE REAL RULES[/color]\n\n"
		b += "· Odds are computed live from how much you bet\n"
		b += "  Bet ¥100   → 97%\n"
		b += "  Bet ¥1,000 → 75%\n"
		b += "  Bet ¥5,000 → 38%\n"
		b += "  Bet ¥10,000 → 23%\n"
		b += "  Bet ¥40,000 → 7%\n"
		b += "  [color=#7c8b9c](Smooth throughout — no thresholds at all)[/color]\n\n"
		b += "· The more you win overall, the further the odds drop\n"
		b += "  Decay starts after ¥20,000 in winnings; zero at ¥60,000\n"
		b += "· The ¥50,000 trial balance can never be withdrawn\n"
		b += "· Max ¥2,000 per withdrawal, ¥10,000 in a lifetime\n\n"
		b += "[color=#7c8b9c]ONLINE GAMBLING IN REAL LIFE[/color]\n\n"
		b += "Live dealers are real. The deal is real.\nThe result is decided by the server.\n"
		b += "What you can withdraw is always less than what you put in.\n"
		b += "[color=#e8b64c]Many seized platforms run a hidden \"custom odds\" switch.[/color]\n\n"
		b += "[color=#7c8b9c]You thought you were gambling on luck.\nThe ending was written the second you pressed \"Deposit\".[/color]"
		return b

	var rb := ""
	rb += "[color=#7c8b9c]平 台 的 真 实 规 则[/color]\n\n"
	rb += "· 平台按「你押多少」实时算胜率\n"
	rb += "  押 ¥100   → 97%\n"
	rb += "  押 ¥1,000 → 75%\n"
	rb += "  押 ¥5,000 → 38%\n"
	rb += "  押 ¥10,000 → 23%\n"
	rb += "  押 ¥40,000 → 7%\n"
	rb += "  [color=#7c8b9c]（全程平滑，没有任何一个「阈值」）[/color]\n\n"
	rb += "· 累计赢得越多，胜率再往下压\n"
	rb += "  赢到 ¥20,000 开始衰减，¥60,000 归零\n"
	rb += "· 体验金本金 ¥50,000 永远不可提现\n"
	rb += "· 单笔提现上限 ¥2,000，一生最多 ¥10,000\n\n"
	rb += "[color=#7c8b9c]现 实 中 的 网 赌[/color]\n\n"
	rb += "真人荷官是真的，发牌也是真的，\n但结算由服务器说了算。\n"
	rb += "你能提现的额度，永远小于你已经充进去的钱。\n"
	rb += "[color=#e8b64c]很多被查获的平台，后台都带一个「自定义胜率」开关。[/color]\n\n"
	rb += "[color=#7c8b9c]你以为你在赌运气。\n其实从你按下「充值」那一秒，结局就已经写好了。[/color]"
	return rb
