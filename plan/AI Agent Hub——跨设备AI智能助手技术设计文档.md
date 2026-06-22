# AI Agent Hub——跨设备AI智能助手技术设计文档

# 一、项目概述

## 1\.1 项目背景与产品定位

AI Agent Hub 是一款面向苹果生态、支持 iOS / macOS 双端的跨设备AI智能助手应用，主打**多AI模型统一管理\+自然语言设备自动化\+跨端协同操控**。区别于市面单一AI聊天客户端，本应用打通手机与电脑设备权限，支持用户通过自然语言指令完成AI对话、本地数据整理、文档生成、代码编写与执行、跨设备文件操作等自动化任务。

产品核心差异化：

- 聚合 DeepSeek、GPT、Claude 等第三方模型 \+ 苹果端智能能力，一键切换，无需多客户端切换；

- 支持 iPhone 远程安全操控 Mac 设备，实现轻量化办公、开发自动化；

- 全链路本地优先，敏感数据本地存储、本地运算，严格控制数据外传；

- 适配低版本系统，兼容**iOS 18\.0\+、macOS 15\.0\+ \(Sequoia\)**，大幅提升用户覆盖。

目标用户：个人开发者、职场办公人群、内容创作者、苹果生态多设备用户。

## 1\.2 核心功能清单（含功能约束）

|功能模块|功能描述|版本约束与边界限制|
|---|---|---|
|多模型管理|支持添加、编辑、删除、切换 DeepSeek、GPT、Claude 等第三方模型，支持自定义API端点、密钥配置|全版本通用；Apple Intelligence 端侧模型仅 iOS26\+/macOS26\+ 可用，低版本自动隐藏入口|
|多会话聊天室|创建、重命名、归档、删除多独立对话会话，上下文隔离，聊天记录本地持久化，支持流式对话|低版本完全兼容；支持上下文自动截断，避免Token溢出|
|跨设备控制|iPhone 局域网远程操控 Mac，执行代码运行、文件创建、文本整理、数据汇总等任务|仅同Apple ID、同一局域网可用；无外网自动降级，高危操作强制弹窗授权|
|数据整理与创建|AI 解析自然语言，自动整理备忘录、本地文件、文本数据，生成报告、文案、代码文档|仅读取应用授权范围内数据，禁止越权访问系统隐私数据|

## 1\.3 目标平台与兼容说明

- **移动端**：iOS 18\.0\+、iPadOS 18\.0\+（全面适配iPhone、iPad）

- **桌面端**：macOS 15\.0\+ \(Sequoia\)，兼容 Intel / Apple Silicon 双架构

- **跨设备能力**：双设备登录同一Apple ID、接入同一局域网，支持双向设备发现与单向远程控制

- **高版本专属能力**：iOS26\+/macOS26\+ 自动启用 Apple Foundation Models 端侧AI，低版本自动屏蔽，仅保留第三方API模型能力

# 二、技术架构

## 2\.1 整体分层架构（兼容低版本）

整体采用五层分层架构，新增公共基础层，解耦通用能力，适配 macOS15 / iOS18 系统API限制，移除高版本专属依赖。

```mermaid

graph TD
    A["用户交互层"] --> B["业务逻辑层"]
    B --> C["AI服务层"]
    B --> D["跨设备通信层"]
    C --> E["数据持久层"]
    D --> E
    F["公共基础层"] --> 所有上层

    subgraph 用户交互层
    A1["会话列表"]
    A2["聊天界面"]
    A3["模型配置"]
    A4["设备管理"]
    end

    subgraph 业务逻辑层
    B1["会话管理器"]
    B2["消息路由器"]
    B3["工具调用器"]
    B4["设备协调器"]
    end

    subgraph AI服务层
    C1["第三方AI API服务"]
    C2["高版本端侧模型适配"]
    end

    subgraph 跨设备通信层
    D1["Bonjour设备发现"]
    D2["App Intents动作调度"]
    D3["端到端加密传输"]
    end

    subgraph 数据持久层
    E1["SwiftData本地存储"]
    E2["Keychain敏感存储"]
    end

    subgraph 公共基础层
    F1["加密工具"]
    F2["权限管理"]
    F3["网络封装"]
    F4["日志/异常处理"]
    F5["版本兼容适配"]
    end
    ```

