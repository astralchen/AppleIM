//
//  LoginViewController.swift
//  AppleIM
//
//  账号密码登录页
//

import Combine
import UIKit

/// 账号密码登录页控制器
@MainActor
final class LoginViewController: UIViewController {
    /// 登录页 ViewModel
    private let viewModel: LoginViewModel
    /// 登录成功回调
    private let onLoginSucceeded: (AccountSession) -> Void
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 应用图标
    private let iconImageView = UIImageView()
    /// 页面标题标签
    private let titleLabel = UILabel()
    /// 页面副标题标签
    private let subtitleLabel = UILabel()
    /// 登录表单容器
    private let formContainerView = UIView()
    /// 输入框分割线
    private let fieldSeparatorView = UIView()
    /// 账号输入框
    private let accountTextField = UITextField()
    /// 密码输入框
    private let passwordTextField = UITextField()
    /// 错误提示标签
    private let errorLabel = UILabel()
    /// 登录按钮
    private let loginButton = UIButton(type: .system)
    /// 登录加载指示器
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    /// 登录内容容器
    private let contentContainerView = UIView()
    /// 登录内容垂直居中约束，用于键盘抬升
    private var contentCenterYConstraint: NSLayoutConstraint?
    /// 当前键盘抬升距离
    private var currentKeyboardLift: CGFloat = 0
    /// 键盘是否处于可见状态
    private var isKeyboardVisible = false

    /// 初始化登录页
    init(viewModel: LoginViewModel, onLoginSucceeded: @escaping (AccountSession) -> Void) {
        self.viewModel = viewModel
        self.onLoginSucceeded = onLoginSucceeded
        super.init(nibName: nil, bundle: nil)
    }

