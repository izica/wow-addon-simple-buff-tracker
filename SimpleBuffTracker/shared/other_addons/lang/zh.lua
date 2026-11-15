-- zh.lua -- the texts of the "Other addons" page, Simplified Chinese. Part of
-- the shared/other_addons module: copied with it into every addon of the author.
-- Offered only on a Chinese client: other clients have no Chinese letters in
-- their fonts.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.zh = {
    language_name = "简体中文",
    language = "语言",
    title = "其他插件",
    subtitle = "更多 WoW Forever 插件。已安装：%d / %d。",
    footer = "复制名称，到 CurseForge 搜索。",
    copy = "复制名称",
    copy_hint = "Ctrl+C 复制",
    copied = "已复制！",
    state = {
        loaded = "已安装",
        disabled = "已安装，已禁用",
        missing = "未安装",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "为你遇到的玩家写备注：显示在姓名板、鼠标提示和聊天中。",
        prr = "物品由什么制作、可作为哪些配方的材料：显示在鼠标提示和配方窗口中。",
        target_it = "动作条样式的按钮，选中你指定的最近的存活 NPC：任务怪优先。",
        simple_buff_tracker = "你的增益显示在一排图标上：全部带计时，或只显示缺少的。点击即可补上增益。",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "一键为任何人写备注：现成短语或自定义文字",
            "备注显示在姓名板上方、聊天和鼠标提示中",
            "被标记的玩家出现在附近时有声音提醒",
            "周围玩家窗口，以及可搜索的全部相遇记录",
            "与公会共享备注",
            "每条备注都有署名和日期：每个角色都可以有自己的备注",
        },
        prr = {
            "每个物品的鼠标提示中显示“制作来源”和“用作材料”",
            "配方窗口：Alt+点击任意物品，沿材料链查看，收藏夹",
            "制作规划：拍卖行价格、利润，以及最省钱的专业升级路线",
            "内置约 2500 个 WoW Forever 配方，无需扫描",
            "界面支持 8 种语言，物品和配方名称来自你的游戏客户端",
        },
        target_it = {
            "动作条样式的按钮：点击即选中你指定的最近的存活 NPC",
            "任务怪和任务 NPC 优先；可搜索 10000 多个 NPC",
            "为目标加团队标记，每个按钮可设快捷键",
            "Alt+点击：在最近的刷新点设置路径点",
            "记住你见到的 Forever 新 NPC",
        },
        simple_buff_tracker = {
            "你的增益显示在一排动作条样式的图标上：带计时，或只显示缺少的",
            "左键点击补上增益：施放法术、吃食物获得进食充分、为武器涂油",
            "也能追踪武器附魔，甚至同一把武器上的油和火舌",
            "缺少的增益会发光，三种图标样式，任意大小和增长方向",
            "右键点击面板上的增益即可打开其设置",
        },
    },
}
