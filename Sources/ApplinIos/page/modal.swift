import Foundation
import UIKit

public enum ModalKind: String {
    case alert
    case drawer

    public func typ() -> String {
        switch self {
        case .alert:
            return "alert-modal"
        case .drawer:
            return "drawer-modal"
        }
    }

    public func style() -> UIAlertController.Style {
        switch self {
        case .alert:
            return .alert
        case .drawer:
            return .actionSheet
        }
    }
}

public struct ModalSpec: CustomStringConvertible, Equatable {
    let connectionMode: ConnectionMode
    let kind: ModalKind
    let pageKey: String
    let text: String?
    let title: String
    let typ: String
    let widgets: [ModalButtonSpec]

    init(pageKey: String, _ kind: ModalKind, _ item: JsonItem) throws {
        self.connectionMode = ConnectionMode(item.stream, item.pollSeconds)
        self.kind = kind
        self.pageKey = pageKey
        self.text = item.text
        self.title = try item.requireTitle()
        self.typ = kind.typ()
        var widgets: [ModalButtonSpec] = []
        guard let items = item.widgets else {
            throw ApplinError.appError("\(self.typ).widgets is empty")
        }
        for item in items {
            if item.typ == ModalButtonSpec.TYP {
                widgets.append(try ModalButtonSpec(item))
            } else {
                throw ApplinError.appError(
                        "\(self.typ).widgets contains entry that is not \(ModalButtonSpec.TYP): \(item.typ)")
            }
        }
        self.widgets = widgets
    }

    func toJsonItem() -> JsonItem {
        let item = JsonItem(self.kind.typ())
        item.pollSeconds = self.connectionMode.getPollSeconds()
        item.stream = self.connectionMode.getStream()
        item.text = self.text
        item.title = self.title
        item.widgets = self.widgets.map({ widgets in widgets.toJsonItem() })
        return item
    }

    public init(pageKey: String, kind: ModalKind, title: String, text: String? = nil, _ widgets: [ModalButtonSpec]) {
        self.connectionMode = .disconnect
        self.kind = kind
        self.pageKey = pageKey
        self.typ = kind.typ()
        self.title = title
        self.text = text
        self.widgets = widgets
    }

    func toSpec() -> PageSpec {
        .modal(self)
    }

    func toAlert(_ ctx: PageContext) -> AlertController {
        let interactiveErrorDetails: String = ctx.varSet?.getInteractiveError()?.message()
                ?? "Error details not found."
        let text = self.text?.replacingOccurrences(of: "${INTERACTIVE_ERROR_DETAILS}", with: interactiveErrorDetails)
        let alert = AlertController(title: self.title, message: text, preferredStyle: self.kind.style())
        for widget in self.widgets {
            alert.addAction(widget.toAlertAction(ctx, pageKey: self.pageKey))
        }
        return alert
    }

    func visitActions(_ f: (ActionSpec) -> ()) {
        for button in self.widgets {
            for action in button.actions {
                f(action)
            }
        }
    }

    func vars() -> [(String, Var)] {
        []
    }

    public var description: String {
        "ModalSpec{\(self.kind) title=\(self.title)}"
    }
}

class AlertController: UIAlertController {
    var animated = false

    func allowBackSwipe() -> Bool {
        false
    }

