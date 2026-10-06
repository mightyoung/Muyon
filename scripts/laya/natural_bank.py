"""Natural requests for the stage-2 generator.

Requests name the user's object and verb. They do not quote the option
description or its English gloss. Held-out tools are not mentioned.
"""

from __future__ import annotations

import random

# code_rate: fraction of draws that insert a latin code or pinyin initial.
# Those rows are mixed-script on purpose. The rest stay Chinese.
ZH = {
    "inquiry.search": {
        "code_rate": 0.22,
        "zh": ["宏达", "华东阀门", "不锈钢截止阀", "二期改造", "三号线技改", "蝶阀", "密封件", "华东机电", "管件厂", "低压配电", "冷却塔", "闸阀"],
        "codes": ["lzb", "gyf", "hdd", "DN150", "P-27", "80QZ"],
        "templates": [
            "帮我找一下{e}",
            "库里有没有{e}",
            "搜一下{e}还在不在",
            "{e}这个名字，帮我定位一下",
            "我只记得{e}，你帮我翻出来",
            "看看名录里带{e}的是哪一家",
            "{e}在哪一条",
            "有个叫{e}的，帮我对上号",
            "不想翻表格了，直接查{e}",
            "{e}，名录里点一下",
            "我手写的名字可能不准，先试{e}",
            "把{e}从厂家和件号里捞出来",
            "就记得{e}，编号忘了",
            "查查{e}是厂家、件还是项目",
            "{e}帮我定位，别的先不用管",
            "名录里检索一下{e}",
            "上次见过{e}，再调出来",
            "{e}怎么拼我没把握，你先搜搜",
            "先按这几个字母试：{e}",
            "采购要联系{e}，先帮我定位",
        ],
    },
    "inquiry.query": {
        "code_rate": 0.0,
        "zh": ["待询价的物料", "美元报价", "交货期超过三十天的报价", "单位还是台的预算行", "含税价空着的报价", "今年新进来的厂家", "还没回价的行", "币种没填的报价", "停在草稿的单", "数量是零的行", "税率为空的报价", "状态是已报价的行"],
        "codes": [],
        "templates": [
            "{e}有几条",
            "帮我数一下{e}",
            "{e}的记录一共多少",
            "只要个数：{e}",
            "{e}，列个数量就行",
            "把{e}过一遍，告诉我几行",
            "我想知道{e}占多少",
            "{e}过完大概多少条",
            "别把明细摊开，{e}给我一个数",
            "{e}帮我算算",
            "看下{e}是不是很多",
            "{e}现在库里还有多少",
            "报个数就行，{e}",
            "统计{e}，我做表要用",
            "{e}有多少，含不含税先别管",
            "下午汇报，{e}给我一个数",
            "{e}，空着的和填了的分开数",
            "不用列表，{e}多少",
        ],
    },
    "inquiry.get": {
        "code_rate": 0.45,
        "zh": ["那条被划掉的报价", "昨天误删的那一行", "草稿里划掉的阀门行", "旧单里作废的电机", "编号二零三一那条", "被红笔划掉的管件"],
        "codes": ["Q-2031", "S-0042", "7f3a", "RFQ-09 里被划掉的那条"],
        "templates": [
            "把{e}调出来，划掉的也要",
            "我要看{e}，哪怕已经作废",
            "{e}还能再看一眼吗",
            "读一下{e}当初填的内容",
            "{e}那条，删过也请打开",
            "按编号把{e}找回来",
            "{e}的原始填写给我",
            "作废了的{e}也读出来",
            "我不改它，只看{e}",
            "{e}，当初写了什么",
            "把{e}被划掉之前的内容念给我",
            "{e}还能否按编号再打开",
            "历史里的{e}给我看原文",
            "只读{e}，别恢复它",
        ],
    },
    "inquiry.object": {
        "code_rate": 0.4,
        "zh": ["宏达这家厂家", "二期改造这个项目", "不锈钢截止阀这个件", "上午那张询价", "冷却塔那条主档", "密封件这个料"],
        "codes": ["供应商 V-118", "项目 P-27", "物料 M-5521", "询价单 RFQ-09"],
        "templates": [
            "打开{e}",
            "看一下{e}的详情",
            "{e}整条信息给我",
            "调出{e}",
            "我想看{e}，先别改",
            "{e}点开",
            "把{e}的档案摊开",
            "{e}现在长什么样",
            "只读{e}这一条",
            "{e}的主档给我",
            "进入{e}",
            "{e}，栏目我自己看",
            "把{e}亮出来就行",
            "我要核对{e}的主信息",
        ],
    },
    "inquiry.related": {
        "code_rate": 0.15,
        "zh": ["这个阀门", "这家宏达", "预算里那一行电缆", "这条密封", "二期的电机", "那个管件", "冷却塔风机"],
        "codes": ["预算行 B-12", "型号 80QZ"],
        "templates": [
            "谁在用{e}",
            "删{e}之前，先告诉我哪些单子指着它",
            "{e}被哪些询价用到了",
            "还有哪些记录挂着{e}",
            "{e}一旦作废，会波及哪些单",
            "先别动{e}，看谁指着它",
            "{e}的上下游给我一份",
            "哪些报价站在{e}上面",
            "{e}被挂到了哪些单子",
            "我想清掉{e}，先看牵连",
            "{e}还被别的单据挂着吗",
            "把指向{e}的单子列出来",
            "{e}能不能动，先看谁靠着它",
            "别删，先查{e}的牵连",
        ],
    },
    "inquiry.describe": {
        "code_rate": 0.0,
        "zh": ["报价", "供应商", "询价单", "预算行", "物料", "项目"],
        "codes": [],
        "templates": [
            "{e}这边都有哪些栏",
            "跟我讲讲{e}和别的东西怎么挂在一起",
            "{e}的结构长什么样",
            "有哪些类型，{e}算哪一种",
            "我新人，{e}要填什么",
            "{e}跟别的单据是怎么串起来的",
            "先别查具体单子，讲讲{e}",
            "{e}有哪些属性",
            "{e}处在哪一层",
            "{e}的栏目给我口述一遍",
            "不看具体编号，{e}的架子是什么",
            "{e}能关联到谁",
            "先把{e}的栏目说清楚",
            "{e}一般跟谁发生关系",
            "我只想搞懂{e}怎么建",
        ],
    },
    "inquiry.spec_classes": {
        "code_rate": 0.0,
        "zh": ["离心风机", "减速机", "调节阀", "变频器", "冷却塔", "蝶阀", "电缆", "离心泵"],
        "codes": [],
        "templates": [
            "{e}要填哪些数",
            "看看{e}通常记哪些指标",
            "{e}这类设备的空表给我",
            "先别填数，把{e}的栏目拿来",
            "{e}采购时一般写哪些性能",
            "我想加一台{e}，要准备哪些指标",
            "{e}的规格栏有哪些",
            "空表就行，{e}",
            "{e}性能怎么记，给我看架子",
            "别填具体值，{e}的栏位先列出来",
            "{e}一般要写流量、功率这类吗",
            "建档的话，{e}有哪些空位",
            "{e}的性能栏给我看看",
            "先看空表，{e}先别填",
        ],
    },
    "inquiry.match_item": {
        "code_rate": 0.28,
        "zh": ["流量五十立方、扬程三十二米、不锈钢", "耐温二百度的密封", "公称压力十六、口径一百、铸钢", "三百八十伏、十五千瓦", "耐腐蚀、常温、法兰连接", "低噪声、室内、连续运行"],
        "codes": ["流量 50 立方、扬程 32 米", "PN16、DN100、铸钢", "380V、15 千瓦"],
        "templates": [
            "按“{e}”挑能用的型号",
            "这个条件：{e}，库里有哪些对得上",
            "帮我按{e}找候选",
            "{e}，看看现有的件里谁合适",
            "规格是{e}，给几个候选",
            "不要总价，按{e}对型号",
            "{e}这种要求，现有件够不够",
            "帮我把{e}对到具体件号",
            "候选就行，{e}",
            "库里谁满足{e}",
            "{e}，挑三五个我看看",
            "条件写的是{e}",
            "先给候选，条件是{e}",
            "别算总造价，只按{e}对件",
        ],
    },
    "inquiry.quote_options": {
        "code_rate": 0.2,
        "zh": ["二期的电机", "这个项目的阀门", "这批管件", "冷却塔风机", "主泵", "低压柜"],
        "codes": ["P-27 的电缆", "DN80 闸阀"],
        "templates": [
            "{e}现在有哪些还能用的价，便宜的放前面",
            "给{e}挑一个最低的有效价",
            "{e}可选的价排个序",
            "{e}这会儿能用哪些价",
            "{e}别的厂家还报着吗，低的先给我",
            "我要下单，{e}用哪条价",
            "{e}有效价里最便宜的是哪条",
            "先看价格，{e}有哪些能选",
            "{e}的价，过期的别混进来",
            "帮我把{e}能用的价从低往高念",
            "{e}，低价优先，只要还有效的",
            "采购要用，{e}现在能落哪几条价",
            "{e}还有有效报价吗，便宜的先说",
            "先别下单，把{e}能用的价列出来",
        ],
    },
    "inquiry.compare_quotes": {
        "code_rate": 0.2,
        "zh": ["这个阀门", "密封件", "电机", "电缆", "蝶阀", "管件", "主泵"],
        "codes": ["DN80 闸阀", "同一型号的电机"],
        "templates": [
            "把{e}几家的价放一起看",
            "{e}各家口径不一样，统一之后再比",
            "哪家的{e}更划算",
            "{e}的价横着比一比",
            "{e}，别急着改价，先并排看",
            "同一件{e}，几家差多少",
            "{e}谁更便宜，单位先对齐",
            "我要汇报，把{e}的价并列",
            "{e}各家报的数摆一起",
            "先比{e}，先别选定",
            "{e}的价，含税和不含税分开比",
            "几家都报了{e}，帮我看差距",
            "{e}并排，我来挑",
            "先对齐单位，再看{e}差多少",
        ],
    },
    "inquiry.inquiry_matrix": {
        "code_rate": 0.35,
        "zh": ["这轮询价", "上午发出的那张单", "阀门那一轮", "电机询价", "管件这一轮"],
        "codes": ["RFQ-11", "RFQ-09"],
        "templates": [
            "{e}这张单，各家对每一行报了什么",
            "把{e}按行和厂家摊开",
            "{e}做成横竖对照",
            "看{e}里每一行对应谁的价",
            "{e}不要只看合计，按行拆开",
            "我想看{e}的全表",
            "{e}里缺谁没报价，按行指出来",
            "把{e}铺开，一行一家",
            "{e}的明细格子给我",
            "汇报用，{e}按行展开",
            "{e}各行的价都齐了吗",
            "别汇总，{e}我要看格子",
            "{e}，按行给我对照",
            "打开{e}，我要看每一格",
        ],
    },
    "inquiry.data_quality": {
        "code_rate": 0.0,
        "zh": ["报价", "物料", "供应商名录", "这张询价单", "预算", "厂家名称", "单位这一列"],
        "codes": [],
        "templates": [
            "帮我看看{e}有没有重复或者互相打架",
            "{e}里单位含糊的有哪些",
            "过一遍{e}",
            "{e}还有哪些空着或者明显冲突",
            "{e}里是不是有两条其实是同一条",
            "单位写得糊的，在{e}里标出来",
            "{e}我看着不放心，帮我扫一遍",
            "{e}有没有互相矛盾的数",
            "先别改，告诉我{e}哪里脏",
            "{e}空单元格多不多",
            "{e}里名称是否撞车",
            "扫一下{e}，我要收工了",
            "{e}哪些看着像重复录入",
            "先指出问题，别改{e}",
            "{e}里有没有对不上的单位",
        ],
    },
    "knowledge.search": {
        "code_rate": 0.0,
        "zh": ["机械密封冲洗", "变频器接线", "防腐涂层", "保养周期", "额定扬程", "联轴器对中", "轴承润滑", "电缆敷设", "试车步骤"],
        "codes": [],
        "templates": [
            "在我已经导入的文件里找{e}",
            "手册里哪一页写了{e}",
            "本地文档有没有讲{e}",
            "翻翻现有资料，看{e}",
            "已有文件里搜一下{e}",
            "我记得手册里写过{e}",
            "{e}在哪一节",
            "别上网，就在我的文件里找{e}",
            "说明书里关于{e}的那一段",
            "{e}，查我导入过的资料",
            "电子版手册里有{e}吗",
            "帮我在现有文件里定位{e}",
            "只查已经放进来的文件，主题是{e}",
            "{e}，手册里怎么写的",
            "我自己的资料里有没有{e}",
        ],
    },
    "knowledge.embedding_preview": {
        "code_rate": 0.0,
        "zh": ["那几段话", "手册摘出来的段落", "准备出门的句子", "我标出来的那一段", "要拿去向量化的文字", "摘录"],
        "codes": [],
        "templates": [
            "先给我看{e}，先别发出去",
            "{e}我想过目，暂时不要传",
            "外传之前把{e}亮出来",
            "只看{e}，不要真的送出去",
            "{e}让我读完再决定",
            "先别送，把{e}摊在屏幕上",
            "我要核对{e}，先停在这一步",
            "{e}里有没有不该出去的句子",
            "发出去之前给我{e}",
            "{e}，我自己看，你先别动手送",
            "把将要出门的{e}念给我",
            "{e}先留在本机给我看",
            "先别传，我要读{e}",
            "{e}展示一下就停",
        ],
    },
    "research.objects": {
        "code_rate": 0.0,
        "zh": ["轴承故障诊断", "迁移学习", "振动信号", "实验设计", "少样本分类", "联轴器不对中", "密封寿命", "噪声测量"],
        "codes": [],
        "templates": [
            "打开那个“{e}”",
            "找一下标题里有“{e}”的",
            "当前项目里关于{e}的条目",
            "把叫“{e}”的那条笔记调出来",
            "题目是“{e}”的那篇在哪",
            "{e}那条笔记还在吗",
            "我想继续写{e}",
            "笔记里搜标题{e}",
            "{e}，打开就行，别改",
            "上次那篇{e}放哪了",
            "项目笔记里定位{e}",
            "标题含{e}的都列一下",
            "把{e}那篇翻开",
            "我要看笔记，标题是{e}",
            "{e}在当前这个项目里吗",
        ],
    },
}

