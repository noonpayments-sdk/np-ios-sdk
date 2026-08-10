import SwiftUI
import WebKit
import PassKit
import SharedLogic

public struct NPMobileSDKPaymentRequest {
    public let orderId: String
    public let authHeader: String
    public let url: String

    public init(orderId: String, authHeader: String, url: String) {
        self.orderId = orderId
        self.authHeader = authHeader
        self.url = url
    }
}

public struct NPMobileSDKStyleConfiguration {
    public let sheetTitle: String

    public init(sheetTitle: String = "NoonPayments SDK") {
        self.sheetTitle = sheetTitle
    }
}

public enum NPMobileSDKOrderStatus {
    case success
    case failed
    case cancelled
}

public struct NPMobileSDKPaymentResponse {
    public let orderId: String
    public let orderStatus: NPMobileSDKOrderStatus
    public let errorMessage: String?

    public init(orderId: String, orderStatus: NPMobileSDKOrderStatus, errorMessage: String? = nil) {
        self.orderId = orderId
        self.orderStatus = orderStatus
        self.errorMessage = errorMessage
    }
}

private enum PaymentSheetRoute: Hashable {
    case orderConfiguration
    case cardPayment
    case applePay
    case threeDS(postUrl: String)
    case orderStatus
    case cancel
}

private let demoSdkVersion = "1.0.0-demo"
private let threeDsCallbackUrlPrefix = "https://noonpayments.com/sdk/response"

public struct NPMobileSDKPaymentView: View {
    @Binding private var isPresented: Bool
    private let request: NPMobileSDKPaymentRequest
    private let style: NPMobileSDKStyleConfiguration
    private let onPaymentResult: (NPMobileSDKPaymentResponse) -> Void

    public init(
        isPresented: Binding<Bool>,
        request: NPMobileSDKPaymentRequest,
        style: NPMobileSDKStyleConfiguration = NPMobileSDKStyleConfiguration(),
        onPaymentResult: @escaping (NPMobileSDKPaymentResponse) -> Void = { _ in }
    ) {
        _isPresented = isPresented
        self.request = request
        self.style = style
        self.onPaymentResult = onPaymentResult
    }

    public var body: some View {
        EmptyView()
            .sheet(isPresented: $isPresented) {
                SheetRootView(
                    request: request,
                    style: style,
                    onPaymentResult: onPaymentResult,
                    onDismiss: { isPresented = false }
                )
            }
    }
}

private struct SheetRootView: View {
    let request: NPMobileSDKPaymentRequest
    let style: NPMobileSDKStyleConfiguration
    let onPaymentResult: (NPMobileSDKPaymentResponse) -> Void
    let onDismiss: () -> Void

    @State private var path: [PaymentSheetRoute] = []
    @State private var component: PaymentSheetDemoComponent
    @State private var orderIdFromThreeDs: String?

