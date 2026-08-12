import SwiftUI
import WebKit
import PassKit
import Foundation
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
    public let layoutMode: NPMobileSDKLayoutMode
    public let includedPaymentMethods: Set<NPMobileSDKPaymentMethod>
    public let excludedPaymentMethods: Set<NPMobileSDKPaymentMethod>

    public init(
        sheetTitle: String = "NoonPayments SDK",
        layoutMode: NPMobileSDKLayoutMode = .radio,
        includedPaymentMethods: Set<NPMobileSDKPaymentMethod> = [],
        excludedPaymentMethods: Set<NPMobileSDKPaymentMethod> = []
    ) {
        self.sheetTitle = sheetTitle
        self.layoutMode = layoutMode
        self.includedPaymentMethods = includedPaymentMethods
        self.excludedPaymentMethods = excludedPaymentMethods
    }
}

public enum NPMobileSDKLayoutMode {
    case radio
    case checkmark
    case floatingButtons
}

public enum NPMobileSDKPaymentMethod: String, Hashable, CaseIterable {
    case card = "Card"
    case applePay = "ApplePay"
    case googlePay = "GooglePay"

    var displayName: String {
        switch self {
        case .card:
            return "Card"
        case .applePay:
            return "Apple Pay"
        case .googlePay:
            return "Google Pay"
        }
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

public struct NPMobileSDKConfiguration {
    public let loggingEnabled: Bool
    public let logger: NPMobileSDKLogger?

    public init(
        loggingEnabled: Bool = false,
        logger: NPMobileSDKLogger? = nil
    ) {
        self.loggingEnabled = loggingEnabled
        self.logger = logger
    }
}

public struct NPMobileSDKLogEvent {
    public let level: String
    public let tag: String
    public let message: String
    public let orderId: String

    public init(level: String, tag: String, message: String, orderId: String) {
        self.level = level
        self.tag = tag
        self.message = message
        self.orderId = orderId
    }
}

public protocol NPMobileSDKLogger {
    func log(event: NPMobileSDKLogEvent)

    func logOrderConfigurationFailure(event: NPMobileSDKLogEvent)

    func logCardPaymentFailure(event: NPMobileSDKLogEvent)

    func logApplePayFailure(event: NPMobileSDKLogEvent)

    func logGooglePayFailure(event: NPMobileSDKLogEvent)

    func logOrderStatusFailure(event: NPMobileSDKLogEvent)

    func logCancelPaymentFailure(event: NPMobileSDKLogEvent)

    func logNetworkFailure(event: NPMobileSDKLogEvent)

    func logUnknownFailure(event: NPMobileSDKLogEvent)
}

public extension NPMobileSDKLogger {
    func logOrderConfigurationFailure(event: NPMobileSDKLogEvent) {}
    func logCardPaymentFailure(event: NPMobileSDKLogEvent) {}
    func logApplePayFailure(event: NPMobileSDKLogEvent) {}
    func logGooglePayFailure(event: NPMobileSDKLogEvent) {}
    func logOrderStatusFailure(event: NPMobileSDKLogEvent) {}
    func logCancelPaymentFailure(event: NPMobileSDKLogEvent) {}
    func logNetworkFailure(event: NPMobileSDKLogEvent) {}
    func logUnknownFailure(event: NPMobileSDKLogEvent) {}
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
    private let configuration: NPMobileSDKConfiguration
    private let onPaymentResult: (NPMobileSDKPaymentResponse) -> Void

    public init(
        isPresented: Binding<Bool>,
        request: NPMobileSDKPaymentRequest,
        style: NPMobileSDKStyleConfiguration = NPMobileSDKStyleConfiguration(),
        configuration: NPMobileSDKConfiguration = NPMobileSDKConfiguration(),
        onPaymentResult: @escaping (NPMobileSDKPaymentResponse) -> Void = { _ in }
    ) {
        _isPresented = isPresented
        self.request = request
        self.style = style
        self.configuration = configuration
        self.onPaymentResult = onPaymentResult
    }

    public var body: some View {
        EmptyView()
            .sheet(isPresented: $isPresented) {
                SheetRootView(
                    request: request,
                    style: style,
                    configuration: configuration,
                    onPaymentResult: onPaymentResult,
                    onDismiss: { isPresented = false }
                )
            }
    }
}

public struct NPMobileSDKEmbeddedPaymentView: View {
    private let request: NPMobileSDKPaymentRequest
    private let style: NPMobileSDKStyleConfiguration
    private let onPaymentResult: (NPMobileSDKPaymentResponse) -> Void
    private let onHeightChanged: (CGFloat) -> Void

    @State private var component: PaymentSheetDemoComponent
    @State private var orderConfigurationState: OrderConfigurationDemoState
    @State private var orderStatusState: FetchOrderStatusDemoState
    @State private var selectedMethod: NPMobileSDKPaymentMethod?
    @State private var showAddCardSheet = false
    @State private var threeDsPostUrl: String?
    @State private var lastReportedHeight: CGFloat = .zero

    public init(
        request: NPMobileSDKPaymentRequest,
        style: NPMobileSDKStyleConfiguration = NPMobileSDKStyleConfiguration(),
        onPaymentResult: @escaping (NPMobileSDKPaymentResponse) -> Void = { _ in },
        onHeightChanged: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.request = request
        self.style = style
        self.onPaymentResult = onPaymentResult
        self.onHeightChanged = onHeightChanged

        let apiConfig = PaymentApiConfig(
            baseUrl: request.url,
            orderId: request.orderId,
            authHeader: request.authHeader,
            sdkVersion: demoSdkVersion
        )
        let component = PaymentSheetDemoComponentFactory.shared.create(apiConfig: apiConfig)
        _component = State(initialValue: component)
        _orderConfigurationState = State(initialValue: component.orderConfigurationViewModel.state.value)
        _orderStatusState = State(initialValue: component.fetchOrderStatusViewModel.state.value)
    }

    private var visibleMethods: [NPMobileSDKPaymentMethod] {
        resolveVisiblePaymentMethods(
            paymentOptionsJson: orderConfigurationState.paymentOptionsJson,
            includedPaymentMethods: style.includedPaymentMethods,
            excludedPaymentMethods: style.excludedPaymentMethods,
            platformSupportedMethods: [.card, .applePay]
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(style.sheetTitle)
                .font(.headline)
            Text("API: \(request.url)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if orderConfigurationState.isLoading && orderConfigurationState.paymentOptionsJson == nil {
                Text("Loading payment methods…")
            } else if let error = orderConfigurationState.errorMessage {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            } else if visibleMethods.isEmpty {
                Text("No payment methods are available for the current configuration.")
                    .foregroundStyle(.red)
            } else {
                Text("Choose payment method")
                    .font(.subheadline.weight(.semibold))

                PaymentMethodSelectorView(
                    methods: visibleMethods,
                    selectedMethod: selectedMethod,
                    layoutMode: style.layoutMode,
                    onSelect: { selectedMethod = $0 }
                )

                switch selectedMethod {
                case .card:
                    Text("Card payment opens the add-card form in a sheet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Add New Card") {
                        showAddCardSheet = true
                    }
                    .buttonStyle(.borderedProminent)

                case .applePay:
                    ApplePayScreen(
                        viewModel: component.applePayViewModel,
                        orderConfigurationViewModel: component.orderConfigurationViewModel,
                        onOpen3DS: { postUrl in
                            threeDsPostUrl = postUrl
                        },
                        showNavigationTitle: false,
                        onCompletedWithout3DS: { resolvedOrderId in
                            Task {
                                await finalizePayment(orderIdOverride: resolvedOrderId)
                            }
                        }
                    )

                case .googlePay, .none:
                    EmptyView()
                }
            }

            if orderStatusState.resultCode != nil || orderStatusState.errorMessage != nil {
                Text(
                    embeddedResultText(for: orderStatusState)
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: EmbeddedPaymentHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(EmbeddedPaymentHeightPreferenceKey.self) { newHeight in
            guard newHeight != lastReportedHeight else { return }
            lastReportedHeight = newHeight
            onHeightChanged(newHeight)
        }
        .task {
            try? await component.orderConfigurationViewModel.load()
            orderConfigurationState = component.orderConfigurationViewModel.state.value
            if selectedMethod == nil || !visibleMethods.contains(selectedMethod!) {
                selectedMethod = visibleMethods.first
            }
        }
        .onChange(of: orderConfigurationState.paymentOptionsJson) { _, _ in
            if selectedMethod == nil || !visibleMethods.contains(selectedMethod!) {
                selectedMethod = visibleMethods.first
            }
        }
        .sheet(isPresented: $showAddCardSheet) {
            CardPaymentScreen(
                viewModel: component.cardPaymentViewModel,
                onOpen3DS: { postUrl in
                    showAddCardSheet = false
                    threeDsPostUrl = postUrl
                },
                allowSavedCardInput: false,
                showNavigationTitle: false,
                onCompletedWithout3DS: { resolvedOrderId in
                    showAddCardSheet = false
                    Task {
                        await finalizePayment(orderIdOverride: resolvedOrderId)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { threeDsPostUrl != nil },
                set: { isPresented in
                    if !isPresented {
                        threeDsPostUrl = nil
                    }
                }
            )
        ) {
            if let postUrl = threeDsPostUrl {
                ThreeDSSheetView(postUrl: postUrl) { callbackUrl in
                    threeDsPostUrl = nil
                    Task {
                        await finalizePayment(orderIdOverride: extractOrderId(from: callbackUrl))
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    private func finalizePayment(orderIdOverride: String?) async {
        try? await component.fetchOrderStatusViewModel.fetch(orderIdOverride: orderIdOverride ?? "")
        orderStatusState = component.fetchOrderStatusViewModel.state.value
        onPaymentResult(
            NPMobileSDKPaymentResponse(
                orderId: orderStatusState.usedOrderId ?? request.orderId,
                orderStatus: mappedStatus(from: orderStatusState),
                errorMessage: orderStatusState.errorMessage
            )
        )
    }
}

private struct SheetRootView: View {
    let request: NPMobileSDKPaymentRequest
    let style: NPMobileSDKStyleConfiguration
    let configuration: NPMobileSDKConfiguration
    let onPaymentResult: (NPMobileSDKPaymentResponse) -> Void
    let onDismiss: () -> Void

    @State private var path: [PaymentSheetRoute] = []
    @State private var component: PaymentSheetDemoComponent
    @State private var orderIdFromThreeDs: String?

    init(
        request: NPMobileSDKPaymentRequest,
        style: NPMobileSDKStyleConfiguration,
        configuration: NPMobileSDKConfiguration,
        onPaymentResult: @escaping (NPMobileSDKPaymentResponse) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.style = style
        self.configuration = configuration
        self.onPaymentResult = onPaymentResult
        self.onDismiss = onDismiss

        // Apply merchant-controlled logger directly from the sheet entry point.
        let logger: SdkLogger = configuration.logger?.asSdkLogger()
            ?? (configuration.loggingEnabled ? PrintSdkLogger.shared : NoOpSdkLogger.shared)
        SdkLoggerConfig.shared.configure(logger: logger)

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

private final class NPMobileSDKLoggerAdapter: SdkLogger {
    private let logger: NPMobileSDKLogger

    init(logger: NPMobileSDKLogger) {
        self.logger = logger
    }

    func log(level: LogLevel, tag: String, message: String, orderId: String) {
        let event = NPMobileSDKLogEvent(
            level: "\(level)",
            tag: tag,
            message: message,
            orderId: orderId
        )
        logger.log(event: event)
        guard event.level.uppercased().contains("ERROR") else { return }
        switch event.tag {
        case "OrderConfigurationDemoViewModel":
            logger.logOrderConfigurationFailure(event: event)
        case "CardPaymentDemoViewModel":
            logger.logCardPaymentFailure(event: event)
        case "ApplePayDemoViewModel":
            logger.logApplePayFailure(event: event)
        case "GooglePayDemoViewModel":
            logger.logGooglePayFailure(event: event)
        case "FetchOrderStatusDemoViewModel":
            logger.logOrderStatusFailure(event: event)
        case "CancelPaymentDemoViewModel":
            logger.logCancelPaymentFailure(event: event)
        case "NetworkClient":
            logger.logNetworkFailure(event: event)
        default:
            logger.logUnknownFailure(event: event)
        }
    }
}

private extension NPMobileSDKLogger {
    func asSdkLogger() -> SdkLogger {
        NPMobileSDKLoggerAdapter(logger: self)
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
               // Text("configuration: \(state.configurationJson ?? "-")")
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
    let allowSavedCardInput: Bool
    let showNavigationTitle: Bool
    let onCompletedWithout3DS: ((String?) -> Void)?

    @State private var useSavedCard: Bool = true
    @State private var tokenIdentifier = ""
    @State private var cvv = ""
    @State private var cardNumber = ""
    @State private var expiryMonth = ""
    @State private var expiryYear = ""
    @State private var nameOnCard = ""
    @State private var payerConsent = false
    @State private var openedPostUrl: String?

    init(
        viewModel: CardPaymentDemoViewModel,
        onOpen3DS: @escaping (String) -> Void,
        allowSavedCardInput: Bool = true,
        showNavigationTitle: Bool = true,
        onCompletedWithout3DS: ((String?) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        _state = State(initialValue: viewModel.state.value)
        self.onOpen3DS = onOpen3DS
        self.allowSavedCardInput = allowSavedCardInput
        self.showNavigationTitle = showNavigationTitle
        self.onCompletedWithout3DS = onCompletedWithout3DS
        _useSavedCard = State(initialValue: allowSavedCardInput)
        _openedPostUrl = State(initialValue: viewModel.state.value.postUrl)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if allowSavedCardInput {
                    Toggle("Use saved card token", isOn: $useSavedCard)
                }

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
                        if state.errorMessage == nil, state.resultCode != nil, state.postUrl == nil {
                            onCompletedWithout3DS?(state.resolvedOrderId)
                        }
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
        .navigationTitle(showNavigationTitle ? "Card" : "")
        .onChange(of: state.postUrl) { _, postUrl in
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
    let showNavigationTitle: Bool
    let onCompletedWithout3DS: ((String?) -> Void)?
    @State private var openedPostUrl: String?

    init(
        viewModel: ApplePayDemoViewModel,
        orderConfigurationViewModel: OrderConfigurationDemoViewModel,
        onOpen3DS: @escaping (String) -> Void,
        showNavigationTitle: Bool = true,
        onCompletedWithout3DS: ((String?) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        _orderConfigurationViewModel = State(initialValue: orderConfigurationViewModel)
        _state = State(initialValue: viewModel.state.value)
        _orderConfigurationState = State(initialValue: orderConfigurationViewModel.state.value)
        self.onOpen3DS = onOpen3DS
        self.showNavigationTitle = showNavigationTitle
        self.onCompletedWithout3DS = onCompletedWithout3DS
        _openedPostUrl = State(initialValue: viewModel.state.value.postUrl)
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
                    Text("amount: \(configuration.summaryAmount.description)")

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
        .navigationTitle(showNavigationTitle ? "ApplePay" : "")
        .onAppear {
            // Sync both states eagerly when screen appears
            orderConfigurationState = orderConfigurationViewModel.state.value
            state = viewModel.state.value
        }
        .onChange(of: state.postUrl) { _, postUrl in
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
        request.merchantCapabilities = .threeDSecure
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
                        if self.state.errorMessage == nil, self.state.resultCode != nil, self.state.postUrl == nil {
                            self.onCompletedWithout3DS?(self.state.resolvedOrderId)
                        }
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

private struct ThreeDSSheetView: View {
    let postUrl: String
    let onCallback: (String) -> Void

    var body: some View {
        NavigationStack {
            ThreeDSScreen(postUrl: postUrl, onCallback: onCallback)
        }
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

private struct PaymentMethodSelectorView: View {
    let methods: [NPMobileSDKPaymentMethod]
    let selectedMethod: NPMobileSDKPaymentMethod?
    let layoutMode: NPMobileSDKLayoutMode
    let onSelect: (NPMobileSDKPaymentMethod) -> Void

    var body: some View {
        switch layoutMode {
        case .radio:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(methods, id: \.self) { method in
                    Button {
                        onSelect(method)
                    } label: {
                        HStack {
                            Text(selectedMethod == method ? "◉" : "○")
                            Text(method.displayName)
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .checkmark:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(methods, id: \.self) { method in
                    Button {
                        onSelect(method)
                    } label: {
                        HStack {
                            Text(selectedMethod == method ? "✓" : "□")
                            Text(method.displayName)
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .floatingButtons:
            HStack(spacing: 8) {
                ForEach(methods, id: \.self) { method in
                    if selectedMethod == method {
                        Button(method.displayName) {
                            onSelect(method)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button(method.displayName) {
                            onSelect(method)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct EmbeddedPaymentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func resolveVisiblePaymentMethods(
    paymentOptionsJson: String?,
    includedPaymentMethods: Set<NPMobileSDKPaymentMethod>,
    excludedPaymentMethods: Set<NPMobileSDKPaymentMethod>,
    platformSupportedMethods: Set<NPMobileSDKPaymentMethod>
) -> [NPMobileSDKPaymentMethod] {
    let backendMethods = parseBackendPaymentMethods(paymentOptionsJson)
        .filter { platformSupportedMethods.contains($0) }
    let included = includedPaymentMethods.intersection(platformSupportedMethods)
    let filtered = included.isEmpty
        ? backendMethods
        : backendMethods.filter { included.contains($0) }
    return filtered.filter { !excludedPaymentMethods.contains($0) }
}

private func parseBackendPaymentMethods(_ paymentOptionsJson: String?) -> [NPMobileSDKPaymentMethod] {
    guard let paymentOptionsJson,
          let data = paymentOptionsJson.data(using: .utf8),
          let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
        return []
    }

    var methods: [NPMobileSDKPaymentMethod] = []
    for item in items {
        guard let method = mapBackendPaymentMethod(item), !methods.contains(method) else { continue }
        methods.append(method)
    }
    return methods
}

private func mapBackendPaymentMethod(_ item: [String: Any]) -> NPMobileSDKPaymentMethod? {
    let rawValue = ["action", "type", "method"]
        .compactMap { item[$0] as? String }
        .first { !$0.isEmpty }

    switch rawValue?.lowercased() {
    case "card":
        return .card
    case "applepay":
        return .applePay
    case "googlepay":
        return .googlePay
    default:
        return nil
    }
}

private func extractOrderId(from callbackUrl: String) -> String? {
    guard let components = URLComponents(string: callbackUrl) else { return nil }
    return components.queryItems?.first(where: { $0.name == "orderId" })?.value
}

private func mappedStatus(from state: FetchOrderStatusDemoState) -> NPMobileSDKOrderStatus {
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

private func embeddedResultText(for state: FetchOrderStatusDemoState) -> String {
    var parts = ["Embedded result: \(mappedStatus(from: state))"]
    if let usedOrderId = state.usedOrderId, !usedOrderId.isEmpty {
        parts.append("orderId=\(usedOrderId)")
    }
    if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
        parts.append("error=\(errorMessage)")
    }
    return parts.joined(separator: " | ")
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
