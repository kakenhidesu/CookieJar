<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="CookieJar" width="128">
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/agpl-3.0"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="License: AGPL-3.0"></a>
</p>

# CookieJar — 基于 SwiftUI 的第三方 X 岛客户端

一个基于 SwiftUI 的第三方 X 岛客户端

## 功能

- **浏览**：时间线 + 全部版块，无限滚动、下拉刷新、版块说明、版块排序/隐藏
- **串**：分页加载（可往上加载上一页）、跳页、只看 Po、阅读进度记忆、引用 `>>No.` 点击弹窗
- **发串/回复**：图片（相册 / 涂鸦板）、水印开关、颜文字面板（内置 + 自定义 + 最近使用）、草稿箱、发串后自动回填串号
- **订阅**：服务器订阅（uuid 或网页版）、关键字搜索、自定义排序
- **历史**：浏览记录（按天分组）、发串/回复记录
- **饼干**：多饼干管理、二维码扫描导入、二维码导出、剪贴板导入、登录官方账号导出饼干
- **黑名单**：屏蔽饼干 / 串 / 版块 / 关键词
- **外观**：5 套主题色、深浅色、字号与行距调节、紧凑卡片模式

## 启动

首次启动会请求：

* 相机权限（扫描饼干二维码）
* 相册权限（上传图片）

均可按需授权。

## 已知问题

* 官方搜索接口 `Api/search` 不可用，未实现相关功能，仅有串号跳转功能
* 本地数据保存在 App Support 目录，卸载后会清除；饼干存储于 Keychain

## 致谢

感谢以下开源项目：

* [orzogc/xdnmb_api](https://github.com/orzogc/xdnmb_api)：提供 API 逻辑参考

## 一些废话

AppStore的上架和审核机制确实是一坨，看霞岛ios端也好久没更新了，先写一个自己用着