import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation
import UniformTypeIdentifiers
import CoreText
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils

private let systemDefaultId = ""
private let roundedId = "__rounded__"
private let serifId = "__serif__"
private let monoId = "__mono__"
private let addFontId = "__add__"

private struct FontEntry {
    let id: String
    let title: String
    let isImported: Bool
}

private struct FontSection {
    let title: String?
    let footer: String?
    let entries: [FontEntry]
}

private func previewFont(id: String, size: CGFloat) -> UIFont {
    switch id {
    case systemDefaultId, addFontId:
        return UIFont.systemFont(ofSize: size)
    case roundedId, serifId, monoId:
        let base = UIFont.systemFont(ofSize: size).fontDescriptor
        let design: UIFontDescriptor.SystemDesign
        if id == roundedId {
            design = .rounded
        } else if id == serifId {
            design = .serif
        } else {
            design = .monospaced
        }
        return UIFont(descriptor: base.withDesign(design) ?? base, size: size)
    default:
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: id]), size: size)
    }
}

private final class FontsSettingsScreenNode: ASDisplayNode, UITableViewDataSource, UITableViewDelegate {
    private var presentationData: PresentationData
    private let isRussian: Bool
    
    private let tableView: UITableView
    private let headerView = UIView()
    private let videoContainer = UIView()
    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    
    private var sections: [FontSection] = []
    private var selectedId: String
    private var didSetInitialOffset = false
    private var lastHeaderWidth: CGFloat = 0.0
    
    var fontSelected: ((String) -> Void)?
    var addFontPressed: (() -> Void)?
    var fontDeleted: ((String) -> Void)?
    
    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.isRussian = presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
        self.selectedId = UserDefaults.standard.string(forKey: Font.customFontFamilyDefaultsKey) ?? ""
        self.tableView = UITableView(frame: CGRect(), style: .insetGrouped)
        
        super.init()
        
        Font.registerImportedFonts()
        self.reloadSections()
        
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.cellLayoutMarginsFollowReadableWidth = false
        
        self.videoContainer.backgroundColor = UIColor.black
        self.videoContainer.layer.cornerRadius = 24.0
        self.videoContainer.clipsToBounds = true
        self.headerView.addSubview(self.videoContainer)
        self.tableView.tableHeaderView = self.headerView
        
