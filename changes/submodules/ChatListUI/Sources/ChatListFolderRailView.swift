import Foundation
import UIKit
import Display
import TelegramPresentationData
import ChatListFilterTabContainerNode

/// Vertical folder column in the style of Telegram Desktop: icon, title and an unread badge per folder,
/// plus an "Edit" entry at the end. Shown to the left of the chat list when an iPhone is in landscape.
final class ChatListFolderRailView: UIView {
    struct Item: Equatable {
        let id: ChatListFilterTabEntryId
        let title: String
        let badgeValue: Int
        let badgeIsAccent: Bool
    }
    
    static let railWidth: CGFloat = 64.0
    
    private final class ItemView: UIControl {
        let selectionBackground = UIView()
        let iconView = UIImageView()
        let titleLabel = UILabel()
        let badgeBackground = UIView()
        let badgeLabel = UILabel()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.selectionBackground.layer.cornerRadius = 10.0
            self.selectionBackground.isUserInteractionEnabled = false
            self.addSubview(self.selectionBackground)
            
            self.iconView.contentMode = .center
            self.iconView.isUserInteractionEnabled = false
            self.addSubview(self.iconView)
            
            self.titleLabel.font = Font.regular(10.0)
            self.titleLabel.textAlignment = .center
            self.titleLabel.lineBreakMode = .byTruncatingTail
            self.titleLabel.isUserInteractionEnabled = false
            self.addSubview(self.titleLabel)
            
            self.badgeBackground.isUserInteractionEnabled = false
            self.badgeBackground.isHidden = true
            self.addSubview(self.badgeBackground)
            
            self.badgeLabel.font = Font.with(size: 10.0, design: .regular, weight: .semibold, traits: [.monospacedNumbers])
            self.badgeLabel.textAlignment = .center
            self.badgeLabel.isUserInteractionEnabled = false
            self.badgeBackground.addSubview(self.badgeLabel)
        }
        
        required init?(coder: NSCoder) {
            preconditionFailure()
        }
        
