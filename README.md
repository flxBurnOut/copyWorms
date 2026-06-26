织梦者 — Dreamweaver
Godot 4.6 2D 横向叙事探索动作游戏 | 黑客松项目
岭南文化 × 赛博未来 × 梦境撕裂

🎮 游戏简介
织梦者 是一款以「岭南文化」与「赛博朋克」碰撞融合为主题的 2D 动作叙事游戏。玩家扮演一名剑客，穿梭于被数字侵蚀撕裂的梦境世界，在岭南旧梦与赛博蜃境之间切换，迎战越来越强的敌人，最终直面花旦 Boss 守护梦境核心。

世界观
一场数据入侵正在吞噬梦境。梦境深处的记忆碎片被数字化侵蚀，古老的街巷与赛博城市交替闪现——你需要找到侵蚀的源头，并斩断它。

🎯 核心特性

🎨 双世界切换 — 岭南古风与赛博未来两种风格的自由切换，像素地图拼接渲染

⚔️ 多样化敌人 AI — 5 种不同敌人类型，包含漂浮、冲撞、远程、召唤等行为模式

👹 花旦 Boss 战 — 4 阶段 Boss AI，2800+ 行决策逻辑，悬停系统、剑气弹幕、近战连击

📖 深度叙事 — 7 态叙事状态机，多角色对话系统，可交互式 IDE 自由对话

🌀 维度侵蚀系统 — 侵蚀值实时增长机制，shader 驱动的画面撕裂与色彩腐蚀特效

🛡️ 防火墙屏障 — Glitch 特效系统，能量带流动 + 横向撕裂 + RGB 色散

🔧 Code-Buddy 主题 IDE — 关卡内嵌可交互代码编辑器，模拟 AI 编译

🛠️ 技术栈

技术	说明

引擎	Godot 4.6 (GL Compatibility Mode)

语言	GDScript

分辨率	1280×720，canvas_items 拉伸

部署	Docker + Nginx (Alpine)

Web 导出	Godot Web Export (WASM + SharedArrayBuffer)

架构模式	事件驱动 (EventBus) + 状态机 (FSM)

📁 项目结构

黑客松正式项目文档/
├── build/web/             # Godot Web 导出产物
│   ├── index.html         # 入口 HTML
│   ├── index.js           # JS 胶水层
│   ├── index.wasm         # WebAssembly 核心
│   ├── index.pck          # 资源包
│   └── index.*.worklet.js # Audio Worklet
├── Dockerfile             # Docker 构建配置
├── nginx.conf             # Nginx 配置（含 COOP/COEP 头）
├── entrypoint.sh          # 容器启动脚本
├── TECHNICAL_ARCHITECTURE_REPORT.md  # 技术架构报告
└── WORK_SESSION_SUMMARY.md           # 工作会话总结
注意：以上仅为部署相关文件。完整游戏源码（Godot 项目）包含以下关键模块：

模块	路径	说明

全局系统	Global/	EventBus、GameManager、InputManager、GlobalDefine、KeybindManager

玩家系统	PlayerModule/Formal/	PlayerBase + 3 种皮肤（Warrior/Cyber/Lingnan）

敌人系统	EnemyModule/Formal/	5 种敌人 + Boss 花旦 4 阶段 AI

关卡系统	LevelModule/Formal/	Level_01 ~ Level_05，关卡基类 + 场景构建器

像素地图	LevelModule/Scenes/PixelworkMapStitch/	多层拼接地图系统

工具类	Tools/	剑气弹体、CodeRain 渲染、防火墙特效

UI 系统	UI/	TitleScreen、MainEntry、HUD

资源	Assets/	精灵图、音乐、Shader 特效

🎮 关卡概览

关卡	名称	核心玩法

Level_01	苏醒	7 态叙事状态机，熟悉操作，IDE 编码互动

Level_02	阁楼→老街	分段式关卡链，纸扎人 + 灯笼鬼，梯子攀爬解谜

Level_03	赛博蜃景	6 态空间异化，回声收集，防火墙系统

Level_04	维度侵蚀	半对半空间硬切，赛博↔岭南瞬移切换

Level_05	双世界撕裂	双世界 Map Stitch，侵蚀值系统，花旦 Boss 战

👹 Boss：花旦（Huadan）

花旦是本作的最终 Boss，拥有 4 阶段 渐进式 AI 系统：

阶段	HP 范围	核心特性

Phase 1	600~451	基础行为，高闪避(70%)，易打断

Phase 2	450~301	霸体免疫打断，移速+10%

Phase 3	300~151	🔥 跳跃悬停，3 发独立瞄准剑气，空中 10s

Phase 4	150~0	🔥 近战+剑气连击，移速暴增至 350，极低闪避(15%)

行为决策：每 0.3s 评估一次，包含 IDLE / APPROACH / RETREAT / RANGED / MELEE / EVADE / JUMP / HOVER 共 8 种行为，各阶段独立决策树。


🔧 本地开发

环境要求

Godot 4.6（GL Compatibility Mode）

使用 Godot 编辑器打开项目根目录

Web 导出

在 Godot 编辑器中配置 Web 导出预设

确保启用 ensure_cross_origin_isolation_headers = true

导出到 build/web/ 目录

使用上述 Docker 方式部署

注意：Godot 4 Web 导出依赖 SharedArrayBuffer，需要服务端返回 Cross-Origin-Opener-Policy 和 Cross-Origin-Embedder-Policy 头，已在内置 Nginx 配置中处理。

🎨 视觉风格

像素艺术: 基于像素拼接的地图系统（PixelworkMapStitch）

Shader 特效: Glitch 撕裂、RGB 色散、色彩腐蚀、警告屏障

CodeRain: 自绘代码雨系统（_draw() + Silkscreen 像素字体）

双世界美学: 岭南古风（暖色调街巷）+ 赛博未来（终端绿霓虹）

📝 变更日志

最新版本 v0.12.0 主要更新：



✅ CodeRain 完全重写（_draw() 实时渲染）

✅ 防火墙屏障 Glitch 特效系统

✅ Level_05 双世界侵蚀 + BossHuadan 花旦 4 阶段 AI

✅ 剑气弹道追踪系统

✅ 花旦悬停 + 3 发独立瞄准剑气

✅ 近战附带剑气连击（Phase 4）

✅ 全局事件驱动架构完善

详细变更请参见 TECHNICAL_ARCHITECTURE_REPORT.md


🤝 贡献

本项目为黑客松竞赛作品，欢迎 Fork 和 Star！

📄 许可证

本项目仅供学习和竞赛用途。

Made with Godot 4.6