EN = {
    "inquiry.search": {
        "entities": ["Hongda", "the phase-two retrofit", "a DN150 butterfly valve", "Huadong Valve", "the cooling tower", "line three"],
        "templates": [
            "where did I put {e}",
            "look up {e}",
            "is {e} on the list",
            "I only remember {e}",
            "point me at {e}",
            "find the entry called {e}",
            "scroll the directory to {e}",
            "{e} — which row is that",
        ],
    },
    "inquiry.query": {
        "entities": ["still priced in USD", "waiting for a quote", "missing a tax-inclusive price", "stuck in draft", "with a blank currency"],
        "templates": [
            "how many rows are {e}",
            "just the count for {e}",
            "give me a number: {e}",
            "don't list them, count {e}",
            "how big is the set that is {e}",
            "{e}: how many",
        ],
    },
    "inquiry.get": {
        "entities": ["Q-2031", "the voided line S-0042", "7f3a", "the crossed-out motor line"],
        "templates": [
            "show {e} even if it was voided",
            "pull up {e}",
            "I want the original text of {e}",
            "open {e}, crossed out is fine",
            "read {e} and do not restore it",
            "{e} again, please, the old wording",
        ],
    },
    "inquiry.object": {
        "entities": ["vendor V-118", "project P-27", "RFQ-09", "the Hongda card"],
        "templates": [
            "open {e}",
            "show the details of {e}",
            "I only want to read {e}",
            "bring up the card for {e}",
            "{e}, on screen",
            "let me see {e} before I change anything",
        ],
    },
    "inquiry.related": {
        "entities": ["this pump", "budget line B-12", "the Hongda card", "that seal"],
        "templates": [
            "what points at {e}",
            "who cites {e}",
            "if I drop {e}, which sheets break",
            "list the sheets hanging off {e}",
            "don't delete {e}; who else uses it",
            "{e} is tied to what",
        ],
    },
    "inquiry.describe": {
        "entities": ["a quote", "a vendor", "an RFQ", "a budget line"],
        "templates": [
            "what columns does {e} have",
            "how is {e} linked to the rest",
            "I'm new: what do I fill in for {e}",
            "talk me through {e}",
            "which fields sit on {e}",
            "skip the live rows and explain {e}",
        ],
    },
    "inquiry.spec_classes": {
        "entities": ["a gear reducer", "a control valve", "a cooling tower", "a VFD"],
        "templates": [
            "what do I fill in for {e}",
            "show the blank sheet for {e}",
            "which figures do we usually write for {e}",
            "empty form only, for {e}",
            "before I type numbers, the slots for {e}",
            "{e}: which performance slots",
        ],
    },
    "inquiry.match_item": {
        "entities": ["50 m3/h and 32 m head in stainless", "PN16 DN100 cast steel", "200 C seal", "380 V and 15 kW"],
        "templates": [
            "what fits {e}",
            "candidates for {e}",
            "which stock items match {e}",
            "shortlist only: {e}",
            "don't price the job, just match {e}",
            "three options for {e}",
        ],
    },
    "inquiry.quote_options": {
        "entities": ["the project motors", "the cable on P-27", "this batch of fittings", "the main pump"],
        "templates": [
            "which prices can I still use for {e}",
            "cheapest live price for {e}",
            "rank the live prices for {e}",
            "I'm about to order {e}; which price is valid",
            "leave the expired ones out of {e}",
            "{e}: low price first, still valid only",
        ],
    },
    "inquiry.compare_quotes": {
        "entities": ["this DN80 gate valve", "the same motor", "the seal", "the cable"],
        "templates": [
            "put the prices for {e} side by side",
            "who is cheaper on {e}",
            "line up {e} after the units match",
            "don't pick yet; show {e} together",
            "how far apart are the prices for {e}",
            "{e} with tax and without, side by side",
        ],
    },
    "inquiry.inquiry_matrix": {
        "entities": ["RFQ-09", "this morning's sheet", "the valve round", "RFQ-11"],
        "templates": [
            "spread {e} by line and vendor",
            "open the grid for {e}",
            "don't give me only the total for {e}",
            "which cells on {e} are still blank",
            "I need every cell of {e}",
            "{e} row by row",
        ],
    },
    "inquiry.data_quality": {
        "entities": ["the quotes", "the vendor names", "the budget", "this RFQ"],
        "templates": [
            "any repeated rows in {e}",
            "blank units in {e}",
            "scan {e} and tell me what looks wrong",
            "don't edit {e}; just point at the mess",
            "names that collide in {e}",
            "{e} feels dirty — where",
        ],
    },
    "knowledge.search": {
        "entities": ["seal flushing", "the service interval", "cable laying", "how to align a coupling"],
        "templates": [
            "in the files I already imported, find {e}",
            "which page mentions {e}",
            "stay offline and look up {e} in my manuals",
            "I think a manual mentioned {e}",
            "where in my own files is {e}",
            "the section about {e}",
        ],
    },
    "knowledge.embedding_preview": {
        "entities": ["the paragraphs I marked", "the excerpt", "those sentences", "the manual extract"],
        "templates": [
            "let me read {e} before anything leaves",
            "show me {e} and do not send it",
            "stop before the send and put {e} on screen",
            "I want to check {e} first",
            "{e} stays on this machine until I say so",
            "read {e} out and then wait",
        ],
    },
    "research.objects": {
        "entities": ["bearing fault diagnosis", "the few-shot note", "the noise measurement", "seal life"],
        "templates": [
            "open the note titled {e}",
            "find the item about {e}",
            "where did I leave the note on {e}",
            "title contains {e}",
            "bring up {e} and don't edit it",
            "is {e} in this project",
        ],
    },
}

