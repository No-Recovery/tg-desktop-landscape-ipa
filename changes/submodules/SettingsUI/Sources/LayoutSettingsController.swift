import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

private struct LayoutOption {
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct LayoutSection {
    let title: String
    let footer: String?
    let options: [LayoutOption]
}

private final class LayoutSettingsScreenNode: ASDisplayNode, UITableViewDataSource, UITableViewDelegate {
    private var presentationData: PresentationData
    private let isRussian: Bool
    private let tableView: UITableView
    private var sections: [LayoutSection] = []
    private var didSetInitialOffset = false
    
    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.isRussian = presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
        self.tableView = UITableView(frame: CGRect(), style: .insetGrouped)
        
        super.init()
        
        self.reloadSections()
        
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.updateColors()
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
    
    private func reloadSections() {
        let ru = self.isRussian
        let orientation = DesktopLayoutPreferences.orientationMode
        let placement = DesktopLayoutPreferences.tabBarPlacement
        
        var sections: [LayoutSection] = []
        sections.append(LayoutSection(
            title: ru ? "ПОЛОЖЕНИЕ TELEGRAM" : "TELEGRAM ORIENTATION",
            footer: ru ? "В горизонтальном положении включается вид как в Telegram Desktop: слева папки и список чатов, справа чат." : "In landscape the Telegram Desktop style layout is used: folders and the chat list on the left, the chat on the right.",
            options: [
                LayoutOption(title: ru ? "Всегда горизонтально (как на ПК)" : "Always landscape (desktop style)", isSelected: orientation == .landscape, action: {
                    DesktopLayoutPreferences.orientationMode = .landscape
                }),
                LayoutOption(title: ru ? "Всегда вертикально (обычный вид)" : "Always portrait (regular layout)", isSelected: orientation == .portrait, action: {
                    DesktopLayoutPreferences.orientationMode = .portrait
                }),
                LayoutOption(title: ru ? "По повороту телефона" : "Follow the phone rotation", isSelected: orientation == .auto, action: {
                    DesktopLayoutPreferences.orientationMode = .auto
                })
            ]
        ))
        sections.append(LayoutSection(
            title: ru ? "ПАНЕЛЬ ВКЛАДОК" : "TAB BAR",
            footer: ru ? "Панель с вкладками «Контакты», «Звонки», «Чаты» и «Настройки». Работает в горизонтальном положении." : "The bar with Contacts, Calls, Chats and Settings. Used in landscape.",
            options: [
                LayoutOption(title: ru ? "Справа от чата" : "At the right, behind the chat", isSelected: placement == .right, action: {
                    DesktopLayoutPreferences.tabBarPlacement = .right
                }),
                LayoutOption(title: ru ? "Снизу, под списком чатов" : "At the bottom, below the chat list", isSelected: placement == .bottom, action: {
                    DesktopLayoutPreferences.tabBarPlacement = .bottom
                })
            ]
        ))
        self.sections = sections
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let leftInset = layout.safeInsets.left
        let rightInset = layout.safeInsets.right
        self.tableView.frame = CGRect(x: leftInset, y: 0.0, width: max(100.0, layout.size.width - leftInset - rightInset), height: layout.size.height)
        self.tableView.contentInset = UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0)
        self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset
        if !self.didSetInitialOffset {
            self.didSetInitialOffset = true
            self.tableView.contentOffset = CGPoint(x: 0.0, y: -navigationHeight)
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].options.count
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
        let option = self.sections[indexPath.section].options[indexPath.row]
        let theme = self.presentationData.theme
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.tintColor = theme.list.itemAccentColor
        let selectionView = UIView()
        selectionView.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.12)
        cell.selectedBackgroundView = selectionView
        cell.textLabel?.text = option.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 17.0)
        cell.textLabel?.textColor = theme.list.itemPrimaryTextColor
        cell.accessoryType = option.isSelected ? .checkmark : .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.sections[indexPath.section].options[indexPath.row].action()
        self.reloadSections()
        self.tableView.reloadData()
    }
}

final class LayoutSettingsScreen: ViewController {
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private var controllerNode: LayoutSettingsScreenNode {
        return self.displayNode as! LayoutSettingsScreenNode
    }
    
    init(context: AccountContext) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings))
        
        self._hasGlassStyle = true
        
        let isRussian = self.presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
        self.navigationItem.title = isRussian ? "Расположение" : "Layout"
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
        
        self.displayNode = LayoutSettingsScreenNode(presentationData: self.presentationData)
        self.displayNodeDidLoad()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

public func layoutSettingsController(context: AccountContext) -> ViewController {
    return LayoutSettingsScreen(context: context)
}
