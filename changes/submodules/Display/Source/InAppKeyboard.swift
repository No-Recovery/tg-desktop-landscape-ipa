import Foundation
import UIKit

private func inAppKeyboardColor(dark: UIColor, light: UIColor) -> UIColor {
    return UIColor { traits in
        return traits.userInterfaceStyle == .dark ? dark : light
    }
}

/// Keeps the state of the keyboard that is drawn inside the chat pane (desktop-style layout on iPhone).
/// The chat text view asks `inputViewOverride(for:)` for its `inputView`; while the text view lives in the
/// detail pane, an empty view replaces the system keyboard and `InAppKeyboardView` is shown in the pane instead.
public final class InAppKeyboardManager {
    public static let shared = InAppKeyboardManager()
    
    private let emptyInputView = UIView(frame: CGRect())
    
    /// The view of the detail pane. Set by the split container.
    weak var hostView: UIView?
    /// Called when the keyboard appears or disappears, so that the split container can relayout.
    var heightChanged: (() -> Void)?
    
    let keyboardView = InAppKeyboardView()
    private(set) var isVisible: Bool = false
    private weak var activeTextView: UITextView?
    
    private init() {
        NotificationCenter.default.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: nil, using: { [weak self] notification in
            guard let self, let textView = notification.object as? UITextView else {
                return
            }
            if textView.inputView === self.emptyInputView {
                self.activeTextView = textView
                self.keyboardView.attach(textView: textView)
                self.setVisible(true)
            }
        })
        NotificationCenter.default.addObserver(forName: UITextView.textDidEndEditingNotification, object: nil, queue: nil, using: { [weak self] notification in
            guard let self, let textView = notification.object as? UITextView else {
                return
            }
            if self.activeTextView === textView {
                self.activeTextView = nil
                self.keyboardView.detach()
                self.setVisible(false)
            }
        })
    }
    
    private func setVisible(_ isVisible: Bool) {
        if self.isVisible != isVisible {
            self.isVisible = isVisible
            self.heightChanged?()
        }
    }
    
    /// The replacement for the system keyboard of a text view, or nil to keep the system keyboard.
    public func inputViewOverride(for textView: UITextView) -> UIView? {
        guard UIDevice.current.userInterfaceIdiom == .phone, let hostView = self.hostView, hostView.window != nil else {
            return nil
        }
        if textView.isDescendant(of: hostView) {
            return self.emptyInputView
        }
        return nil
    }
    
    /// The height of the keyboard including the bottom safe inset, 0 when it is hidden.
    func keyboardHeight(bottomInset: CGFloat) -> CGFloat {
        if self.isVisible {
            return InAppKeyboardView.contentHeight + bottomInset
        } else {
            return 0.0
        }
    }
}

private final class InAppKeyboardKeyView: UIControl {
    enum Style {
        case letter
        case special
    }
    
    private let style: Style
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    
    var tapped: (() -> Void)?
    var longPressed: (() -> Void)?
    var pressBegan: (() -> Void)?
    var pressEnded: (() -> Void)?
    
    var hasLongPress: Bool = false {
        didSet {
            self.longPressRecognizer.isEnabled = self.hasLongPress
        }
    }
    private let longPressRecognizer = UILongPressGestureRecognizer()
    
    override var isHighlighted: Bool {
        didSet {
            self.updateBackground()
        }
    }
    
    init(style: Style) {
        self.style = style
        
        super.init(frame: CGRect())
        
        self.layer.cornerRadius = 6.0
        self.layer.cornerCurve = .continuous
        
        self.titleLabel.textAlignment = .center
        self.titleLabel.font = UIFont.systemFont(ofSize: 21.0, weight: .regular)
        self.titleLabel.textColor = inAppKeyboardColor(dark: .white, light: .black)
        self.titleLabel.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel)
        
