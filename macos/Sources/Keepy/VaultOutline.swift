import SwiftUI
import AppKit

private let draftPasteboardType = NSPasteboard.PasteboardType("dev.keepy.draft")
private let nodePasteboardType = NSPasteboard.PasteboardType("dev.keepy.node")
private let fieldPasteboardType = NSPasteboard.PasteboardType("dev.keepy.saved-field")

// A small native view keeps row markers crisp at every display scale and gives
// VoiceOver the color names as well as the visual indication.
final class TagDotsView: NSView {
    let tags: [TagColor]
    init(tags: [TagColor]) {
        self.tags = tags
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Tags: \(tags.map(\.title).joined(separator: ", "))")
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(tags.count * 13 - 4), height: 10) }
    override func draw(_ dirtyRect: NSRect) {
        for (index, tag) in tags.enumerated() {
            let circle = NSBezierPath(ovalIn: NSRect(x: CGFloat(index * 13), y: 1, width: 9, height: 9))
            tag.nsColor.setFill(); circle.fill()
            NSColor.labelColor.withAlphaComponent(0.16).setStroke(); circle.lineWidth = 0.5; circle.stroke()
        }
    }
}
extension TagColor {
    var menuImage: NSImage {
        let fill = nsColor
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { _ in
            fill.setFill(); NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 10, height: 10)).fill()
            return true
        }
    }
}
private extension NSOutlineView {
    var contentTrailingEdge: CGFloat {
        guard let viewport = enclosingScrollView?.contentView else { return visibleRect.maxX }
        return convert(viewport.bounds, from: viewport).maxX
    }
}
final class NodeOutlineCell: NSTableCellView {
    weak var outline: NSOutlineView?
    var trailingConstraint: NSLayoutConstraint?
    init(outline: NSOutlineView) { self.outline = outline; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); needsLayout = true
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin); needsLayout = true
    }
    override func layout() {
        if let outline, let trailingConstraint {
            // Inset root cells end inside the viewport, while indented cells can
            // extend beyond it. Anchor every tag to the viewport, not the cell.
            let cellRight = convert(bounds, to: outline).maxX
            trailingConstraint.constant = outline.contentTrailingEdge - 16 - cellRight
        }
        super.layout()
    }
}