        func update(
            theme: PresentationTheme,
            image: UIImage?,
            title: String,
            badgeValue: Int,
            badgeIsAccent: Bool,
            isSelected: Bool,
            size: CGSize
        ) {
            let accentColor = theme.rootController.tabBar.selectedIconColor
            let normalColor = theme.rootController.tabBar.iconColor
            let tint = isSelected ? accentColor : normalColor
            
            self.selectionBackground.backgroundColor = accentColor.withAlphaComponent(0.14)
            self.selectionBackground.isHidden = !isSelected
            self.selectionBackground.frame = CGRect(x: 6.0, y: 2.0, width: size.width - 12.0, height: size.height - 4.0)
            
            self.iconView.image = image?.withRenderingMode(.alwaysTemplate)
            self.iconView.tintColor = tint
            self.iconView.frame = CGRect(x: floor((size.width - 28.0) / 2.0), y: 8.0, width: 28.0, height: 28.0)
            
            self.titleLabel.text = title
            self.titleLabel.textColor = tint
            self.titleLabel.frame = CGRect(x: 2.0, y: 38.0, width: size.width - 4.0, height: 14.0)
            
            if badgeValue > 0 {
                let text = badgeValue > 999 ? "999+" : "\(badgeValue)"
                self.badgeLabel.text = text
                self.badgeLabel.textColor = badgeIsAccent ? theme.chatList.unreadBadgeActiveTextColor : theme.chatList.unreadBadgeInactiveTextColor
                self.badgeBackground.backgroundColor = badgeIsAccent ? theme.chatList.unreadBadgeActiveBackgroundColor : theme.chatList.unreadBadgeInactiveBackgroundColor
                
                self.badgeLabel.sizeToFit()
                let badgeHeight: CGFloat = 16.0
                let badgeWidth = max(badgeHeight, ceil(self.badgeLabel.bounds.width) + 8.0)
                self.badgeBackground.frame = CGRect(x: size.width - badgeWidth - 6.0, y: 4.0, width: badgeWidth, height: badgeHeight)
                self.badgeBackground.layer.cornerRadius = badgeHeight / 2.0
                self.badgeLabel.frame = CGRect(x: floor((badgeWidth - self.badgeLabel.bounds.width) / 2.0), y: floor((badgeHeight - self.badgeLabel.bounds.height) / 2.0), width: self.badgeLabel.bounds.width, height: self.badgeLabel.bounds.height)
                self.badgeBackground.isHidden = false
            } else {
                self.badgeBackground.isHidden = true
            }
        }
    }
    
    private let scrollView = UIScrollView()
    private let separatorView = UIView()
    private var itemViews: [ChatListFilterTabEntryId: ItemView] = [:]
    private let editItemView = ItemView()
    
    var tabSelected: ((ChatListFilterTabEntryId) -> Void)?
    var editPressed: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.addSubview(self.scrollView)
        self.addSubview(self.separatorView)
        
        self.editItemView.addTarget(self, action: #selector(self.editItemPressed), for: .touchUpInside)
        self.scrollView.addSubview(self.editItemView)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    @objc private func editItemPressed() {
        self.editPressed?()
    }
    
    @objc private func itemPressed(_ sender: UIControl) {
        for (id, view) in self.itemViews where view === sender {
            self.tabSelected?(id)
            return
        }
    }
    
    /// - Parameters:
    ///   - leftInset: the left safe inset (iPhone notch in landscape): the background extends under it, items stay clear of it.
    func update(theme: PresentationTheme, strings: PresentationStrings, items: [Item], selectedId: ChatListFilterTabEntryId, size: CGSize, leftInset: CGFloat, topInset: CGFloat, bottomInset: CGFloat) {
        self.backgroundColor = theme.rootController.tabBar.backgroundColor
        self.separatorView.backgroundColor = theme.rootController.tabBar.separatorColor
        self.separatorView.frame = CGRect(x: size.width - UIScreenPixel, y: 0.0, width: UIScreenPixel, height: size.height)
        
        self.scrollView.frame = CGRect(origin: CGPoint(), size: size)
        
        let itemWidth = size.width - leftInset
        let itemHeight: CGFloat = 56.0
        let itemSize = CGSize(width: itemWidth, height: itemHeight)
        
        var validIds = Set<ChatListFilterTabEntryId>()
        var y: CGFloat = topInset
        for item in items {
            validIds.insert(item.id)
            
            let itemView: ItemView
            if let current = self.itemViews[item.id] {
                itemView = current
            } else {
                itemView = ItemView()
                itemView.addTarget(self, action: #selector(self.itemPressed(_:)), for: .touchUpInside)
                self.itemViews[item.id] = itemView
                self.scrollView.addSubview(itemView)
            }
            
            let symbolName: String
            if case .all = item.id {
                symbolName = "bubble.left.and.bubble.right.fill"
            } else {
                symbolName = "folder.fill"
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
            itemView.update(
                theme: theme,
                image: UIImage(systemName: symbolName, withConfiguration: configuration),
                title: item.title,
                badgeValue: item.badgeValue,
                badgeIsAccent: item.badgeIsAccent,
                isSelected: item.id == selectedId,
                size: itemSize
            )
            itemView.frame = CGRect(origin: CGPoint(x: leftInset, y: y), size: itemSize)
            y += itemHeight
        }
        
        for (id, view) in self.itemViews where !validIds.contains(id) {
            view.removeFromSuperview()
            self.itemViews.removeValue(forKey: id)
        }
        
        let editConfiguration = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
        self.editItemView.update(
            theme: theme,
            image: UIImage(systemName: "slider.horizontal.3", withConfiguration: editConfiguration),
            title: strings.Common_Edit,
            badgeValue: 0,
            badgeIsAccent: false,
            isSelected: false,
            size: itemSize
        )
        self.editItemView.frame = CGRect(origin: CGPoint(x: leftInset, y: y), size: itemSize)
        y += itemHeight
        
        self.scrollView.contentSize = CGSize(width: size.width, height: y + bottomInset)
    }
}