    func setAnimated(_ animated: Bool) {
        self.animated = animated
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !self.animated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.setAnimationsEnabled(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !self.animated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIView.setAnimationsEnabled(true)
        //self.delegate?.modalDismissed()
    }

    // TODONT: Don't add a constructor.
    //         Our constructor cannot call the "convenience" constructor which is
    //         the only known way to properly initialize the class.
    // let preferredStyleOverride: UIAlertController.Style
    // // https://stackoverflow.com/a/45895513
    // override var preferredStyle: UIAlertController.Style {
    //     return self.preferredStyleOverride
    // }
    // init(title: String?, message: String?, preferredStyle: UIAlertController.Style) {
    //     self.preferredStyleOverride = preferredStyle
    //     // After calling this constructor, the class will throw
    //     // "Unable to simultaneously satisfy constraints" errors and display
    //     // the dialog with maximum height.  Strangely, displaying a second
    //     // dialog causes the one underneath to display properly.
    //     super.init(nibName: nil, bundle: nil)
    //     self.title = title
    //     self.message = message
    // }

    // TODONT: Don't try to intercept `dismiss` calls because it doesn't work.
    //         UIViewController does not call this when a button is tapped.
    // override func dismiss(animated flag: Bool, completion: (() -> ())?) {
    //     print("dismiss")
    //     super.dismiss(animated: flag, completion: completion)
    // }
}

// TODONT: Don't make each page controller present the modals above it.
// You will hit two errors:
// 1. "setViewControllers:animated: called on <NavigationController> while
//    an existing transition or presentation is occurring; the navigation
//    stack will not be updated."
//    This means that the UINavigationController refuses to update the stack
//    whenever a modal is displayed by any page in the stack.
// 2. "Attempt to present <AlertController> on <ModalPageController>
//    whose view is not in the window hierarchy."
//    This happens when you call present() on a window that is not visible.
//    This means that displaying multiple modals requires a long slow dance of
//    display, wait for the modal to show, then display.
//    Coding this to work reliably is very challenging.  I gave up.
//
// class ModalPageController: UIViewController, PageController {
//    var spec: ModalSpec?
//    var toPresent: AlertController?
//    var presented: AlertController?
//    var visible = false
//
//    func allowBackSwipe() -> Bool {
//        false
//    }
//
//    func update(_ session: ApplinSession, _ spec: ModalSpec, isTop: Bool) {
//        print("modal update isTop=\(isTop) \(spec)")
//        self.view.backgroundColor = .systemBackground // pastelPeach.withAlphaComponent(0.5)
//        if isTop {
//            if (self.presented == nil) || !(self.presented?.isBeingPresented ?? false) {
//                let alert = AlertController(title: spec.title, message: spec.text, preferredStyle: spec.kind.style())
//                for widget in spec.widgets {
//                    alert.addAction(widget.toAlertAction(session))
//                }
//                if self.visible {
//                    print("modal present animated=false")
//                    self.present(alert, animated: false)
//                    self.presented = alert
//                } else {
//                    print("modal postpone present")
//                    self.toPresent = alert
//                }
//            } else {
//                print("postponing update to top modal")
//            }
//        } else {
//            print("modal dismiss")
//            self.spec = spec
//            self.title = spec.title
//            self.toPresent = nil
//            self.presented?.dismiss(animated: false, completion: {})
//            self.presented = nil
//        }
//    }
//
//    override func viewDidAppear(_ animated: Bool) {
//        self.visible = true
//        if let alert = self.toPresent {
//            print("modal present animated=true")
//            self.toPresent = nil
//            alert.setAnimated(true)
//            self.present(alert, animated: true) {
//                alert.setAnimated(false)
//            }
//            self.presented = alert
//        }
//        super.viewDidAppear(animated)
//    }
//
//    override func viewWillDisappear(_ animated: Bool) {
//        self.visible = false
//        super.viewWillDisappear(animated)
//    }
// }

// TODONT: Don't try to add the UIAlertController as a child view controller.
//         It will display properly, but will not call button handlers.
// class ModalPageController: UIViewController, PageController {
//    var spec: ModalSpec?
//    var alert: AlertController?
//    let helper = SuperviewHelper()
//
//    func allowBackSwipe() -> Bool { false }
//
//    func update(_ session: ApplinSession, _ spec: ModalSpec, hasNextPage: Bool) {
//        if spec == self.spec {
//            return
//        }
//        if self.alert != nil && !hasNextPage {
//            print("postponing update to modal")
//            return
//        }
//        self.spec = spec
//        self.title = spec.title
//        self.helper.removeSubviewsAndConstraints(self.view)
//
//        // self.view.backgroundColor = pastelPeach.withAlphaComponent(0.5)
//        self.alert = nil
//        self.alert = AlertController(title: spec.title, message: spec.text, preferredStyle: spec.kind.style())
//        for widget in spec.widgets {
//            self.alert!.addAction(widget.toAlertAction(session))
//        }
//        // This doesn't make a difference.
//        //self.addChild(self.alert!)
//        self.view.addSubview(self.alert!.view)
//
//        self.helper.setConstraints([
//            self.alert!.view.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
//            self.alert!.view.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
//        ])
//    }
// }
