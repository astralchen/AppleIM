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

    /// 页面标题标签
    private let titleLabel = UILabel()
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
    /// 渐变背景
    private let backgroundView = GradientBackgroundView()
    /// 登录表单玻璃卡片
    private let cardView = GlassContainerView()
    /// 卡片垂直居中约束，用于键盘抬升
    private var cardCenterYConstraint: NSLayoutConstraint?
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

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "ChatBridge"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.textColor = ChatBridgeDesignSystem.ColorToken.ink

        accountTextField.translatesAutoresizingMaskIntoConstraints = false
        configureAuthTextField(accountTextField)
        accountTextField.placeholder = "Account or phone"
        accountTextField.textContentType = .username
        accountTextField.autocapitalizationType = .none
        accountTextField.autocorrectionType = .no
        accountTextField.returnKeyType = .next
        accountTextField.accessibilityIdentifier = "login.accountTextField"
        accountTextField.addTarget(self, action: #selector(accountDidChange), for: .editingChanged)

        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        configureAuthTextField(passwordTextField)
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
        var loginConfiguration = ChatBridgeDesignSystem.makeGlassButtonConfiguration(role: .primary)
        loginConfiguration.title = "Log In"
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

        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)
        cardView.contentView.addSubview(stackView)

        let centerYConstraint = cardView.centerYAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.centerYAnchor,
            constant: -24
        )
        centerYConstraint.priority = .defaultHigh
        cardCenterYConstraint = centerYConstraint

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            centerYConstraint,
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cardView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: cardView.contentView.topAnchor, constant: 28),
            stackView.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 22),
            stackView.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -22),
            stackView.bottomAnchor.constraint(equalTo: cardView.contentView.bottomAnchor, constant: -24),
            accountTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            passwordTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    /// 配置账号和密码输入框的统一样式
    private func configureAuthTextField(_ textField: UITextField) {
        textField.borderStyle = .none
        textField.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        textField.layer.cornerRadius = ChatBridgeDesignSystem.RadiusToken.field
        textField.layer.masksToBounds = true
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true

        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
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

    /// 键盘 frame 变化时计算登录卡片需要抬升的距离
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
        let overlap = max(0, cardView.frame.maxY - desiredBottom)
        let desiredLift = overlap > 0 ? overlap + 52 : 0

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
        cardCenterYConstraint?.constant = -24 - lift

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
