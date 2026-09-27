import SwiftUI
import UIKit

/// Clipbara keyboard: tap a clip to type it into the current text field.
///
/// Works without Full Access. It only reads the snapshot the app writes and inserts
/// text through `textDocumentProxy`, so nothing typed elsewhere is ever read or sent.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var hostingController: UIHostingController<KeyboardRootView>?

    override func loadView() {
        let inputView = ClickableInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        model.insert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
            UIDevice.current.playInputClick()
        }
        model.deleteBackward = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
            UIDevice.current.playInputClick()
        }
        model.nextKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }

        let host = UIHostingController(rootView: KeyboardRootView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 272)
        height.priority = .defaultHigh
        height.isActive = true
        host.didMove(toParent: self)
        hostingController = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.showsNextKeyboardKey = needsInputModeSwitchKey
        model.reload()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        model.returnKeyType = textDocumentProxy.returnKeyType ?? .default
    }
}

/// Keyboard clicks only play when the input view adopts this protocol.
final class ClickableInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