        self.updateColors()
    }
    
    deinit {
        self.player?.pause()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addSubview(self.tableView)
    }
    
    private func updateColors() {
        let theme = self.presentationData.theme
        self.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.separatorColor = theme.list.itemBlocksSeparatorColor
    }
    
    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.updateColors()
        self.tableView.reloadData()
    }
    
    func reloadSections() {
        self.selectedId = UserDefaults.standard.string(forKey: Font.customFontFamilyDefaultsKey) ?? ""
        let ru = self.isRussian
        
        var sections: [FontSection] = []
        sections.append(FontSection(title: ru ? "СИСТЕМНЫЕ" : "SYSTEM", footer: nil, entries: [
            FontEntry(id: systemDefaultId, title: ru ? "По умолчанию (SF Pro)" : "Default (SF Pro)", isImported: false),
            FontEntry(id: roundedId, title: "SF Rounded", isImported: false),
            FontEntry(id: serifId, title: "New York", isImported: false),
            FontEntry(id: monoId, title: "SF Mono", isImported: false)
        ]))
        
        let popularFamilies = [
            "Copperplate", "Papyrus", "Chalkduster", "Marker Felt", "Noteworthy", "American Typewriter",
            "Futura", "Didot", "Georgia", "Avenir Next", "Baskerville", "Optima", "Zapfino", "Snell Roundhand",
            "Bradley Hand", "Gill Sans", "Hoefler Text", "Cochin", "Rockwell", "Palatino", "Times New Roman",
            "Verdana", "Trebuchet MS", "Menlo", "Courier New", "Party LET", "Academy Engraved LET",
            "Arial Rounded MT Bold", "Bodoni 72", "DIN Alternate"
        ]
        let availableFamilies = Set(UIFont.familyNames)
        var popularEntries: [FontEntry] = []
        for family in popularFamilies where availableFamilies.contains(family) {
            popularEntries.append(FontEntry(id: family, title: family, isImported: false))
        }
        sections.append(FontSection(title: ru ? "ПОПУЛЯРНЫЕ" : "POPULAR", footer: nil, entries: popularEntries))
        
        var ownEntries: [FontEntry] = []
        if let items = UserDefaults.standard.array(forKey: Font.importedFontsDefaultsKey) as? [[String: String]] {
            for item in items {
                if let family = item["family"] {
                    ownEntries.append(FontEntry(id: family, title: family, isImported: true))
                }
            }
        }
        ownEntries.append(FontEntry(id: addFontId, title: ru ? "Добавить свой шрифт…" : "Add your own font…", isImported: false))
        sections.append(FontSection(
            title: ru ? "МОИ ШРИФТЫ" : "MY FONTS",
            footer: ru ? "Выберите файл .ttf или .otf (например, Minecraft). Шрифт применится ко всему приложению после перезапуска. Свайп влево удаляет добавленный шрифт." : "Pick a .ttf or .otf file (for example Minecraft). The font is applied to the whole app after a restart. Swipe left to remove an added font.",
            entries: ownEntries
        ))
        self.sections = sections
    }
    
    func reloadTable() {
        self.reloadSections()
        self.tableView.reloadData()
    }
    
    // MARK: - Video
    
    private func setupPlayerIfNeeded() {
        if self.player != nil {
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fonts_character.mp4")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let data = Data(base64Encoded: fontsCharacterVideoBase64) else {
                return
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return
            }
        }
        let player = AVQueuePlayer()
        player.isMuted = true
        self.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = self.videoContainer.bounds
        self.videoContainer.layer.addSublayer(playerLayer)
        
        self.player = player
        self.playerLayer = playerLayer
    }
    
    func playVideo() {
        self.setupPlayerIfNeeded()
        self.player?.play()
    }
    
    func pauseVideo() {
        self.player?.pause()
    }
    
    // MARK: - Layout
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let leftInset = layout.safeInsets.left
        let rightInset = layout.safeInsets.right
        let tableWidth = max(100.0, layout.size.width - leftInset - rightInset)
        self.tableView.frame = CGRect(x: leftInset, y: 0.0, width: tableWidth, height: layout.size.height)
        self.tableView.contentInset = UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0)
        self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset
        
        let videoSize = min(max(120.0, tableWidth - 64.0), 220.0)
        self.headerView.frame = CGRect(x: 0.0, y: 0.0, width: tableWidth, height: videoSize + 28.0)
        self.videoContainer.frame = CGRect(x: floor((tableWidth - videoSize) / 2.0), y: 14.0, width: videoSize, height: videoSize)
        self.playerLayer?.frame = self.videoContainer.bounds
        if self.lastHeaderWidth != tableWidth {
            self.lastHeaderWidth = tableWidth
            // Reassign to let the table pick up the new header height.
            self.tableView.tableHeaderView = self.headerView
        }
        
        if !self.didSetInitialOffset {
            self.didSetInitialOffset = true
            self.tableView.contentOffset = CGPoint(x: 0.0, y: -navigationHeight)
        }
    }
    
    // MARK: - Table
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].entries.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].title
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.sections[section].footer
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.textLabel?.textColor = self.presentationData.theme.list.sectionHeaderTextColor
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        if let footerView = view as? UITableViewHeaderFooterView {
            footerView.textLabel?.textColor = self.presentationData.theme.list.freeTextColor
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = self.sections[indexPath.section].entries[indexPath.row]
        let theme = self.presentationData.theme
        
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.tintColor = theme.list.itemAccentColor
        let selectionView = UIView()
        selectionView.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectionView
        
        if entry.id == addFontId {
            cell.textLabel?.text = entry.title
            cell.textLabel?.font = UIFont.systemFont(ofSize: 17.0)
            cell.textLabel?.textColor = theme.list.itemAccentColor
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .none
        } else {
            cell.textLabel?.text = entry.title
            cell.textLabel?.font = previewFont(id: entry.id, size: 18.0)
            cell.textLabel?.textColor = theme.list.itemPrimaryTextColor
            cell.detailTextLabel?.text = self.isRussian ? "Привет, мир! The quick brown fox 0123" : "Hello, world! The quick brown fox 0123"
            cell.detailTextLabel?.font = previewFont(id: entry.id, size: 13.0)
            cell.detailTextLabel?.textColor = theme.list.itemSecondaryTextColor
            cell.accessoryType = entry.id == self.selectedId ? .checkmark : .none
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = self.sections[indexPath.section].entries[indexPath.row]
        if entry.id == addFontId {
            self.addFontPressed?()
        } else {
            self.fontSelected?(entry.id)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return self.sections[indexPath.section].entries[indexPath.row].isImported
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return self.sections[indexPath.section].entries[indexPath.row].isImported ? .delete : .none
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let entry = self.sections[indexPath.section].entries[indexPath.row]
            if entry.isImported {
                self.fontDeleted?(entry.id)
            }
        }
    }
}

