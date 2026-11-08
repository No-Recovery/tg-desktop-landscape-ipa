import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit

enum NavigationSplitContainerScrollToTop {
    case master
    case detail
}

/// The width of the master pane. While the fold is active and runs vertically through the whole
/// container (iPhone Duo half-open in landscape), the split sits on the hinge's midline, so the
/// chat list and the chat each get one side of the fold. Otherwise a third of the width, at least
/// 320pt and at most half.
public func splitMasterWidth(containerSize: CGSize, division: CGRect?) -> CGFloat {
    if let division, division.width < containerSize.width, division.minY <= 0.5, division.maxY >= containerSize.height - 0.5 {
        return floorToScreenPixels(division.midX)
    }
    if UIDevice.current.userInterfaceIdiom == .phone {
        // iPhone in landscape: the master pane also holds the vertical folder column, so it is a bit wider.
        return min(max(380.0, floor(containerSize.width * 0.42)), floor(containerSize.width / 2.0))
    }
    return min(max(320.0, floor(containerSize.width / 3.0)), floor(containerSize.width / 2.0))
}

final class NavigationSplitContainer: ASDisplayNode {
    private var theme: NavigationControllerTheme
    
    private let masterContainer: NavigationContainer
    private let detailContainer: NavigationContainer
    private let separator: ASDisplayNode
    
    private(set) var masterControllers: [ViewController] = []
    private(set) var detailControllers: [ViewController] = []
    
    private var lastUpdateParams: (layout: ContainerViewLayout, masterControllers: [ViewController], detailControllers: [ViewController], detailsPlaceholderNode: NavigationDetailsPlaceholderNode?)?
    
    var canHaveKeyboardFocus: Bool = false {
        didSet {
            self.masterContainer.canHaveKeyboardFocus = self.canHaveKeyboardFocus
            self.detailContainer.canHaveKeyboardFocus = self.canHaveKeyboardFocus
        }
    }
    
    var isInFocus: Bool = false {
        didSet {
            if self.isInFocus != oldValue {
                self.inFocusUpdated(isInFocus: self.isInFocus)
            }
        }
    }
    func inFocusUpdated(isInFocus: Bool) {
        self.masterContainer.isInFocus = isInFocus
        self.detailContainer.isInFocus = isInFocus
    }
    
    init(theme: NavigationControllerTheme, controllerRemoved: @escaping (ViewController) -> Void) {
        self.theme = theme
        
        self.masterContainer = NavigationContainer(isFlat: false, controllerRemoved: controllerRemoved)
        self.masterContainer.clipsToBounds = true
        
        self.detailContainer = NavigationContainer(isFlat: false, controllerRemoved: controllerRemoved)
        self.detailContainer.clipsToBounds = true
        
        self.separator = ASDisplayNode()
        self.separator.backgroundColor = theme.separatorColor
        
        super.init()
        
        self.addSubnode(self.masterContainer)
        self.addSubnode(self.detailContainer)
        self.addSubnode(self.separator)
    }
    