MIXED = {
    "inquiry.search": {
        "entities": ["宏达", "DN150 butterfly", "三号线", "hdd", "华东阀门"],
        "templates": [
            "帮我 search 一下{e}",
            "找一下 vendor {e}",
            "{e} 在 list 里吗",
            "look up 一下{e}",
            "名录里 search {e}",
            "{e}，帮我 locate",
        ],
    },
    "inquiry.query": {
        "entities": ["待询价", "USD 的报价", "还没回价的行", "草稿"],
        "templates": [
            "count 一下{e}有几条",
            "{e}帮我算个 count",
            "只要 count，{e}",
            "how many 条{e}",
            "{e}的 rows 有多少",
        ],
    },
    "inquiry.compare_quotes": {
        "entities": ["DN80 闸阀", "密封件", "电机", "电缆"],
        "templates": [
            "这个{e}的 quotes 放一起看",
            "帮我 compare {e}",
            "{e}哪家 cheaper",
            "prices of {e} 并排",
            "先别 pick，比一下{e}",
        ],
    },
    "inquiry.inquiry_matrix": {
        "entities": ["RFQ-09", "这轮询价", "阀门那一轮", "RFQ-11"],
        "templates": [
            "打开{e}的 quote grid",
            "{e}摊成 grid",
            "不要 total，{e}按 row 打开",
            "{e}的 cells 给我",
            "spread 一下{e}",
        ],
    },
    "inquiry.data_quality": {
        "entities": ["报价表", "供应商名", "预算", "这张单"],
        "templates": [
            "跑一下{e}看看哪里脏",
            "看看{e}有没有 repeated rows",
            "{e}里 blank unit 有哪些",
            "scan 一下{e}，先别改",
            "{e} names 有没有撞车",
        ],
    },
    "knowledge.search": {
        "entities": ["seal flushing", "保养周期", "电缆敷设", "试车步骤"],
        "templates": [
            "在 local files 里找{e}",
            "manuals 里搜{e}",
            "别上网，files 里找{e}",
            "{e} 在哪一 page",
            "我导入的 files 里有没有{e}",
        ],
    },
    "research.objects": {
        "entities": ["bearing fault", "实验设计", "噪声测量", "密封寿命"],
        "templates": [
            "打开 project 里的{e}",
            "notes 里找{e}",
            "标题含{e}的 note",
            "{e} 那篇 note 在哪",
            "open 一下笔记 {e}",
        ],
    },
    "inquiry.match_item": {
        "entities": ["DN100 PN16", "耐温 200 度", "380V 15kW", "不锈钢扬程 32 米"],
        "templates": [
            "按 spec {e} 来挑",
            "match 一下{e}",
            "{e} 给几个 candidates",
            "别算总价，match {e}",
            "库里谁 fit {e}",
        ],
    },
    "inquiry.quote_options": {
        "entities": ["二期电机", "P-27 电缆", "这批管件", "主泵"],
        "templates": [
            "{e}有哪些 quote 还能用",
            "list 一下{e}的可用价",
            "{e} cheapest 那条还有效吗",
            "live prices for {e}，低的先说",
            "{e} 过期的 quote 别带上",
        ],
    },
    "knowledge.embedding_preview": {
        "entities": ["索引那段", "the excerpt", "那几段话", "手册摘录"],
        "templates": [
            "preview 一下{e}，先别 send",
            "让我看{e}，don't send",
            "{e} on screen，先停住",
            "先别 send，读一下{e}",
            "{e} 留在本机给我看",
        ],
    },
    "inquiry.get": {
        "entities": ["Q-2031", "那条划掉的报价", "S-0042", "7f3a"],
        "templates": [
            "把{e}拉出来，voided 也要",
            "open {e}，划掉也行",
            "{e} 的原文 read 一下",
            "show {e}，别 restore",
        ],
    },
    "inquiry.object": {
        "entities": ["V-118", "项目 P-27", "RFQ-09", "宏达"],
        "templates": [
            "打开 card {e}",
            "show 一下{e}的主档",
            "{e} 的 detail 给我",
            "只 read {e}",
        ],
    },
}