    init(
        request: NPMobileSDKPaymentRequest,
        style: NPMobileSDKStyleConfiguration,
        onPaymentResult: @escaping (NPMobileSDKPaymentResponse) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.style = style
        self.onPaymentResult = onPaymentResult
        self.onDismiss = onDismiss

        let apiConfig = PaymentApiConfig(
            baseUrl: request.url,
            orderId: request.orderId,
            authHeader: request.authHeader,
            sdkVersion: demoSdkVersion
        )
        _component = State(initialValue: PaymentSheetDemoComponentFactory.shared.create(apiConfig: apiConfig))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 12) {
                Text(style.sheetTitle)
                    .font(.headline)
                Text("API: \(request.url)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("SDK_ORDER_CONFIGURATION") {
                    path.append(.orderConfiguration)
                }
                .buttonStyle(.borderedProminent)

                Button("ADD_PAYMENT_INFO (Card)") {
                    path.append(.cardPayment)
                }
                .buttonStyle(.borderedProminent)

                Button("ADD_PAYMENT_INFO (ApplePay)") {
                    path.append(.applePay)
                }
                .buttonStyle(.borderedProminent)

                Button("GET /order/{orderId}") {
                    path.append(.orderStatus)
                }
                .buttonStyle(.borderedProminent)

                Button("CANCEL") {
                    path.append(.cancel)
                }
                .buttonStyle(.borderedProminent)

                Divider()

                Button("Close Sheet") {
                    onPaymentResult(
                        NPMobileSDKPaymentResponse(
                            orderId: request.orderId,
                            orderStatus: .cancelled
                        )
                    )
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .task {
                // Auto-load order configuration when sheet opens
                try? await component.orderConfigurationViewModel.load()
            }
            .navigationDestination(for: PaymentSheetRoute.self) { route in
                switch route {
                case .orderConfiguration:
                    OrderConfigurationScreen(viewModel: component.orderConfigurationViewModel)
                case .cardPayment:
                    CardPaymentScreen(
                        viewModel: component.cardPaymentViewModel,
                        onOpen3DS: { postUrl in
                            path.append(.threeDS(postUrl: postUrl))
                        }
                    )
                case .applePay:
                    ApplePayScreen(
                        viewModel: component.applePayViewModel,
                        orderConfigurationViewModel: component.orderConfigurationViewModel,
                        onOpen3DS: { postUrl in
                            path.append(.threeDS(postUrl: postUrl))
                        }
                    )
                case .threeDS(let postUrl):
                    ThreeDSScreen(
                        postUrl: postUrl,
                        onCallback: { callbackUrl in
                            orderIdFromThreeDs = extractOrderId(from: callbackUrl)
                            if !path.isEmpty {
                                _ = path.removeLast()
                            }
                            path.append(.orderStatus)
                        }
                    )
                case .orderStatus:
                    OrderStatusScreen(
                        viewModel: component.fetchOrderStatusViewModel,
                        defaultOrderId: orderIdFromThreeDs ?? request.orderId,
                        onEmitResult: { status, message in
                            onPaymentResult(
                                NPMobileSDKPaymentResponse(
                                    orderId: request.orderId,
                                    orderStatus: status,
                                    errorMessage: message
                                )
                            )
                        }
                    )
                case .cancel:
                    CancelScreen(
                        viewModel: component.cancelPaymentViewModel,
                        onFinishCancelled: {
                            onPaymentResult(
                                NPMobileSDKPaymentResponse(
                                    orderId: request.orderId,
                                    orderStatus: .cancelled
                                )
                            )
                            onDismiss()
                        }
                    )
                }
            }
        }
    }

    private func extractOrderId(from callbackUrl: String) -> String? {
        guard let components = URLComponents(string: callbackUrl) else { return nil }
        return components.queryItems?.first(where: { $0.name == "orderId" })?.value
    }
}

private struct OrderConfigurationScreen: View {
    @State private var viewModel: OrderConfigurationDemoViewModel
    @State private var state: OrderConfigurationDemoState

