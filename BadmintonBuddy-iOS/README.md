# 羽毛球搭子 (BadmintonBuddy) - iOS App

## 项目概述

羽毛球搭子是一款帮助用户寻找羽毛球球友的社交匹配 App。

## 技术栈

| 组件 | 技术选型 | 版本 |
|------|---------|------|
| UI 框架 | SwiftUI | iOS 17+ |
| 动画库 | Lottie (Airbnb) | 4.4.0+ |
| 最低系统 | iOS 17.0 | - |
| 语言 | Swift | 5.9 |

## 功能模块

### 已实现
- [x] 启动页 (羽毛球弹跳动画)
- [x] 登录/注册 (水平选择)
- [x] 主页 (地图 + 模式选择)
- [x] 匹配中 (脉冲搜索动画)
- [x] 匹配成功 (卡片碰撞特效 + 粒子爆炸)
- [x] 个人资料页
- [x] 约球确认页

### 动画性能指标
| 动画 | 帧率目标 | 内存占用 |
|------|---------|---------|
| 卡片碰撞 | 60 FPS | < 50MB |
| 脉冲搜索 | 60 FPS | < 30MB |
| 页面转场 | 60 FPS | < 20MB |

## 项目结构

```
BadmintonBuddy-iOS/
├── BadmintonBuddy.xcodeproj/
├── BadmintonBuddy/
│   ├── BadmintonBuddyApp.swift    # App 入口 + 全局状态
│   ├── ContentView.swift          # 主视图路由
│   ├── Models.swift               # 数据模型
│   ├── Theme.swift                # 设计系统 (颜色/字体/间距)
│   ├── Components.swift           # 可复用组件
│   ├── Views/
│   │   ├── SplashView.swift       # 启动页
│   │   ├── AuthView.swift         # 登录/注册
│   │   ├── HomeView.swift         # 主页
│   │   ├── MatchingView.swift     # 匹配中
│   │   ├── MatchSuccessView.swift # 匹配成功 (碰撞特效)
│   │   └── ProfileView.swift      # 个人资料
│   └── Assets.xcassets/
└── README.md
```

## 设计系统

### 颜色 Token
```swift
primary:    #00D4AA  // 主色 - 青绿
secondary:  #6C5CE7  // 次要色 - 紫
accent:     #FD79A8  // 强调色 - 粉
bgDark:     #1A1A2E  // 深色背景
bgCard:     #16213E  // 卡片背景
```

### 动画时长
```swift
fast:      0.2s  // 按钮反馈
normal:    0.3s  // 页面转场
slow:      0.5s  // 复杂动画
collision: 0.7s  // 卡片碰撞
```

## 运行方式

1. 使用 Xcode 15+ 打开 `BadmintonBuddy.xcodeproj`
2. 选择 iOS 17+ 模拟器或真机
3. Command + R 运行

## 依赖管理

项目使用 Swift Package Manager，Lottie 会在首次构建时自动下载。

如需手动添加:
1. Xcode → File → Add Package Dependencies
2. 输入: `https://github.com/airbnb/lottie-ios.git`
3. 选择版本 4.4.0+

## 后续规划

- [ ] 集成 MapKit 真实地图
- [ ] 添加 Lottie 动画文件 (匹配成功/加载中)
- [ ] 接入后端 API
- [ ] 推送通知
- [ ] 聊天功能