## 2\.2 技术选型（低版本兼容优化版）

|层级|技术方案|详细说明与兼容适配|
|---|---|---|
|UI框架|SwiftUI \+ UIKit混编|iOS18/macOS15 全面适配，修复低版本SwiftUI布局兼容问题，核心页面兼容双端|
|AI能力|第三方RESTful API \+ 高版本端侧模型降级|低版本全量使用DeepSeek/GPT/Claude API；iOS26\+/macOS26\+自动启用Foundation Models，做版本分支适配|
|跨设备通信|Bonjour\(NW\) \+ App Intents|App Intents负责系统标准化动作，Bonjour负责底层P2P加密传输，macOS15/iOS18完美支持|
|数据持久化|SwiftData \+ Keychain|普通业务数据SwiftData存储，密钥、设备凭证等敏感数据强制Keychain加密|
|网络框架|原生URLSession \+ 自定义封装|无第三方依赖，支持超时、重试、限流、SSL校验，适配低版本系统网络策略|
|加密方案|Apple CryptoKit|系统原生加密，支持AES\-256端到端加密，兼容iOS18/macOS15，无第三方漏洞风险|
|版本适配|Availability 版本分支管控|通过系统版本判断，自动屏蔽高版本专属功能，保证低版本稳定运行|

# 三、功能模块详细设计

## 3\.1 AI模型配置模块

### 3\.1\.1 功能描述

用户可自主添加、编辑、删除、启用/禁用多厂商AI模型配置，支持自定义API地址、模型参数，聊天场景可实时切换模型。所有敏感密钥数据加密存储，永不明文留存。

### 3\.1\.2 支持模型与适配规则

|模型|接入方式|版本适配规则|
|---|---|---|
|DeepSeek|RESTful API|iOS18\+/macOS15\+ 全支持|
|OpenAI GPT|RESTful API|iOS18\+/macOS15\+ 全支持|
|Claude|RESTful API|iOS18\+/macOS15\+ 全支持|
|Apple Foundation Model|系统内置|仅 iOS26\+/macOS26\+ 可用，低版本自动隐藏入口|

### 3\.1\.3 核心数据模型（兼容低版本）

```swift
// 模型配置实体
@Model
class ModelConfig {
    var id: UUID
    var name: String               // 自定义显示名称
    var provider: ModelProvider    // 模型厂商枚举
    var apiKey: String             // 加密后存储密文
    var baseURL: String?           // 自定义API端点
    var temperature: Double        // 创造性参数
    var maxTokens: Int             // 最大生成长度
    var isDefault: Bool
    var isEnabled: Bool            // 启用/禁用开关
    var createdAt: Date
    var updatedAt: Date
}

enum ModelProvider: String, Codable, CaseIterable {
    case deepseek, openai, anthropic, apple
}

```

### 3\.1\.4 API调用抽象与容错机制

统一AI服务协议，多模型统一调度，内置超时、重试、失败降级、Token用量统计能力。

```swift
protocol AIService {
    func sendMessage(_ message: String, 
                     sessionId: UUID, 
                     onToken: @escaping (String) -> Void) async throws -> String
}

// 各厂商独立实现，统一对外接口
class DeepSeekService: AIService { }
class OpenAIService: AIService { }
class ClaudeService: AIService { }

// 高版本专属服务，低版本编译隔离
@available(iOS 26.0, macOS 26.0, *)
class AppleFoundationService: AIService { }

```

容错规则：单接口失败自动重试2次、超时15s、接口限流弹窗提示、异常模型自动禁用。

## 3\.2 多会话聊天室模块

### 3\.2\.1 功能描述

支持多独立对话会话，上下文完全隔离，提供会话新建、重命名、归档、删除、置顶能力。支持流式对话、历史记录持久化、上下文自动截断、异常兜底渲染。

### 3\.2\.2 核心能力优化

- **上下文截断策略**：自动检测对话Token总量，超出阈值自动裁剪早期历史，避免接口报错、性能卡顿；

