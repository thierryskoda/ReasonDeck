import CoreGraphics
import Testing
@testable import ReasonDeck

private func chatNode(
    _ id: Int,
    parent: Int? = nil,
    role: String = "AXGroup",
    labels: Set<ChatGPTAXLabel> = [],
    actions: Set<ChatGPTAXAction> = [],
    visible: Bool = true,
    frame: CGRect? = CGRect(x: 10, y: 10, width: 100, height: 30)
) -> ChatGPTAXNode {
    ChatGPTAXNode(id: id, parentID: parent, role: role, labels: labels, actions: actions, visible: visible, frame: frame)
}

private func chatSnapshot(_ nodes: [ChatGPTAXNode]) -> ChatGPTAXSnapshot {
    ChatGPTAXSnapshot(windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 900), nodes: nodes)
}

@Test func chatGPTPlannerRequiresOneComposerBoundModelControl() throws {
    let snapshot = chatSnapshot([
        chatNode(1, frame: CGRect(x: 0, y: 700, width: 900, height: 180)),
        chatNode(2, parent: 1, role: "AXTextArea", frame: CGRect(x: 30, y: 730, width: 700, height: 100)),
        chatNode(3, parent: 1, role: "AXButton", labels: [.model(.sol56), .effort(.high)], actions: [.press], frame: CGRect(x: 760, y: 820, width: 100, height: 28)),
    ])
    let composer = try ChatGPTSurfacePlanner.composer(in: snapshot)
    #expect(composer.composerID == 1)
    #expect(try ChatGPTSurfacePlanner.modelControl(in: snapshot, composer: composer) == .press(3))
}

@Test func chatGPTPlannerRejectsModelTextOutsideTheComposer() {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXTextArea", frame: CGRect(x: 30, y: 730, width: 700, height: 100)),
        chatNode(2, role: "AXStaticText", labels: [.model(.sol56)], frame: CGRect(x: 10, y: 10, width: 100, height: 20)),
    ])
    #expect(throws: ChatGPTSurfaceFailure.unsupportedSurface) {
        try ChatGPTSurfacePlanner.composer(in: snapshot)
    }
}

@Test func chatGPTPlannerRejectsDuplicateComposerCandidates() {
    let snapshot = chatSnapshot([
        chatNode(1), chatNode(2, parent: 1, role: "AXTextArea"), chatNode(3, parent: 1, labels: [.model(.sol56)]),
        chatNode(4), chatNode(5, parent: 4, role: "AXTextArea"), chatNode(6, parent: 4, labels: [.model(.terra56)]),
    ])
    #expect(throws: ChatGPTSurfaceFailure.ambiguousComposer) {
        try ChatGPTSurfacePlanner.composer(in: snapshot)
    }
}

@Test func chatGPTPlannerRejectsDuplicateRowsInsideOwnedMenu() {
    let snapshot = chatSnapshot([
        chatNode(1), chatNode(2, parent: 1, labels: [.modelRow], actions: [.press]), chatNode(3, parent: 1, labels: [.modelRow], actions: [.press]),
    ])
    #expect(throws: ChatGPTSurfaceFailure.ambiguousItem) {
        try ChatGPTSurfacePlanner.row(.modelRow, in: snapshot, menuID: 1)
    }
}

@Test func chatGPTPlannerAllowsGeometryOnlyForUniqueComposerControl() throws {
    let snapshot = chatSnapshot([
        chatNode(1, frame: CGRect(x: 0, y: 700, width: 900, height: 180)),
        chatNode(2, parent: 1, role: "AXTextArea", frame: CGRect(x: 30, y: 730, width: 700, height: 100)),
        chatNode(3, parent: 1, labels: [.model(.sol56)], frame: CGRect(x: 760, y: 820, width: 100, height: 28)),
    ])
    let composer = try ChatGPTSurfacePlanner.composer(in: snapshot)
    #expect(try ChatGPTSurfacePlanner.modelControl(in: snapshot, composer: composer) == .click(3))
}

@Test func chatGPTPlannerAcceptsOneActionableNativePickerState() throws {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXMenu"),
        chatNode(2, parent: 1, role: "AXMenuItem", labels: [.modelRow, .model(.terra56)], actions: [.press]),
        chatNode(3, parent: 1, role: "AXMenuItem", labels: [.effortRow, .effort(.high)], actions: [.press]),
    ])

    let picker = try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    #expect(picker.model == .terra56)
    #expect(picker.effort == .high)
    #expect(picker.modelRow == .press(2))
    #expect(picker.effortRow == .press(3))
}