final class FontsSettingsScreen: ViewController, UIDocumentPickerDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private var controllerNode: FontsSettingsScreenNode {
        return self.displayNode as! FontsSettingsScreenNode
    }
    
    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings))
        
        self._hasGlassStyle = true
        
        let isRussian = self.presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
        self.navigationItem.title = isRussian ? "Шрифты" : "Fonts"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.presentationData = presentationData
                if strongSelf.isNodeLoaded {
                    strongSelf.controllerNode.updatePresentationData(presentationData)
                }
            }
        })
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
    }
    
    override func loadDisplayNode() {
        super.loadDisplayNode()
        
        let node = FontsSettingsScreenNode(presentationData: self.presentationData)
        node.fontSelected = { [weak self] id in
            self?.selectFont(id: id)
        }
        node.addFontPressed = { [weak self] in
            self?.presentFontPicker()
        }
        node.fontDeleted = { [weak self] family in
            self?.deleteImportedFont(family: family)
        }
        self.displayNode = node
        self.displayNodeDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.controllerNode.playVideo()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.controllerNode.pauseVideo()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
    
    private var isRussian: Bool {
        return self.presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
    }
    
    private func showRestartNotice() {
        let ru = self.isRussian
        let controller = textAlertController(
            context: self.context,
            title: ru ? "Шрифт выбран" : "Font selected",
            text: ru ? "Чтобы шрифт применился ко всему приложению, полностью закройте Telegram (смахните его вверх) и откройте снова." : "To apply the font to the whole app, fully close Telegram (swipe it up) and open it again.",
            actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]
        )
        self.present(controller, in: .window(.root))
    }
    
    private func selectFont(id: String) {
        if id.isEmpty {
            UserDefaults.standard.removeObject(forKey: Font.customFontFamilyDefaultsKey)
        } else {
            UserDefaults.standard.set(id, forKey: Font.customFontFamilyDefaultsKey)
        }
        self.controllerNode.reloadTable()
        self.showRestartNotice()
    }
    
    private func presentFontPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.font], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        let presenter: UIViewController = self.view.window?.rootViewController ?? self
        presenter.present(picker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        self.importFont(from: url)
    }
    
    private func importFont(from url: URL) {
        let ru = self.isRussian
        
        func presentFailure() {
            let controller = textAlertController(
                context: self.context,
                title: ru ? "Не удалось добавить шрифт" : "Could not add the font",
                text: ru ? "Файл не похож на шрифт. Подойдут файлы .ttf и .otf." : "This file does not look like a font. Use .ttf or .otf files.",
                actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]
            )
            self.present(controller, in: .window(.root))
        }
        
        guard let directory = Font.importedFontsDirectory() else {
            presentFailure()
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileExtension = url.pathExtension.lowercased() == "otf" ? "otf" : "ttf"
        let fileName = UUID().uuidString + "." + fileExtension
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            presentFailure()
            return
        }
        
        var family: String?
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first {
            family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        }
        guard let family, !family.isEmpty else {
            try? FileManager.default.removeItem(at: destination)
            presentFailure()
            return
        }
        
        // Makes the font available right away, for the previews.
        let _ = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil)
        
        var items = (UserDefaults.standard.array(forKey: Font.importedFontsDefaultsKey) as? [[String: String]]) ?? []
        for item in items where item["family"] == family {
            if let oldFile = item["file"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldFile))
            }
        }
        items.removeAll(where: { $0["family"] == family })
        items.append(["file": fileName, "family": family])
        UserDefaults.standard.set(items, forKey: Font.importedFontsDefaultsKey)
        
        self.controllerNode.reloadTable()
        self.selectFont(id: family)
    }
    
    private func deleteImportedFont(family: String) {
        guard let directory = Font.importedFontsDirectory() else {
            return
        }
        var items = (UserDefaults.standard.array(forKey: Font.importedFontsDefaultsKey) as? [[String: String]]) ?? []
        for item in items where item["family"] == family {
            if let file = item["file"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
        items.removeAll(where: { $0["family"] == family })
        UserDefaults.standard.set(items, forKey: Font.importedFontsDefaultsKey)
        
        if UserDefaults.standard.string(forKey: Font.customFontFamilyDefaultsKey) == family {
            UserDefaults.standard.removeObject(forKey: Font.customFontFamilyDefaultsKey)
        }
        self.controllerNode.reloadTable()
    }
}

public func fontsSettingsController(context: AccountContext) -> ViewController {
    return FontsSettingsScreen(context: context)
}
