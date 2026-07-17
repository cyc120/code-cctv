import SwiftUI

private final class DragTracker: ObservableObject {
    var lastTranslation = CGSize.zero
}

struct PillView: View {
    @ObservedObject var store: StatusStore
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(store.state.projects.first?.status ?? "", active: store.connected))
                    .frame(width: 8, height: 8)
                Text(store.pillTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Code CCTV")
        .accessibilityValue(store.pillTitle)
        .accessibilityHint("单击展开消息，双击打开预览，拖动移动浮窗")
        .help("单击展开消息，双击打开全局预览，拖动移动浮窗")
    }
}

struct FloatingPanelView: View {
    @ObservedObject var controller: FloatingPanelController
    @ObservedObject var store: StatusStore
    let onOpen: () -> Void
    let onMove: (CGSize) -> Void
    let onMoveEnd: () -> Void
    let onResize: (CGSize) -> Void

    private let collapsedSize = CGSize(width: 154, height: 38)
    private let expandedSize = CGSize(width: 320, height: 190)
    @StateObject private var dragTracker = DragTracker()

    private var panelSize: CGSize {
        controller.isExpanded ? expandedSize : collapsedSize
    }

    var body: some View {
        Group {
            if controller.isExpanded {
                ActivityBubble(
                    activity: store.latestActivity,
                    onOpen: onOpen,
                    onCollapse: controller.collapseBubble,
                    onDismiss: { controller.dismissBubble(stateID: store.state.generatedAt) },
                    onHidePanel: controller.hide
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)),
                        removal: .opacity
                    )
                )
            } else {
                PillView(
                    store: store,
                    onTap: { controller.presentBubble() },
                    onDoubleTap: onOpen
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: controller.isExpanded)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width - dragTracker.lastTranslation.width,
                        height: value.translation.height - dragTracker.lastTranslation.height
                    )
                    if delta != .zero {
                        onMove(delta)
                    }
                    dragTracker.lastTranslation = value.translation
                }
                .onEnded { _ in
                    dragTracker.lastTranslation = .zero
                    onMoveEnd()
                }
        )
        .contextMenu {
            Button(action: onOpen) {
                Label("打开全局预览", systemImage: "rectangle.3.group")
            }
            Button(action: toggleBubble) {
                Label(controller.isExpanded ? "收起消息" : "显示消息", systemImage: controller.isExpanded ? "chevron.down" : "text.bubble")
            }
            Divider()
            Button(action: controller.hide) {
                Label("隐藏浮窗", systemImage: "eye.slash")
            }
        }
        .onAppear {
            onResize(panelSize)
        }
        .onChange(of: controller.isExpanded) { _ in
            onResize(panelSize)
        }
        .onChange(of: store.state.generatedAt) { _ in
            controller.presentBubble(for: store.state.generatedAt)
        }
    }

    private func toggleBubble() {
        if controller.isExpanded {
            controller.dismissBubble(stateID: store.state.generatedAt)
        } else {
            controller.presentBubble()
        }
    }
}

private struct ActivityBubble: View {
    let activity: ActivitySummary?
    let onOpen: () -> Void
    let onCollapse: () -> Void
    let onDismiss: () -> Void
    let onHidePanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(activity?.status ?? "", active: activity?.active ?? false))
                    .frame(width: 9, height: 9)
                Text(activity?.projectName ?? "Code CCTV")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("关闭消息泡泡")
            }

            if let activity, !activity.phase.isEmpty {
                Text(activity.phase)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(activity.status, active: activity.active))
                    .lineLimit(1)
            }

            if let activity {
                Text(activity.focus.isEmpty ? "暂无最新活动" : activity.focus)
                    .font(.body)
                    .lineLimit(2)
            } else {
                Text("暂无最新活动")
                    .font(.body)
                    .lineLimit(2)
            }

            if let activity, !activity.note.isEmpty {
                Text(activity.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(activity.map { shortActivityTime($0.timestamp) } ?? "等待后台状态")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpen) {
                    Label("全局预览", systemImage: "rectangle.3.group")
                }
                .buttonStyle(.borderless)
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("收起消息")
                Button(action: onHidePanel) {
                    Image(systemName: "eye.slash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("隐藏浮窗")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private func shortActivityTime(_ value: String) -> String {
    let input = ISO8601DateFormatter()
    guard let date = input.date(from: value) else { return value }
    let output = DateFormatter()
    output.locale = Locale(identifier: "zh_CN")
    output.dateFormat = "HH:mm:ss"
    return output.string(from: date)
}

struct PreviewView: View {
    @ObservedObject var store: StatusStore
    @State private var selectedWorkspace: String?

    private var selectedProject: ProjectSummary? {
        let selected = selectedWorkspace ?? store.state.projects.first?.workspace
        return store.state.projects.first { $0.workspace == selected }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                projectList
                    .frame(width: 330)
                Divider()
                detail
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Code CCTV")
                    .font(.title2.weight(.bold))
                Text(store.connected ? "全局状态摘要" : "等待后台服务")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Metric(title: "项目", value: "\(store.state.summary.totalProjects)")
            Metric(title: "活跃", value: "\(store.state.summary.activeProjects)")
            Metric(title: "阻塞", value: "\(store.state.summary.blockedProjects)")
            Circle()
                .fill(store.connected ? .green : .secondary)
                .frame(width: 9, height: 9)
                .help(store.connected ? "服务已连接" : "服务未连接")
        }
        .padding(20)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if store.state.projects.isEmpty {
                    EmptyStateView(title: "暂无工作区", systemImage: "rectangle.dashed")
                        .padding(.top, 80)
                } else {
                    ForEach(store.state.projects) { project in
                        Button {
                            selectedWorkspace = project.workspace
                        } label: {
                            ProjectRow(project: project, selected: selectedProject?.workspace == project.workspace)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let project = selectedProject {
            ProjectDetail(project: project)
        } else {
            EmptyStateView(title: "选择一个工作区", systemImage: "cursorarrow.click")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
    }
}

private struct ProjectRow: View {
    let project: ProjectSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(project.status, active: project.active))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.focus.isEmpty ? project.status : project.focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(project.eventCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        )
    }
}

private struct ProjectDetail: View {
    let project: ProjectSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name)
                            .font(.title2.weight(.bold))
                        Text(project.workspace)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Label(project.status, systemImage: project.active ? "bolt.fill" : "clock")
                        .foregroundStyle(statusColor(project.status, active: project.active))
                }

                if !project.phase.isEmpty {
                    DetailBlock(title: "阶段", text: project.phase)
                }
                if !project.focus.isEmpty {
                    DetailBlock(title: "当前关注", text: project.focus)
                }
                if !project.note.isEmpty {
                    DetailBlock(title: "最近摘要", text: project.note)
                }

                Text("最近事件")
                    .font(.headline)
                if project.recentEvents.isEmpty {
                    Text("暂无事件")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(project.recentEvents) { event in
                            EventRow(event: event)
                            if event.id != project.recentEvents.last?.id {
                                Divider().padding(.leading, 28)
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
        }
    }
}

private struct EventRow: View {
    let event: EventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.phase.isEmpty ? event.eventType : event.phase)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(event.timestamp)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
    }

    private var iconName: String {
        switch event.eventType {
        case "file-change": return "doc.badge.gearshape"
        case "validation": return "checkmark.circle"
        default: return "waveform.path.ecg"
        }
    }
}