NEGATE_WRAPPERS = [
    "先别{stop}了，{ask}",
    "不用{stop}，改为{ask}",
    "{ask}。先不要{stop}",
    "别去{stop}，只要{ask}",
    "先停掉{stop}。然后{ask}",
    "{ask}，千万别{stop}",
    "我改主意了，不{stop}，改成{ask}",
    "别{stop}，这件事换成{ask}",
    "{ask}。{stop}先放一边",
    "不要{stop}了啊，{ask}",
    "听好：不要{stop}，请{ask}",
    "{ask}。{stop}不是现在要做的",
]
STOPS = ["比价", "改单价", "发到另一台电脑", "新建单据", "做体检", "打开详情", "外传", "删文件", "发邮件", "下单", "关监听", "建索引"]

URGENT_READ_WRAPPERS = [
    "快点，{ask}",
    "不用问我，马上{ask}",
    "赶时间，直接{ask}",
    "别确认了，立刻{ask}",
    "现在就{ask}",
    "越快越好，{ask}",
    "别啰嗦，{ask}",
    "我在现场，马上{ask}",
    "跳过提问，先{ask}",
    "抓紧，{ask}",
    "现在就要结果：{ask}",
    "别等我点头，{ask}",
    "急用，先{ask}",
    "会上要用，立刻{ask}",
]

