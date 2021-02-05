//
//  SelfTestingCoronaSuspicionViewController.swift
//  CoronaContact
//

import Reusable
import UIKit
import Resolver

final class SelfTestingCoronaSuspicionViewController: UIViewController, StoryboardBased, ViewModelBased, FlashableScrollIndicators {
    @Injected private var localStorage: LocalStorage

    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet weak var textfield: UITextField!
    
    let datePicker = DatePickerView()

    var viewModel: SelfTestingCoronaSuspicionViewModel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        flashScrollIndicators()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        title = "self_testing_corona_suspicion_title".localized
        showDatePicker()
    }
    
    @IBAction func contactsConfirmedButtonPressed(_ sender: Any) {
        viewModel?.showRevocation()
    }
    
    @IBAction func contactsNotConfirmedButtonPressed(_ sender: Any) {
        viewModel?.showStatusReport()
    }
    
    func showDatePicker() {
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(title: "accessibility_keyboard_confirm_title".localized, style: .plain, target: self, action: #selector(confirmButtonTapped))
        
        toolbar.setItems([doneButton], animated: false)
        
        textfield.inputAccessoryView = toolbar
        textfield.inputView = datePicker
        confirmButtonTapped()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(notification:)), name: UIResponder.keyboardDidShowNotification, object: nil)
    }
    
    @objc func keyboardDidShow(notification: NSNotification) {
        UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: datePicker)
    }
    
    @objc func confirmButtonTapped() {
        let date = datePicker.getSelectedDate ?? Date()
        
        localStorage.hasSymptomsOrPositiveAttestAt = date
        textfield.text = Calendar.current.isDateInToday(date) ? "general_today".localized : date.shortMonthNameString
        
        self.view.endEditing(true)
    }
}