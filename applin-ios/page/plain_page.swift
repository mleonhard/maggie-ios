import Foundation
import UIKit

struct PlainPageSpec: Equatable {
    static let TYP = "plain-page"
    let connectionMode: ConnectionMode
    let title: String?
    let widget: Spec

    init(_ config: ApplinConfig, pageKey: String, _ item: JsonItem) throws {
        self.connectionMode = ConnectionMode(item.stream, item.pollSeconds)
        self.title = item.title
        self.widget = try item.requireWidget(config)
    }

    func toJsonItem() -> JsonItem {
        let item = JsonItem(PlainPageSpec.TYP)
        item.pollSeconds = self.connectionMode.getPollSeconds()
        item.stream = self.connectionMode.getStream()
        item.title = self.title
        item.widget = self.widget.toJsonItem()
        return item
    }

    init(title: String?, connectionMode: ConnectionMode = .disconnect, _ widget: ToSpec) {
        self.connectionMode = connectionMode
        self.title = title
        self.widget = widget.toSpec()
    }

    func toSpec() -> PageSpec {
        .plainPage(self)
    }

    func vars() -> [(String, Var)] {
        self.widget.vars()
    }

    func visitActions(_ f: (ActionSpec) -> ()) {
        self.widget.visitActions(f)
    }
}

class PlainPageController: UIViewController, PageController {
    var spec: PlainPageSpec?
    var helper: SingleViewContainerHelper!

    init() {
        print("NavPageController.init")
        super.init(nibName: nil, bundle: nil)
        self.helper = SingleViewContainerHelper(superView: self.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not implemented")
    }

    // Implement PageController -----------------

    func allowBackSwipe() -> Bool {
        true
    }

    func klass() -> AnyClass {
        PlainPageController.self
    }

    func update(_ ctx: PageContext, _ newPageSpec: PageSpec) {
        guard let cache = ctx.cache else {
            return
        }
        guard case let .plainPage(plainPageSpec) = newPageSpec else {
            print("FATAL: PlainPageController.update() called with newPageSpec=\(newPageSpec)")
            abort()
        }
        self.title = plainPageSpec.title
        self.view.backgroundColor = .systemBackground
        let widget = cache.updateAll(ctx, plainPageSpec.widget)
        let subView = widget.getView()
        subView.translatesAutoresizingMaskIntoConstraints = false
        self.helper.update(subView) {
            [
                subView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                subView.bottomAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.bottomAnchor),
                subView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
                subView.trailingAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            ]
        }
    }

    override var description: String {
        "PlainPageController{title=\(self.title ?? "")}"
    }
}