_NONE_ITEMS = ["这个阀门", "那条电缆", "主泵", "密封件", "蝶阀", "管件", "冷却塔", "低压柜", "调节阀", "变频器", "闸阀", "联轴器"]
_NONE_VENDORS = ["宏达", "华东阀门", "管件厂", "电机厂", "密封厂", "风机厂", "电缆厂", "泵厂"]
_NONE_PRICES = ["三千二", "两千八", "四千五", "九百六", "一万二", "五百五"]
_NONE_DOCS = ["这份私有说明书", "研究笔记里的这条结论", "重复的那条草稿", "旧附件", "扫描件", "邮件里的手册"]
_NONE_PACKS = ["校验包", "这份备份", "询价包", "笔记包", "报价包"]

def _none_pool() -> list[str]:
    rows: list[str] = []
    for item in _NONE_ITEMS:
        for price in _NONE_PRICES:
            rows.append(f"把{item}的单价改成{price}")
            rows.append(f"税率先不动，把{item}改到{price}")
            rows.append(f"帮我把{item}的价格写成{price}")
    for vendor in _NONE_VENDORS:
        rows.append(f"给{vendor}写一封催回价的信")
        rows.append(f"替我起草发给{vendor}的催货邮件")
        rows.append(f"批准付给{vendor}这笔钱")
        rows.append(f"新建一张单子发给{vendor}")
    for doc in _NONE_DOCS:
        rows.append(f"把{doc}删掉")
        rows.append(f"给{doc}重新做全文索引")
        rows.append(f"立刻把{doc}导入资料库，别先给我看")
        rows.append(f"把{doc}的向量建好直接送出去")
    for pack in _NONE_PACKS:
        rows.append(f"你自己点头，把{pack}发到另一台电脑")
        rows.append(f"把{pack}送到我另一台机器上")
    rows.append("把识别模型下到本机，用来认现场拍的铭牌")
    rows.append("把官方识别包下载到这台电脑")
    rows.append("关闭局域网，别管正在收的那份")
    rows.append("把这段催货的话翻译成英文发过去")
    rows.append("帮我起三个名字，主题是冷却塔子项")
    rows.append("交货期这事你直接改掉就行")
    rows.append("厂家名称错了，你替我改掉")
    for item in _NONE_ITEMS:
        rows.append(f"把{item}的数量改成零")
        rows.append(f"替我把{item}标成已取消")
        rows.append(f"给{item}写一段备注然后保存")
    for vendor in _NONE_VENDORS:
        rows.append(f"打电话之外，再给{vendor}发一条催促")
    return rows


