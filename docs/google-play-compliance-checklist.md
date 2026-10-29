# TorgSeek库存 —— 上架 Google Play 合规改造清单

核对日期：2026-10-29　｜　对应代码：`cc3900d`（v2.1.1）　｜　Flutter 3.47.8 / Dart 3.13.7

本清单每一项都标了「现状」，现状来自本仓库实际读取，不是通用模板。
政策日期与费率来自 Google 官方页面，文末列了来源；标 ⚠️ 的是我无法从官方页面确证、需要在 Play Console 当期核对的数字。

---

## 0. 先做业务决策，再动代码

有三件事是**取舍**不是技术问题，没定之前下面的改造无法收尾：

| # | 待决问题 | 影响 |
|---|---|---|
| D1 | **是否真的要上 Google Play？** 现在 APK 从 GitHub Release 侧载，不受任何商店条款约束。 | 决定要不要做 B、C 两组全部工作 |
| D2 | **订阅定价能否承受商店抽成？** 现网 ₵ 走 Monobank、$ 走 Paddle，价格写在服务端价目表里。走 Play 计费要重算价格。 | 决定 B 组走哪条路线 |
| D3 | **到期租户怎么办？** 目前到期后经营模块全锁死，「我的」页续费卡是唯一解锁入口。摘掉购买 UI 会让到期用户在 App 内无路可走。 | 决定 C 组要不要保留 CTA |

> 如果 D1 答案是「暂时不上架」，本清单只需执行 A 组（签名与产物），因为 debug 签名的包在 Android 14+ 上会持续遇到安装限制。

---

## A. 阻断项 —— 不解决连上传都过不去

### A1. 发布签名：debug keystore → upload key + Play App Signing ⛔ 最高优先级

**现状**：`android/app/build.gradle.kts:33`

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

release 构建用的是 Flutter 自动生成的 debug keystore。

**要做**：
- [ ] 生成一把 upload key（只用于签名上传，私钥不进仓库）
- [ ] 在 Play Console 启用 **Play App Signing**，让 Google 保管真正的应用签名密钥
- [ ] 把 upload key 以 secret 形式存进 GitHub Actions（`ANDROID_KEYSTORE_BASE64` + 两个密码 secret）
- [ ] `build.gradle.kts` 增加 `release` signingConfig，从 secret/环境变量读，**本地开发仍可回落 debug**
- [ ] 密钥文件与口令的备份方案（丢了 upload key 要靠 Play App Signing 重置，丢了 Google 那把就永久无法更新）

**注意**：一旦上架，换签名密钥要求老用户卸载重装。所以**第一版就要签对**，别先传 debug 包再换。

### A2. 产物格式：APK → Android App Bundle（.aab）

**现状**：`.github/workflows/build-apk.yml:35`

```yaml
run: flutter build apk --release --android-skip-build-dependency-validation
```

**要做**：
- [ ] 改为 `flutter build appbundle --release`
- [ ] 产物路径 `build/app/outputs/bundle/release/app-release.aab`
- [ ] 上传 Play 用 AAB；**GitHub Release 可继续附 APK** 给侧载用户（两条分发并存，见 `flutter build apk` 保留）
- [ ] ⚠️ 去掉 `--android-skip-build-dependency-validation`：这个 flag 是在跳过 Android SDK/构建工具校验，上架包不该带着它构建。要确认去掉后 CI 仍绿。

### A3. API 级别 —— ✅ 已达标，无需改动

**现状**：`compileSdk`/`targetSdk` 走 `flutter.compileSdkVersion`/`flutter.targetSdkVersion`，Flutter 3.47.8 解析为 **36**；`minSdk` = 24。

Google 要求 2026-08-31 起新应用与更新必须 target **Android 16 (API 36)** 及以上 —— 当前构建已满足。

- [ ] 唯一动作：把这条写进升级 Flutter 的检查项。Flutter 大版本升级会自己抬 targetSdk，降回去就会在上传时被拒。

### A4. 包名与身份