    init(viewModel: OrderConfigurationDemoViewModel) {
        _viewModel = State(initialValue: viewModel)
        _state = State(initialValue: viewModel.state.value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button(state.isLoading ? "Loading..." : "Fetch SDK_ORDER_CONFIGURATION") {
                    Task {
                        try? await viewModel.load()
                        state = viewModel.state.value
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isLoading)

                Text("resultCode: \(state.resultCode ?? "-")")
                Text("order: \(state.orderJson ?? "-")")
                Text("paymentOptions: \(state.paymentOptionsJson ?? "-")")

                if let error = state.errorMessage {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .navigationTitle("Order Config")
    }
}

private struct CardPaymentScreen: View {
    @State private var viewModel: CardPaymentDemoViewModel
    @State private var state: CardPaymentDemoState
    let onOpen3DS: (String) -> Void

    @State private var useSavedCard: Bool = true
    @State private var tokenIdentifier = ""
    @State private var cvv = ""
    @State private var cardNumber = ""
    @State private var expiryMonth = ""
    @State private var expiryYear = ""
    @State private var nameOnCard = ""
    @State private var payerConsent = false
    @State private var openedPostUrl: String?

    init(viewModel: CardPaymentDemoViewModel, onOpen3DS: @escaping (String) -> Void) {
        _viewModel = State(initialValue: viewModel)
        _state = State(initialValue: viewModel.state.value)
        self.onOpen3DS = onOpen3DS
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use saved card token", isOn: $useSavedCard)

                if useSavedCard {
                    TextField("tokenIdentifier", text: $tokenIdentifier)
                        .textFieldStyle(.roundedBorder)
                } else {
                    // Card number input with brand detection
                    HStack {
                        TextField("Card Number", text: $cardNumber)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: cardNumber) { _, newValue in
                                viewModel.updateCardNumber(cardNumber: newValue)
                                state = viewModel.state.value
                            }
                        
                        // Display detected card brand
                        if let detectedType = state.detectedCardType {
                            Text(detectedType.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                    
                    TextField("expiryMonth", text: $expiryMonth)
                        .textFieldStyle(.roundedBorder)
                    TextField("expiryYear", text: $expiryYear)
                        .textFieldStyle(.roundedBorder)
                    TextField("nameOnCard (optional)", text: $nameOnCard)
                        .textFieldStyle(.roundedBorder)
                    Toggle("payerConsentForToken", isOn: $payerConsent)
                }

                TextField("cvv", text: $cvv)
                    .textFieldStyle(.roundedBorder)

                Button(state.isLoading ? "Submitting..." : "Submit ADD_PAYMENT_INFO") {
                    Task {
                        if useSavedCard {
                            try? await viewModel.submitSavedCard(
                                tokenIdentifier: tokenIdentifier,
                                cvv: cvv
                            )
                        } else {
                            try? await viewModel.submitNewCard(
                                cvv: cvv,
                                cardNumber: cardNumber,
                                expiryMonth: expiryMonth,
                                expiryYear: expiryYear,
                                nameOnCard: nameOnCard.isEmpty ? nil : nameOnCard,
                                payerConsentForToken: payerConsent
                            )
                        }
                        state = viewModel.state.value
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isLoading)

                Text("resultCode: \(state.resultCode ?? "-")")
                Text("postUrl: \(state.postUrl ?? "-")")
                Text("resolvedOrderId: \(state.resolvedOrderId ?? "-")")

                if let error = state.errorMessage {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .navigationTitle("Card")
        .onChange(of: state.postUrl) { postUrl in
            guard let postUrl, !postUrl.isEmpty else { return }
            guard postUrl != openedPostUrl else { return }
            openedPostUrl = postUrl
            onOpen3DS(postUrl)
        }
    }
}

private struct ApplePayScreen: View {
    @State private var viewModel: ApplePayDemoViewModel
    @State private var orderConfigurationViewModel: OrderConfigurationDemoViewModel
    @State private var state: ApplePayDemoState
    @State private var orderConfigurationState: OrderConfigurationDemoState
    @State private var localErrorMessage: String?
    @State private var applePayCoordinator: ApplePayAuthorizationCoordinator?
    @State private var applePayController: PKPaymentAuthorizationController?   // ← must retain to prevent dealloc
    let onOpen3DS: (String) -> Void
    @State private var openedPostUrl: String?

    init(
        viewModel: ApplePayDemoViewModel,
        orderConfigurationViewModel: OrderConfigurationDemoViewModel,
        onOpen3DS: @escaping (String) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _orderConfigurationViewModel = State(initialValue: orderConfigurationViewModel)
        _state = State(initialValue: viewModel.state.value)
        _orderConfigurationState = State(initialValue: orderConfigurationViewModel.state.value)
        self.onOpen3DS = onOpen3DS
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apple Pay is configured from SDK_ORDER_CONFIGURATION.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let configuration = nativeConfiguration() {
                    Text("merchantIdentifier: \(configuration.merchantIdentifier)")
                    Text("countryCode: \(configuration.countryCode)")
                    Text("currencyCode: \(configuration.currencyCode)")
                    Text("amount: \(configuration.summaryAmount)")

                    ApplePayButtonRepresentable(onTap: {
                        presentApplePay(configuration: configuration)
                    })
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .disabled(state.isLoading)
                } else {
                    Text("Apple Pay configuration is not available in backend payment options.")
                        .foregroundStyle(.red)
                }

                Text("resultCode: \(state.resultCode ?? "-")")
                Text("postUrl: \(state.postUrl ?? "-")")
                Text("resolvedOrderId: \(state.resolvedOrderId ?? "-")")

                if let error = state.errorMessage ?? localErrorMessage {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .navigationTitle("ApplePay")
        .onAppear {
            // Sync both states eagerly when screen appears
            orderConfigurationState = orderConfigurationViewModel.state.value
            state = viewModel.state.value
        }
        .onChange(of: state.postUrl) { postUrl in
            guard let postUrl, !postUrl.isEmpty else { return }
            guard postUrl != openedPostUrl else { return }
            openedPostUrl = postUrl
            onOpen3DS(postUrl)
        }
    }

    private func nativeConfiguration() -> ApplePayNativeConfiguration? {
        guard let merchantIdentifier = orderConfigurationState.applePayMerchantIdentifier,
              let countryCode = orderConfigurationState.applePayCountryCode,
              let currencyCode = orderConfigurationState.applePayCurrencyCode,
              let summaryAmount = orderConfigurationState.applePaySummaryAmount,
              let amount = Decimal(string: summaryAmount)
        else {
            return nil
        }

        let summaryLabel = orderConfigurationState.applePaySummaryLabel ?? "Noon Payments"
        let networks = mapNetworks(orderConfigurationState.applePaySupportedNetworksCsv)
        guard !networks.isEmpty else { return nil }

        return ApplePayNativeConfiguration(
            merchantIdentifier: merchantIdentifier,
            countryCode: countryCode,
            currencyCode: currencyCode,
            summaryLabel: summaryLabel,
            summaryAmount: amount,
            supportedNetworks: networks
        )
    }

    private func mapNetworks(_ networksCsv: String?) -> [PKPaymentNetwork] {
        guard let networksCsv else { return [] }
        return networksCsv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap { raw in
                switch raw {
                case "amex", "americanexpress":
                    return .amex
                case "visa":
                    return .visa
                case "mastercard":
                    return .masterCard
                case "discover":
                    return .discover
                case "chinaunionpay", "unionpay":
                    return .chinaUnionPay
                case "maestro":
                    return .maestro
                case "jcb":
                    return .JCB
                case "mada":
                    if #available(iOS 12.1.1, *) { return .mada }
                    return nil
                case "meeza":
                    if #available(iOS 17.4, *) { return .meeza }
                    return nil
                default:
                    return nil
                }
            }
    }

    private func presentApplePay(configuration: ApplePayNativeConfiguration) {
        localErrorMessage = nil

        print("[ApplePay] canMakePayments: \(PKPaymentAuthorizationController.canMakePayments())")
        print("[ApplePay] merchantIdentifier: \(configuration.merchantIdentifier)")
        print("[ApplePay] countryCode: \(configuration.countryCode)")
        print("[ApplePay] currencyCode: \(configuration.currencyCode)")
        print("[ApplePay] summaryLabel: \(configuration.summaryLabel)")
        print("[ApplePay] summaryAmount: \(configuration.summaryAmount)")
        print("[ApplePay] supportedNetworks: \(configuration.supportedNetworks)")

        guard PKPaymentAuthorizationController.canMakePayments() else {
            localErrorMessage = "Apple Pay is unavailable on this device."
            return
        }

        let request = PKPaymentRequest()
        request.merchantIdentifier = configuration.merchantIdentifier
        request.countryCode = configuration.countryCode
        request.currencyCode = configuration.currencyCode
        request.merchantCapabilities = .capability3DS
        request.supportedNetworks = configuration.supportedNetworks
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: configuration.summaryLabel,
                amount: NSDecimalNumber(decimal: configuration.summaryAmount),
                type: .final
            )
        ]

        // Also check if the device can make payments with these specific networks
        let canPayWithNetworks = PKPaymentAuthorizationController.canMakePayments(usingNetworks: configuration.supportedNetworks)
        print("[ApplePay] canMakePayments(usingNetworks:): \(canPayWithNetworks)")

        let coordinator = ApplePayAuthorizationCoordinator(
            onDidAuthorize: { payment, completion in
                guard let token = String(data: payment.token.paymentData, encoding: .utf8), !token.isEmpty else {
                    self.localErrorMessage = "Failed to read Apple Pay token from device wallet."
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    return
                }

                Task {
                    try? await self.viewModel.submit(paymentToken: token)
                    await MainActor.run {
                        self.state = self.viewModel.state.value
                        let status: PKPaymentAuthorizationStatus = self.state.errorMessage == nil ? .success : .failure
                        completion(PKPaymentAuthorizationResult(status: status, errors: nil))
                    }
                }
            },
            onDidFinish: {
                self.applePayController = nil
                self.applePayCoordinator = nil
            }
        )

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = coordinator
        applePayController = controller
        applePayCoordinator = coordinator

        print("[ApplePay] Calling controller.present()...")
        controller.present { presented in
            print("[ApplePay] present() callback — presented: \(presented)")
            if !presented {
                self.applePayController = nil
                self.applePayCoordinator = nil
                self.localErrorMessage = "Unable to present Apple Pay sheet. Check that the merchant ID '\(configuration.merchantIdentifier)' is registered in your Apple Developer account and added to this app's entitlements."
            }
        }
    }
}

private struct ApplePayNativeConfiguration {
    let merchantIdentifier: String
    let countryCode: String
    let currencyCode: String
    let summaryLabel: String
    let summaryAmount: Decimal
    let supportedNetworks: [PKPaymentNetwork]
}

private final class ApplePayAuthorizationCoordinator: NSObject, PKPaymentAuthorizationControllerDelegate {
    let onDidAuthorize: (PKPayment, @escaping (PKPaymentAuthorizationResult) -> Void) -> Void
    let onDidFinish: () -> Void

    init(
        onDidAuthorize: @escaping (PKPayment, @escaping (PKPaymentAuthorizationResult) -> Void) -> Void,
        onDidFinish: @escaping () -> Void
    ) {
        self.onDidAuthorize = onDidAuthorize
        self.onDidFinish = onDidFinish
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        onDidAuthorize(payment, completion)
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            self.onDidFinish()
        }
    }
}

private struct ApplePayButtonRepresentable: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func didTap() {
            onTap()
        }
    }
}


private struct ThreeDSScreen: View {
    let postUrl: String
    let onCallback: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ThreeDSWebView(postUrl: postUrl, onCallback: onCallback)
                .frame(minHeight: 420)
        }
        .padding(16)
        .navigationTitle("3DS Verification")
    }
}

private struct ThreeDSWebView: UIViewRepresentable {
    let postUrl: String
    let onCallback: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: postUrl) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let current = uiView.url?.absoluteString else {
            if let url = URL(string: postUrl) {
                uiView.load(URLRequest(url: url))
            }
            return
        }
        if current != postUrl, let url = URL(string: postUrl) {
            uiView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCallback: (String) -> Void

        init(onCallback: @escaping (String) -> Void) {
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            if url.hasPrefix(threeDsCallbackUrlPrefix) {
                DispatchQueue.main.async {
                    self.onCallback(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

private struct OrderStatusScreen: View {
    @State private var viewModel: FetchOrderStatusDemoViewModel
    @State private var state: FetchOrderStatusDemoState

    let defaultOrderId: String
    let onEmitResult: (NPMobileSDKOrderStatus, String?) -> Void

    @State private var overrideOrderId = ""

    init(
        viewModel: FetchOrderStatusDemoViewModel,
        defaultOrderId: String,
        onEmitResult: @escaping (NPMobileSDKOrderStatus, String?) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _state = State(initialValue: viewModel.state.value)
        self.defaultOrderId = defaultOrderId
        self.onEmitResult = onEmitResult
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("orderId override (default: \(defaultOrderId))", text: $overrideOrderId)
                    .textFieldStyle(.roundedBorder)

                Button(state.isLoading ? "Fetching..." : "Fetch /order/{orderId}") {
                    Task {
                        try? await viewModel.fetch(orderIdOverride: overrideOrderId)
                        state = viewModel.state.value
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isLoading)

                Text("usedOrderId: \(state.usedOrderId ?? "-")")
                Text("resultCode: \(state.resultCode ?? "-")")
                Text("orderStatus: \(state.orderStatus ?? "-")")
                Text("transactionStatus: \(state.transactionStatus ?? "-")")
                Text("paymentDetails: \(state.paymentDetailsJson ?? "-")")

                Button("Emit Merchant Result") {
                    onEmitResult(mappedStatus(), state.errorMessage)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .navigationTitle("Order Status")
    }

    private func mappedStatus() -> NPMobileSDKOrderStatus {
        if state.errorMessage != nil {
            return .failed
        }
        if state.orderStatus?.uppercased() == "CANCELLED" {
            return .cancelled
        }
        if state.transactionStatus?.uppercased() == "SUCCESS" {
            return .success
        }
        if state.orderStatus?.uppercased() == "SUCCESS" {
            return .success
        }
        return .failed
    }
}

private struct CancelScreen: View {
    @State private var viewModel: CancelPaymentDemoViewModel
    @State private var state: CancelPaymentDemoState
    @State private var reason = "Cancelled from checkout header."

    let onFinishCancelled: () -> Void

    init(viewModel: CancelPaymentDemoViewModel, onFinishCancelled: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        _state = State(initialValue: viewModel.state.value)
        self.onFinishCancelled = onFinishCancelled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("cancellationReason", text: $reason)
                    .textFieldStyle(.roundedBorder)

                Button(state.isLoading ? "Cancelling..." : "Submit CANCEL") {
                    Task {
                        try? await viewModel.cancel(reason: reason)
                        state = viewModel.state.value
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isLoading)

                Text("isCancelled: \(state.isCancelled)")
                Text("usedReason: \(state.usedReason ?? "-")")

                if let error = state.errorMessage {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                }

                if state.isCancelled {
                    Button("Finish With Cancelled Result") {
                        onFinishCancelled()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .navigationTitle("Cancel")
    }
}

#Preview {
    NPMobileSDKPaymentView(
        isPresented: .constant(true),
        request: NPMobileSDKPaymentRequest(
            orderId: "ORDER-12345",
            authHeader: "Key_Test <your-auth-header>",
            url: "https://api-test.noonpayments.com/payment/v1/order"
        )
    )
}
