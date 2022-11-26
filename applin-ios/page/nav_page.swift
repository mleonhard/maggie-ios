import Foundation
import UIKit

enum StartEnum: Equatable {
    case backButton(BackButtonSpec)
    case defaultBackButton
    case empty
}

struct NavPageSpec: Equatable {
    static let TYP = "nav-page"
    let connectionMode: ConnectionMode
    let end: Spec?
    let start: StartEnum
    let title: String
    let widget: Spec

    init(
            pageKey: String,
            title: String,
            widget: Spec,
            start: StartEnum = .defaultBackButton,
            end: Spec? = nil
    ) {
        self.connectionMode = .disconnect
        self.end = end
        self.start = start
        self.title = title
        self.widget = widget
    }

    init(_ session: ApplinSession?, pageKey: String, _ item: JsonItem) throws {
        self.connectionMode = ConnectionMode(item.stream, item.pollSeconds)
        self.end = try item.optEnd(session, pageKey: pageKey)
        switch try item.optStart(session, pageKey: pageKey)?.value {
        case let .backButton(inner):
            self.start = .backButton(inner)
        case .none:
            self.start = .defaultBackButton
        case .empty:
            self.start = .empty
        case let .some(other):
            throw ApplinError.deserializeError("bad \(item.typ).start: \(other)")
        }
        self.title = try item.requireTitle()
        self.widget = try item.requireWidget(session, pageKey: pageKey)
    }

    func controllerClass() -> AnyClass {
        NavPageController.self
    }

    func newController(_ navController: NavigationController?, _ session: ApplinSession?, _ cache: WidgetCache) -> PageController {
        NavPageController(navController, session, cache)
    }

    func toJsonItem() -> JsonItem {
        let item = JsonItem(NavPageSpec.TYP)
        item.end = self.end?.toJsonItem()
        item.pollSeconds = self.connectionMode.getPollSeconds()
        item.stream = self.connectionMode.getStream()
        item.title = self.title
        switch self.start {
        case let .backButton(inner):
            item.start = inner.toJsonItem()
        case .defaultBackButton:
            break
        case .empty:
            item.start = EmptySpec().toJsonItem()
        }
        item.widget = self.widget.toJsonItem()
        return item
    }

    func vars() -> [(String, Var)] {
        self.widget.vars()
    }
}

class NavPageController: UIViewController, UINavigationBarDelegate, PageController {
    weak var navController: NavigationController?
    weak var weakSession: ApplinSession?
    weak var weakCache: WidgetCache?
    var helper: SingleViewContainerHelper!
    var spec: NavPageSpec?
    var hasPrevPage: Bool = false
    var navBar: UINavigationBar
    var optOriginalBackButton: UIBarButtonItem?
    var subView: UIView?

    init(_ navController: NavigationController?, _ session: ApplinSession?, _ cache: WidgetCache?) {
        self.navController = navController
        self.weakSession = session
        self.weakCache = cache
        // PlainPageController cannot do self.navigationItem.navBarHidden = true,
        // because Apple didn't add support for that.
        // Instead, we must show/hide UINavigationController's navbar whenever the top
        // page changes between NavPage and PlainPage.
        // This works, but whenever we pop a NavPage with a PlainPage underneath,
        // the PlainPage shows a navbar for a second while the animation is running, then it disappears.
        // This is looks bad.  So we hide the UINavigationController's navbar
        // and give each NavPage its own navbar.
        self.navBar = UINavigationBar()
        self.navBar.translatesAutoresizingMaskIntoConstraints = false
        super.init(nibName: nil, bundle: nil)
        self.navBar.delegate = self
        self.view.backgroundColor = .systemBackground
        self.view.addSubview(self.navBar)
        self.helper = SingleViewContainerHelper(superView: self.view)
    }

    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    func back() {
        print("back")
        if self.navController?.topPageController() !== self {
            return
        }
        guard let spec = self.spec else {
            return
        }
        switch spec.start {
        case let .backButton(inner):
            if let session = self.weakSession, let cache = self.weakCache {
                print("back inner.tap()")
                inner.tap(session, cache)
            }
        case .defaultBackButton:
            self.weakSession?.pop()
        case .empty:
            break
        }
    }

    // Implement UINavigationBarDelegate --------------

    /// Called when the user taps the Back button.
    func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        print("navigationBar shouldPop=\(item)")
        self.back()
        return false  // UINavigationBar should not remove NavigationItem objects.
    }

    /// Called when the user taps the Back button,
    /// or long-presses the Back button and taps Back from the popup menu.
    func navigationBar(_ navigationBar: UINavigationBar, didPop item: UINavigationItem) {
        print("navigationBar didPop=\(item)")
        self.back()
    }

    /// Called when the view gets covered by another view (isMovingFromParent=false) or
    /// when the view is removed from the view (isMovingFromParent=true).
    override func viewDidDisappear(_ animated: Bool) {
        // NOTE: UIKit on iOS 15 does not set self.isBeingDismissed=true like the docs claim.
        print("NavPageController '\(self.title ?? "")' viewDidDisappear isMovingFromParent=\(self.isMovingFromParent)")
        if self.isMovingFromParent {
            self.back()
        }
        super.viewDidDisappear(animated)
    }

    // Implement PageController -----------------

    func allowBackSwipe() -> Bool {
        switch self.spec?.start {
        case .none:
            return false
        case .backButton:
            return false
        case .defaultBackButton:
            return true
        case .empty:
            return false
        }
    }

    func klass() -> AnyClass {
        NavPageController.self
    }

    func update(
            _ session: ApplinSession,
            _ cache: WidgetCache,
            _ newPageSpec: PageSpec,
            hasPrevPage: Bool
    ) {
        guard case let .navPage(navPageSpec) = newPageSpec else {
            print("FATAL: NavPageController.update called with newPageSpec=\(newPageSpec)")
            abort() // This should never happen.
        }
        if self.spec == navPageSpec {
            return
        }
        self.spec = navPageSpec
        self.hasPrevPage = hasPrevPage
        self.title = navPageSpec.title

        if let originalBackButton = self.optOriginalBackButton {
            self.navBar.backItem?.backBarButtonItem = originalBackButton
            self.optOriginalBackButton = nil
        }
        self.navigationItem.hidesBackButton = false
        switch navPageSpec.start {
        case let .backButton(inner):
            if inner.actions.isEmpty {
                self.navBar.items = [UINavigationItem(title: "Back"), self.navigationItem]
                let backButton = UIBarButtonItem(title: "Back")
                backButton.isEnabled = false
                self.optOriginalBackButton = self.navBar.backItem?.backBarButtonItem
                self.navBar.backItem?.backBarButtonItem = backButton
            } else {
                self.navBar.items = [UINavigationItem(title: "Back"), self.navigationItem]
            }
        case .defaultBackButton:
            if hasPrevPage {
                self.navBar.items = [UINavigationItem(title: "Back"), self.navigationItem]
            } else {
                self.navBar.items = [self.navigationItem]
            }
        case .empty:
            self.navigationItem.hidesBackButton = true
            self.navBar.items = [self.navigationItem]
        }
        let widget = cache.updateAll(session, navPageSpec.widget)
        let subView = widget.getView()
        self.helper.update(subView) {
            // subView.setNeedsDisplay()
            [
                self.navBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                self.navBar.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
                self.navBar.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
                subView.topAnchor.constraint(equalTo: self.navBar.safeAreaLayoutGuide.bottomAnchor),
                subView.bottomAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.bottomAnchor),
                subView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
                subView.trailingAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            ]
        }
    }
}
