//
//  Forms.swift
//  FormsSample
//
//  Created by Chris Eidhof on 26.03.18.
//  Copyright © 2018 objc.io. All rights reserved.
//

import UIKit

class Section {
    let cells: [FormCell]
    var footerTitle: String?
    init(cells: [FormCell], footerTitle: String? = nil) {
        self.cells = cells
        self.footerTitle = footerTitle
    }
}

class FormCell: UITableViewCell {
    var shouldHighlight = false
    var didSelect: (() -> ())?
}

class FormViewController: UITableViewController {
    var sections: [Section] = []
    @objc var firstResponder: UIResponder?
    
    func reloadSectionFooters() {
        UIView.setAnimationsEnabled(false)
        tableView.beginUpdates()
        for index in sections.indices {
            let footer = tableView.footerView(forSection: index)
            footer?.textLabel?.text = tableView(tableView, titleForFooterInSection: index)
            footer?.setNeedsLayout()
            
        }
        tableView.endUpdates()
        UIView.setAnimationsEnabled(true)
    }
    
    func reloadSections() {
        tableView.reloadData()
    }
    
    init(sections: [Section], title: String, firstResponder: UIResponder? = nil) {
        self.firstResponder = firstResponder
        self.sections = sections
        super.init(style: .grouped)
        self.title = title
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        firstResponder?.becomeFirstResponder()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].cells.count
    }
    
    func cell(for indexPath: IndexPath) -> FormCell {
        return sections[indexPath.section].cells[indexPath.row]
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return cell(for: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return cell(for: indexPath).shouldHighlight
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footerTitle
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        cell(for: indexPath).didSelect?()
    }
    
}

class FormDriver<State> {
    var formViewController: FormViewController!
    var rendered: RenderedElement<[Section], State>!
    var context: RenderingContext<State>!
    
    let build: (RenderingContext<State>) -> RenderedElement<[Section], State>
    
    var state: State {
        didSet {
            context._replace(state)
            rendered = build(context)
            rendered.update(state)
            
            formViewController.sections = rendered.element
            formViewController.reloadSections()
            formViewController.reloadSectionFooters()
        }
    }
    
    init(initial state: State, title: String, build: @escaping (RenderingContext<State>) -> RenderedElement<[Section], State>) {
        self.state = state
        self.build = build
        
        self.context = RenderingContext(state: state, change: { [unowned self] f in
            f(&self.state)
            }, pushViewController: { [unowned self] vc in
                self.formViewController.navigationController?.pushViewController(vc, animated: true)
            }, popViewController: {
                self.formViewController.navigationController?.popViewController(animated: true)
        })
        self.rendered = build(self.context)
        rendered.update(state)
        
        formViewController = FormViewController(sections: rendered.element, title: title)
    }
}

final class TargetAction {
    let execute: () -> ()
    init(_ execute: @escaping () -> ()) {
        self.execute = execute
    }
    @objc func action(_ sender: Any) {
        execute()
    }
}

struct RenderedElement<Element, State> {
    var element: Element
    var strongReferences: [Any]
    var update: (State) -> ()
}

struct RenderingContext<State> {
    private(set) var state: State
    
    // HACK/XXX: An ugly mechanism for replacing the contents of the current
    // state in its entirety. This is required in order to get rebuilding the
    // forms to work.
    fileprivate mutating func _replace(_ state: State) {
        self.state = state
    }
    
    let change: ((inout State) -> ()) -> ()
    let pushViewController: (UIViewController) -> ()
    let popViewController: () -> ()
}

func uiSwitch<State>(context: RenderingContext<State>, keyPath: WritableKeyPath<State, Bool>) -> RenderedElement<UIView, State> {
    let toggle = UISwitch()
    toggle.translatesAutoresizingMaskIntoConstraints = false
    let toggleTarget = TargetAction {
        context.change { $0[keyPath: keyPath] = toggle.isOn }
    }
    toggle.addTarget(toggleTarget, action: #selector(TargetAction.action(_:)), for: .valueChanged)
    return RenderedElement(element: toggle, strongReferences: [toggleTarget], update: { state in
        toggle.isOn = state[keyPath: keyPath]
    })
}

func textField<State>(context: RenderingContext<State>, keyPath: WritableKeyPath<State, String>) -> RenderedElement<UIView, State> {
    let textField = UITextField()
    textField.translatesAutoresizingMaskIntoConstraints = false
    let didEnd = TargetAction {
        context.change { $0[keyPath: keyPath] = textField.text ?? "" }
    }
    let didExit = TargetAction {
        context.change { $0[keyPath: keyPath] = textField.text ?? "" }
        context.popViewController()
    }
    
    textField.addTarget(didEnd, action: #selector(TargetAction.action(_:)), for: .editingDidEnd)
    textField.addTarget(didExit, action: #selector(TargetAction.action(_:)), for: .editingDidEndOnExit)
    return RenderedElement(element: textField, strongReferences: [didEnd, didExit], update: { state in
        textField.text = state[keyPath: keyPath]
    })
}