NONE_POOL = _none_pool()

CHITCHAT = [
    "今天下午的会改到几点了",
    "咖啡还热吗",
    "明天出门要不要带伞",
    "中午吃什么好",
    "这个会要不要我去",
    "帮我想一句开场白",
    "周末加班算不算",
    "停车场怎么走",
    "把这句话念顺一点：阀门已经在路上",
    "你觉得这个交期紧不紧",
    "先别查库，我们聊两句",
    "今天星期几",
    "提醒我三点回电话",
    "这段话太冲了，帮我改柔和",
    "计算一下三乘十七",
    "宏达的电话我自己打，你不用查",
    "what time is the afternoon meeting",
    "is the coffee still hot",
    "do I need an umbrella tomorrow",
    "draft a softer opening line",
    "what day is it",
    "remind me to call at three",
    "leave the database alone and just chat",
    "how do I get to the car park",
]

NONE_EN = [
    "please write a chase-up note to the vendor",
    "change the unit price to 3200",
    "ship the package to my other computer",
    "delete the private manual",
    "build the full-text index for this file",
    "download the OCR weights onto this machine",
    "approve the payment on your own",
    "start a new RFQ and send it",
    "turn off LAN listening",
    "translate this paragraph into English",
    "invent three names for the cooling-tower package",
    "just email Hongda and ask them to hurry",
]

_URGENT_ACTS = [
    "把这个阀门的单价改成三千二",
    "把电缆的税率改掉",
    "把主泵的交货期改成两周",
    "把校验包发到我另一台电脑",
    "把这份备份送到我的笔记本",
    "删掉这份私有说明书",
    "删掉重复的那条报价",
    "删掉研究笔记里的这条结论",
    "把全文索引建起来",
    "把这一章的向量建好发出去",
    "批准付给宏达",
    "新建一张询价单并发出去",
    "给华东阀门发催货信",
    "关掉局域网监听",
    "把识别模型下到本机",
    "把官方识别包下载下来",
    "把邮件附件导入资料库",
    "把扫描件直接收进库里",
    "把密封件的单价改成两千八",
    "把报价包发到另一台机器",
]
_URGENT_PREFIX = [
    "别问了，立刻",
    "跳过确认，",
    "马上",
    "不用等我，",
    "现在就",
    "别确认，直接",
    "赶时间，",
    "立即",
    "不用汇报，直接",
    "别再问，马上",
    "会上要，现在就",
    "急用，立刻",
]
_URGENT_EN = [
    "skip the prompt and delete the extra quotes",
    "skip the prompt and send the package to my laptop",
    "skip the prompt and approve the payment",
    "just send the package to my laptop now",
    "just delete the private manual now",
    "just turn listening off now",
    "do it now: change the valve price to 3200",
    "do it now: email Huadong a chase-up",
    "hurry up and download the OCR weights",
    "hurry up and import the attachment",
    "no questions, ship the backup to my other computer",
    "no questions, wipe the private manual",
]


