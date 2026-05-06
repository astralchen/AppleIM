//
//  LoginViewController.swift
//  AppleIM
//
//  账号密码登录页
//

import Combine
import UIKit

@MainActor
final class LoginViewController: UIViewController {
    private let viewModel: LoginViewModel
    private let onLoginSucceeded: (AccountSession) -> Void
    private var cancellables = Set<AnyCancellable>()

    private let titleLabel = UILabel()
    private let accountTextField = UITextField()
    private let passwordTextField = UITextField()
    private let errorLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(viewModel: LoginViewModel, onLoginSucceeded: @escaping (AccountSession) -> Void) {
        self.viewModel = viewModel
        self.onLoginSucceeded = onLoginSucceeded
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        bindViewModel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
    }

    private func configureView() {
        title = "Login"
        view.backgroundColor = .systemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "ChatBridge"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center

        accountTextField.translatesAutoresizingMaskIntoConstraints = false
        accountTextField.borderStyle = .roundedRect
        accountTextField.placeholder = "Account or phone"
        accountTextField.textContentType = .username
        accountTextField.autocapitalizationType = .none
        accountTextField.autocorrectionType = .no
        accountTextField.returnKeyType = .next
        accountTextField.accessibilityIdentifier = "login.accountTextField"
        accountTextField.addTarget(self, action: #selector(accountDidChange), for: .editingChanged)

        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        passwordTextField.borderStyle = .roundedRect
        passwordTextField.placeholder = "Password"
        passwordTextField.textContentType = .password
        passwordTextField.isSecureTextEntry = true
        passwordTextField.returnKeyType = .go
        passwordTextField.accessibilityIdentifier = "login.passwordTextField"
        passwordTextField.addTarget(self, action: #selector(passwordDidChange), for: .editingChanged)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .systemRed
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
        errorLabel.accessibilityIdentifier = "login.errorLabel"

        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.setTitle("Log In", for: .normal)
        loginButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        loginButton.accessibilityIdentifier = "login.submitButton"
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.accessibilityIdentifier = "login.activityIndicator"

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            accountTextField,
            passwordTextField,
            errorLabel,
            loginButton,
            activityIndicator
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.setCustomSpacing(28, after: titleLabel)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -40),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            accountTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            passwordTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func bindViewModel() {
        viewModel.statePublisher
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)

        viewModel.sessionPublisher
            .sink { [weak self] session in
                self?.onLoginSucceeded(session)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: LoginViewState) {
        if accountTextField.text != state.accountIdentifier {
            accountTextField.text = state.accountIdentifier
        }

        if passwordTextField.text != state.password {
            passwordTextField.text = state.password
        }

        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        loginButton.isEnabled = state.canSubmit

        if state.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    @objc private func accountDidChange() {
        viewModel.updateAccountIdentifier(accountTextField.text ?? "")
    }

    @objc private func passwordDidChange() {
        viewModel.updatePassword(passwordTextField.text ?? "")
    }

    @objc private func loginButtonTapped() {
        view.endEditing(true)
        viewModel.login()
    }
}