@Test func chatGPTPlannerIgnoresGenericContainersAroundNativePickerRows() throws {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXGroup", labels: [.modelRow, .model(.terra56), .effortRow, .effort(.high)], actions: [.showMenu]),
        chatNode(2, role: "AXGroup", labels: [.modelRow, .model(.terra56), .effortRow, .effort(.high)], actions: [.showMenu]),
        chatNode(3, role: "AXMenuItem", labels: [.modelRow, .model(.terra56)], actions: [.press]),
        chatNode(4, role: "AXMenuItem", labels: [.effortRow, .effort(.high)], actions: [.press]),
    ])

    let picker = try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    #expect(picker.modelRow == .press(3))
    #expect(picker.effortRow == .press(4))
}

@Test func chatGPTPlannerRejectsOneActionClaimingBothNativeRows() {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXMenu"),
        chatNode(2, parent: 1, role: "AXMenuItem", labels: [.modelRow, .model(.terra56), .effortRow, .effort(.high)], actions: [.press]),
    ])

    #expect(throws: ChatGPTSurfaceFailure.ambiguousItem) {
        try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    }
}

@Test func chatGPTPlannerAcceptsNativeRowsWhenAccessibilityParentReferencesAreUnstable() throws {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXMenu"),
        chatNode(2, parent: 1, role: "AXMenuItem", labels: [.modelRow, .model(.terra56)], actions: [.press]),
        chatNode(3, role: "AXMenu"),
        chatNode(4, parent: 3, role: "AXMenuItem", labels: [.effortRow, .effort(.high)], actions: [.press]),
    ])

    let picker = try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    #expect(picker.model == .terra56)
    #expect(picker.effort == .high)
}

@Test func chatGPTPlannerLiftsNativeStaticLabelsToTheirDirectActionableRows() throws {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXMenu"),
        chatNode(2, parent: 1, role: "AXMenuItem", actions: [.press]),
        chatNode(3, parent: 2, role: "AXStaticText", labels: [.modelRow]),
        chatNode(4, parent: 2, role: "AXStaticText", labels: [.model(.terra56)]),
        chatNode(5, parent: 1, role: "AXMenuItem", actions: [.press]),
        chatNode(6, parent: 5, role: "AXStaticText", labels: [.effortRow]),
        chatNode(7, parent: 5, role: "AXStaticText", labels: [.effort(.high)]),
    ])

    let picker = try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    #expect(picker.modelRow == .press(2))
    #expect(picker.effortRow == .press(5))
    #expect(picker.model == .terra56)
    #expect(picker.effort == .high)
}

@Test func chatGPTPlannerRejectsGeometryOnlyNativeRows() {
    let snapshot = chatSnapshot([
        chatNode(1, role: "AXMenu"),
        chatNode(2, parent: 1, role: "AXMenuItem", labels: [.modelRow, .model(.terra56)]),
        chatNode(3, parent: 1, role: "AXMenuItem", labels: [.effortRow, .effort(.high)]),
    ])

    #expect(throws: ChatGPTSurfaceFailure.itemMissing) {
        try ChatGPTSurfacePlanner.nativePicker(in: snapshot)
    }
}

private func modernChatSnapshot(open: Bool = false, power: Bool = false) -> ChatGPTAXSnapshot {
    var popup = chatNode(3, parent: 1, role: "AXPopUpButton",
        labels: power ? [.selectEffort] : [.model(.astra6), .effort(.high)], actions: [.press])
    popup.expanded = open
    var nodes = [chatNode(0), chatNode(1, parent: 0), chatNode(2, parent: 1, role: "AXTextArea"), popup]
    if power {
        nodes += [chatNode(10, parent: 0), chatNode(11, parent: 10),
            chatNode(12, parent: 10, role: "AXMenuItem", labels: [.power], actions: [.press]),
            chatNode(13, parent: 11, role: "AXMenuItem", labels: [.selectModel], actions: [.press]),
            chatNode(14, parent: 10, role: "AXStaticText", labels: [.powerStatus(.init(selection: .init(model: .astra6, effort: .high), position: 3, total: 6))]),
            chatNode(15, parent: 10, role: "AXStaticText", labels: [.powerInstructions])]
    }
    return chatSnapshot(nodes)
}