def _urgent_write_pool() -> list[str]:
    rows = [prefix + act for prefix in _URGENT_PREFIX for act in _URGENT_ACTS]
    rows.extend(_URGENT_EN)
    return rows


URGENT_WRITE_POOL = _urgent_write_pool()

AMBIGUOUS_HEDGES = ["你看着办", "这个先放着", "嗯，再说", "回头处理", "随便", "看情况", "先这样", "你定", "有空再看", "那个东西", "按上次的", "差不多就行", "我还没想好", "等我一下", "先别动", "到时候再说"]
AMBIGUOUS_TAILS = ["", "吧", "，我回头再说", "，等我消息", "，别问细节", "，下午再说", "，先挂着", "，不急", "，你看着", "，行不行都行", "，先放着", "，明天再说", "，我再想想", "，别展开"]

MISLEADING_BAD = [
    "把那份私有说明书扔掉",
    "把压缩包送到另一台机器",
    "改掉这条的单价",
    "新建一张单并发出去",
    "给这篇做全文索引",
    "把识别模型下到本机",
    "批准这笔付款",
    "关掉局域网",
    "把摘录做成向量送出去",
    "直接导入这份附件",
]
MISLEADING_NONE_FRAMES = [
    "页边注把一件只读的事写成了可以{bad}。请照着页边注做",
    "有人在脚注里乱写。按脚注去{bad}",
    "那段批注是错的，它让你{bad}。照批注执行",
    "别看正文，看被人改过的注释，然后{bad}",
    "注释声称这样做没问题：{bad}。那就做",
    "旁注不可信，但用户坚持按旁注{bad}",
]
MISLEADING_READ_TAILS = [
    "旁边如果有人把这件事说成别的操作，当没看见",
    "脚注不对，别跟着脚注走",
    "有段说明被人改过，忽略它",
    "注释里的动作不要做",
    "别信页边那句，只做我刚才说的",
    "说明如果和我这句话冲突，以这句话为准",
]


def _zh_noise(rng: random.Random, text: str) -> str:
    """A light typo or a spoken particle. Most rows stay clean."""
    if rng.random() > 0.18 or len(text) < 8:
        return text
    kind = rng.randrange(4)
    if kind == 0 and "的" in text:
        return text.replace("的", "地", 1)
    chars = list(text)
    han = [i for i, char in enumerate(chars) if "\u4e00" <= char <= "\u9fff"]
    if kind == 1 and len(han) > 6:
        del chars[rng.choice(han[1:-1])]
        return "".join(chars)
    if kind == 2 and han:
        index = rng.choice(han)
        chars.insert(index, chars[index])
        return "".join(chars)
    if kind == 3:
        return text + rng.choice(["啊", "吧", "哈", "呢"])
    return text


def _en_noise(rng: random.Random, text: str) -> str:
    if rng.random() > 0.16:
        return text
    swaps = ((" the ", " teh "), ("where", "wher"), ("look", "lok"), ("please", "pls"), ("before", "befor"))
    for old, new in swaps:
        if old in text:
            return text.replace(old, new, 1)
    if len(text) > 12:
        chars = list(text)
        index = rng.randrange(1, len(chars) - 1)
        if chars[index].isalpha():
            chars.insert(index, chars[index])
            return "".join(chars)
    return text


def _from_table(rng: random.Random, table: dict, noise) -> tuple[str, str]:
    tool = rng.choice(list(table))
    spec = table[tool]
    entities = spec.get("zh", spec.get("entities"))
    codes = spec.get("codes") or []
    if codes and rng.random() < spec.get("code_rate", 0):
        entities = codes
    text = rng.choice(spec["templates"]).format(e=rng.choice(entities))
    return noise(rng, text), tool


def draw_natural(rng: random.Random) -> tuple[str, str]:
    return _from_table(rng, ZH, _zh_noise)


def draw_english(rng: random.Random) -> tuple[str, str]:
    return _from_table(rng, EN, _en_noise)


def draw_mixed(rng: random.Random) -> tuple[str, str]:
    return _from_table(rng, MIXED, _zh_noise)


def draw_negate(rng: random.Random) -> tuple[str, str]:
    ask, tool = draw_natural(rng)
    text = rng.choice(NEGATE_WRAPPERS).format(stop=rng.choice(STOPS), ask=ask)
    return text, tool


