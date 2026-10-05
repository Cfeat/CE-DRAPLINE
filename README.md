# DRAPLINE 中文 CE 表

此表通过一个本地桥接模块调用游戏 API；不是纯内存地址表。

## 单文件版（推荐用于其他电脑）

当前正式版为 **v3.0.0**。适配已校验的 Windows 中文版 DRAPLINE 1.0.0（未封包的 RPG Maker MZ + Electron 版本）；具体兼容性以 `compatibility.json` 中的引擎和数据库指纹为准。

只需[下载单文件 CT](https://github.com/Cfeat/CE-DRAPLINE/raw/refs/heads/main/DRAPLINE_SingleFile.CT)，在 Cheat Engine 中打开并允许运行这份表的 Lua。无需 Python、Node.js 或单独下载安装脚本。下载后的文件名应为 `DRAPLINE_SingleFile.CT`；校验值见 [SHA256SUMS.txt](SHA256SUMS.txt)。

使用 Windows 64 位 Cheat Engine 7.5 或更新版本及 Windows 自带 PowerShell。已在 CE 7.7 上完成原生验证；旧版 CE 缺少所需接口时会提示升级。

- 已安装桥接并运行游戏时，表会自动查找桥接并启用连接。存在多个游戏实例时，需要选择目标游戏。
- 首次使用：先在游戏内保存并正常退出，再打开 CT；按文件选择窗口指定 `DRAPLINE.exe`。CT 会校验游戏版本、备份并安装桥接，然后自动启动游戏并连接。进入存档后可使用全部数值、道具和技能功能。
- 自动检测未成功时，展开「单文件设置」，点击「一键连接 / 首次安装」；通过「选择或切换游戏」更换目标目录。
- 卸载时先保存并退出游戏，在 CT 的「单文件设置」点击「卸载桥接」。备份及当前存档保留。

「单文件」表示分发时只携带一张 CT。首次安装会在游戏目录生成 `resources/app/electron/drapline-ce` 模块、`CE-DRAPLINE/backup` 备份，并在用户临时目录生成本地设置脚本及连接缓存。无需运行外部命令；CT 内置的设置通过 Windows 自带 PowerShell 执行，不联网下载模块。

首次为已经运行且未安装桥接的游戏安装时，仍需先保存退出。CT 不会强行关闭游戏或直接向 V8 注入代码。兼容性校验目前针对本项目适配的 Windows、未封包的 RPG Maker MZ + Electron 中文游戏版本；其他版本会停止安装。游戏和 CE 应使用同一 Windows 用户运行。

## 已包含

- 金币、债务。
- 当前行动力、最大行动力、气质（-50～50）。
- 龙娘永久养成属性：HP、STR、VIT、INT、RES、AGI。
- 龙娘当前 HP、BP，战斗中保持满 HP，以及单次回满 HP。
- 已过周数只读显示。
- 道具数量编辑器：默认包含常规道具和全部 78 种神器 / 重要道具；名称或 ID 搜索全部分类，支持常规/神器/隐藏道具筛选、仅显示持有、设置最终数量。输入 0 可移除道具。
- 技能拥有状态编辑器：中文名称或 ID 搜索、战斗/被动技能筛选、仅显示拥有、学会或忘记选中技能，并显示已装备状态。

## 脚本版使用

1. 将仓库文件放到游戏根目录下的 `CE-DRAPLINE` 文件夹中，形成 `DRAPLINE.exe` 与 `CE-DRAPLINE` 并列的结构。先保存并退出游戏。
2. 安装 Python 3.9 或以上版本，在此目录执行 `python .\build_table.py`，再执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1`，然后重新启动游戏。该 PowerShell 参数仅作用于本次脚本，不更改系统策略。
3. 在 Cheat Engine 打开 `DRAPLINE.CT`，允许运行这份表的 Lua 脚本。
4. 勾选「启用连接」，读档或进入养成。标题、读档界面和没有角色 1 的队伍不能修改。
5. 双击对应行的「值」输入整数；勾选数值行锁定，取消勾选解锁。
6. 停用「启用连接」或关闭表后，锁定自动释放。游戏保留最后修改的数值；如果希望永久保存，请在游戏内正常存档。

脚本版的 `DRAPLINE.CT` 包含生成时的路径标识，移动游戏目录或在另一台电脑使用时必须重新生成。单文件版会自动匹配所选路径，不需要重新生成。

## 道具与技能

展开 CT 的「道具 / 技能」，勾选「打开道具数量编辑器」或「打开技能拥有状态编辑器」。入口会自动取消勾选，可反复打开。

道具编辑器默认显示「全部道具（常规＋神器）」，其中包含本游戏全部 78 种神器 / 重要道具。也可单独选择「神器 / 重要道具」。选中目标，填写最终数量，再点击「设置数量」。本版本游戏通常最多持有 99 个同类道具。数量 0 表示从背包移除。重复名称可用 ID 区分；「仅显示持有」便于查看当前背包，查看未持有道具时请取消该选项。

输入名称或 ID 时，会查找全部分类，包括隐藏道具，不受分类下拉框限制。清空搜索后恢复当前分类。「隐藏道具 / 图鉴」包含图鉴和事件用途的条目；「全部数据库（高级）」显示所有 544 条有名称的道具记录，包括游戏内部的分类标题。

技能编辑器默认显示角色可学习的战斗技能及被动技能。选中技能后点击「学会」或「忘记」；可以筛选「仅显示拥有」查看已拥有技能。战斗技能的「已拥有」同时包括未装备和已装备的技能，避免将已装备技能误判成未学会。忘记已装备技能时会同时清理装备槽。被动技能会刷新角色数值，不需要装备。

技能请在非战斗状态下编辑。来自装备或状态的临时技能应在游戏内移除相应来源。「全部（高级）」还包含敌人技能和内部辅助技能。学会战斗技能后，可以在游戏内技能装备界面管理装备；CT 不改变技能槽和装备费用规则。游戏菜单已打开时，切换一次界面即可重新显示最新列表。

## 备份和卸载

`Install.ps1` 自动备份原始 `resources/app/electron/main.mjs` 及安装时已有的 `save` 目录到 `CE-DRAPLINE/backup`，并记录 SHA-256。备份不会覆盖你之后的存档。

卸载：关闭游戏并在此目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1`，然后重启游戏。卸载恢复原始启动文件，不覆盖当前存档。如果启动文件后来被其他工具修改，卸载脚本会停止以保护那些修改。模块源码和备份保留供检查。

## 代码说明

`bridge/renderer.js`：变量映射、输入范围和锁定逻辑。
`bridge/main.mjs`：Electron 本地文件通信。
`table.lua` ：CE Lua。

`single_file.lua`：单文件版的路径选择、自动连接及设置控制器。

`single_file.ps1`：内嵌安装/卸载模板，由构建脚本填入模块内容；不是供用户直接运行的独立脚本。

`compatibility.json`：适配游戏数据和引擎的 SHA-256 指纹，不包含游戏文件或安装路径。

`build_table.py`：生成脚本版或单文件版。开发者可执行 `python build_table.py --single-file`，产物为 `DRAPLINE_SingleFile.CT`。有本地游戏时可传 `--game-root "游戏根目录"`；没有本地游戏时复用仓库 `DRAPLINE.CT` 内的道具/技能目录。

## 验证与上传

`validate_single_file.py` 在隔离目录中测试实际嵌入 CT 的安装脚本，覆盖中文/空格/引号路径、版本校验、备份、重复安装、桥接发现、移动后卸载、其他修改保护、运行中游戏保护及存档保留。运行方式：`python validate_single_file.py --game-root "游戏根目录"`；可用 `--ce-dir "Cheat Engine目录"` 校验 CE Lua 语法。

`validate_native.lua` 是单独 CE 实例的验证驱动，默认不执行。它通过专用环境变量指向上述隔离目录，检查实际 CT 加载、原生控件及命令往返。不要在日常 CE 实例中设置测试环境变量。

运行原生验证：先执行上述 Python 验证，复制最后输出的测试目录；再运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\validate_native.ps1 -Fixture "测试目录" -CeDirectory "Cheat Engine目录"`。该驱动只操作隔离的模拟游戏，完成后清理自己创建的 CE 实例和测试 autorun 文件。

开发者可用 Node.js 运行 `node validate_engine.mjs --game-root "游戏根目录" --save "本地存档.rmmzsave"`，验证游戏实际对象、常规/重要道具和 AbilitySystem 技能插件。请选择龙娘角色 1 已在队伍中的存档。脚本只读取存档并在内存副本中测试，不写回文件；存档不要上传到仓库。

v3.0.0 的验证覆盖：47 段 CE Lua 语法、34 个唯一条目 ID；实际 CT 加载与重新打开后的自动连接；中文路径；120 种默认道具（含 78 种神器 / 重要道具）；跨分类中文搜索；道具修改及技能学会/忘记往返；备份、移动后卸载、版本与运行状态保护。另已核对真实游戏的自动启动和标题界面连接，并用游戏实际对象及技能插件验证数值和技能操作。测试未修改实际游戏存档中的进度数值。

上传文件及仓库审查结论见 `UPLOAD.md`。不要上传 `backup`、`save`、游戏本体、临时通信文件或个人工具索引；`.gitignore` 已包含本项目生成的备份与索引目录。

CE 行事件接口参见 [Cheat Engine 官方 MemoryRecord 文档](https://wiki.cheatengine.org/index.php?title=Lua%3AClass%3AMemoryRecord)。

版本记录见 `CHANGELOG.md`。项目未附游戏文件；`DRAPLINE.CT` 保留原有脚本版，跨电脑分发建议使用 `DRAPLINE_SingleFile.CT`。

## 支持与赞助

如果使用过程有什么问题，欢迎issues留言~

开发不易，若您乐意，可以赞助一杯咖啡，谢谢喵QwQ

<img width="1280" height="1744" alt="34639e7b9df9f4c0d2cf14b3533cf367" src="https://github.com/user-attachments/assets/d3c814f0-4291-4c56-bf01-c3eb1caf981b" />

