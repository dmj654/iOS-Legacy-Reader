# 开源阅读·iOS（iOS-Legacy-Reader）

> 对标安卓开源阅读 **Legado** 的 iOS 原生客户端。书源规则引擎 1:1 对齐 Legado 语法，
> 支持 GitHub Actions 云端自动打包，输出**未签名 IPA**，可直接侧载（TrollStore / 爱思助手）。

---

## 一、核心功能对标（与 Legado 一致）

### 1. 书源规则引擎（核心灵魂，完全兼容）
- ✅ 四种解析规则：**CSS 选择器 / XPath / JSONPath / 正则表达式**，与开源阅读语法通用
- ✅ 五段式书源结构：搜索 / 发现 / 详情 / 目录 / 正文
- ✅ 书源属性：源地址、请求头、编码、并发、分组、启停、登录态、动态参数
- ✅ 书源管理：批量导入/导出 **Legado 标准 JSON**、单条编辑、分组、启停、失效校验、连通性检测、排序置顶、按组筛选
- ✅ 规则前缀：`@CSS:` `@XPath:` `@JSon:/@JSON:` `@Regex:`；串联 `&&`；替换 `##`；`{{key}}` 关键字占位

### 2. 书籍搜索与发现
- ✅ 聚合搜索：同时调用所有已启用书源，结果去重、按源展示
- ✅ 发现板块：各书源分类/排行/更新列表
- ✅ 书籍详情：自动解析封面、作者、简介、最新章节、更新时间、字数

### 3. 书架管理
- ✅ 网格 / 列表 两种视图
- ✅ 加入/移除/置顶/分组/重命名/手动更新
- ✅ 按名称 / 更新时间 / 阅读进度 / 添加时间 排序
- ✅ 一键全书架检测章节更新
- ✅ 本地导入 **TXT / EPUB**（自动解析封面与章节目录）

### 4. 阅读页体验
- ✅ 翻页：滚动 / 覆盖 / 仿真 / 滑动 / 无动画（五种模式）
- ✅ 排版：字体、字号、行距、段距、首行缩进、左右/上下边距全可调
- ✅ 主题：白天 / 夜间 / 护眼 / 羊皮纸 + 自定义文字色/背景色
- ✅ 目录跳转、进度自动保存、书签管理、本书内全文搜索、自动阅读、屏幕常亮、全屏沉浸

### 5. 内容净化系统
- ✅ 三级规则：全局 / 单本书 / 单书源
- ✅ 类型：关键词替换、正则替换、删除整行、保留整行
- ✅ 兼容导入导出规则包；正文自动套用三级净化

### 6. 数据与设置
- ✅ 完整备份/恢复（书架、书源、净化规则、阅读设置）
- ✅ 全局默认阅读配置，新导入书籍自动套用
- ✅ 纯本地存储，无后台上传，无网络强制要求

---

## 二、技术与打包

- **语言/框架**：Swift + SwiftUI，最低适配 **iOS 15.0**，支持 iPhone 全机型，横竖屏
- **依赖**：Kanna（HTML 的 CSS / XPath 解析，通过 Swift Package Manager 引入）
- **CI 流水线**：`.github/workflows/build-ipa.yml`，推送 `main` 自动触发
  - macOS 官方最新镜像
  - Release 模式，`arm64` 架构
  - 全程禁用签名：`CODE_SIGNING_ALLOWED=NO` / `CODE_SIGNING_REQUIRED=NO` / 空签名身份
  - 内置 `exportOptions.plist`（无签名导出配置）
  - 构建产物上传 Actions Artifacts，并自动创建 Release 附带 IPA 下载链接
- **零配置**：无需证书、无需开发者账号，公开仓库即可免费运行

---

## 三、本地开发与部署

### 本地运行（需 macOS + Xcode）
```bash
brew install xcodegen
xcodegen generate            # 由 project.yml 生成 iOSLegacyReader.xcodeproj
open iOSLegacyReader.xcworkspace   # 或 .xcodeproj
```
> 真机运行未签名 App 需越狱或 TrollStore；模拟器可直接 Run。

### 一键部署到 GitHub（自动建库 + 触发构建 + 返回 IPA）
```bash
chmod +x deploy.sh
./deploy.sh <你的GitHub_PAT> <你的GitHub用户名>
```
脚本会：创建公开仓库 `iOS-Legacy-Reader` → 推送 `main` → 触发 Actions 构建 → 构建完成后在 Releases 给出 IPA 直链。

### 侧载安装
- **巨魔商店 (TrollStore)**：直接安装未签名 IPA（最推荐，永久驻留）
- **爱思助手**：用 Apple ID 免费签名安装（7 天有效期，可续签）
- **AltStore / Sideloadly**：同样支持未签名 IPA 侧载

---

## 四、已知限制（与原版的差异，已在工程内注明）
1. **翻页仿真/覆盖/滑动/无动画**：iOS 原生以 `TabView` 翻页形式统一呈现（与原版视觉略有差异，但操作逻辑一致：点击左右边缘 / 滑动翻页）。
2. **音量键翻页**：iOS 非越狱环境无公开 API，故未实现；改用点按边缘 + 滑动。
3. **JS 规则（`@JS:`）与部分高级函数**：当前规则引擎覆盖 CSS/XPath/JSONPath/Regex 四大类及 `&&`/`##`/`{{key}}`；`@JS:` 动态脚本暂未实现。
4. **EPUB 导入**为 best-effort（内置极简 ZIP 解压，覆盖绝大多数标准 EPUB；个别加密/特殊压缩可能解析不全）。
5. 未含原版「订阅更新」「阅读统计时长」的图形化报表，相关字段已预留。

---

## 五、目录结构
```
iOS-Legacy-Reader/
├── .github/workflows/build-ipa.yml   # 云端自动打包流水线
├── exportOptions.plist               # 无签名导出配置
├── project.yml                       # xcodegen 工程描述
├── deploy.sh                         # 一键建库部署脚本
├── README.md
└── iOSLegacyReader/
    ├── LegacyReaderApp.swift         # 入口 + 主 Tab
    ├── Store.swift                   # 全局状态 + 本地持久化
    ├── Models.swift                  # 数据模型（书源/书籍/规则/设置）
    ├── RuleEngine.swift              # 规则引擎（CSS/XPath/JSONPath/Regex）
    ├── BookSourceEngine.swift        # 网络 + 搜索/发现/详情/目录/正文 + 净化
    ├── LocalImport.swift             # TXT/EPUB 本地导入
    ├── BookshelfView.swift           # 书架
    ├── SearchView.swift              # 发现 / 聚合搜索
    ├── BookSourceView.swift          # 书源管理（导入导出/编辑/检测）
    ├── ReaderView.swift              # 阅读器（翻页/排版/主题/书签/搜索）
    ├── SettingsView.swift            # 设置 / 备份恢复 / 净化规则
    ├── Assets.xcassets
    └── Info.plist
```