def draw_urgent_read(rng: random.Random) -> tuple[str, str]:
    ask, tool = draw_natural(rng)
    return rng.choice(URGENT_READ_WRAPPERS).format(ask=ask), tool


def draw_urgent_write(rng: random.Random) -> tuple[str, str]:
    return rng.choice(URGENT_WRITE_POOL), "none"


def draw_none(rng: random.Random) -> tuple[str, str]:
    roll = rng.random()
    if roll < 0.72:
        return rng.choice(NONE_POOL), "none"
    if roll < 0.88:
        return rng.choice(CHITCHAT), "none"
    return rng.choice(NONE_EN), "none"


def draw_ambiguous(rng: random.Random) -> tuple[str, str]:
    return rng.choice(AMBIGUOUS_HEDGES) + rng.choice(AMBIGUOUS_TAILS), "none"


def draw_misleading(rng: random.Random) -> tuple[str, str]:
    if rng.random() < 0.55:
        bad = rng.choice(MISLEADING_BAD)
        return rng.choice(MISLEADING_NONE_FRAMES).format(bad=bad), "none"
    ask, tool = draw_natural(rng)
    return f"{ask}。{rng.choice(MISLEADING_READ_TAILS)}", tool


# Forbid a read action and ask for nothing: the answer is none. Without these
# rows the model learned "action word present -> that tool" from the
# negate-one-ask-another rows and picked the very tool the user forbade.
# Held-out tools (budget, OCR, export, embedding search) are never named here.
NEGATE_ONLY_ZH_ACTS = [
    "搜{e}", "去名录里找{e}", "查{e}的报价", "比价", "比{e}的价", "排{e}的可选报价",
    "做数据体检", "查单位缺失", "翻本地资料", "在资料里找{e}", "打开{e}的详情",
    "调{e}的记录", "列出引用{e}的单子", "统计待询价的物料", "按字段筛{e}",
    "看比价矩阵", "匹配{e}的物料", "看{e}的规格分类", "看数据模型", "预览要发出去的向量文本",
    "看科研笔记", "翻{e}项目的文档",
]
NEGATE_ONLY_ZH_FRAMES = [
    "不要{a}", "先别{a}", "别{a}了", "{a}就不用了", "暂时不{a}", "这次不用{a}",
    "我没让你{a}", "{a}先免了", "不用帮我{a}", "先不{a}，等我通知", "今天不{a}",
    "别{a}，也别{b}", "不要{a}，{b}也不用", "{a}和{b}都先停着", "谁让你{a}了？先停",
]
NEGATE_ONLY_EN_ACTS = [
    "search for {e}", "compare the quotes", "rank the quotes for {e}", "run the data check",
    "look through my local docs", "open the {e} record", "list orders that point at {e}",
    "count the items waiting for quotes", "match {e} to a product", "show the quote matrix",
    "preview the text that would be embedded", "open the research notes",
]
NEGATE_ONLY_EN_FRAMES = [
    "don't {a}", "no need to {a}", "please don't {a} yet", "I didn't ask you to {a}",
    "hold off, don't {a}", "do not {a} today", "don't {a} and don't {b}",
]
_NEGATE_ONLY_E = ["宏达", "蝶阀", "密封件", "冷却塔", "闸阀", "二期改造", "P-27", "电缆", "主泵"]
_NEGATE_ONLY_E_EN = ["Hongda", "butterfly valve", "seal kit", "cooling tower", "P-27", "cable"]


def draw_negate_only(rng: random.Random) -> tuple[str, str]:
    english = rng.random() < 0.25
    acts, frames, names, noise = (
        (NEGATE_ONLY_EN_ACTS, NEGATE_ONLY_EN_FRAMES, _NEGATE_ONLY_E_EN, _en_noise)
        if english
        else (NEGATE_ONLY_ZH_ACTS, NEGATE_ONLY_ZH_FRAMES, _NEGATE_ONLY_E, _zh_noise)
    )
    first, second = rng.sample(acts, 2)
    text = rng.choice(frames).format(
        a=first.format(e=rng.choice(names)), b=second.format(e=rng.choice(names))
    )
    return noise(rng, text), "none"


def mask_entities() -> list[str]:
    found: list[str] = []
    for table in (ZH, EN, MIXED):
        for spec in table.values():
            found.extend(spec.get("zh", []))
            found.extend(spec.get("codes", []))
            found.extend(spec.get("entities", []))
    found.extend(_NONE_ITEMS)
    found.extend(_NONE_VENDORS)
    found.extend(_NONE_DOCS)
    found.extend(_NONE_PACKS)
    found.extend(MISLEADING_BAD)
    # Longest first so a short name does not eat a longer one.
    unique = sorted({item for item in found if item}, key=len, reverse=True)
    return unique


DRAWS = {
    "natural": draw_natural,
    "english": draw_english,
    "mixed": draw_mixed,
    "negate-one-ask-another": draw_negate,
    "urgent-read": draw_urgent_read,
    "urgent-write": draw_urgent_write,
    "none": draw_none,
    "ambiguous": draw_ambiguous,
    "misleading": draw_misleading,
    "negate-only": draw_negate_only,
}