        self.iconView.contentMode = .center
        self.iconView.tintColor = inAppKeyboardColor(dark: .white, light: .black)
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)
        
        self.longPressRecognizer.minimumPressDuration = 0.4
        self.longPressRecognizer.addTarget(self, action: #selector(self.longPressAction(_:)))
        self.longPressRecognizer.isEnabled = false
        self.addGestureRecognizer(self.longPressRecognizer)
        
        self.addTarget(self, action: #selector(self.touchDownAction), for: .touchDown)
        self.addTarget(self, action: #selector(self.touchUpInsideAction), for: .touchUpInside)
        self.addTarget(self, action: #selector(self.touchEndedAction), for: [.touchUpOutside, .touchCancel])
        
        self.updateBackground()
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    private func updateBackground() {
        switch self.style {
        case .letter:
            self.backgroundColor = self.isHighlighted ? inAppKeyboardColor(dark: UIColor(white: 0.42, alpha: 1.0), light: UIColor(white: 0.80, alpha: 1.0)) : inAppKeyboardColor(dark: UIColor(white: 0.27, alpha: 1.0), light: .white)
        case .special:
            self.backgroundColor = self.isHighlighted ? inAppKeyboardColor(dark: UIColor(white: 0.42, alpha: 1.0), light: .white) : inAppKeyboardColor(dark: UIColor(white: 0.19, alpha: 1.0), light: UIColor(white: 0.70, alpha: 1.0))
        }
    }
    
    func setTitle(_ title: String?, fontSize: CGFloat = 21.0) {
        self.titleLabel.text = title
        self.titleLabel.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        self.iconView.image = nil
        self.setNeedsLayout()
    }
    
    func setSymbol(_ name: String) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 17.0, weight: .regular)
        self.iconView.image = UIImage(systemName: name, withConfiguration: configuration)
        self.titleLabel.text = nil
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.titleLabel.frame = self.bounds
        self.iconView.frame = self.bounds
    }
    
    @objc private func touchDownAction() {
        self.pressBegan?()
    }
    
    @objc private func touchUpInsideAction() {
        self.pressEnded?()
        self.tapped?()
    }
    
    @objc private func touchEndedAction() {
        self.pressEnded?()
    }
    
    @objc private func longPressAction(_ recognizer: UILongPressGestureRecognizer) {
        if case .began = recognizer.state {
            self.longPressed?()
        }
    }
}

final class InAppKeyboardView: UIView {
    static let rowHeight: CGFloat = 34.0
    static let spacing: CGFloat = 5.0
    static var contentHeight: CGFloat {
        return rowHeight * 4.0 + spacing * 5.0
    }
    
    private enum Page {
        case letters
        case symbols
    }
    
    private enum Language: Int {
        case russian
        case english
    }
    
    private enum ShiftState {
        case off
        case once
        case caps
    }
    
    private enum Kind {
        case character(String)
        case shift
        case backspace
        case page
        case language
        case space
        case newline
    }
    
    private struct KeySpec {
        let kind: Kind
        let weight: CGFloat
    }
    
    private static let languageDefaultsKey = "inAppKeyboard.language"
    
    private weak var textView: UITextView?
    var bottomInset: CGFloat = 0.0 {
        didSet {
            if self.bottomInset != oldValue {
                self.setNeedsLayout()
            }
        }
    }
    
    private var page: Page = .letters
    private var language: Language
    private var shift: ShiftState = .once
    private var lastShiftTapTimestamp: Double = 0.0
    
    private var rows: [[(spec: KeySpec, view: InAppKeyboardKeyView)]] = []
    private var shiftKeyView: InAppKeyboardKeyView?
    private var characterKeyViews: [(title: String, view: InAppKeyboardKeyView)] = []
    private var pageKeyView: InAppKeyboardKeyView?
    private var spaceKeyView: InAppKeyboardKeyView?
    
    private var backspaceTimer: Timer?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init() {
        let storedLanguage = UserDefaults.standard.integer(forKey: InAppKeyboardView.languageDefaultsKey)
        self.language = Language(rawValue: storedLanguage) ?? .russian
        
        super.init(frame: CGRect())
        
        self.backgroundColor = inAppKeyboardColor(dark: UIColor(white: 0.11, alpha: 1.0), light: UIColor(white: 0.82, alpha: 1.0))
        self.rebuildKeys()
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    deinit {
        self.backspaceTimer?.invalidate()
    }
    
    func attach(textView: UITextView) {
        self.textView = textView
        self.page = .letters
        self.rebuildKeys()
        self.updateAutoShift()
    }
    
    func detach() {
        self.stopBackspaceRepeat()
        self.textView = nil
    }
    
    // MARK: - Keys
    
    private func specs() -> [[KeySpec]] {
        func characters(_ string: String) -> [KeySpec] {
            return string.map { KeySpec(kind: .character(String($0)), weight: 1.0) }
        }
        
        var result: [[KeySpec]] = []
        switch self.page {
        case .letters:
            let lines: [String]
            switch self.language {
            case .russian:
                lines = ["йцукенгшщзх", "фывапролджэ", "ячсмитьбю"]
            case .english:
                lines = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
            }
            let sideWeight: CGFloat = self.language == .russian ? 1.0 : 1.5
            result.append(characters(lines[0]))
            result.append(characters(lines[1]))
            result.append([KeySpec(kind: .shift, weight: sideWeight)] + characters(lines[2]) + [KeySpec(kind: .backspace, weight: sideWeight)])
        case .symbols:
            result.append(characters("1234567890"))
            result.append(["-", "/", ":", ";", "(", ")", "\u{20BD}", "&", "@", "\""].map { KeySpec(kind: .character($0), weight: 1.0) })
            result.append(["%", ".", ",", "?", "!", "'", "+", "="].map { KeySpec(kind: .character($0), weight: 1.0) } + [KeySpec(kind: .backspace, weight: 1.5)])
        }
        result.append([
            KeySpec(kind: .page, weight: 1.6),
            KeySpec(kind: .language, weight: 1.2),
            KeySpec(kind: .space, weight: 0.0),
            KeySpec(kind: .newline, weight: 2.2)
        ])
        return result
    }
    
    private func rebuildKeys() {
        self.stopBackspaceRepeat()
        for row in self.rows {
            for item in row {
                item.view.removeFromSuperview()
            }
        }
        self.rows = []
        self.characterKeyViews = []
        self.shiftKeyView = nil
        self.pageKeyView = nil
        self.spaceKeyView = nil
        
        for rowSpecs in self.specs() {
            var row: [(spec: KeySpec, view: InAppKeyboardKeyView)] = []
            for spec in rowSpecs {
                let view = self.makeKeyView(spec: spec)
                self.addSubview(view)
                row.append((spec, view))
            }
            self.rows.append(row)
        }
        self.refreshTitles()
        self.setNeedsLayout()
    }
    
    private func makeKeyView(spec: KeySpec) -> InAppKeyboardKeyView {
        switch spec.kind {
        case let .character(title):
            let view = InAppKeyboardKeyView(style: .letter)
            view.tapped = { [weak self] in
                self?.insertCharacter(title)
            }
            if self.page == .letters, self.language == .russian {
                // Long press inserts the alternative character, as on the system keyboard.
                let alternatives: [String: String] = ["е": "ё", "ь": "ъ"]
                if let alternative = alternatives[title] {
                    view.hasLongPress = true
                    view.longPressed = { [weak self] in
                        self?.insertCharacter(alternative)
                    }
                }
            }
            self.characterKeyViews.append((title, view))
            return view
        case .shift:
            let view = InAppKeyboardKeyView(style: .special)
            view.tapped = { [weak self] in
                self?.shiftPressed()
            }
            self.shiftKeyView = view
            return view
        case .backspace:
            let view = InAppKeyboardKeyView(style: .special)
            view.setSymbol("delete.left")
            view.pressBegan = { [weak self] in
                self?.startBackspaceRepeat()
            }
            view.pressEnded = { [weak self] in
                self?.stopBackspaceRepeat()
            }
            return view
        case .page:
            let view = InAppKeyboardKeyView(style: .special)
            view.tapped = { [weak self] in
                guard let self else {
                    return
                }
                self.feedbackGenerator.impactOccurred()
                self.page = self.page == .letters ? .symbols : .letters
                self.rebuildKeys()
                self.updateAutoShift()
            }
            self.pageKeyView = view
            return view
        case .language:
            let view = InAppKeyboardKeyView(style: .special)
            view.setSymbol("globe")
            view.tapped = { [weak self] in
                guard let self else {
                    return
                }
                self.feedbackGenerator.impactOccurred()
                self.language = self.language == .russian ? .english : .russian
                UserDefaults.standard.set(self.language.rawValue, forKey: InAppKeyboardView.languageDefaultsKey)
                self.page = .letters
                self.rebuildKeys()
                self.updateAutoShift()
            }
            return view
        case .space:
            let view = InAppKeyboardKeyView(style: .letter)
            view.tapped = { [weak self] in
                guard let self else {
                    return
                }
                self.feedbackGenerator.impactOccurred()
                self.textView?.insertText(" ")
                self.updateAutoShift()
            }
            self.spaceKeyView = view
            return view
        case .newline:
            let view = InAppKeyboardKeyView(style: .special)
            view.setSymbol("return")
            view.tapped = { [weak self] in
                guard let self else {
                    return
                }
                self.feedbackGenerator.impactOccurred()
                self.textView?.insertText("\n")
                self.updateAutoShift()
            }
            return view
        }
    }
    
    private func refreshTitles() {
        let isUppercase = self.page == .letters && self.shift != .off
        for item in self.characterKeyViews {
            item.view.setTitle(isUppercase ? item.title.uppercased() : item.title)
        }
        
        if let shiftKeyView = self.shiftKeyView {
            switch self.shift {
            case .off:
                shiftKeyView.setSymbol("shift")
            case .once:
                shiftKeyView.setSymbol("shift.fill")
            case .caps:
                shiftKeyView.setSymbol("capslock.fill")
            }
        }
        
        if let pageKeyView = self.pageKeyView {
            switch self.page {
            case .letters:
                pageKeyView.setTitle("123", fontSize: 17.0)
            case .symbols:
                pageKeyView.setTitle(self.language == .russian ? "\u{0430}\u{0431}\u{0432}" : "ABC", fontSize: 17.0)
            }
        }
        
        if let spaceKeyView = self.spaceKeyView {
            spaceKeyView.setTitle(self.language == .russian ? "\u{0440}\u{0443}" : "en", fontSize: 14.0)
        }
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let spacing = InAppKeyboardView.spacing
        let margin: CGFloat = 6.0
        let availableWidth = self.bounds.width - margin * 2.0
        if availableWidth <= 0.0 || self.rows.isEmpty {
            return
        }
        
        let topRowCount = CGFloat(max(self.rows[0].count, 1))
        let unit = (availableWidth - spacing * (topRowCount - 1.0)) / topRowCount
        
        var y = spacing
        for row in self.rows {
            var fixedWidth: CGFloat = 0.0
            var hasFlexibleKey = false
            for item in row {
                if item.spec.weight > 0.0 {
                    fixedWidth += item.spec.weight * unit
                } else {
                    hasFlexibleKey = true
                }
            }
            let totalSpacing = spacing * CGFloat(max(row.count - 1, 0))
            let flexibleWidth = max(0.0, availableWidth - fixedWidth - totalSpacing)
            let rowWidth = hasFlexibleKey ? availableWidth : fixedWidth + totalSpacing
            
            var x = margin + floor((availableWidth - rowWidth) / 2.0)
            for item in row {
                let width = item.spec.weight > 0.0 ? item.spec.weight * unit : flexibleWidth
                item.view.frame = CGRect(x: floor(x), y: y, width: floor(width), height: InAppKeyboardView.rowHeight)
                x += width + spacing
            }
            y += InAppKeyboardView.rowHeight + spacing
        }
    }
    
    // MARK: - Actions
    
    private func insertCharacter(_ title: String) {
        guard let textView = self.textView else {
            return
        }
        self.feedbackGenerator.impactOccurred()
        let isUppercase = self.page == .letters && self.shift != .off
        textView.insertText(isUppercase ? title.uppercased() : title)
        if self.shift == .once {
            self.shift = .off
            self.refreshTitles()
        }
        self.updateAutoShift()
    }
    
    private func shiftPressed() {
        self.feedbackGenerator.impactOccurred()
        let now = CACurrentMediaTime()
        switch self.shift {
        case .off:
            self.shift = .once
        case .once:
            self.shift = now - self.lastShiftTapTimestamp < 0.35 ? .caps : .off
        case .caps:
            self.shift = .off
        }
        self.lastShiftTapTimestamp = now
        self.refreshTitles()
    }
    
    private func startBackspaceRepeat() {
        self.stopBackspaceRepeat()
        self.feedbackGenerator.impactOccurred()
        self.deleteBackward()
        let timer = Timer(timeInterval: 0.4, repeats: false, block: { [weak self] _ in
            guard let self else {
                return
            }
            let repeatTimer = Timer(timeInterval: 0.07, repeats: true, block: { [weak self] _ in
                self?.deleteBackward()
            })
            RunLoop.main.add(repeatTimer, forMode: .common)
            self.backspaceTimer = repeatTimer
        })
        RunLoop.main.add(timer, forMode: .common)
        self.backspaceTimer = timer
    }
    
    private func stopBackspaceRepeat() {
        self.backspaceTimer?.invalidate()
        self.backspaceTimer = nil
    }
    
    private func deleteBackward() {
        self.textView?.deleteBackward()
        self.updateAutoShift()
    }
    
    /// Capitalizes the first letter of the text and the first letter after a sentence end.
    private func updateAutoShift() {
        if self.shift == .caps {
            return
        }
        let shouldCapitalize = self.page == .letters && self.shouldCapitalizeNextCharacter()
        let updatedShift: ShiftState = shouldCapitalize ? .once : .off
        if self.shift != updatedShift {
            self.shift = updatedShift
            self.refreshTitles()
        }
    }
    
    private func shouldCapitalizeNextCharacter() -> Bool {
        guard let textView = self.textView, let selectedRange = textView.selectedTextRange, let range = textView.textRange(from: textView.beginningOfDocument, to: selectedRange.start) else {
            return false
        }
        let text = textView.text(in: range) ?? ""
        if text.isEmpty || text.hasSuffix("\n") {
            return true
        }
        if text.hasSuffix(" ") {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.isEmpty
        }
        return false
    }
}
