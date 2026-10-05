# 仓库维护与发布说明

审查对象：https://github.com/Cfeat/CE-DRAPLINE ，main 分支 f91d552。

## 已修正或补齐

1. 原 `DRAPLINE.CT` 内嵌本机路径的散列标识，其他安装路径直接打开不能连接。新增 `DRAPLINE_SingleFile.CT` 自动查找桥接、选择游戏并计算正确标识；脚本版提供重新生成方式。
2. 安装脚本的旧提示指向仓库不存在的 `DRAPLINE_v2.CT`，已统一为 `DRAPLINE.CT`。
3. 原卸载脚本使用清单记录的绝对路径，整体移动游戏后可能定位旧目录。现在使用当前游戏目录并校验备份与启动文件散列；单文件版同样支持移动后卸载。
4. 仓库此前没有构建脚本。新增/补充构建脚本及兼容性指纹；无游戏数据时可以复用现有 CT 内的目录，生成单文件版。
5. 安装增加版本和运行状态校验；已有桥接时兼容原备份，拒绝覆盖其他工具修改过的启动文件。
6. README 补充正确目录结构、跨电脑使用、单文件版首次安装条件、构建及测试方式；保留作者的说明与赞助内容。

## 发布给普通用户

发布 **v3.0.0** 的 `DRAPLINE_SingleFile.CT` 即可。已完成原生 CE 7.7 的实际 CT 加载、重新打开后自动连接、道具与技能往返验证，以及真实游戏启动与标题连接检查。适合同时作为 GitHub Releases 的附件，用户无需下载整个源码仓库。

## 仓库文件

保留已有的 `DRAPLINE.CT`、`bridge/renderer.js`。

更新：

- `README.md`
- `Install.ps1`
- `Uninstall.ps1`
- `table.lua`
- `bridge/main.mjs`

新增：

- `DRAPLINE_SingleFile.CT`
- `single_file.lua`
- `single_file.ps1`
- `build_table.py`
- `compatibility.json`
- `validate_single_file.py`
- `validate_native.lua`
- `validate_native.ps1`
- `validate_engine.mjs`
- `CHANGELOG.md`
- `SHA256SUMS.txt`
- `.gitignore`
- `.gitattributes`
- `UPLOAD.md`

不要上传本机的 `backup`、`save`、`.omo`、`.codegraph` 或测试使用的个人存档副本。`validate_engine.mjs` 已改为从命令参数读取本地存档，不包含个人存档路径。游戏源码/数据由用户自己的游戏提供；本项目不需要上传游戏本体。

## 可选补充

- 根据作者希望允许的使用和再发布方式选择许可证；当前没有代替作者添加 LICENSE。
- 当前适配游戏界面标注的 1.0.0 中文版本，并提供实际引擎及数据库文件的散列校验；同版本号的其他发行包仍需匹配指纹。
- 若将来增加其他游戏版本，为各版本增加明确的指纹和数值映射，不直接放宽现有校验。

发布时可将 `DRAPLINE_SingleFile.CT` 作为 GitHub Releases 附件，普通用户只需下载这一张表。`SHA256SUMS.txt` 提供该正式 CT 的校验值；重新构建并发布后应同步更新。构建源码包时只包含上述文件；本地 `release/` 产物目录已加入忽略规则。