final class OutlineNode: NSObject {
    let id: String
    var node: VaultNode?
    var field: VaultField?
    var entryId: String?
    var route: EditorRoute?
    var isEditor = false
    var children: [OutlineNode] = []
    init(_ id: String) { self.id = id }
}
// Outline indentation shifts cell origins; constrain hosted content to the visible
// trailing edge instead of letting SwiftUI use the full unindented column width.
final class HostedOutlineCell: NSTableCellView {
    let host: NSView
    weak var outline: NSOutlineView?
    init(host: NSView, outline: NSOutlineView) {
        self.host = host; self.outline = outline
        super.init(frame: .zero)
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); needsLayout = true
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin); needsLayout = true
    }
    override func layout() {
        super.layout()
        let origin = outline.map { convert(bounds, to: $0).minX } ?? 0
        let available = (outline?.contentTrailingEdge ?? bounds.width) - origin - 12
        host.frame = NSRect(x: 0, y: 0, width: max(0, min(bounds.width, available)), height: bounds.height)
    }
}
final class VaultOutlineView: NSOutlineView {
    var activate: (() -> Void)?
    var delete: (() -> Void)?
    var requestInitialFocus: (() -> Void)?
    var claimNavigationFocus: (() -> Bool)?
    private var keyboardMonitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detachKeyboardMonitor()
        guard window != nil else { return }
        requestInitialFocus?()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                  window.firstResponder !== self, Self.isPlainArrow(event),
                  self.claimNavigationFocus?() == true else { return event }
            self.keyDown(with: event)
            return nil
        }
    }
    func detachKeyboardMonitor() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
    }
    private static func isPlainArrow(_ event: NSEvent) -> Bool {
        [UInt16(123), 124, 125, 126].contains(event.keyCode) &&
        event.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty
    }
    override func keyDown(with event: NSEvent) {
        if selectedRow == -1, numberOfRows > 0, Self.isPlainArrow(event) {
            let row = event.keyCode == 126 ? numberOfRows - 1 : 0
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            scrollRowToVisible(row)
        }
        else if event.keyCode == 36 || event.keyCode == 76 { activate?() }
        else if event.keyCode == 51 { delete?() }
        else { super.keyDown(with: event) }
    }
}
struct VaultOutline: NSViewRepresentable {
    @ObservedObject var store: AppStore
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }
    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let outline = VaultOutlineView()
        let column = NSTableColumn(identifier: .init("credentials")); column.title = "Credentials"
        column.resizingMask = .autoresizingMask
        outline.autoresizingMask = [.width]
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.addTableColumn(column); outline.outlineTableColumn = column; outline.headerView = nil
        outline.dataSource = coordinator; outline.delegate = coordinator
        outline.rowSizeStyle = .medium; outline.indentationPerLevel = 14
        outline.style = .inset; outline.selectionHighlightStyle = .regular
        outline.backgroundColor = .clear; outline.focusRingType = .none
        outline.registerForDraggedTypes([nodePasteboardType, draftPasteboardType, fieldPasteboardType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.target = coordinator; outline.doubleAction = #selector(Coordinator.doubleClick)
        outline.activate = { [weak coordinator] in coordinator?.activate() }
        outline.delete = { [weak coordinator] in coordinator?.contextItem = nil; coordinator?.remove() }
        outline.requestInitialFocus = { [weak coordinator] in coordinator?.scheduleInitialFocus() }
        outline.claimNavigationFocus = { [weak coordinator] in coordinator?.claimKeyboardFocus() == true }
        let menu = NSMenu(); menu.delegate = coordinator; outline.menu = menu
        let scroll = NSScrollView(); scroll.documentView = outline; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false; scroll.autohidesScrollers = true
        coordinator.outline = outline
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(store.filteredNodes) }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.outline?.detachKeyboardMonitor()
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        let store: AppStore
        weak var outline: VaultOutlineView?
        var roots: [OutlineNode] = []
        var boxes: [String: OutlineNode] = [:]
        var previous: [VaultNode] = []
        var previousSearch = ""
        var previousTags = Set<TagColor>()
        var editorSignature = ""
        var editorHost: NSHostingView<InlineEditor>?
        var expanded = Set<String>()
        var tagExpanded = Set<String>()
        var updating = false
        var didFocus = false
        private var focusScheduled = false
        var contextItem: OutlineNode?
        init(_ store: AppStore) { self.store = store }

        func scheduleInitialFocus() {
            guard !didFocus, !focusScheduled else { return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusScheduled = false
                if !self.didFocus { _ = self.claimKeyboardFocus() }
            }
        }
        @discardableResult func claimKeyboardFocus() -> Bool {
            guard store.canFilterTags, let outline, let window = outline.window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            let responder = window.firstResponder
            let neutral: Bool
            if let text = responder as? NSTextView, text.isFieldEditor {
                // A removed authentication field may leave the shared field
                // editor behind. An attached search/editor always keeps focus.
                neutral = (text.delegate as? NSView)?.window !== window
            } else {
                neutral = responder == nil || responder === window || responder === window.contentView || responder === outline
            }
            guard neutral, window.makeFirstResponder(outline) else { return false }
            didFocus = true
            return true
        }

        func update(_ nodes: [VaultNode]) {
            guard let outline else { return }
            let route = store.editor?.isInline == true ? store.editor : nil
            let signature = route.map { "\($0.id):\($0.parentId ?? "root"):\($0.insertionIndex ?? -1)" } ?? ""
            updating = true; defer { updating = false }
            let selectedItem = outline.item(atRow: outline.selectedRow) as? OutlineNode
            if previous != nodes || signature != editorSignature || previousSearch != store.search || previousTags != store.tagFilter {
                if previousTags.isEmpty && !store.tagFilter.isEmpty { tagExpanded = expanded }
                let oldRoute = editorHost?.rootView.routeId
                previous = nodes; editorSignature = signature; previousSearch = store.search; previousTags = store.tagFilter
                var next: [String: OutlineNode] = [:]
                func box(_ id: String) -> OutlineNode {
                    let item = boxes[id] ?? OutlineNode(id)
                    item.node = nil; item.field = nil; item.entryId = nil; item.route = nil; item.isEditor = false; item.children = []
                    next[id] = item; return item
                }
                func editor(_ route: EditorRoute) -> OutlineNode {
                    let item = box("editor:\(route.id)"); item.route = route; item.isEditor = true; return item
                }
                func tree(_ node: VaultNode) -> OutlineNode {
                    let item = box(node.id); item.node = node
                    if node.isGroup { item.children = (node.children ?? []).map(tree) }
                    else {
                        item.children = (node.fields ?? []).map { field in
                            let item = box("field:\(node.id):\(field.id)"); item.field = field; item.entryId = node.id; return item
                        }
                    }
                    if let route {
                        switch route.kind {
                        case .entry(let edited), .group(let edited):
                            if edited?.id == node.id {
                                if node.isGroup { item.children.insert(editor(route), at: 0) }
                                else { item.children = [editor(route)] }
                            }
                        default: break
                        }
                    }
                    return item
                }
                roots = nodes.map(tree)
                if let route {
                    let edited: VaultNode?
                    switch route.kind { case .entry(let node), .group(let node): edited = node; default: edited = nil }
                    if edited == nil {
                        let draft = box("draft:\(route.id)"); draft.route = route; draft.children = [editor(route)]
                        if let parentId = route.parentId, let parent = next[parentId] {
                            parent.children.insert(draft, at: min(route.insertionIndex ?? parent.children.count, parent.children.count))
                        } else { roots.insert(draft, at: min(route.insertionIndex ?? roots.count, roots.count)) }
                        expanded.insert(draft.id)
                    } else if let edited { expanded.insert(edited.id) }
                    var ancestor = edited?.id ?? route.parentId
                    while let id = ancestor {
                        expanded.insert(id); ancestor = store.vault?.parent(of: id)
                    }
                    if oldRoute != route.id {
                        editorHost = NSHostingView(rootView: InlineEditor(store: store, routeId: route.id))
                        editorHost?.sizingOptions = []
                    }
                } else { editorHost = nil }
                boxes = next
                outline.reloadData()
                // AppKit retains expansion for reused item objects. Reset its
                // temporary presentation before restoring normal browsing state.
                outline.collapseItem(nil, collapseChildren: true)
                let saved = store.tagFilter.isEmpty ? expanded : tagExpanded
                func restore(_ items: [OutlineNode]) {
                    for item in items where saved.contains(item.id) || !store.search.isEmpty || (!store.tagFilter.isEmpty && item.node?.isGroup == true) {
                        outline.expandItem(item); restore(item.children)
                    }
                }
                restore(roots)
                if let route, oldRoute != route.id, let item = boxes["editor:\(route.id)"] {
                    let row = outline.row(forItem: item)
                    if row >= 0 { outline.scrollRowToVisible(row) }
                }
            }
            var fieldRows = IndexSet()
            for row in 0..<outline.numberOfRows where (outline.item(atRow: row) as? OutlineNode)?.field != nil { fieldRows.insert(row) }
            outline.noteHeightOfRows(withIndexesChanged: fieldRows)
            scheduleInitialFocus()
            let selectedNodeId = selectedItem?.node?.id ?? selectedItem?.entryId ?? selectedItem?.route?.parentId
            if let selectedItem, selectedNodeId == store.selection,
               let item = boxes[selectedItem.id], outline.row(forItem: item) >= 0 {
                outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: item)), byExtendingSelection: false)
            } else if let selection = store.selection, let item = boxes[selection], outline.row(forItem: item) >= 0 {
                outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: item)), byExtendingSelection: false)
            } else if outline.selectedRow != -1 { outline.deselectAll(nil) }
        }
        func children(_ item: Any?) -> [OutlineNode] { (item as? OutlineNode)?.children ?? roots }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(item)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineNode else { return false }
            return item.node?.isGroup == true || !item.children.isEmpty
        }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let item = item as? OutlineNode else { return false }
            return !item.isEditor
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            guard let item = item as? OutlineNode, let field = item.field, let entry = item.entryId else { return nil }
            let row = NSTableRowView()
            var actions: [NSAccessibilityCustomAction] = []
            if field.kind != "ssh" {
                actions.append(NSAccessibilityCustomAction(name: "Copy \(field.label)") { [weak store] in store?.copy(entry: entry, field: field.id); return true })
            }
            if field.masked {
                actions.append(NSAccessibilityCustomAction(name: "Reveal or hide \(field.label)") { [weak store] in store?.reveal(entry: entry, field: field.id); return true })
            }
            if field.kind == "url" || field.kind == "ssh" {
                actions.append(NSAccessibilityCustomAction(name: field.kind == "url" ? "Open URL" : "Connect in Terminal") { [weak self] in self?.performFieldAction(field, entry: entry); return true })
            }
            row.setAccessibilityCustomActions(actions)
            return row
        }
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let item = item as? OutlineNode else { return 30 }
            if item.isEditor {
                if case .group = item.route?.kind { return 300 }
                return 480
            }
            if let field = item.field {
                if field.ssh != nil { return 72 }
                let lines = min(3, (store.revealed[field.id] ?? field.value ?? "").split(separator: "\n", omittingEmptySubsequences: false).count)
                return CGFloat(48 + max(0, lines - 1) * 16)
            }
            return 30
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? OutlineNode else { return nil }
            if item.isEditor, let host = editorHost {
                host.removeFromSuperview()
                return HostedOutlineCell(host: host, outline: outlineView)
            }
            if let field = item.field, let entry = item.entryId {
                let host = NSHostingView(rootView: FieldRow(store: store, entry: entry, field: field).preferredColorScheme(store.colorScheme))
                host.sizingOptions = []
                return HostedOutlineCell(host: host, outline: outlineView)
            }
            let cell = NodeOutlineCell(outline: outlineView)
            let group: Bool
            if let node = item.node { group = node.isGroup }
            else if case .group = item.route?.kind { group = true }
            else { group = false }
            let name = item.node?.name ?? (group ? "New Group" : "New Entry")
            let image = NSImageView(); image.image = NSImage(systemSymbolName: group ? "folder" : "key.horizontal", accessibilityDescription: group ? "Group" : "Entry")
            image.contentTintColor = group ? .secondaryLabelColor : .controlAccentColor
            let text = NSTextField(labelWithString: name); text.lineBreakMode = .byTruncatingTail; text.font = .systemFont(ofSize: NSFont.systemFontSize)
            image.translatesAutoresizingMaskIntoConstraints = false; text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image); cell.addSubview(text); cell.imageView = image; cell.textField = text
            var constraints = [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ]
            let tags = item.node?.tags ?? []
            if !tags.isEmpty {
                let dots = TagDotsView(tags: tags); dots.translatesAutoresizingMaskIntoConstraints = false
                dots.setContentHuggingPriority(.required, for: .horizontal)
                dots.setContentCompressionResistancePriority(.required, for: .horizontal)
                cell.addSubview(dots)
                cell.trailingConstraint = dots.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6)
                constraints += [cell.trailingConstraint!,
                                dots.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                text.trailingAnchor.constraint(equalTo: dots.leadingAnchor, constant: -10)]
                cell.setAccessibilityLabel("\(name), tags: \(tags.map(\.title).joined(separator: ", "))")
            } else {
                cell.trailingConstraint = text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6)
                constraints.append(cell.trailingConstraint!)
                cell.setAccessibilityLabel(name)
            }
            NSLayoutConstraint.activate(constraints)
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline else { return }
            let item = outline.item(atRow: outline.selectedRow) as? OutlineNode
            store.selection = item?.node?.id ?? item?.entryId ?? item?.route?.parentId; store.touch()
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !updating, store.search.isEmpty,
                  let item = notification.userInfo?["NSObject"] as? OutlineNode else { return }
            if store.tagFilter.isEmpty { expanded.insert(item.id) }
            else { tagExpanded.insert(item.id) }
            // Descendant objects can disappear from a filtered datasource.
            // Restore their saved state when a user reopens the parent.
            let saved = store.tagFilter.isEmpty ? expanded : tagExpanded
            updating = true; defer { updating = false }
            func restore(_ children: [OutlineNode]) {
                for child in children where saved.contains(child.id) {
                    outline?.expandItem(child); restore(child.children)
                }
            }
            restore(item.children)
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !updating, store.search.isEmpty else { return }
            if let item = notification.userInfo?["NSObject"] as? OutlineNode {
                if store.tagFilter.isEmpty { expanded.remove(item.id) }
                else { tagExpanded.remove(item.id) }
            }
        }
        @objc func doubleClick() { activate(edit: true) }
        func activate(edit: Bool = false) {
            guard let outline, let item = outline.item(atRow: outline.selectedRow) as? OutlineNode else { return }
            if let field = item.field, let entry = item.entryId { performFieldAction(field, entry: entry) }
            else if let node = item.node {
                if edit && !node.isGroup { store.edit(node) }
                else if outline.isItemExpanded(item) { outline.collapseItem(item) }
                else { outline.expandItem(item) }
            }
        }
        func performFieldAction(_ field: VaultField, entry: String) {
            if field.kind == "url" { store.openURL(entry: entry, field: field.id) }
            else if field.kind == "ssh" { Task { await store.connect(entry: entry, field: field.id) } }
            else { store.copy(entry: entry, field: field.id) }
        }
        @objc func remove() {
            guard store.editor == nil, !store.busy else { return }
            let selected = outline.flatMap { $0.item(atRow: $0.selectedRow) as? OutlineNode }
            if (contextItem ?? selected)?.field != nil { return }
            if let node = contextItem?.node ?? store.selectedNode { store.deleteTarget = node }
        }
        @objc func editNode() {
            if let item = contextItem, let node = item.node ?? store.vault?.node(item.entryId) { store.edit(node) }
        }
        @objc func copyField() { if let item = contextItem, let field = item.field, let entry = item.entryId { store.copy(entry: entry, field: field.id) } }
        @objc func revealField() { if let item = contextItem, let field = item.field, let entry = item.entryId { store.reveal(entry: entry, field: field.id) } }
        @objc func openField() { if let item = contextItem, let field = item.field, let entry = item.entryId { performFieldAction(field, entry: entry) } }
        @objc func toggleTag(_ sender: NSMenuItem) {
            guard !store.busy, store.editor == nil, let node = contextItem?.node,
                  let value = sender.representedObject as? String, let tag = TagColor(rawValue: value) else { return }
            store.toggleTag(tag, for: node)
        }
        @objc func removeTags() {
            guard !store.busy, store.editor == nil, let node = contextItem?.node else { return }
            Task { await store.setTags([], for: node) }
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let outline else { return }
            let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
            populateMenu(menu, for: outline.item(atRow: row) as? OutlineNode)
        }
        func populateMenu(_ menu: NSMenu, for item: OutlineNode?) {
            menu.removeAllItems(); menu.autoenablesItems = false; contextItem = item
            guard let item, !item.isEditor, item.route == nil else { return }
            func add(_ title: String, _ action: Selector) {
                let actionItem = NSMenuItem(title: title, action: action, keyEquivalent: ""); actionItem.target = self
                actionItem.isEnabled = !store.busy && store.editor == nil; menu.addItem(actionItem)
            }
            if let field = item.field {
                if field.kind != "ssh" { add("Copy", #selector(copyField)) }
                if field.masked { add("Reveal / Hide", #selector(revealField)) }
                if field.kind == "url" { add("Open URL", #selector(openField)) }
                if field.kind == "ssh" { add("Connect in Terminal", #selector(openField)) }
                menu.addItem(.separator())
            }
            add("Edit…", #selector(editNode))
            if let node = item.node {
                let tagsItem = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
                tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "Tags")
                tagsItem.isEnabled = !store.busy && store.editor == nil
                let tagsMenu = NSMenu(title: "Tags"); tagsMenu.autoenablesItems = false
                for tag in TagColor.allCases {
                    let tagItem = NSMenuItem(title: tag.title, action: #selector(toggleTag(_:)), keyEquivalent: "")
                    tagItem.target = self; tagItem.representedObject = tag.rawValue; tagItem.image = tag.menuImage
                    tagItem.state = node.tags.contains(tag) ? .on : .off
                    tagItem.isEnabled = !store.busy && store.editor == nil
                    tagsMenu.addItem(tagItem)
                }
                tagsMenu.addItem(.separator())
                let clearItem = NSMenuItem(title: "Remove All Tags", action: #selector(removeTags), keyEquivalent: "")
                clearItem.target = self; clearItem.isEnabled = !node.tags.isEmpty && !store.busy && store.editor == nil
                tagsMenu.addItem(clearItem); tagsItem.submenu = tagsMenu; menu.addItem(tagsItem)
                menu.addItem(.separator())
                add("Delete…", #selector(remove))
            }
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard !store.isFiltering, !store.busy, let node = item as? OutlineNode, !node.isEditor else { return nil }
            let item = NSPasteboardItem()
            if let route = node.route {
                item.setData(Data(route.id.uuidString.utf8), forType: draftPasteboardType)
            } else {
                guard store.editor == nil else { return nil }
                if let field = node.field, let entry = node.entryId { item.setString("\(entry):\(field.id)", forType: fieldPasteboardType) }
                else if let value = node.node { item.setString(value.id, forType: nodePasteboardType) }
                else { return nil }
            }
            return item
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard !store.isFiltering, !store.busy else { return [] }
            let target = item as? OutlineNode
            if let draft = info.draggingPasteboard.data(forType: draftPasteboardType), String(data: draft, encoding: .utf8) == store.editor?.id.uuidString {
                if let target, target.node?.isGroup != true { return [] }
                return .move
            }
            guard store.editor == nil else { return [] }
            if let value = info.draggingPasteboard.string(forType: fieldPasteboardType) {
                let ids = value.split(separator: ":").map(String.init)
                guard ids.count == 2, target?.node?.id == ids[0], target?.node?.isGroup == false else { return [] }
                return .move
            }
            guard let id = info.draggingPasteboard.string(forType: nodePasteboardType), let dragged = store.vault?.node(id) else { return [] }
            if let target { guard let node = target.node, node.isGroup, dragged.find(node.id) == nil else { return [] } }
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard !self.outlineView(outlineView, validateDrop: info, proposedItem: item, proposedChildIndex: index).isEmpty else { return false }
            let targetItem = item as? OutlineNode
            let parent = targetItem?.node
            if let draft = info.draggingPasteboard.data(forType: draftPasteboardType), String(data: draft, encoding: .utf8) == store.editor?.id.uuidString {
                let children = targetItem?.children ?? roots
                let before = index == NSOutlineViewDropOnItemIndex ? children : Array(children.prefix(index))
                store.editor?.parentId = parent?.id
                store.editor?.insertionIndex = before.filter { $0.node != nil }.count
                store.selection = parent?.id
                if let item { outlineView.expandItem(item) }
                return true
            }
            if let value = info.draggingPasteboard.string(forType: fieldPasteboardType) {
                let ids = value.split(separator: ":").map(String.init)
                guard ids.count == 2, let fields = parent?.fields, let source = fields.firstIndex(where: { $0.id == ids[1] }) else { return false }
                var destination = index == NSOutlineViewDropOnItemIndex ? fields.count : index
                if source < destination { destination -= 1 }
                store.moveField(ids[1], entry: ids[0], index: destination); return true
            }
            guard let id = info.draggingPasteboard.string(forType: nodePasteboardType), let vault = store.vault else { return false }
            let children = parent?.children ?? vault.nodes
            var destination = index == NSOutlineViewDropOnItemIndex ? children.count : index
            if vault.parent(of: id) == parent?.id, let source = children.firstIndex(where: { $0.id == id }), source < destination { destination -= 1 }
            store.move(id, parent: parent?.id, index: destination)
            if let item { outlineView.expandItem(item) }
            return true
        }
    }
}