- **异常兜底**：断网、接口报错、流式中断时，终止加载并展示友好错误提示，保留用户输入草稿；

- **数据安全**：会话删除为软删除，保留7天可恢复，过期自动清理；

- **UI适配**：采用 NavigationSplitView 三栏布局，完美适配macOS15、iOS18桌面与移动端布局。

### 3\.2\.3 数据模型

```swift
// 会话实体
@Model
class ChatSession {
    var id: UUID
    var title: String
    var modelConfigId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var isDeleted: Bool       // 软删除标记
    var deleteExpireAt: Date? // 过期清理时间
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage]
}

// 消息实体
@Model
class ChatMessage {
    var id: UUID
    var sessionId: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var errorMsg: String?    // 异常信息记录
}

enum MessageRole: String, Codable {
    case user, assistant, system
}

```

## 3\.3 工具调用（Tool Calling）模块（安全强化版）

### 3\.3\.1 功能描述

AI通过标准Tool Calling机制调用本地预定义工具，实现设备自动化操作。新增**工具分级、权限校验、隐私脱敏、用户强制授权、操作日志审计**，完全满足App Store审核规范。

### 3\.3\.2 工具权限分级机制

|风险等级|工具类型|授权规则|脱敏规则|
|---|---|---|---|
|低危|创建备忘录、生成文本、数据汇总|首次授权，后续可免确认|无需脱敏|
|高危|代码执行、文件创建/修改/删除、批量数据整理|**每次执行强制弹窗二次确认**|自动屏蔽本地路径、设备信息、隐私字段，禁止上传第三方模型|

### 3\.3\.3 核心工具协议与安全约束

```swift
import Foundation

// 工具风险等级枚举
enum ToolRiskLevel {
    case low, high
}

// 标准化工具协议
protocol Tool {
    var name: String { get }
    var description: String { get }
    var riskLevel: ToolRiskLevel { get }
    var parameters: [ToolParameter] { get }
    func execute(with arguments: [String: Any]) async throws -> ToolResult
}

```

### 3\.3\.4 安全调用流程

用户输入指令 → AI解析工具意图 → 工具风险校验 → 高危弹窗授权 → 数据脱敏处理 → 本地沙盒执行 → 日志留存 → 结果返回AI。

## 3\.4 跨设备控制模块（macOS15\+ 适配优化）

### 3\.4\.1 核心方案

基于 **Bonjour 设备发现 \+ App Intents 系统动作 \+ CryptoKit端到端加密** 实现跨设备协同，完全兼容 macOS15 / iOS18，移除高版本API依赖。

### 3\.4\.2 设备连接前置约束（硬性规则）

- 双设备必须登录同一合法Apple ID；

- 双设备处于同一局域网，无外网P2P中继（一期）；

- Mac端手动开启设备接收权限，iPhone端完成首次绑定授权；

- 公共Wi\-Fi路由器拦截设备发现时，提供手动IP连接兜底方案。

### 3\.4\.3 安全沙盒机制（解决代码执行审核风险）

Mac端所有代码执行、文件操作均启用**应用沙盒隔离**：

- 仅允许操作应用沙盒目录、用户授权的文档目录；

- 禁止执行系统命令、修改系统配置、访问核心隐私目录；

- 代码执行超时机制：单次执行最大30s，超时自动强制终止进程；

- 限制CPU、内存资源占用，避免设备卡顿。

### 3\.4\.4 设备发现与加密通信

基于 Network 框架 Bonjour 实现零配置设备发现，全程AES\-256加密传输，数据不经过任何第三方服务器，纯本地P2P通信。支持设备解绑、过期重连、多设备冲突处理。

# 四、核心业务流程（含异常兜底）

## 4\.1 聊天与工具调用完整流程

用户输入消息 → 本地预处理（脱敏、校验） → 发送至AI模型 → 模型返回工具调用意图 → 风险分级校验 → 用户授权确认（高危） → 沙盒执行工具 → 执行结果本地留存 → AI整合结果回复 → 会话记录持久化。

