<p align="center">
  <img src="assets/logo.svg" alt="Plasma Island 标志" width="128" height="128">
</p>

# Plasma Island

KDE Plasma 6 顶部面板上的「灵动岛」风格胶囊组件。

- **平时**：黑色胶囊显示时间；播放音乐时带一个跳动的均衡器。
- **悬停**：向两侧弹开——左侧天气，右侧日期。
- **点击时间**：下方展开同色卡片，显示正在播放的内容——封面、标题、艺术家、可点击或拖动跳转的进度条，以及上一首 / 播放暂停 / 下一首。在卡片上滚动可调节播放器音量；点击封面可把播放器窗口切到前台。
- **点击天气**：显示详情——天气状况、体感温度、湿度、风速、今日最高/最低温和未来数天预报。未设置城市时，胶囊显示「设置城市」，点击打开设置。
- **点击日期**：月历（可用箭头或滚动翻月）和世界时钟。
- **新曲目**：胶囊会短暂展开显示新歌标题（可关闭）。
- **中键点击**：直接播放/暂停，不打开卡片。

再次点击同一位置，或点击其他位置，即可关闭卡片。

媒体功能通过 Plasma 自带的媒体服务支持任何兼容 MPRIS 的播放器（Spotify、浏览器、VLC、Elisa、mpv…），并跟随 Plasma 认为当前活跃的播放器。

默认天气数据来自[中国气象局](https://www.nmc.cn)（免费、无需账号），每 15 分钟刷新，覆盖中国城市，提供实况和 7 天预报。也可以在设置中改用[高德天气](https://lbs.amap.com/api/webservice/guide/api/weatherinfo)：填入高德 **Web 服务** Key 后即可按城市搜索，每 30 分钟刷新，提供实况和 4 天预报；高德没有体感温度和数值风速，风力以等级显示。温度单位（°C/°F）跟随系统区域设置。时间格式（12/24 小时制）和日期格式默认跟随系统区域设置，可在设置中修改。

## 安装

```sh
./install.sh
```

然后右键顶部面板 → **添加或管理组件** → 搜索 **Plasma Island** 并拖到面板上。右键胶囊 → **配置 Plasma Island…**，可以切换天气源（中国气象局 / 高德天气，高德需填写 Web 服务 Key）、搜索并选择城市、调整大小（胶囊高度，单位 px，默认 32；卡片会等比缩放）、语言、透明背景（仅文字，使用面板颜色）、时间与日期格式（12/24 小时制、多种日期样式，或自定义 Qt 格式如 `HH:mm:ss`、`yyyy-MM-dd`，不受系统区域设置影响）、显示秒以及新曲目提示。**时区**页面可添加任意数量的世界时钟（搜索城市，点击添加，用箭头调整顺序）。也可以按住 **Ctrl** 在胶囊上滚动，实时调整大小。

想让胶囊居中，可在其左右各放一个 **弹性间隔**（面板编辑模式 → 添加间隔）。间隔会把剩余空间均分，因此只有左右控件等宽时，胶囊才正好位于屏幕中央。

你可能还想把面板上 Plasma 自带的数字时钟移除。

## 翻译

Plasma Island 已翻译为希腊语、西班牙语、德语、俄语和简体中文（跟随系统语言）。
要新增或修正语言，编辑或复制 [`po/`](po) 中的文件（例如从 `po/plasma_applet_io.github.luminarysrc.plasmaisland.pot` 复制出 `po/fr.po`），然后提交 Pull Request。`./install.sh` 会用 `msgfmt`（来自 gettext）编译它们。

## 语言

English、Русский、Español、Deutsch、Ελληνικά 和简体中文。默认跟随 Plasma 语言；**配置 → 语言** 可以只为本组件覆盖语言（卡片、设置、月份和星期名称）。天气中的城市名来自中国气象局或高德，显示为中文。翻译由 AI 生成，欢迎指正——编辑 `po/<lang>.po` 文件并提交 Pull Request。

Plasma 会对整个桌面只应用一种语言，因此组件自带一份文案：`po/gen-js.py` 会把 `po/*.po` 转换成 `package/contents/ui/Translations.js`。`./install.sh` 和 `./package.sh` 会通过 `po/build.sh` 执行它，生成的文件也会提交到仓库。
要新增语言，复制 `po/plasma_applet_io.github.luminarysrc.plasmaisland.pot` 为 `po/<lang>.po`，翻译后把该语言加到 `package/contents/ui/configGeneral.qml` 的列表中。

## 更新

```sh
git pull && ./install.sh
systemctl --user restart plasma-plasmashell   # Plasma 会缓存旧 QML，需重启
```

## 卸载

```sh
kpackagetool6 -t Plasma/Applet -r io.github.luminarysrc.plasmaisland
```

## 发布到 KDE Store

1. 修改 `package/metadata.json` 中的 `Version`（商店和「获取新组件」会据此检测更新）。
2. 运行 `./package.sh` 生成 `plasma-island-<version>.plasmoid`，其中已包含翻译。不要手动压缩 `package/`：编译后的翻译是生成文件，不在仓库中。
3. 把文件作为新版本上传到现有商店页面。不要修改 `Id`。

## 说明

- 专为水平（顶部）面板设计。
- 胶囊会在面板中预留展开后的宽度，因此动画时相邻组件不会移动。
- 使用 `org.kde.plasma.private.mpris`，这是 Plasma 的私有媒体模块（内置媒体播放器组件也用它）。未来的 Plasma 版本可能改变它。