    /// 禁用 storyboard 初始化
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is not supported.")
    }

    /// 移除键盘通知观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 配置视图并绑定 ViewModel
    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        observeKeyboard()
        bindViewModel()
    }

    /// 页面消失时取消进行中的登录任务
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
    }

    /// 创建登录页视图层级和约束
    private func configureView() {
        title = "Login"
        view.backgroundColor = .systemBackground

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.image = UIImage(systemName: "message.fill")
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        iconImageView.tintColor = .systemBlue
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "AppleIM"
        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Sign in to continue to Messages."
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        formContainerView.translatesAutoresizingMaskIntoConstraints = false
        formContainerView.backgroundColor = ChatBridgeDesignSystem.ColorToken.appleLoginFieldBackground
        formContainerView.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.appleLoginField
        formContainerView.layer.borderColor = UIColor.separator.withAlphaComponent(0.28).cgColor
        formContainerView.layer.borderWidth = 0.5
        formContainerView.layer.masksToBounds = true

        fieldSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        fieldSeparatorView.backgroundColor = .separator

        accountTextField.translatesAutoresizingMaskIntoConstraints = false
        configureAuthTextField(accountTextField)
        accountTextField.placeholder = "Apple ID or account"
        accountTextField.textContentType = AppUITestConfiguration.current == nil ? .username : .oneTimeCode
        accountTextField.autocapitalizationType = .none
        accountTextField.autocorrectionType = .no
        accountTextField.returnKeyType = .next
        accountTextField.accessibilityIdentifier = "login.accountTextField"
        accountTextField.addTarget(self, action: #selector(accountDidChange), for: .editingChanged)

        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        configureAuthTextField(passwordTextField)
        passwordTextField.placeholder = "Password"
        passwordTextField.textContentType = AppUITestConfiguration.current == nil ? .password : .oneTimeCode
        passwordTextField.isSecureTextEntry = true
        passwordTextField.returnKeyType = .go
        passwordTextField.accessibilityIdentifier = "login.passwordTextField"
        passwordTextField.addTarget(self, action: #selector(passwordDidChange), for: .editingChanged)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .systemRed
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .natural
        errorLabel.isHidden = true
        errorLabel.accessibilityIdentifier = "login.errorLabel"

        loginButton.translatesAutoresizingMaskIntoConstraints = false
        var loginConfiguration = UIButton.Configuration.filled()
        loginConfiguration.title = "Log In"
        loginConfiguration.baseBackgroundColor = .systemBlue
        loginConfiguration.baseForegroundColor = .white
        loginConfiguration.cornerStyle = .capsule
        loginConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        loginConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        loginButton.configuration = loginConfiguration
        loginButton.accessibilityIdentifier = "login.submitButton"
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.accessibilityIdentifier = "login.activityIndicator"

        formContainerView.addSubview(accountTextField)
        formContainerView.addSubview(fieldSeparatorView)
        formContainerView.addSubview(passwordTextField)

        let headerStackView = UIStackView(arrangedSubviews: [
            iconImageView,
            titleLabel,
            subtitleLabel
        ])
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.axis = .vertical
        headerStackView.spacing = 10
        headerStackView.alignment = .center
        headerStackView.setCustomSpacing(14, after: iconImageView)

        let stackView = UIStackView(arrangedSubviews: [
            headerStackView,
            formContainerView,
            errorLabel,
            loginButton,
            activityIndicator
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.alignment = .fill
        stackView.setCustomSpacing(30, after: headerStackView)
        stackView.setCustomSpacing(18, after: formContainerView)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainerView)
        contentContainerView.addSubview(stackView)

        let centerYConstraint = contentContainerView.centerYAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.centerYAnchor,
            constant: -24
        )
        centerYConstraint.priority = .defaultHigh
        contentCenterYConstraint = centerYConstraint
        let contentTopConstraint = contentContainerView.topAnchor.constraint(
            greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
            constant: 24
        )
        contentTopConstraint.priority = .defaultLow
        let contentWidthConstraint = contentContainerView.widthAnchor.constraint(equalTo: view.layoutMarginsGuide.widthAnchor)
        contentWidthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            centerYConstraint,
            contentTopConstraint,
            contentContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            contentContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            contentWidthConstraint,
            contentContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            stackView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),

            iconImageView.widthAnchor.constraint(equalToConstant: 72),
            iconImageView.heightAnchor.constraint(equalToConstant: 72),

            accountTextField.topAnchor.constraint(equalTo: formContainerView.topAnchor),
            accountTextField.leadingAnchor.constraint(equalTo: formContainerView.leadingAnchor),
            accountTextField.trailingAnchor.constraint(equalTo: formContainerView.trailingAnchor),
            accountTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            fieldSeparatorView.topAnchor.constraint(equalTo: accountTextField.bottomAnchor),
            fieldSeparatorView.leadingAnchor.constraint(equalTo: formContainerView.leadingAnchor, constant: 16),
            fieldSeparatorView.trailingAnchor.constraint(equalTo: formContainerView.trailingAnchor),
            fieldSeparatorView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            passwordTextField.topAnchor.constraint(equalTo: fieldSeparatorView.bottomAnchor),
            passwordTextField.leadingAnchor.constraint(equalTo: formContainerView.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: formContainerView.trailingAnchor),
            passwordTextField.bottomAnchor.constraint(equalTo: formContainerView.bottomAnchor),
            passwordTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: ChatBridgeDesignSystem.SpacingToken.appleLoginButtonHeight)
        ])
    }

    /// 配置账号和密码输入框的统一样式
    private func configureAuthTextField(_ textField: UITextField) {
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.tintColor = .systemBlue

        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        textField.leftView = spacer
        textField.leftViewMode = .always
    }

    /// 监听键盘位置变化
    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    /// 绑定登录状态和登录成功事件
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

    /// 根据最新登录状态刷新 UI
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

    /// 账号输入变化回写到 ViewModel
    @objc private func accountDidChange() {
        viewModel.updateAccountIdentifier(accountTextField.text ?? "")
    }

    /// 密码输入变化回写到 ViewModel
    @objc private func passwordDidChange() {
        viewModel.updatePassword(passwordTextField.text ?? "")
    }

    /// 点击登录按钮后提交登录
    @objc private func loginButtonTapped() {
        view.endEditing(true)
        viewModel.login()
    }

    /// 键盘 frame 变化时计算登录内容需要抬升的距离
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let endFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else {
            return
        }

        let keyboardFrame = view.convert(endFrameValue.cgRectValue, from: nil)
        let keyboardTop = keyboardFrame.minY
        guard keyboardTop < view.bounds.maxY else {
            applyKeyboardLift(0, notification: notification)
            return
        }

        view.layoutIfNeeded()
        let desiredBottom = keyboardTop - 16
        let overlap = max(0, contentContainerView.frame.maxY - desiredBottom)
        let desiredLift = overlap > 0 ? overlap + 32 : 0

        if !isKeyboardVisible || desiredLift > currentKeyboardLift + 48 {
            isKeyboardVisible = true
            applyKeyboardLift(desiredLift, notification: notification)
        }
    }

    /// 键盘隐藏时恢复卡片位置
    @objc private func keyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
        applyKeyboardLift(0, notification: notification)
    }

    /// 应用键盘抬升动画
    private func applyKeyboardLift(_ lift: CGFloat, notification: Notification) {
        currentKeyboardLift = lift
        contentCenterYConstraint?.constant = -24 - lift

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        let options = UIView.AnimationOptions(rawValue: rawCurve << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.view.layoutIfNeeded()
            }
        )
    }
}
