import Foundation
import UIKit

struct CheckboxData: Equatable, Hashable {
    static let TYP = "checkbox"
    let id: String
    let initialBool: Bool
    let actions: [MaggieAction]

    init(_ item: JsonItem, _ session: MaggieSession) throws {
        self.actions = try item.optActions() ?? []
        self.id = try item.requireId()
        self.initialBool = item.initialBool ?? false
    }

    func toJsonItem() -> JsonItem {
        let item = JsonItem(CheckboxData.TYP)
        item.actions = self.actions.map({ action in action.toString() })
        item.id = self.id
        item.initialBool = self.initialBool
        return item
    }

    func keys() -> [String] {
        ["checkbox:\(self.id)"]
    }

    func getView(_ session: MaggieSession, _ widgetCache: WidgetCache) -> UIView {
        var widget: CheckboxWidget
        switch widgetCache.remove(self.keys()) {
        case let checkboxWidget as CheckboxWidget:
            widget = checkboxWidget
            widget.data = self
        default:
            widget = CheckboxWidget(self)
        }
        widgetCache.putNext(widget)
        return widget.getView(session, widgetCache)
    }
}

class CheckboxWidget: Widget {
    var data: CheckboxData
    let view: UISwitch
    weak var session: MaggieSession?

    init(_ data: CheckboxData) {
        print("CheckboxWidget.init(\(data))")
        self.data = data
        self.view = UISwitch()
        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.preferredStyle = .checkbox
        self.view.addAction(for: .valueChanged, handler: { [weak self] _ in
            print("checkbox .valueChanged")
            self?.valueChanged()
        })
        self.view.setOn(self.data.initialBool, animated: false)
    }

    func keys() -> [String] {
        self.data.keys()
    }

    func valueChanged() {
        print("checkbox actions")
        self.session?.doActions(self.data.actions)
    }

    func getView(_ session: MaggieSession, _ widgetCache: WidgetCache) -> UIView {
        self.session = session
        return self.view
    }
}