@Test func chatGPTModernComposerDoesNotConfuseInlineModelRowsWithThePopup() throws {
    let initial = modernChatSnapshot()
    let snapshot = chatSnapshot(initial.nodes + [chatNode(5, parent: 0),
        chatNode(6, parent: 5, role: "AXButton", labels: [.model(.astra6)], actions: [.press]),
        chatNode(7, parent: 5, role: "AXButton", labels: [.model(.sol56)], actions: [.press])])
    let composer = try ChatGPTModernPlanner.composer(in: snapshot)
    #expect(composer.controlID == 3)
    #expect(composer.selection == .init(model: .astra6, effort: .high))
    #expect(try ChatGPTModernPlanner.modelList(in: snapshot, composer: composer)[.sol56] == 7)
}

@Test func chatGPTModernComposerRejectsAmbiguousAndUnrelatedControls() {
    let original = modernChatSnapshot()
    let duplicate = chatSnapshot(original.nodes + [chatNode(4, parent: 1, role: "AXPopUpButton",
        labels: [.model(.sol56), .effort(.high)], actions: [.press])])
    #expect(throws: ChatGPTSurfaceFailure.ambiguousComposer) { try ChatGPTModernPlanner.composer(in: duplicate) }
    let unrelated = chatSnapshot([chatNode(0), chatNode(1, parent: 0), chatNode(2, parent: 1, role: "AXTextArea"),
        chatNode(3, parent: 0, role: "AXPopUpButton", labels: [.model(.astra6), .effort(.high)], actions: [.press])])
    #expect(throws: ChatGPTSurfaceFailure.unsupportedSurface) { try ChatGPTModernPlanner.composer(in: unrelated) }
}

@Test func chatGPTCompactListRequiresTheComposerPopupToBeOpen() throws {
    let rows = [chatNode(5),
        chatNode(6, parent: 5, role: "AXMenuItem", labels: [.model(.astra6)], actions: [.press]),
        chatNode(7, parent: 5, role: "AXMenuItem", labels: [.model(.sol56)], actions: [.press])]
    let closed = chatSnapshot(modernChatSnapshot().nodes + rows)
    let composer = try ChatGPTModernPlanner.composer(in: closed)
    #expect(throws: ChatGPTSurfaceFailure.itemMissing) { try ChatGPTModernPlanner.modelList(in: closed, composer: composer) }
    let opened = chatSnapshot(modernChatSnapshot(open: true).nodes + rows)
    #expect(try ChatGPTModernPlanner.modelList(in: opened, composer: composer)[.astra6] == 6)
    let duplicate = chatSnapshot(opened.nodes + [chatNode(8, parent: 5, role: "AXMenuItem", labels: [.model(.sol56)], actions: [.press])])
    #expect(throws: ChatGPTSurfaceFailure.ambiguousItem) { try ChatGPTModernPlanner.modelList(in: duplicate, composer: composer) }
}

@Test func chatGPTPowerRequiresStatusInstructionsAndOwnedModelAction() throws {
    let snapshot = modernChatSnapshot(open: true, power: true)
    let picker = try ChatGPTModernPlanner.powerPicker(in: snapshot)
    #expect(picker.status.selection == .init(model: .astra6, effort: .high))
    #expect(picker.modelActionID == 13)
    for missing in [13, 14, 15] {
        #expect(throws: ChatGPTSurfaceFailure.itemMissing) {
            try ChatGPTModernPlanner.powerPicker(in: chatSnapshot(snapshot.nodes.filter { $0.id != missing }))
        }
    }
}

@Test func chatGPTPowerAliasesAndBoundsAreExact() throws {
    let high = try #require(ChatGPTPowerStatus.parse("GPT-6 Astra Extended, 3 of 6."))
    #expect(high.selection == .init(model: .astra6, effort: .high))
    #expect(try high.direction(toward: .extraHigh))
    #expect(try !high.direction(toward: .medium))
    #expect(ChatGPTPowerStatus.parse("GPT-6 Astra Standard, 2 of 6.")?.selection.effort == .medium)
    for text in ["GPT-6 Astra Extended, 0 of 6.", "GPT-6 Astra Extended, 7 of 6.",
                 "GPT-6 Astra Extended, 3 of 60.", "GPT-6 Astra Preview Extended, 3 of 6.",
                 "GPT-6 Astra Extended, 3 of 6. arbitrary suffix"] {
        #expect(ChatGPTPowerStatus.parse(text) == nil)
    }
    #expect(ChatGPTControlLabels.classify("GPT-5.50 High") == [.unknownText])
    #expect(ChatGPTControlLabels.classify("Discuss GPT-6 Astra High") == [.unknownText])
    #expect(ChatGPTControlLabels.classify("GPT-6 Astra Extra High") == [.model(.astra6), .effort(.extraHigh)])
}