**现状**：`applicationId = "com.torgseek.kucun"`，`namespace` 同。

- [ ] 确认这个包名是唯一且长期使用的（上架后不可改）。与品牌 `TorgSeek库存` 不一致只是不好看，不影响合规。
- [ ] `android:label="TorgSeek库存"` 会成为商店显示名，注意 30 字符上限与本地化。

---

## B. 支付合规 —— 工作量与成本最大的一组

### B1. 现状为什么过不了

App 目前的行为：「我的 → 订阅方案」渲染服务端价目表，每档 `onTap` 弹 `payment_guide.dart` 的抽屉，文案是「App 内暂不支持打开订阅收银台。请使用同一账号在网页端登录后…完成付款」，按钮直接 `launchUrl` 到 `https://app.torgseek.com/app/settings`。财务页同构。钱包充值走 `_pay()`，取 `page_url` 后用外部浏览器打开 Monobank 收银台并轮询状态。

问题：解锁订阅这类数字功能必须走 Play 计费；App 内**零 Play Billing 集成**；而且这是**硬跳转、不提供 Play 选项**，属于典型的引导到外部支付。

### B2. 四条可选路线（按用户安装地区生效，不是开发者地区）

| 路线 | 适用地区 | 是否要集成 Play Billing | 强制并列选择屏 | 订阅费率 |
|---|---|---|---|---|
| **R1 只用 Play 计费** | 全球 | 是 | 不需要 | service fee 10%（首 $1M 年度营收内）+ billing fee 5%（US/UK/EEA） |
| **R2 External Content Links** | 仅美国 | 是（要拿 token 回传交易） | Google 渲染信息页，不要求并列 Play | 原 0%，Google 宣布 2026-10-01 起收费（标准 20%/订阅 10%）⚠️ 该费率有诉讼不确定性 |
| **R3 Billing Choice** | 英国 + EEA | 是 | **强制**与 Play Billing 并列 | 订阅 10%（首 $1M 内），其余 20% |
| **R4 External Offers** | EEA（DMA） | 是（注册后 Play Billing 反而不可用） | Google 渲染 | 订阅 10%，其余 20% |
| **R5 外部支付计划** | 日本 | 是，且要求 **Play Billing Library 8.3+** | **强制** | ⚠️ 未在官方页确证 |

**对你的用户构成的现实判断**：定价是 ₴/Monobank、界面带 uk/vi，主力租户大概率在乌克兰。上表**没有一条覆盖乌克兰**。也就是说 R2–R5 都帮不到主要收入来源，实际只有 R1 可走。

### B3. 无论选哪条都要做的

- [ ] 集成 **Play Billing Library 8.0+**（2026-08-31 起新应用与更新强制 v8+；Google 现已推荐迁移到 v9，v9 的强制日是 2028-08-31）
  - Flutter 侧：`in_app_purchase` 或 `flutter_billingplus`，都要落到原生 v8+
- [ ] 在 Play Console 创建与网页端**同档**的订阅商品（月/季/年），价格、宽限期、账号恢复策略逐条配
- [ ] 服务端加**收据校验**：Play 的 purchase token 要在后端验签，不能信客户端上报
- [ ] 订阅状态同步：网页端已付的租户，App 内要能识别为已激活（现走 `/profile` 的 `subscription_status`，这条链路可复用）
- [ ] 取消/改档要引导到 Play 的订阅管理，App 内不要自建
- [ ] 若走 R2/R3/R4/R5：注册对应计划 + 逐 App 审批 + 交易回传（用 Play 下发的 external transaction token 通知 Google 该笔外部成交）

### B4. 如果决定「上架但把购买 UI 摘干净」

这是成本最低的合规形态，但要先解决 D3：

- [ ] 删除 `_RenewalCard` 的价目表与档位行、删除 `payment_guide.dart` 的全部 CTA
- [ ] 删除财务页的订阅区块与钱包充值入口
- [ ] 只保留**只读**状态：「订阅状态：生效中 · 到期 2027-10-13」
- [ ] 到期路径改成非购买说明（例如「请在网页端续费」的纯文本，不带按钮、不带可点链接、不显示价格）
- [ ] 商店描述里也不要提价格