    override func didLoad() {
        super.didLoad()
        
        // Desktop-style layout: the keyboard of the chat is drawn inside the detail pane (see InAppKeyboardManager).
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.view.addSubview(InAppKeyboardManager.shared.keyboardView)
        }
    }
    
    private func updateForInAppKeyboard() {
        guard let params = self.lastUpdateParams else {
            return
        }
        self.update(layout: params.layout, masterControllers: params.masterControllers, detailControllers: params.detailControllers, detailsPlaceholderNode: params.detailsPlaceholderNode, transition: .animated(duration: 0.25, curve: .easeInOut))
    }
    
    func hasNonReadyControllers() -> Bool {
        if self.masterContainer.hasNonReadyControllers() {
            return true
        }
        if self.detailContainer.hasNonReadyControllers() {
            return true
        }
        return false
    }
    
    func updateTheme(theme: NavigationControllerTheme) {
        self.separator.backgroundColor = theme.separatorColor
    }
    
    /// The master controllers highlight the chat the detail pane shows (`updateNavigationCustomData`);
    /// when the split goes away (the layout became compact, e.g. folding iPhone Duo) nothing else clears
    /// that highlight, so the container clears it before it is removed.
    func clearDetailSelection() {
        for controller in self.masterControllers {
            controller.updateNavigationCustomData(nil, progress: 0.0, transition: .immediate)
        }
    }

    func scrollToTopProxyFrames(layout: ContainerViewLayout) -> (master: CGRect, detail: CGRect) {
        let masterWidth = splitMasterWidth(containerSize: layout.size, division: layout.division)
        let detailWidth = layout.size.width - masterWidth
        let scrollToTopHeight = max(layout.statusBarHeight ?? layout.safeInsets.top, 1.0)
        
        return (
            master: CGRect(origin: CGPoint(), size: CGSize(width: masterWidth, height: scrollToTopHeight)),
            detail: CGRect(origin: CGPoint(x: masterWidth, y: 0.0), size: CGSize(width: detailWidth, height: scrollToTopHeight))
        )
    }

    func update(layout: ContainerViewLayout, masterControllers: [ViewController], detailControllers: [ViewController], detailsPlaceholderNode: NavigationDetailsPlaceholderNode?, transition: ContainedViewLayoutTransition) {
        self.lastUpdateParams = (layout, masterControllers, detailControllers, detailsPlaceholderNode)
        
        let masterWidth = splitMasterWidth(containerSize: layout.size, division: layout.division)
        let detailWidth = layout.size.width - masterWidth
        
        var detailInputHeight: CGFloat? = layout.inputHeight
        if UIDevice.current.userInterfaceIdiom == .phone {
            let keyboardManager = InAppKeyboardManager.shared
            keyboardManager.hostView = self.detailContainer.view
            keyboardManager.heightChanged = { [weak self] in
                self?.updateForInAppKeyboard()
            }
            let keyboardHeight = keyboardManager.keyboardHeight(bottomInset: layout.intrinsicInsets.bottom)
            let keyboardView = keyboardManager.keyboardView
            keyboardView.bottomInset = layout.intrinsicInsets.bottom
            if keyboardView.superview !== self.view {
                self.view.addSubview(keyboardView)
            }
            self.view.bringSubviewToFront(keyboardView)
            transition.updateFrame(view: keyboardView, frame: CGRect(origin: CGPoint(x: masterWidth, y: layout.size.height - keyboardHeight), size: CGSize(width: detailWidth, height: InAppKeyboardView.contentHeight + layout.intrinsicInsets.bottom)))
            if keyboardHeight > 0.0 {
                detailInputHeight = keyboardHeight
            }
        }
        
        transition.updateFrame(node: self.masterContainer, frame: CGRect(origin: CGPoint(), size: CGSize(width: masterWidth, height: layout.size.height)))
        transition.updateFrame(node: self.detailContainer, frame: CGRect(origin: CGPoint(x: masterWidth, y: 0.0), size: CGSize(width: detailWidth, height: layout.size.height)))
        transition.updateFrame(node: self.separator, frame: CGRect(origin: CGPoint(x: masterWidth, y: 0.0), size: CGSize(width: UIScreenPixel, height: layout.size.height)))
        
        if let detailsPlaceholderNode {
            let needsTiling = layout.size.width > layout.size.height
            detailsPlaceholderNode.updateLayout(size: CGSize(width: detailWidth, height: layout.size.height), needsTiling: needsTiling, transition: transition)
            transition.updateFrame(node: detailsPlaceholderNode, frame: CGRect(origin: CGPoint(x: masterWidth, y: 0.0), size: CGSize(width: detailWidth, height: layout.size.height)))
        }
        
        // Each pane touches the screen edge on one side only; the split line
        // is not a screen edge, so it must not inherit that side's safe inset.
        var masterSafeInsets = layout.safeInsets
        masterSafeInsets.right = 0.0
        var detailSafeInsets = layout.safeInsets
        detailSafeInsets.left = 0.0
        let masterReserved = reservedAreaForPane(corners: layout.reservedCorners, division: layout.division, paneFrame: CGRect(x: 0.0, y: 0.0, width: masterWidth, height: layout.size.height), containerSize: layout.size)
        let detailReserved = reservedAreaForPane(corners: layout.reservedCorners, division: layout.division, paneFrame: CGRect(x: masterWidth, y: 0.0, width: detailWidth, height: layout.size.height), containerSize: layout.size)
        
        self.masterContainer.update(layout: ContainerViewLayout(size: CGSize(width: masterWidth, height: layout.size.height), metrics: layout.metrics, deviceMetrics: layout.deviceMetrics, intrinsicInsets: layout.intrinsicInsets, safeInsets: masterSafeInsets, reservedCorners: masterReserved.corners, division: masterReserved.division, additionalInsets: UIEdgeInsets(), statusBarHeight: layout.statusBarHeight, inputHeight: layout.inputHeight, inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging, inVoiceOver: layout.inVoiceOver, presentedInFormSheet: layout.presentedInFormSheet), canBeClosed: false, controllers: masterControllers, transition: transition)
        self.detailContainer.update(layout: ContainerViewLayout(size: CGSize(width: detailWidth, height: layout.size.height), metrics: layout.metrics, deviceMetrics: layout.deviceMetrics, intrinsicInsets: layout.intrinsicInsets, safeInsets: detailSafeInsets, reservedCorners: detailReserved.corners, division: detailReserved.division, additionalInsets: layout.additionalInsets, statusBarHeight: layout.statusBarHeight, inputHeight: detailInputHeight, inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging, inVoiceOver: layout.inVoiceOver, presentedInFormSheet: layout.presentedInFormSheet), canBeClosed: true, controllers: detailControllers, transition: transition)
        
        var controllersUpdated = false
        if self.detailControllers.last !== detailControllers.last {
            controllersUpdated = true
        } else if self.masterControllers.count != masterControllers.count {
            controllersUpdated = true
        } else {
            for i in 0 ..< masterControllers.count {
                if masterControllers[i] !== self.masterControllers[i] {
                    controllersUpdated = true
                    break
                }
            }
        }
        
        let detailChanged = self.detailControllers.last !== detailControllers.last && detailControllers.last != nil
        
        self.masterControllers = masterControllers
        self.detailControllers = detailControllers
        
        // Desktop-style layout: a chat opened in the right pane slides in and fades in.
        if detailChanged, UIDevice.current.userInterfaceIdiom == .phone, self.isNodeLoaded {
            let detailLayer = self.detailContainer.layer
            let slideAnimation = CABasicAnimation(keyPath: "transform.translation.x")
            slideAnimation.fromValue = 28.0
            slideAnimation.toValue = 0.0
            slideAnimation.duration = 0.3
            slideAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailLayer.add(slideAnimation, forKey: "desktopDetailSlide")
            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = 0.0
            fadeAnimation.toValue = 1.0
            fadeAnimation.duration = 0.3
            fadeAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailLayer.add(fadeAnimation, forKey: "desktopDetailFade")
        }
        
        if controllersUpdated {
            let data = self.detailControllers.last?.customData
            for controller in self.masterControllers {
                controller.updateNavigationCustomData(data, progress: 1.0, transition: transition)
            }
        }
    }
}
