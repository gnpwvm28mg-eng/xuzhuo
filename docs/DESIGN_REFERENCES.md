# 续桌 0.3.0 · 设计参考

本轮参考了桌面刘海工具的交互组织，以及 Apple Liquid Glass / 应用图标的设计方向。续桌的 SwiftUI 界面、图形与图标均独立绘制；没有复制第三方源码、图标、截图或其他资源。参考项目不构成本项目的代码依赖，保留原作者各自的许可说明。

| 参考 | 实际查看内容 | 对续桌的设计启发 |
| --- | --- | --- |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch) · GPL-3.0 | GitHub README、项目目录、`NotchShape.swift` 和 `ShelfView.swift` | 收起时保持安静，展开时给内容留出空间；上下边角与形变有明确关系；拖入资料采用清楚的空态和反馈。 |
| [NotchDrop](https://github.com/Lakr233/NotchDrop) · MIT | GitHub 项目目录、`NotchView.swift`、`NotchHeaderView.swift`、`NotchContentView.swift`，以及 README 产品截图（通过 Contents API 获取并缩小查看） | 小型桌面入口承载原地操作；标题与辅助入口保持简洁；不同内容通过轻量过渡切换。 |
| [OnlySwitch](https://github.com/jacklandrin/OnlySwitch) · MIT | GitHub README 与项目目录 | 把常用操作集中于一个短路径控制面板，避免每次进入完整管理窗口。 |
| [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) | 设计参考链接；本轮官网网络访问未成功 | 用单一、可识别的主体和克制的层次表达品牌；避免把小图标做成缩小版页面。 |
| [Apple Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/liquid-glass) | 设计参考链接；本轮官网网络访问未成功。可用 API 以本机 Xcode 26 SDK 为依据：`glassEffect` 标注自 macOS 26 起可用 | 让玻璃用于控件层次、高光和背景分离，内容保持清晰；兼顾旧系统与辅助功能。 |

GitHub 查阅时间：2026-10-10。源文件观察基于下列提交，未将其实现移入续桌：

- boring.notch [`e2654ee`](https://github.com/TheBoredTeam/boring.notch/tree/e2654ee41b0b9aee72c5a8113a11ab855896d6e6)：[NotchShape](https://github.com/TheBoredTeam/boring.notch/blob/e2654ee41b0b9aee72c5a8113a11ab855896d6e6/boringNotch/components/Notch/NotchShape.swift)、[ShelfView](https://github.com/TheBoredTeam/boring.notch/blob/e2654ee41b0b9aee72c5a8113a11ab855896d6e6/boringNotch/components/Shelf/Views/ShelfView.swift)。
- NotchDrop [`e70b3d7`](https://github.com/Lakr233/NotchDrop/tree/e70b3d715a99e47de6eb823540282eafc7401a3a)：[NotchView](https://github.com/Lakr233/NotchDrop/blob/e70b3d715a99e47de6eb823540282eafc7401a3a/NotchDrop/NotchView.swift)、[NotchHeaderView](https://github.com/Lakr233/NotchDrop/blob/e70b3d715a99e47de6eb823540282eafc7401a3a/NotchDrop/NotchHeaderView.swift)、[NotchContentView](https://github.com/Lakr233/NotchDrop/blob/e70b3d715a99e47de6eb823540282eafc7401a3a/NotchDrop/NotchContentView.swift)。

## English

The desktop interactions were informed by boring.notch, NotchDrop, and OnlySwitch. All XuZhuo SwiftUI views, graphics, and app icon artwork were created independently. No third-party source code or visual assets were copied, and these projects are not dependencies. Their original licenses remain applicable to their own work.

The GitHub files above were inspected through the GitHub API on October 10, 2026. The NotchDrop README product screenshot was also retrieved through the Contents API, reduced in size, and visually inspected; its horizontal tiles and file shelf match the source observations. Apple’s icon and Liquid Glass pages are provided as design references; online access failed during this pass, so no claim is made that their current text was reviewed. API availability was checked against the locally installed Xcode 26 SDK.
