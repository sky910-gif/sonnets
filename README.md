# Sonnets

Sonnets 是基于开源项目 [MusicFree](https://github.com/maotoumao/MusicFree) 二次开发而来的原生 iOS 音乐播放器。项目使用 SwiftUI、AVFoundation、MediaPlayer 与 JavaScriptCore，最低支持 iOS 18；在 iOS 26 及以上使用系统 Liquid Glass 效果，旧系统自动回退到原生材质。

## 已实现

- 网络插件源导入、更新、启用、删除、用户变量与默认插件
- JavaScriptCore CommonJS 运行环境，以及 axios、cheerio、crypto-js、dayjs、qs、he、big-integer、WebDAV 等兼容模块
- 歌曲、专辑、歌手、歌单和歌词搜索
- 榜单、推荐歌单、远程歌单导入及详情获取
- 在线播放、音质、倍速、队列、顺序播放、列表循环、单曲循环、随机播放、进度跳转、定时关闭、后台播放与系统媒体控制
- 插件评论与回复分页、滚动歌词、收藏、本地歌单、播放历史、下载、本地文件导入和资料库备份/恢复

## 测试插件源

```text
https://musicfreepluginshub.2020818.xyz/plugins.json
```

首次启动会自动导入该源，也可以在“设置 → 插件设置”中添加其他 JSON 或单个 JavaScript 插件地址。

## 运行

使用 Xcode 26 或更新版本打开 `sonnets.xcodeproj`，选择 iOS 18 及以上的模拟器或真机运行。后台播放与远程控制能力已经在 `AppInfo.plist` 中配置。

## 说明

应用不内置音乐平台、账号或受版权保护的内容。插件及内容由用户自行选择，请只在获得合法授权的范围内使用。插件协议与产品思路源自 [MusicFree](https://github.com/maotoumao/MusicFree)，请同时遵守原项目和所用插件的许可条款。

## 开源协议

本项目基于 [MusicFree](https://github.com/maotoumao/MusicFree) 二次开发，原项目同样采用 AGPL-3.0 协议。本项目沿用相同协议，遵循自由软件基金会的 GNU Affero General Public License v3.0，详见 [LICENSE](./LICENSE)。

任何对本项目的使用、修改、分发或网络服务化均须遵守 AGPL-3.0 的条款，包括公开对应的源代码。