异常分支：网络超时、模型报错、用户取消授权、工具执行失败、设备断开，均有对应UI兜底与日志记录。

## 4\.2 跨设备控制标准流程

iPhone端接收自然语言指令 → AI识别跨设备操作意图 → 校验已绑定Mac设备 → 发起加密P2P连接 → 二次授权确认 → 传输加密指令 → Mac沙盒内执行操作 → 结果加密回传 → 移动端展示结果并留存审计日志。

# 五、数据存储与安全设计

## 5\.1 存储分层方案

- **Keychain（最高安全等级）**：存储API密钥、设备加密凭证、绑定Token，系统级加密，不可导出；

- **SwiftData（业务数据）**：存储会话、消息、模型配置、设备信息、工具执行日志，开启系统数据保护；

- **临时缓存**：流式消息临时数据，退出页面自动清空，无持久化留存。

## 5\.2 数据生命周期管理

- 工具执行日志：自动留存30天，到期自动清理，支持手动清空；

- 删除会话：软删除保留7天，逾期永久销毁；

- 支持用户一键清空所有聊天记录、操作日志、设备绑定信息。

# 六、隐私与合规设计（过审核心）

## 6\.1 核心隐私原则

- **本地优先**：低版本完全依赖本地API调度，高版本优先设备端AI，最小化数据外传；

- **数据透明**：首次使用弹窗告知用户第三方模型数据外传风险，提供「禁用第三方API」开关；

- **最小权限**：所有系统权限按需申请、动态授权，可随时在系统设置撤回；

- **操作可审计**：所有工具调用、跨设备操作均留存日志，用户可查看、可清空。

## 6\.2 权限清单与申请时机

|权限|用途|申请时机|
|---|---|---|
|网络访问|API调用、跨设备通信|应用首次启动|
|本地网络|Bonjour设备发现、P2P传输|首次使用跨设备功能时|
|备忘录/文件/相册|本地数据整理、生成文件|用户主动触发对应功能时动态申请|

# 七、开发路线图（适配低版本）

## 7\.1 阶段一：基础框架适配（1\-2月）

搭建 iOS18 / macOS15 双端项目骨架、SwiftData数据模型、基础聊天UI、版本兼容适配层、加密基础工具。

## 7\.2 阶段二：多模型接入（3月）

完成DeepSeek/GPT/Claude API接入、模型配置管理、参数自定义、容错与限流机制。

## 7\.3 阶段三：安全工具系统（4月）

实现工具分级、授权机制、数据脱敏、日志审计、核心自动化工具开发。

## 7\.4 阶段四：跨设备协同（5月）

完成Bonjour设备发现、App Intents动作封装、P2P加密通信、Mac沙盒执行能力。

## 7\.5 阶段五：测试合规与上线（6月）

双端兼容测试、安全渗透测试、隐私合规自查、审核优化、App Store提审。

# 八、技术风险与落地应对方案

|技术风险|影响范围|落地应对方案|
|---|---|---|
|macOS15/iOS18 无端侧AI能力|低版本功能缺失|代码版本隔离，自动隐藏高版本入口，全量降级为第三方API|
|公共网络拦截Bonjour设备发现|跨设备功能失效|新增手动IP连接兜底方案，支持固定设备配对|
|代码执行触发App审核风险|提审被拒|沙盒严格隔离、高危二次授权、禁止系统命令、全程日志留存|
|第三方API限流、扣费|功能异常、用户纠纷|用量统计、超限提醒、接口重试、模型故障自动切换|
|跨设备密钥丢失、重连失败|设备绑定失效|支持设备解绑重置、重新授权、密钥自动刷新|

# 九、附录

## 9\.1 开发环境要求

- Xcode：16\.0\+（适配iOS18/macOS15）

- Swift：6\.0\+

- 最低编译目标：iOS18\.0、macOS15\.0

## 9\.2 参考文档

- Apple App Intents 官方开发文档

- Apple Network / Bonjour 设备通信文档

- Apple CryptoKit 加密安全规范

- DeepSeek、OpenAI、Anthropic 官方 API 与 ToolCalling 规范

> （注：部分内容可能由 AI 生成）