⚠️ 这个形态下「到期即锁死全部经营模块」的产品设计本身会变成投诉源 —— 用户装了 App 却无法自助解锁。建议同时考虑改成到期只读、不锁死。

---

## C. 账号与数据

### C1. 账号删除 ⛔ 缺失，必须补

**现状**：`settings_screen.dart:784` 只有 `_SignOutCard`（退出登录），**全 App 没有删除账号功能**。

Google 的 User Data 政策：App 内提供账号创建，就必须提供账号删除 —— App 内一键删除，或提供可直接发起删除的网页 URL，并在数据安全表单的「Data deletion」栏填写。

- [ ] 服务端补一个删除端点（Supabase Auth 用户 + 该用户与租户的关系 + 业务数据保留策略）
- [ ] App 内「我的」页加「删除账号」，破坏性二次确认，文案要如实说明服务端会做什么（本仓库已有 `confirmAction` 与这个惯例）
- [ ] 或者：在 `app.torgseek.com` 提供删除页，并把 URL 填进 Play Console
- [ ] 明确区分**退出登录**与**删除账号**，不能只给退出
- [ ] 想清楚租户管理员账号被删时租户归属怎么转移 —— 这是 B2B 场景的真问题，不是表单问题

### C2. 数据安全表单（Data safety form）

按本仓库实际依赖与权限，需要申报的采集项：

| 采集点 | 代码位置 | 类型 |
|---|---|---|
| 邮箱 + 密码 | Supabase Auth（`supabase_flutter`） | 个人可识别信息，需申报 |
| 商品/订单/库存/客户名 | `/api/business/*` | 业务数据，但**客户姓名属个人数据** |
| 拍照与相册图 | `image_picker` + `CAMERA`/`READ_MEDIA_IMAGES` | 照片 |
| 语音 | `speech_to_text`、`record` + `RECORD_AUDIO` | 音频 |
| 本地缓存 | `shared_preferences`、`path_provider`、`cached_network_image`、`GetCache` | 需说明是否出设备 |
| 文件导出 | `file_picker`、`printing`、`pdf`、`excel` | 一般不采集，但要如实勾 |

- [ ] 逐项填：是否采集、是否出设备、用途、是否可删除
- [ ] 上传加密与删除机制说明
- [ ] ⚠️ 表单答案必须与**实际代码行为一致**，Google 会做自动比对，不一致是拒案常见原因

### C3. 隐私政策

- [ ] 准备一份公开可访问的隐私政策 URL（Play Console 必填，商店页会展示）
- [ ] 内容要覆盖：采集什么、Supabase 作为处理方、AI 功能把图像/语音送到哪里、保留期、删除途径
- [ ] `app.torgseek.com` 上要有对应页面，且语言至少覆盖商店目标地区语言

### C4. 权限与深链

**现状**：`AndroidManifest.xml` 声明 `INTERNET`、`ACCESS_NETWORK_STATE`、`CAMERA`、`READ_MEDIA_IMAGES`、`RECORD_AUDIO`。

- [ ] 每一项权限在商店页的「数据安全/权限说明」里给得出理由（本仓库都有真实功能对应，好写）
- [ ] `READ_MEDIA_IMAGES` 已足够，**不要**加 `WRITE_EXTERNAL_STORAGE` 之类的旧权限
- [ ] 自定义深链 `torgseek://`：Play 不禁止，但如果要接 Play 计费回跳，建议同时配 https App Links
- [ ] 复核 `uses-feature required="false"` 的写法（camera/microphone 都已是可选，正确）

---

## D. 内容与商店素材

- [ ] **内容分级（IARC 问卷）**：如实填。B2B 库存工具通常落在 Everyone，但问卷要真答。
- [ ] **目标受众与受众群体**：勾「不是儿童」。一旦把儿童列入，会触发 Families 政策全套附加要求（广告、数据最小化、第三方 SDK 白名单）。当前 UI 与文案没有儿童取向，保持不勾。
- [ ] **类别**：商业（Business）
- [ ] **商店素材**：图标（已有 512px 源，`assets/brand/app_icon.png`）、5 张手机截图、⚠️ 1024×500 特色图、⚠️ 1024×512 高分辨率图标 —— 这些要按 Play 当期规格重新出，仓库里现有的是启动器图标规格，不能直接顶替
- [ ] **商店文案**：中/英/乌/越四语（App 内已有 `l10n_table.dart` 四语体系，文案可对应）
- [ ] 文案里**不要**出现价格、"最低价"、或与 Play 计费的比价暗示（走 B4 路线时尤其注意）
- [ ] **联系人、地址、开发者名称**：Play Console 的账号级要求（组织账号需 D-U-N-S 之类），个人账号与组织账号路径不同 —— 上架前先定用哪种

---

## E. 质量与流程门槛

### E1. 新账号的生产环境准入

若用 2023-11-13 之后注册的**个人**开发者账号：

- [ ] 先跑 **closed testing**，至少 **12 名已 opt-in 测试者连续 14 天**，再申请 production 访问
- [ ] 组织账号通常免这一条 —— 用哪种账号要提前定

### E2. Play 质量指标（Vitals）

Google 会按用户可感知口径监控崩溃率、ANR、卡死、唤醒锁，超阈值会限流或下架。⚠️ 具体阈值以 Play Console 当期显示为准，不要在文档里抄旧数字。

- [ ] 接一个崩溃上报（Crashlytics / Sentry），上架前就有数据
- [ ] 关注 Flutter release 模式的布局异常：本仓库历史上出现过「渲染成灰块而非红屏」的 bug，`flutter analyze` 看不见，只能靠真机截图或把 widget 单独 pump 进测试复现

### E3. 发布流程

- [ ] internal → closed → open → production 四轨道，先在 closed 上验签名与 Play 计费沙盒
- [ ] 每次上架留 release notes（本仓库 CI 已有 GitHub Release body，可复用同一份文案）
- [ ] 定向发布（staged rollout）从 5–10% 起

---

## F. 建议执行顺序

```
第 1 步  决策 D1 / D2 / D3                    ← 不花钱，但决定后面所有事
第 2 步  A1 签名 + A2 AAB + CI 改造            ← 独立于支付决策，先做，随时可回滚
第 3 步  C1 账号删除 + C3 隐私政策              ← 政策硬门槛，与 B 组无关
第 4 步  C2 数据安全表单 + D 组素材与问卷        ← 表单填写，不阻塞开发
第 5 步  B 组支付改造                          ← 最贵，且依赖 D2 定价决策
第 6 步  E1 closed testing 14 天 → production
```

A、C 两组加起来约 2–4 人日；B 组按路线不同，R1 约 5–10 人日（含服务端验签与商品配置），B4 摘除路线约 1–2 人日但要改产品设计。

---

## 附：政策来源

- [Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818)
- [Expanded billing choice and lower fees on Google Play（2026-06-24 官方博客）](https://android-developers.googleblog.com/2026/06/play-expanded-billing.html)
- [About the external payments program（日本）](https://developer.android.com/google/play/billing/externalpaymentlinks)
- [Enrolling in the external content links program](https://support.google.com/googleplay/android-developer/answer/16470497)
- [Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878) ／ [Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk)
- [Play Billing Library version deprecation](https://developer.android.com/google/play/billing/deprecation-faq)
- [App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
- [App account deletion policy](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Android App Bundle FAQ](https://developer.android.com/guide/app-bundle/faq)

**未能确证、需在 Console 复核（⚠️）**：ECL 自 2026-10-01 起的具体费率（官方帮助页 JS 渲染抓不到正文，数字来自第三方 Appcharge 2026-08-05 文章，且该文自己质疑该费率能否在诉讼中站住）；Vitals 各项阈值；商店素材的精确像素规格；日本计划的费率。
