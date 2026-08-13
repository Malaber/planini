import PlaniniCore
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
private struct ItemCategoryDropInteractionView: UIViewRepresentable {
    let onTargetedChanged: (Bool) -> Void
    let onDrop: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTargetedChanged: onTargetedChanged, onDrop: onDrop)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTargetedChanged = onTargetedChanged
        context.coordinator.onDrop = onDrop
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var onTargetedChanged: (Bool) -> Void
        var onDrop: (String) -> Void

        init(onTargetedChanged: @escaping (Bool) -> Void, onDrop: @escaping (String) -> Void) {
            self.onTargetedChanged = onTargetedChanged
            self.onDrop = onDrop
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.canLoadObjects(ofClass: NSString.self)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            onTargetedChanged(true)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            onTargetedChanged(false)
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidUpdate session: UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            onTargetedChanged(false)
            session.loadObjects(ofClass: NSString.self) { [weak self] objects in
                guard let itemID = objects.first as? String else { return }
                Task { @MainActor in
                    self?.onDrop(itemID)
                }
            }
        }
    }
}
#endif

private struct AppErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

private enum AppTab: Hashable {
    case favorite
    case lists
    case settings
}

private struct ListAccentColorOption: Identifiable, Equatable {
    let id: String
    let localizationKey: String
    let hex: String?

    static let all: [ListAccentColorOption] = [
        ListAccentColorOption(
            id: "none",
            localizationKey: "ios.list_settings.accent_none",
            hex: nil
        ),
        ListAccentColorOption(
            id: "red",
            localizationKey: "ios.list_settings.accent_red",
            hex: "#ff3b30"
        ),
        ListAccentColorOption(
            id: "orange",
            localizationKey: "ios.list_settings.accent_orange",
            hex: "#ff9500"
        ),
        ListAccentColorOption(
            id: "yellow",
            localizationKey: "ios.list_settings.accent_yellow",
            hex: "#ffcc00"
        ),
        ListAccentColorOption(
            id: "green",
            localizationKey: "ios.list_settings.accent_green",
            hex: "#34c759"
        ),
        ListAccentColorOption(
            id: "teal",
            localizationKey: "ios.list_settings.accent_teal",
            hex: "#30b0c7"
        ),
        ListAccentColorOption(
            id: "blue",
            localizationKey: "ios.list_settings.accent_blue",
            hex: "#007aff"
        ),
        ListAccentColorOption(
            id: "purple",
            localizationKey: "ios.list_settings.accent_purple",
            hex: "#af52de"
        ),
        ListAccentColorOption(
            id: "pink",
            localizationKey: "ios.list_settings.accent_pink",
            hex: "#ff2d55"
        ),
    ]

    static func option(for hex: String?) -> ListAccentColorOption? {
        all.first { option in
            switch (option.hex, hex) {
            case (nil, nil):
                return true
            case let (optionHex?, hex?):
                return optionHex.caseInsensitiveCompare(hex) == .orderedSame
            default:
                return false
            }
        }
    }
}

private struct AddItemPresentation: Identifiable {
    let id = UUID()
    let categoryID: UUID?
}

private struct ItemMoveNotice: Identifiable, Equatable {
    let id: UUID
    let sourceListID: UUID
    let targetListID: UUID
    let targetListName: String
    let sourceItem: GroceryItemRecord
    let movedItem: GroceryItemRecord
    var isExpiring = false
    var restoreErrorMessage: String?

    var itemName: String {
        movedItem.name
    }
}

private enum ListRowContent: Identifiable, Equatable {
    case item(GroceryItemRecord)
    case moveNotice(ItemMoveNotice)

    var id: String {
        switch self {
        case let .item(item):
            return item.id.uuidString
        case let .moveNotice(notice):
            return "move-notice-\(notice.id.uuidString)"
        }
    }

    var sortOrder: Int {
        switch self {
        case let .item(item):
            return item.sortOrder
        case let .moveNotice(notice):
            return notice.sourceItem.sortOrder
        }
    }

    var name: String {
        switch self {
        case let .item(item):
            return item.name
        case let .moveNotice(notice):
            return notice.itemName
        }
    }
}

private struct ListDisplaySection: Identifiable, Equatable {
    let id: String
    let title: String
    let colorHex: String?
    let kind: GroceryItemSectionKind
    var rows: [ListRowContent]

    var itemCount: Int {
        rows.reduce(0) { count, row in
            if case .item = row {
                return count + 1
            }
            return count
        }
    }

    init(
        id: String,
        title: String,
        colorHex: String?,
        kind: GroceryItemSectionKind,
        rows: [ListRowContent]
    ) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.kind = kind
        self.rows = rows
    }

    init(section: GroceryItemSection) {
        id = section.id
        title = section.title
        colorHex = section.colorHex
        kind = section.kind
        rows = section.items.map(ListRowContent.item)
    }
}

private typealias ListUndoAction = @MainActor () async -> Bool

private enum CompactListLayout {
    static let sectionSpacing: CGFloat = 0
    static let headerHeight: CGFloat = 32
    static let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    static let summaryInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
}

private extension View {
    @ViewBuilder
    func compactListSectionSpacing() -> some View {
        if #available(iOS 17.0, *) {
            listSectionSpacing(CompactListLayout.sectionSpacing)
        } else {
            self
        }
    }
}

private struct ListUndoToast: Identifiable {
    let id = UUID()
    let message: String
    let action: ListUndoAction
}

private struct CategoryDisableConfirmation: Identifiable {
    let category: GroceryCategorySummary
    let itemCount: Int

    var id: UUID {
        category.id
    }
}

private enum ListSettingsFocusedField: Equatable {
    case name
}

private enum ListSettingsSaveState: Equatable {
    case saved
    case unsaved
    case saving
    case failed

    var title: String {
        switch self {
        case .saved:
            return "Saved"
        case .unsaved:
            return "Unsaved"
        case .saving:
            return "Saving..."
        case .failed:
            return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .saved:
            return "checkmark.circle"
        case .unsaved:
            return "circle.dotted"
        case .saving:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .saved, .saving:
            return .secondary
        case .unsaved:
            return .orange
        case .failed:
            return .red
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    @State private var selectedTab: AppTab = .favorite
    @State private var presentedError: AppErrorAlert?
    @State private var showingReviewerOnboarding = false
    @State private var showingAccountRegistration = false
    @State private var passkeyAddLinkInput = ""
    @State private var listNavigationPath: [UUID] = []
    @State private var presentedPublicList: PublicListReference?

    var body: some View {
        Group {
            if viewModel.authToken == nil, viewModel.isLocalMode == false {
                NavigationStack {
                    loginPane
                        .navigationTitle("Planini")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        showingReviewerOnboarding = true
                                    } label: {
                                        Label(
                                            l10n.t("ios.login.trouble_signing_in"),
                                            systemImage: "questionmark.circle"
                                        )
                                    }
                                    .accessibilityIdentifier("login-help-trouble-button")
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .accessibilityIdentifier("login-help-menu")
                            }
                        }
                }
            } else {
                authenticatedApp
            }
        }
        .sheet(isPresented: $showingReviewerOnboarding) {
            ReviewerOnboardingSheet(
                initialPasskeyAddInput: passkeyAddLinkInput,
                showsPasskeyAddSection: true
            )
        }
        .sheet(isPresented: $showingAccountRegistration) {
            ReviewerOnboardingSheet(
                initialPasskeyAddInput: "",
                showsPasskeyAddSection: false
            )
        }
        .fullScreenCover(item: $presentedPublicList, onDismiss: {
            Task { await viewModel.closePublicList() }
        }) { reference in
            NavigationStack {
                ListDetailScreen(
                    listID: reference.id,
                    showsFavoriteButton: false,
                    publicList: reference
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(l10n.t("common.done")) {
                            presentedPublicList = nil
                        }
                        .accessibilityIdentifier("public-list-close-button")
                    }
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleIncomingURL(url)
        }
        .onChange(of: viewModel.linkedListNavigationRequest) { request in
            guard let request else { return }
            selectedTab = .lists
            listNavigationPath = [request.listID]
        }
        .onChange(of: viewModel.publicListNavigationRequest) { request in
            guard let request else { return }
            presentedPublicList = request.reference
        }
        .onChange(of: viewModel.localModeUpgradeRequestID) { requestID in
            guard requestID != nil else { return }
            showingAccountRegistration = true
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            guard showingReviewerOnboarding == false, showingAccountRegistration == false else { return }
            if let newValue, newValue.isEmpty == false {
                presentedError = AppErrorAlert(message: newValue)
            } else {
                presentedError = nil
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(l10n.t("ios.error.title")),
                message: Text(error.message),
                dismissButton: .cancel(Text(l10n.t("common.ok"))) {
                    viewModel.errorMessage = nil
                }
            )
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.offlineStatusMessage)
        .task(id: selectedTab) {
            guard selectedTab == .favorite else { return }
            await viewModel.showFavoriteList()
        }
        .task {
            await viewModel.bootstrapLaunchSessionIfNeeded()
        }
    }

    private var loginPane: some View {
        Form {
            Section(l10n.t("ios.login.backend")) {
                LabeledContent(l10n.t("ios.login.configured_host"), value: viewModel.backendDisplayName)
            }

            if let displayName = viewModel.displayName, displayName.isEmpty == false {
                Section(l10n.t("ios.login.account")) {
                    LabeledContent(l10n.t("ios.login.last_signed_in_as"), value: displayName)
                        .accessibilityIdentifier("login-last-account")
                }
            }

            Section(l10n.t("ios.login.sign_in")) {
                Button {
                    Task { await viewModel.loginWithPasskey() }
                } label: {
                    if viewModel.isAuthenticating {
                        Label(l10n.t("ios.login.signing_in"), systemImage: "hourglass")
                    } else {
                        Label(l10n.t("ios.login.continue_with_passkey"), systemImage: "person.badge.key")
                    }
                }
                .disabled(viewModel.isAuthenticating)
                .accessibilityIdentifier("login-passkey-button")

                Button {
                    showingAccountRegistration = true
                } label: {
                    Label(l10n.t("ios.onboarding.create_account"), systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(viewModel.isAuthenticating)
                .accessibilityIdentifier("login-create-account-button")
            }

            if viewModel.publicLists.isEmpty == false {
                Section(l10n.t("ios.public_lists.title")) {
                    RememberedPublicListRows(
                        references: viewModel.publicLists,
                        onOpen: openPublicList,
                        onRemove: viewModel.removePublicList
                    )
                }
            }

            Section {
                NavigationLink {
                    PlaniniPromotionScreen(allowsLocalDemo: true)
                } label: {
                    Label(l10n.t("ios.promo.explore"), systemImage: "sparkles")
                }
                .accessibilityIdentifier("login-promo-link")
            } footer: {
                Text(l10n.t("ios.promo.login_hint"))
            }
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FavoriteListTab(selectedTab: $selectedTab, onListSwitch: openListInListsTab)
            }
            .tabItem {
                Label(
                    viewModel.favoriteList?.name ?? l10n.t("ios.tabs.favorite"),
                    systemImage: viewModel.favoriteListID == nil ? "star" : "star.fill"
                )
                .accessibilityIdentifier("tab-favorite-button")
            }
            .tag(AppTab.favorite)
            .accessibilityIdentifier("tab-favorite")

            NavigationStack(path: $listNavigationPath) {
                ListsTab(selectedTab: $selectedTab, onOpenPublicList: openPublicList)
                    .navigationDestination(for: UUID.self) { listID in
                        ListDetailScreen(listID: listID, showsFavoriteButton: true)
                    }
            }
            .tabItem {
                Label(l10n.t("ios.tabs.lists"), systemImage: "rectangle.grid.1x2")
                    .accessibilityIdentifier("tab-lists-button")
            }
            .tag(AppTab.lists)
            .accessibilityIdentifier("tab-lists")

            NavigationStack {
                SettingsTab()
            }
            .tabItem {
                Label(l10n.t("common.settings"), systemImage: "gearshape")
                    .accessibilityIdentifier("tab-settings-button")
            }
            .tag(AppTab.settings)
            .accessibilityIdentifier("tab-settings")
        }
        .accessibilityIdentifier("main-tab-view")
    }

    private var authenticatedApp: some View {
        VStack(spacing: 0) {
            if viewModel.isLocalMode {
                Button {
                    showingAccountRegistration = true
                } label: {
                    LocalModeStatusBanner()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("local-mode-banner")
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let offlineStatusMessage = viewModel.offlineStatusMessage {
                OfflineStatusBanner(message: offlineStatusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            appTabs
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if MobileAppViewModel.passkeyAddToken(from: url.absoluteString) != nil {
            passkeyAddLinkInput = url.absoluteString
            showingReviewerOnboarding = true
            return
        }

        Task {
            await viewModel.handleIncomingPlaniniLink(url.absoluteString)
        }
    }

    private func openListInListsTab(_ listID: UUID) {
        selectedTab = .lists
        listNavigationPath = [listID]
    }

    private func openPublicList(_ reference: PublicListReference) {
        Task { await viewModel.openRememberedPublicList(reference) }
    }
}

private struct LocalModeStatusBanner: View {
    @EnvironmentObject private var l10n: AppLocalization

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t("ios.local_mode.banner"))
                    .font(.footnote.weight(.semibold))
                Text(l10n.t("ios.local_mode.banner_action"))
                    .font(.caption2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.22))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct OfflineStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .imageScale(.medium)
            Text(message)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.22))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-status-banner")
    }
}

private struct PlaniniPromotionScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    let allowsLocalDemo: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(l10n.t("ios.promo.title"))
                        .font(.largeTitle.bold())
                    Text(l10n.t("ios.promo.subtitle"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 12) {
                    PromotionFeatureRow(
                        systemImage: "person.2.fill",
                        title: l10n.t("ios.promo.households_title"),
                        message: l10n.t("ios.promo.households_message")
                    )
                    PromotionFeatureRow(
                        systemImage: "bolt.fill",
                        title: l10n.t("ios.promo.fast_title"),
                        message: l10n.t("ios.promo.fast_message")
                    )
                    PromotionFeatureRow(
                        systemImage: "wifi.slash",
                        title: l10n.t("ios.promo.offline_title"),
                        message: l10n.t("ios.promo.offline_message")
                    )
                    PromotionFeatureRow(
                        systemImage: "arrow.triangle.2.circlepath.icloud.fill",
                        title: l10n.t("ios.promo.sync_title"),
                        message: l10n.t("ios.promo.sync_message")
                    )
                }

                if allowsLocalDemo {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            viewModel.startLocalDemo()
                        } label: {
                            Label(l10n.t("ios.promo.start_demo"), systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("promo-start-local-demo-button")

                        Text(l10n.t("ios.promo.demo_privacy"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(l10n.t("ios.promo.navigation_title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("planini-promo-screen")
    }
}

private struct PromotionFeatureRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct ReviewerOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    private enum Action {
        case addPasskey
        case registerAccount
    }

    let initialPasskeyAddInput: String
    let showsPasskeyAddSection: Bool

    @State private var passkeyAddInput: String
    @State private var registrationDisplayName = ""
    @State private var registrationEmail = ""
    @State private var busyAction: Action?
    @State private var addPasskeyErrorMessage: String?
    @State private var registrationErrorMessage: String?

    init(initialPasskeyAddInput: String, showsPasskeyAddSection: Bool) {
        self.initialPasskeyAddInput = initialPasskeyAddInput
        self.showsPasskeyAddSection = showsPasskeyAddSection
        _passkeyAddInput = State(initialValue: initialPasskeyAddInput)
    }

    var body: some View {
        NavigationStack {
            Form {
                if showsPasskeyAddSection {
                    Section(l10n.t("ios.onboarding.add_passkey")) {
                        TextField(l10n.t("ios.onboarding.passkey_add_link_or_key"), text: $passkeyAddInput, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("passkey-add-link-field")

                        Button {
                            closeKeyboard()
                            Task {
                                busyAction = .addPasskey
                                addPasskeyErrorMessage = nil
                                registrationErrorMessage = nil
                                viewModel.errorMessage = nil
                                let added = await viewModel.addPasskeyFromLinkInput(passkeyAddInput)
                                busyAction = nil
                                if added {
                                    AppHaptics.confirmation()
                                    dismiss()
                                } else {
                                    addPasskeyErrorMessage = viewModel.errorMessage
                                        ?? l10n.t("ios.onboarding.could_not_add_passkey")
                                }
                            }
                        } label: {
                            if busyAction == .addPasskey {
                                HStack {
                                    ProgressView()
                                    Text(l10n.t("ios.onboarding.adding_passkey"))
                                }
                            } else {
                                Label(l10n.t("ios.onboarding.add_passkey"), systemImage: "person.badge.key")
                            }
                        }
                        .disabled(busyAction != nil || trimmedPasskeyAddInput.isEmpty)
                        .accessibilityIdentifier("passkey-add-submit-button")

                        if let addPasskeyErrorMessage, addPasskeyErrorMessage.isEmpty == false {
                            Label(addPasskeyErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("passkey-add-error")
                        }
                    }
                }

                Section(l10n.t("ios.onboarding.create_account")) {
                    if viewModel.isLocalMode {
                        Label(
                            l10n.t("ios.local_mode.sync_explainer"),
                            systemImage: "arrow.triangle.2.circlepath.icloud"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("local-mode-sync-explainer")
                    }

                    TextField(l10n.t("ios.item.name"), text: $registrationDisplayName)
                        .textContentType(.name)
                        .disabled(canRetryLocalSync)
                        .accessibilityIdentifier("registration-display-name-field")

                    TextField(l10n.t("ios.onboarding.email"), text: $registrationEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .disabled(canRetryLocalSync)
                        .accessibilityIdentifier("registration-email-field")

                    Button {
                        closeKeyboard()
                        Task {
                            busyAction = .registerAccount
                            addPasskeyErrorMessage = nil
                            registrationErrorMessage = nil
                            viewModel.errorMessage = nil
                            let created = await viewModel.registerAccount(
                                displayName: registrationDisplayName,
                                email: registrationEmail
                            )
                            busyAction = nil
                            if created {
                                AppHaptics.confirmation()
                                dismiss()
                            } else {
                                registrationErrorMessage = viewModel.errorMessage
                                    ?? l10n.t("ios.onboarding.could_not_create_account")
                            }
                        }
                    } label: {
                        if busyAction == .registerAccount {
                            HStack {
                                ProgressView()
                                Text(l10n.t("ios.onboarding.creating_account"))
                            }
                        } else {
                            Label(
                                l10n.t(
                                    canRetryLocalSync
                                        ? "ios.local_mode.retry_sync"
                                        : viewModel.isLocalMode
                                            ? "ios.local_mode.create_and_sync"
                                            : "ios.onboarding.create_account"
                                ),
                                systemImage: "person.crop.circle.badge.plus"
                            )
                        }
                    }
                    .disabled(
                        busyAction != nil
                            || (canRetryLocalSync == false && (trimmedName.isEmpty || trimmedEmail.isEmpty))
                    )
                    .accessibilityIdentifier("registration-submit-button")

                    if let registrationErrorMessage, registrationErrorMessage.isEmpty == false {
                        Label(registrationErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("registration-error")
                    }
                }

                if let message = viewModel.reviewerOnboardingMessage, message.isEmpty == false {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(
                l10n.t(showsPasskeyAddSection ? "ios.onboarding.sign_in_help" : "ios.onboarding.create_account")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("reviewer-onboarding-cancel-button")
                }
            }
        }
        .onChange(of: initialPasskeyAddInput) { newValue in
            passkeyAddInput = newValue
        }
        .accessibilityIdentifier(
            showsPasskeyAddSection ? "reviewer-onboarding-sheet" : "account-registration-sheet"
        )
    }

    private var trimmedPasskeyAddInput: String {
        passkeyAddInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        registrationDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        registrationEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRetryLocalSync: Bool {
        viewModel.isLocalMode && viewModel.authToken?.isEmpty == false
    }

    private func closeKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

private struct FavoriteListTab: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    @Binding var selectedTab: AppTab
    let onListSwitch: (UUID) -> Void

    var body: some View {
        Group {
            if let favoriteList = viewModel.favoriteList {
                ListDetailScreen(listID: favoriteList.id, showsFavoriteButton: false, onListSwitch: onListSwitch)
            } else {
                VStack(spacing: 0) {
                    EmptyStateView(
                        title: l10n.t("ios.favorite.empty_title"),
                        systemImage: "star",
                        message: l10n.t(
                            viewModel.lists.isEmpty
                                ? "ios.favorite.no_lists_message"
                                : "ios.favorite.empty_message"
                        )
                    )

                    if viewModel.lists.isEmpty {
                        Button {
                            selectedTab = .settings
                        } label: {
                            Label(l10n.t("ios.favorite.open_settings"), systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("favorite-empty-open-settings-button")
                    } else {
                        Menu {
                            ForEach(viewModel.lists) { list in
                                Button {
                                    viewModel.setFavoriteList(id: list.id)
                                    Task { await viewModel.showFavoriteList() }
                                } label: {
                                    Label(list.name, systemImage: "star")
                                }
                                .accessibilityIdentifier("favorite-choice-\(list.id.uuidString)")
                            }
                        } label: {
                            Label(l10n.t("ios.favorite.choose_list"), systemImage: "star.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("favorite-empty-choose-list-menu")
                    }
                }
                .padding(.horizontal, 24)
                .navigationTitle(l10n.t("ios.tabs.favorite"))
            }
        }
    }
}

private struct ListsTab: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    @Binding var selectedTab: AppTab
    let onOpenPublicList: (PublicListReference) -> Void

    private var householdSections: [(name: String, lists: [GroceryListSummary])] {
        Dictionary(grouping: viewModel.lists, by: \.householdName)
            .map { key, value in
                (name: key, lists: value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if householdSections.isEmpty && viewModel.publicLists.isEmpty {
                VStack(spacing: 0) {
                    EmptyStateView(
                        title: l10n.t("ios.lists.empty_title"),
                        systemImage: "rectangle.grid.1x2",
                        message: l10n.t("ios.lists.empty_message")
                    )

                    Button {
                        selectedTab = .settings
                    } label: {
                        Label(l10n.t("ios.lists.open_settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("lists-empty-open-settings-button")
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(householdSections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.lists) { list in
                            NavigationLink(value: list.id) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name)
                                        if list.id == viewModel.favoriteListID {
                                            Label(l10n.t("ios.favorite.favorite_list"), systemImage: "star.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("list-row-\(list.name)")
                            .listRowBackground(rowBackground(for: list))
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    viewModel.setFavoriteList(id: list.id)
                                    selectedTab = .favorite
                                    Task { await viewModel.showFavoriteList() }
                                } label: {
                                    Label(l10n.t("ios.tabs.favorite"), systemImage: "star.fill")
                                }
                                .tint(.yellow)
                            }
                        }
                    }
                }


                if viewModel.publicLists.isEmpty == false {
                    Section(l10n.t("ios.public_lists.title")) {
                        RememberedPublicListRows(
                            references: viewModel.publicLists,
                            onOpen: onOpenPublicList,
                            onRemove: viewModel.removePublicList
                        )
                    }
                }
            }
        }
        .navigationTitle(l10n.t("ios.tabs.lists"))
    }

    private func rowBackground(for list: GroceryListSummary) -> Color {
        guard let accentColor = Color(hex: list.accentColorHex) else {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        return accentColor.opacity(0.10)
    }
}

private struct RememberedPublicListRows: View {
    @EnvironmentObject private var l10n: AppLocalization
    let references: [PublicListReference]
    let onOpen: (PublicListReference) -> Void
    let onRemove: (PublicListReference) -> Void

    var body: some View {
        ForEach(references) { reference in
            Button {
                onOpen(reference)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reference.name)
                            .foregroundStyle(.primary)
                        Text(status(for: reference))
                            .font(.caption)
                            .foregroundStyle(reference.isExpired() ? .red : .secondary)
                    }
                    Spacer()
                    if reference.isExpired() == false {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(reference.isExpired())
            .accessibilityIdentifier("public-list-row-\(reference.id.uuidString)")
            .swipeActions {
                Button(role: .destructive) {
                    onRemove(reference)
                } label: {
                    Label(l10n.t("common.remove"), systemImage: "trash")
                }
                .accessibilityIdentifier("remove-public-list-\(reference.id.uuidString)")
            }
        }
    }

    private func status(for reference: PublicListReference) -> String {
        if reference.isExpired() {
            return l10n.t("ios.public_lists.expired")
        }
        return l10n.t(
            "ios.public_lists.expires",
            ["date": reference.expiresAt.formatted(date: .abbreviated, time: .shortened)]
        )
    }
}

private struct SettingsTab: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettings
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    var body: some View {
        Form {
            Section(l10n.t("ios.settings.appearance")) {
                Picker(l10n.t("ios.settings.appearance"), selection: $appearanceSettings.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(appearanceModeTitle(mode))
                            .tag(mode)
                            .accessibilityIdentifier("settings-appearance-\(mode.rawValue)-option")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-appearance-picker")
            }

            Section {
                NavigationLink {
                    PlaniniPromotionScreen(allowsLocalDemo: false)
                } label: {
                    Label(l10n.t("ios.promo.explore"), systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings-promo-link")
            }

            Section(l10n.t("ios.settings.account")) {
                LabeledContent(l10n.t("settings.signed_in_as"), value: viewModel.displayName ?? l10n.t("ios.settings.unknown"))
                if let favoriteList = viewModel.favoriteList {
                    LabeledContent(l10n.t("ios.favorite.favorite_list"), value: favoriteList.name)
                }
                NavigationLink {
                    PasskeyManagementScreen()
                } label: {
                    Label(l10n.t("settings.your_passkeys"), systemImage: "person.badge.key")
                }
                .accessibilityIdentifier("settings-passkey-management-link")
                NavigationLink {
                    HouseholdManagementScreen()
                } label: {
                    Label(l10n.t("ios.households.settings_row"), systemImage: "house")
                }
                .accessibilityIdentifier("settings-household-management-link")
                Button(
                    l10n.t(viewModel.isLocalMode ? "ios.local_mode.exit" : "ios.settings.sign_out"),
                    role: .destructive
                ) {
                    viewModel.signOut()
                }
                .accessibilityIdentifier("settings-sign-out-button")
            }

            Section(l10n.t("settings.language")) {
                NavigationLink {
                    LanguageSettingsScreen()
                } label: {
                    LabeledContent(l10n.t("settings.language"), value: l10n.currentLanguageSummary())
                }
                .accessibilityIdentifier("settings-language-row")
            }

            Section(l10n.t("ios.settings.app")) {
                LabeledContent(
                    l10n.t("ios.settings.backend"),
                    value: viewModel.isLocalMode
                        ? l10n.t("ios.local_mode.storage")
                        : viewModel.backendDisplayName
                )
                LabeledContent(l10n.t("ios.settings.available_lists"), value: "\(viewModel.lists.count)")
                LabeledContent(l10n.t("ios.settings.visible_categories"), value: "\(viewModel.categories.count)")
            }
        }
        .navigationTitle(l10n.t("common.settings"))
        .accessibilityIdentifier("settings-screen")
    }

    private func appearanceModeTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return l10n.t("ios.settings.appearance_system")
        case .light:
            return l10n.t("ios.settings.appearance_light")
        case .dark:
            return l10n.t("ios.settings.appearance_dark")
        }
    }
}

private enum PasskeyManagementSheet: Identifiable {
    case add(suggestedName: String)
    case rename(PasskeyRecord)
    case delete(PasskeyRecord)

    var id: String {
        switch self {
        case .add:
            return "add"
        case let .rename(passkey):
            return "rename-\(passkey.id.uuidString)"
        case let .delete(passkey):
            return "delete-\(passkey.id.uuidString)"
        }
    }
}

private struct PasskeyManagementScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    @State private var activeSheet: PasskeyManagementSheet?
    @State private var successMessage: String?

    var body: some View {
        List {
            Section {
                if viewModel.isManagingPasskeys && viewModel.passkeys.isEmpty {
                    ProgressView(l10n.t("ios.passkeys.loading"))
                        .accessibilityIdentifier("passkey-loading-indicator")
                } else if viewModel.passkeys.isEmpty {
                    EmptyStateView(
                        title: l10n.t("settings.no_passkeys_title"),
                        systemImage: "person.badge.key",
                        message: l10n.t("settings.no_passkeys_body")
                    )
                    .accessibilityIdentifier("passkey-empty-state")
                } else {
                    ForEach(viewModel.passkeys) { passkey in
                        PasskeyManagementRow(
                            passkey: passkey,
                            canDelete: viewModel.passkeys.count > 1,
                            isBusy: viewModel.isManagingPasskeys,
                            onRename: {
                                successMessage = nil
                                activeSheet = .rename(passkey)
                            },
                            onDelete: {
                                successMessage = nil
                                activeSheet = .delete(passkey)
                            }
                        )
                    }
                }
            } header: {
                Text(l10n.t("settings.security"))
            } footer: {
                Text(l10n.t("settings.helper"))
            }

            Section {
                Button {
                    successMessage = nil
                    activeSheet = .add(
                        suggestedName: l10n.t(
                            "settings.suggested_name",
                            ["number": "\(viewModel.passkeys.count + 1)"]
                        )
                    )
                } label: {
                    Label(l10n.t("settings.add_another"), systemImage: "plus")
                }
                .disabled(viewModel.isManagingPasskeys)
                .accessibilityIdentifier("passkey-add-button")
            }

            if let errorMessage = viewModel.passkeyManagementErrorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("passkey-management-error")
                }
            }

            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("passkey-management-success")
                }
            }
        }
        .navigationTitle(l10n.t("settings.your_passkeys"))
        .accessibilityIdentifier("passkey-management-screen")
        .task {
            _ = await viewModel.loadPasskeys()
        }
        .refreshable {
            _ = await viewModel.loadPasskeys()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .add(suggestedName):
                PasskeyNameSheet(
                    title: l10n.t("settings.name_this_passkey"),
                    submitTitle: l10n.t("common.continue"),
                    initialName: suggestedName,
                    identifierPrefix: "passkey-add"
                ) { name in
                    let added = await viewModel.addPasskey(name: name)
                    if added {
                        successMessage = l10n.t("settings.added_success")
                    }
                    return added
                }
            case let .rename(passkey):
                PasskeyNameSheet(
                    title: l10n.t("settings.rename_this_passkey"),
                    submitTitle: l10n.t("settings.save_and_verify"),
                    initialName: passkey.name,
                    identifierPrefix: "passkey-rename"
                ) { name in
                    let renamed = await viewModel.renamePasskey(passkey, name: name)
                    if renamed {
                        successMessage = l10n.t("settings.renamed_success")
                    }
                    return renamed
                }
            case let .delete(passkey):
                PasskeyDeleteConfirmationSheet(passkey: passkey) {
                    let deleted = await viewModel.deletePasskey(passkey)
                    if deleted {
                        successMessage = l10n.t("settings.deleted_success")
                    }
                    return deleted
                }
            }
        }
    }
}

private struct PasskeyManagementRow: View {
    @EnvironmentObject private var l10n: AppLocalization

    let passkey: PasskeyRecord
    let canDelete: Bool
    let isBusy: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(passkey.name)
                        .font(.headline)
                        .accessibilityIdentifier(
                            "passkey-name-\(passkey.id.uuidString.lowercased())"
                        )
                    Text(
                        l10n.t(
                            "settings.added_on",
                            ["date": formattedDate(passkey.createdAt)]
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(lastUsedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "key")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    onRename()
                } label: {
                    Label(l10n.t("settings.rename"), systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                .disabled(isBusy)
                .accessibilityIdentifier("passkey-rename-\(passkey.id.uuidString.lowercased())")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(l10n.t("common.delete"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isBusy || canDelete == false)
                .accessibilityIdentifier("passkey-delete-\(passkey.id.uuidString.lowercased())")
            }

            if canDelete == false {
                Text(l10n.t("settings.delete_disabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("passkey-delete-disabled-help")
            }
        }
    }

    private var lastUsedText: String {
        guard let lastUsedAt = passkey.lastUsedAt else {
            return l10n.t("settings.never_used")
        }
        return l10n.t(
            "settings.last_used",
            ["date": formattedDate(lastUsedAt)]
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.effectiveLocale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct PasskeyNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    let title: String
    let submitTitle: String
    let identifierPrefix: String
    let onSubmit: (String) async -> Bool

    @State private var name: String

    init(
        title: String,
        submitTitle: String,
        initialName: String,
        identifierPrefix: String,
        onSubmit: @escaping (String) async -> Bool
    ) {
        self.title = title
        self.submitTitle = submitTitle
        self.identifierPrefix = identifierPrefix
        self.onSubmit = onSubmit
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(l10n.t("settings.passkey_name_placeholder"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("\(identifierPrefix)-name-field")

                    if isNameTooLong {
                        Text(l10n.t("ios.passkeys.name_too_long"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("\(identifierPrefix)-name-error")
                    }
                }

                if let errorMessage = viewModel.passkeyManagementErrorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("\(identifierPrefix)-error")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) {
                        dismiss()
                    }
                    .disabled(viewModel.isManagingPasskeys)
                    .accessibilityIdentifier("\(identifierPrefix)-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitTitle) {
                        closeKeyboard()
                        Task {
                            if await onSubmit(trimmedName) {
                                AppHaptics.confirmation()
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        viewModel.isManagingPasskeys
                            || trimmedName.isEmpty
                            || isNameTooLong
                    )
                    .accessibilityIdentifier("\(identifierPrefix)-submit-button")
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isManagingPasskeys)
        .accessibilityIdentifier("\(identifierPrefix)-name-sheet")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameTooLong: Bool {
        trimmedName.unicodeScalars.count > 120
    }

    private func closeKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

private struct PasskeyDeleteConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization

    let passkey: PasskeyRecord
    let onConfirm: () async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        l10n.t(
                            "settings.delete_help",
                            ["name": passkey.name]
                        )
                    )
                }

                if let errorMessage = viewModel.passkeyManagementErrorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("passkey-delete-confirmation-error")
                    }
                }

                Section {
                    Button(l10n.t("settings.continue_to_verification"), role: .destructive) {
                        Task {
                            if await onConfirm() {
                                AppHaptics.confirmation()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isManagingPasskeys)
                    .accessibilityIdentifier("passkey-delete-confirm-button")
                }
            }
            .navigationTitle(l10n.t("settings.delete_this_passkey"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) {
                        dismiss()
                    }
                    .disabled(viewModel.isManagingPasskeys)
                    .accessibilityIdentifier("passkey-delete-cancel-button")
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isManagingPasskeys)
        .accessibilityIdentifier("passkey-delete-confirmation-sheet")
    }
}

private struct LanguageSettingsScreen: View {
    @EnvironmentObject private var l10n: AppLocalization

    var body: some View {
        Form {
            Section(l10n.t("settings.current_language")) {
                LabeledContent(l10n.t("settings.current_language"), value: l10n.currentLanguageSummary())
                Text(l10n.t("ios.settings.language_helper"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.t("settings.choose_language")) {
                languageOption(id: AppLocalization.systemPreferenceID)
                ForEach(l10n.availableLocaleIDs, id: \.self) { locale in
                    languageOption(id: locale)
                }
            }
        }
        .navigationTitle(l10n.t("settings.language"))
        .accessibilityIdentifier("language-settings-screen")
    }

    private func languageOption(id: String) -> some View {
        Button {
            l10n.setPreference(id: id)
        } label: {
            HStack {
                Text(l10n.languagePreferenceTitle(for: id))
                Spacer()
                if l10n.preferenceID == id {
                    Image(systemName: "checkmark")
                        .accessibilityLabel(l10n.t("ios.settings.language_option_selected"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("language-option-\(id)")
        .accessibilityValue(
            l10n.preferenceID == id ? l10n.t("ios.settings.language_option_selected") : ""
        )
    }
}

private struct HouseholdManagementScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    @State private var showingNewHousehold = false

    var body: some View {
        List {
            Section(l10n.t("ios.households.title")) {
                if viewModel.sortedHouseholdsForManagement.isEmpty {
                    EmptyStateView(
                        title: l10n.t("ios.households.empty_title"),
                        systemImage: "house",
                        message: l10n.t("ios.households.empty_message")
                    )
                } else {
                    ForEach(viewModel.sortedHouseholdsForManagement) { household in
                        NavigationLink {
                            HouseholdDetailManagementScreen(householdID: household.id)
                        } label: {
                            HouseholdManagementRow(
                                household: household,
                                listCount: viewModel.lists.filter { $0.householdID == household.id }.count
                            )
                        }
                        .accessibilityIdentifier("household-row-\(household.name)")
                    }
                }
            }

            Section {
                Button {
                    showingNewHousehold = true
                } label: {
                    Label(l10n.t("ios.households.new_household"), systemImage: "house.badge.plus")
                }
                .accessibilityIdentifier("new-household-button")
            }
        }
        .navigationTitle(l10n.t("ios.households.title"))
        .refreshable {
            try? await viewModel.reloadAllData()
        }
        .task {
            try? await viewModel.reloadAllData()
        }
        .sheet(isPresented: $showingNewHousehold) {
            CreateNamedResourceSheet(
                title: l10n.t("ios.households.new_household"),
                placeholder: l10n.t("ios.households.household_name"),
                saveTitle: l10n.t("common.create"),
                fieldIdentifier: "new-household-name-field",
                saveIdentifier: "new-household-save-button"
            ) { name in
                await viewModel.createHousehold(name: name) != nil
            }
        }
        .accessibilityIdentifier("household-management-screen")
    }
}

private struct HouseholdManagementRow: View {
    @EnvironmentObject private var l10n: AppLocalization
    let household: HouseholdSummary
    let listCount: Int

    private var listCountText: String {
        l10n.t(
            listCount == 1 ? "ios.households.list_count_one" : "ios.households.list_count_other",
            ["count": "\(listCount)"]
        )
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(household.name)
                Text(listCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "house")
        }
    }
}

private struct HouseholdDetailManagementScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let householdID: UUID

    @State private var showingNewList = false
    @State private var showingInviteSheet = false

    private var household: HouseholdSummary? {
        viewModel.households.first { $0.id == householdID }
    }

    private var householdLists: [GroceryListSummary] {
        viewModel.lists
            .filter { $0.householdID == householdID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section(l10n.t("ios.households.lists_section")) {
                if householdLists.isEmpty {
                    EmptyStateView(
                        title: l10n.t("ios.households.no_lists_title"),
                        systemImage: "list.bullet.rectangle",
                        message: l10n.t("ios.households.no_lists_message")
                    )
                } else {
                    ForEach(householdLists) { list in
                        NavigationLink {
                            ListDetailScreen(listID: list.id, showsFavoriteButton: true)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "list.bullet.rectangle")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name)
                                    if list.id == viewModel.favoriteListID {
                                        Label(l10n.t("ios.favorite.favorite_list"), systemImage: "star.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("managed-list-row-\(list.name)")
                        .listRowBackground(rowBackground(for: list))
                    }
                }

                Button {
                    showingNewList = true
                } label: {
                    Label(l10n.t("ios.households.new_list"), systemImage: "plus")
                }
                .accessibilityIdentifier("new-household-list-button")
            }

            Section(l10n.t("ios.households.invites_section")) {
                Button {
                    if viewModel.isLocalMode {
                        viewModel.requestLocalModeAccountCreation()
                    } else {
                        showingInviteSheet = true
                    }
                } label: {
                    Label(l10n.t("ios.households.create_invite_link"), systemImage: "link.badge.plus")
                }
                .accessibilityIdentifier("open-household-invite-sheet-button")
            }
        }
        .navigationTitle(household?.name ?? l10n.t("ios.households.fallback_title"))
        .sheet(isPresented: $showingNewList) {
            CreateNamedResourceSheet(
                title: l10n.t("ios.households.new_list"),
                placeholder: l10n.t("ios.households.list_name"),
                saveTitle: l10n.t("common.create"),
                fieldIdentifier: "new-household-list-name-field",
                saveIdentifier: "new-household-list-save-button"
            ) { name in
                await viewModel.createList(householdID: householdID, name: name) != nil
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            HouseholdInviteSheet(householdID: householdID)
        }
        .accessibilityIdentifier("household-detail-management-screen")
    }

    private func rowBackground(for list: GroceryListSummary) -> Color {
        guard let accentColor = Color(hex: list.accentColorHex) else {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        return accentColor.opacity(0.10)
    }
}

private struct HouseholdInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let householdID: UUID

    @State private var invite: HouseholdInviteLink?
    @State private var isCreatingInvite = false
    @State private var inviteMode = "time"
    @State private var inviteHours = 24
    @State private var inviteMaxUses = 5

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(l10n.t("ios.households.invite_validity"), selection: $inviteMode) {
                        Text(l10n.t("ios.households.invite_time_limited"))
                            .tag("time")
                            .accessibilityIdentifier("household-invite-mode-time")
                        Text(l10n.t("ios.households.invite_usage_limited"))
                            .tag("uses")
                            .accessibilityIdentifier("household-invite-mode-uses")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("household-invite-mode-picker")
                }

                Section {
                    if inviteMode == "time" {
                        VStack(alignment: .leading, spacing: 12) {
                            Stepper(
                                l10n.t("ios.households.invite_hours_valid", ["count": "\(inviteHours)"]),
                                value: $inviteHours,
                                in: 1...720
                            )
                            .accessibilityIdentifier("household-invite-hours-stepper")

                            Text(formattedInviteHours(inviteHours))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("household-invite-duration-label")

                            HStack {
                                Button(l10n.t("ios.households.invite_quick_1_day")) { inviteHours = 24 }
                                    .accessibilityIdentifier("household-invite-quick-1-day-button")
                                Button(l10n.t("ios.households.invite_quick_3_days")) { inviteHours = 72 }
                                    .accessibilityIdentifier("household-invite-quick-3-days-button")
                                Button(l10n.t("ios.households.invite_quick_1_week")) { inviteHours = 168 }
                                    .accessibilityIdentifier("household-invite-quick-1-week-button")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Stepper(
                            l10n.t("ios.households.invite_max_uses", ["count": "\(inviteMaxUses)"]),
                            value: $inviteMaxUses,
                            in: 1...100
                        )
                        .accessibilityIdentifier("household-invite-max-uses-stepper")
                    }
                }

                Section {
                    Button {
                        Task { await createInvite() }
                    } label: {
                        if isCreatingInvite {
                            HStack {
                                ProgressView()
                                Text(l10n.t("ios.households.creating_invite"))
                            }
                        } else {
                            Label(l10n.t("ios.households.create_invite_link"), systemImage: "link.badge.plus")
                        }
                    }
                    .disabled(isCreatingInvite)
                    .accessibilityIdentifier("create-household-invite-button")
                }

                if let invite {
                    Section {
                        Text(invite.inviteURL)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("household-invite-url-value")

                        if let expiresAtText = formattedExpiration(for: invite) {
                            Text(l10n.t("ios.households.expires_at", ["date": expiresAtText]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("household-invite-expiration")
                        } else if let maxUsesText = formattedMaxUses(for: invite) {
                            Text(maxUsesText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("household-invite-expiration")
                        }

                        HStack {
                            Button {
                                copyInvite(invite.inviteURL)
                            } label: {
                                Label(l10n.t("common.copy"), systemImage: "doc.on.doc")
                            }
                            .accessibilityIdentifier("copy-household-invite-button")

                            ShareLink(item: invite.inviteURL) {
                                Label(l10n.t("common.share"), systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier("share-household-invite-button")
                        }
                    }
                }
            }
            .navigationTitle(l10n.t("ios.households.create_invite_link"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("close-household-invite-sheet-button")
                }
            }
            .accessibilityIdentifier("household-invite-sheet")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreatingInvite)
    }

    @MainActor
    private func createInvite() async {
        guard isCreatingInvite == false else { return }
        isCreatingInvite = true
        defer { isCreatingInvite = false }

        let maxUses = inviteMode == "uses" ? inviteMaxUses : nil
        let expiresInHours = inviteMode == "uses" ? nil : inviteHours
        if let createdInvite = await viewModel.createInvite(
            householdID: householdID,
            expiresInHours: expiresInHours,
            maxUses: maxUses
        ) {
            invite = createdInvite
            AppHaptics.confirmation()
        }
    }

    private func formattedExpiration(for invite: HouseholdInviteLink) -> String? {
        guard let expiresAt = invite.expiresAt else { return nil }
        return inviteExpirationFormatter.string(from: expiresAt)
    }

    private func formattedMaxUses(for invite: HouseholdInviteLink) -> String? {
        guard let maxUses = invite.maxUses else { return nil }
        return l10n.t("ios.households.invite_max_uses", ["count": "\(maxUses)"])
    }

    private func formattedInviteHours(_ hours: Int) -> String {
        if hours % 24 == 0 {
            let days = hours / 24
            let key = days == 1 ? "ios.households.invite_duration_day_one" : "ios.households.invite_duration_days"
            return l10n.t(key, ["count": "\(days)"])
        }
        let key = hours == 1 ? "ios.households.invite_duration_hour_one" : "ios.households.invite_duration_hours"
        return l10n.t(key, ["count": "\(hours)"])
    }

    private func copyInvite(_ inviteURL: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = inviteURL
        AppHaptics.confirmation()
        #endif
    }
}

private let inviteExpirationFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private struct CreateNamedResourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: AppLocalization

    let title: String
    let placeholder: String
    let saveTitle: String
    let fieldIdentifier: String
    let saveIdentifier: String
    let onSave: (String) async -> Bool

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier(fieldIdentifier)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("create-resource-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) { save() }
                        .disabled(canSave == false)
                        .accessibilityIdentifier(saveIdentifier)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            isNameFocused = true
        }
    }

    private var canSave: Bool {
        isSaving == false && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil

        Task {
            let saved = await onSave(name)
            if saved {
                AppHaptics.confirmation()
                dismiss()
            } else {
                isSaving = false
                errorMessage = l10n.t("ios.households.save_failed")
            }
        }
    }
}

private struct ListDetailScreen: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let listID: UUID
    let showsFavoriteButton: Bool
    let onListSwitch: ((UUID) -> Void)?
    let publicList: PublicListReference?

    @State private var displayedListID: UUID
    @State private var editingItem: GroceryItemRecord?
    @State private var addItemPresentation: AddItemPresentation?
    @State private var highlightedItemID: UUID?
    @State private var moveNotice: ItemMoveNotice?
    @State private var moveNoticeDismissTask: Task<Void, Never>?
    @State private var undoToast: ListUndoToast?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var isRunningUndo = false
    @State private var showingListSettings = false
    @State private var targetedDropSectionID: String?
    @State private var saleClock = Date()

    init(
        listID: UUID,
        showsFavoriteButton: Bool,
        onListSwitch: ((UUID) -> Void)? = nil,
        publicList: PublicListReference? = nil
    ) {
        self.listID = listID
        self.showsFavoriteButton = showsFavoriteButton
        self.onListSwitch = onListSwitch
        self.publicList = publicList
        _displayedListID = State(initialValue: listID)
    }

    private var currentList: GroceryListSummary? {
        if let publicList {
            return GroceryListSummary(
                id: publicList.id,
                householdID: publicList.householdID,
                householdName: l10n.t("ios.public_lists.shared_list"),
                name: publicList.name,
                archived: false,
                accentColorHex: publicList.accentColorHex
            )
        }
        return viewModel.lists.first { $0.id == displayedListID }
    }

    private var listBackground: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if let accentColor = Color(hex: currentList?.accentColorHex) {
                accentColor.opacity(0.10)
            }
        }
    }

    private var accentColorAccessibilityValue: String {
        guard
            let accentColorHex = currentList?.accentColorHex,
            let option = ListAccentColorOption.option(for: accentColorHex)
        else {
            return l10n.t("ios.list_settings.accent_none")
        }
        return l10n.t(
            "ios.list_settings.accent_selected",
            ["color": l10n.t(option.localizationKey)]
        )
    }

    private var listSwitchSections: [(name: String, lists: [GroceryListSummary])] {
        Dictionary(grouping: viewModel.lists, by: \.householdName)
            .map { key, value in
                (name: key, lists: value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displaySections: [ListDisplaySection] {
        var sections = currentSections.map(ListDisplaySection.init)
        guard let moveNotice else { return sections }

        let noticeSection = displaySection(for: moveNotice)
        if let index = sections.firstIndex(where: { $0.id == noticeSection.id }) {
            sections[index].rows.append(.moveNotice(moveNotice))
            sections[index].rows.sort(by: compareRows)
            return sections
        }

        sections.insert(noticeSection, at: insertionIndex(for: noticeSection, in: sections))
        return sections
    }

    private var currentSections: [GroceryItemSection] {
        GroceryItemSectionBuilder.build(
            items: viewModel.items,
            categories: viewModel.categories,
            categoryOrder: viewModel.categoryOrder,
            now: saleClock
        )
    }

    private var nextSaleBoundary: Date? {
        viewModel.items
            .flatMap { [$0.saleStartsAt, $0.saleEndsAt].compactMap { $0 } }
            .filter { $0 > saleClock }
            .min()
    }

    private var visibleRowIDs: [String] {
        displaySections.flatMap { section in
            section.rows.map(\.id)
        }
    }

    var body: some View {
        List {
            if let list = currentList {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(list.name)
                                .font(.headline)
                                .accessibilityIdentifier("list-detail-title")
                            Spacer(minLength: 8)
                            Text(
                                l10n.t(
                                    "ios.list.item_summary",
                                    [
                                        "items": viewModel.items.count,
                                        "sections": currentSections.count,
                                    ]
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(list.householdName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(CompactListLayout.summaryInsets)
                }
            }

            if displaySections.isEmpty {
                Section {
                    EmptyStateView(
                        title: l10n.t("ios.list.empty_title"),
                        systemImage: "basket",
                        message: l10n.t("ios.list.empty_message")
                    )
                }
            } else {
                ForEach(displaySections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            switch row {
                            case let .item(item):
                                ItemRow(item: item, isOnSaleProjection: section.kind == .onSale) {
                                    editingItem = item
                                } onDelete: {
                                    deleteItem(item)
                                } onUndoableAction: { message, action in
                                    showUndoToast(message: message, action: action)
                                }
                                .background(rowHighlight(for: item))
                                .listRowInsets(CompactListLayout.rowInsets)
                            case let .moveNotice(notice):
                                ItemMoveNoticeRow(notice: notice) {
                                    undoMove(notice)
                                }
                                .opacity(notice.isExpiring ? 0 : 1)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .listRowInsets(CompactListLayout.rowInsets)
                            }
                        }
                    } header: {
                        SectionHeader(
                            section: section,
                            title: localizedTitle(for: section),
                            targetedDropSectionID: $targetedDropSectionID
                        ) { categoryID in
                            addItemPresentation = AddItemPresentation(categoryID: categoryID)
                        } onDropItem: { itemIDText, categoryID in
                            moveItem(itemIDText: itemIDText, toCategory: categoryID)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .compactListSectionSpacing()
        .scrollContentBackground(.hidden)
        .background {
            listBackground.ignoresSafeArea()
        }
        .navigationTitle(currentList?.name ?? l10n.t("ios.list.fallback_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if publicList == nil && viewModel.lists.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(listSwitchSections, id: \.name) { section in
                            Section(section.name) {
                                ForEach(section.lists) { list in
                                    Button {
                                        switchList(to: list.id)
                                    } label: {
                                        if list.id == displayedListID {
                                            Label(list.name, systemImage: "checkmark")
                                        } else {
                                            Text(list.name)
                                        }
                                    }
                                    .accessibilityIdentifier("switch-list-\(list.name)")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier("list-switcher-button")
                    .accessibilityLabel("Switch list")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addItemPresentation = AddItemPresentation(categoryID: nil)
                } label: {
                    Label(l10n.t("ios.item.add_title"), systemImage: "plus")
                }
                .accessibilityIdentifier("add-item-button")
            }

            if publicList == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingListSettings = true
                    } label: {
                        Label("List settings", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("list-settings-button")
                    .disabled(currentList == nil)
                }
            }

            if showsFavoriteButton, let currentList {
                ToolbarItem(placement: .topBarTrailing) {
                    let isFavorite = currentList.id == viewModel.favoriteListID
                    Button {
                        viewModel.toggleFavoriteList(id: currentList.id)
                    } label: {
                        Label(
                            isFavorite ? l10n.t("ios.favorite.unfavorite") : l10n.t("ios.tabs.favorite"),
                            systemImage: isFavorite ? "star.fill" : "star"
                        )
                    }
                    .accessibilityIdentifier("favorite-list-button")
                }
            }
        }
        .task(id: displayedListID) {
            if publicList == nil {
                await viewModel.selectList(id: displayedListID)
            }
        }
        .task(id: nextSaleBoundary) {
            guard let nextSaleBoundary else { return }
            while true {
                let delay = nextSaleBoundary.timeIntervalSinceNow
                guard delay > 0 else { break }
                do {
                    let sleepSeconds = min(delay, 24 * 60 * 60)
                    try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                } catch {
                    return
                }
            }
            saleClock = Date()
        }
        .onChange(of: listID) { newValue in
            displayedListID = newValue
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(
                item: item,
                onUndoableAction: { message, action in
                    showUndoToast(message: message, action: action)
                },
                onMoved: { notice in
                    showMoveNotice(notice)
                }
            )
        }
        .sheet(item: $addItemPresentation) { presentation in
            AddItemSheet(initialCategoryID: presentation.categoryID) { message, action in
                showUndoToast(message: message, action: action)
            }
        }
        .overlay(alignment: .bottom) {
            if let undoToast {
                FloatingUndoToastView(
                    toast: undoToast,
                    isBusy: isRunningUndo
                ) {
                    runUndoToast(undoToast)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingListSettings) {
            ListSettingsSheet(listID: displayedListID)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: visibleRowIDs)
        .animation(.easeInOut(duration: 0.22), value: highlightedItemID)
        .animation(.easeInOut(duration: 0.22), value: moveNotice)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: undoToast?.id)
        .onDisappear {
            moveNoticeDismissTask?.cancel()
            undoDismissTask?.cancel()
        }
        .accessibilityIdentifier("list-detail-screen")
        .accessibilityValue(accentColorAccessibilityValue)
    }

    private func displaySection(for notice: ItemMoveNotice) -> ListDisplaySection {
        let sourceItem = notice.sourceItem
        let kind: GroceryItemSectionKind
        let title: String
        let colorHex: String?

        if sourceItem.checked {
            kind = .checked
            title = l10n.t("ios.list.checked_off")
            colorHex = nil
        } else if sourceItem.isHiddenForLater() {
            kind = .hidden
            title = l10n.t("ios.list.hidden_for_later")
            colorHex = nil
        } else if let categoryID = sourceItem.categoryID,
            let category = viewModel.categories.first(where: { $0.id == categoryID })
        {
            kind = .category(categoryID)
            title = category.name
            colorHex = category.colorHex
        } else {
            kind = .uncategorized
            title = l10n.t("ios.list.uncategorized")
            colorHex = nil
        }

        return ListDisplaySection(
            id: sectionID(for: kind),
            title: title,
            colorHex: colorHex,
            kind: kind,
            rows: [.moveNotice(notice)]
        )
    }

    private func sectionID(for kind: GroceryItemSectionKind) -> String {
        switch kind {
        case .onSale:
            return "on-sale"
        case .uncategorized:
            return "uncategorized"
        case let .category(categoryID):
            return "category-\(categoryID.uuidString)"
        case .hidden:
            return "hidden"
        case .checked:
            return "checked"
        }
    }

    private func insertionIndex(for section: ListDisplaySection, in sections: [ListDisplaySection]) -> Int {
        switch section.kind {
        case .onSale:
            return 0
        case .uncategorized:
            return sections.firstIndex { $0.kind != .onSale } ?? sections.endIndex
        case .hidden:
            return sections.firstIndex { $0.kind == .checked } ?? sections.endIndex
        case .checked:
            return sections.endIndex
        case let .category(categoryID):
            let sortOrder = viewModel.categoryOrder.first { $0.categoryID == categoryID }?.sortOrder ?? Int.max
            return sections.firstIndex { existing in
                switch existing.kind {
                case .hidden, .checked:
                    return true
                case let .category(existingID):
                    let existingSortOrder = viewModel.categoryOrder.first { $0.categoryID == existingID }?.sortOrder ?? Int.max
                    return existingSortOrder > sortOrder
                case .onSale, .uncategorized:
                    return false
                }
            } ?? sections.endIndex
        }
    }

    private func compareRows(_ left: ListRowContent, _ right: ListRowContent) -> Bool {
        if left.sortOrder != right.sortOrder {
            return left.sortOrder < right.sortOrder
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private func showMoveNotice(_ notice: ItemMoveNotice) {
        moveNoticeDismissTask?.cancel()
        var activeNotice = notice
        activeNotice.isExpiring = false
        moveNotice = activeNotice

        moveNoticeDismissTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                moveNotice?.isExpiring = true
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                moveNotice = nil
            }
        }
    }

    @discardableResult
    private func showUndoToast(message: String, action: @escaping ListUndoAction) -> UUID {
        undoDismissTask?.cancel()
        let toast = ListUndoToast(message: message, action: action)
        undoToast = toast
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard undoToast?.id == toast.id else { return }
                undoToast = nil
            }
        }
        return toast.id
    }

    private func deleteItem(_ item: GroceryItemRecord) {
        let deleteTask = Task { @MainActor in
            await viewModel.delete(item: item)
        }
        let toastID = showUndoToast(
            message: l10n.t("ios.undo.item_deleted_named", ["name": item.name]),
            action: {
                guard await deleteTask.value else { return false }
                return await viewModel.restoreDeleted(item: item)
            }
        )

        Task { @MainActor in
            if await deleteTask.value {
                AppHaptics.destructiveAction()
            } else {
                undoDismissTask?.cancel()
                if undoToast?.id == toastID {
                    undoToast = nil
                }
            }
        }
    }

    private func undoMove(_ notice: ItemMoveNotice) {
        moveNoticeDismissTask?.cancel()
        Task {
            let restoredItem = await viewModel.move(
                item: notice.movedItem,
                to: notice.sourceListID,
                payload: GroceryItemEditPayload(item: notice.movedItem)
            )
            await MainActor.run {
                guard let restoredItem else {
                    var failedNotice = notice
                    failedNotice.isExpiring = false
                    failedNotice.restoreErrorMessage = l10n.t("ios.item.move_undo_failed")
                    moveNotice = failedNotice
                    return
                }

                AppHaptics.confirmation()
                moveNotice = nil
                highlightedItemID = restoredItem.id
            }
        }
    }

    private func moveItem(itemIDText: String, toCategory categoryID: UUID?) {
        guard
            let itemID = UUID(uuidString: itemIDText),
            let item = viewModel.items.first(where: { $0.id == itemID }),
            item.categoryID != categoryID
        else {
            return
        }

        let previousPayload = GroceryItemEditPayload(item: item)
        var nextPayload = previousPayload
        nextPayload.categoryID = categoryID
        let categoryName = categoryID.flatMap { id in
            viewModel.categories.first { $0.id == id }?.name
        } ?? l10n.t("ios.list.uncategorized")

        Task { @MainActor in
            let saved = await viewModel.saveEdit(item: item, payload: nextPayload)
            guard saved else { return }
            AppHaptics.itemDrop()
            highlightedItemID = item.id
            onItemMovedToCategory(item: item, categoryName: categoryName, previousPayload: previousPayload)
        }
    }

    private func onItemMovedToCategory(
        item: GroceryItemRecord,
        categoryName: String,
        previousPayload: GroceryItemEditPayload
    ) {
        showUndoToast(
            message: l10n.t(
                "ios.undo.item_moved_to_category_named",
                ["name": item.name, "category": categoryName]
            ),
            action: {
                await viewModel.saveEdit(item: item, payload: previousPayload)
            }
        )
    }

    private func rowHighlight(for item: GroceryItemRecord) -> Color {
        if item.id == highlightedItemID {
            return Color.accentColor.opacity(0.16)
        }
        return item.isOnSale() ? Color.orange.opacity(0.14) : Color.clear
    }

    private func runUndoToast(_ toast: ListUndoToast) {
        guard isRunningUndo == false else { return }
        isRunningUndo = true
        undoDismissTask?.cancel()
        Task {
            let didUndo = await toast.action()
            if didUndo {
                AppHaptics.confirmation()
            }
            if undoToast?.id == toast.id {
                undoToast = nil
            }
            isRunningUndo = false
        }
    }

    private func localizedTitle(for section: ListDisplaySection) -> String {
        switch section.kind {
        case .onSale:
            return l10n.t("ios.list.on_sale")
        case .uncategorized:
            return l10n.t("ios.list.uncategorized")
        case .hidden:
            return l10n.t("ios.list.hidden_for_later")
        case .checked:
            return l10n.t("ios.list.checked_off")
        case .category:
            return section.title
        }
    }

    private func switchList(to listID: UUID) {
        guard displayedListID != listID else { return }
        if let onListSwitch {
            onListSwitch(listID)
            return
        }
        displayedListID = listID
        Task { await viewModel.selectList(id: listID) }
    }
}

private struct ListSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let listID: UUID

    @State private var name = ""
    @State private var isSavingName = false
    @State private var selectedAccentColorHex: String?
    @State private var isSavingAccentColor = false
    @State private var saveState: ListSettingsSaveState = .saved
    @State private var nameSaveTask: Task<Void, Never>?
    @State private var busyCategoryID: UUID?
    @State private var draggedCategoryID: UUID?
    @State private var categoryDragLastTargetID: UUID?
    @State private var orderedCategories: [GroceryCategorySummary] = []
    @State private var pendingDisable: CategoryDisableConfirmation?
    @FocusState private var focusedField: ListSettingsFocusedField?

    private var currentList: GroceryListSummary? {
        viewModel.lists.first { $0.id == listID }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameNeedsSave: Bool {
        guard let currentList else { return false }
        return trimmedName.isEmpty == false && trimmedName != currentList.name
    }

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("List settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Label(saveState.title, systemImage: saveState.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(saveState.tint)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("list-settings-save-state")
                            .accessibilityLabel(saveState.title)
                            .accessibilityRemoveTraits(.isButton)
                            .allowsHitTesting(false)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Label(l10n.t("common.done"), systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("list-settings-done-button")
                    }
                }
        }
        .onAppear {
            syncName()
            syncAccentColor()
            syncOrderedCategories()
            syncCategoryOrderSaveState(viewModel.categoryOrderBackgroundSaveState)
        }
        .onChange(of: currentList?.name ?? "") { _ in syncName() }
        .onChange(of: currentList?.accentColorHex ?? "") { _ in syncAccentColor() }
        .onChange(of: name) { _ in scheduleNameAutosave() }
        .onChange(of: viewModel.categoriesForSettings.map(\.id)) { _ in syncOrderedCategories() }
        .onChange(of: viewModel.categoryOrderBackgroundSaveState) { newValue in
            syncCategoryOrderSaveState(newValue)
        }
        .onChange(of: focusedField) { newValue in
            if newValue != .name {
                saveNameNow()
            }
        }
        .onDisappear {
            nameSaveTask?.cancel()
            if nameNeedsSave {
                saveNameNow()
            }
        }
        .alert(item: $pendingDisable) { request in
            Alert(
                title: Text("Disable \(request.category.name)?"),
                message: Text(disableMessage(for: request)),
                primaryButton: .destructive(Text("Disable category")) {
                    runCategoryToggle(categoryID: request.category.id, disabled: true)
                },
                secondaryButton: .cancel()
            )
        }
        .accessibilityIdentifier("list-settings-sheet")
    }

    private var settingsForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                listNameSection
                listAccentColorSection
                categoriesSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var listNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("List name")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("List name", text: $name)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit(saveNameNow)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("list-name-field")
        }
    }

    private var listAccentColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("ios.list_settings.accent_title"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(ListAccentColorOption.all) { option in
                    accentColorButton(option)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(l10n.t("ios.list_settings.accent_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func accentColorButton(_ option: ListAccentColorOption) -> some View {
        let isSelected = ListAccentColorOption.option(for: selectedAccentColorHex) == option

        return Button {
            saveAccentColor(option.hex)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        Color(hex: option.hex)
                            ?? Color(uiColor: .tertiarySystemGroupedBackground)
                    )

                if option.hex == nil {
                    Image(systemName: "circle.slash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                }

                Circle()
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSavingAccentColor)
        .accessibilityIdentifier("list-accent-color-\(option.id)")
        .accessibilityLabel(l10n.t(option.localizationKey))
        .accessibilityValue(
            isSelected ? l10n.t("ios.list_settings.accent_selection_selected") : ""
        )
    }

    private func syncAccentColor() {
        guard isSavingAccentColor == false else { return }
        selectedAccentColorHex = currentList?.accentColorHex
    }

    private func saveAccentColor(_ accentColorHex: String?) {
        guard
            isSavingAccentColor == false,
            ListAccentColorOption.option(for: selectedAccentColorHex)
                != ListAccentColorOption.option(for: accentColorHex)
        else {
            return
        }

        selectedAccentColorHex = accentColorHex
        isSavingAccentColor = true
        saveState = .saving
        Task { @MainActor in
            let saved = await viewModel.updateListAccentColor(
                id: listID,
                accentColorHex: accentColorHex
            )
            isSavingAccentColor = false
            if saved {
                syncAccentColor()
                saveState = .saved
            } else {
                syncAccentColor()
                saveState = .failed
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if orderedCategories.isEmpty {
                    Label("No categories available", systemImage: "tray")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(orderedCategories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category: category)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [.text],
                                delegate: CategoryReorderDropDelegate(
                                    targetCategoryID: category.id,
                                    draggedCategoryID: $draggedCategoryID,
                                    lastTargetCategoryID: $categoryDragLastTargetID,
                                    orderedCategories: $orderedCategories,
                                    onOrderChanged: saveCategoryOrder
                                )
                            )
                        if index < orderedCategories.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Disabled categories stay hidden from item pickers for this list.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryRow(category: GroceryCategorySummary) -> some View {
        CategorySettingsRow(
            category: category,
            disabled: viewModel.isCategoryDisabled(category.id),
            itemCount: viewModel.itemCount(inCategory: category.id),
            isBusy: busyCategoryID == category.id,
            onToggleDisabled: { disabled in
                set(category, disabled: disabled)
            },
            onDrag: {
                draggedCategoryID = category.id
                categoryDragLastTargetID = nil
                return NSItemProvider(object: category.id.uuidString as NSString)
            }
        )
    }

    private func syncName() {
        guard let currentList else { return }
        if isSavingName == false && focusedField != .name {
            name = currentList.name
            saveState = .saved
        }
    }

    private func scheduleNameAutosave() {
        nameSaveTask?.cancel()
        guard currentList != nil else { return }
        guard trimmedName.isEmpty == false else {
            saveState = .unsaved
            return
        }
        guard nameNeedsSave else {
            if isSavingName == false {
                saveState = .saved
            }
            return
        }

        saveState = .unsaved
        nameSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard Task.isCancelled == false else { return }
            saveNameNow()
        }
    }

    private func saveNameNow() {
        nameSaveTask?.cancel()
        guard nameNeedsSave, let currentList else {
            if isSavingName == false && trimmedName.isEmpty == false {
                saveState = .saved
            }
            return
        }
        guard isSavingName == false else { return }

        let nextName = trimmedName
        isSavingName = true
        saveState = .saving
        Task { @MainActor in
            let saved = await viewModel.renameList(id: currentList.id, name: nextName)
            isSavingName = false
            if saved {
                if trimmedName == nextName {
                    saveState = .saved
                } else {
                    scheduleNameAutosave()
                }
            } else {
                saveState = .failed
            }
        }
    }

    private func saveCategoryOrder(_ categoryIDs: [UUID]) {
        saveState = .saving
        viewModel.saveCategoryOrderInBackground(categoryIDs: categoryIDs)
    }

    private func syncOrderedCategories() {
        let categories = viewModel.categoriesForSettings
        if orderedCategories.map(\.id) != categories.map(\.id) {
            orderedCategories = categories
        }
    }

    private func syncCategoryOrderSaveState(_ state: CategoryOrderBackgroundSaveState) {
        switch state {
        case .saved:
            saveState = .saved
        case .saving:
            saveState = .saving
        case .failed:
            saveState = .failed
        }
    }

    private func set(_ category: GroceryCategorySummary, disabled: Bool) {
        guard busyCategoryID == nil else { return }
        let affectedCount = viewModel.itemCount(inCategory: category.id)
        if disabled && affectedCount > 0 {
            pendingDisable = CategoryDisableConfirmation(category: category, itemCount: affectedCount)
            return
        }
        runCategoryToggle(categoryID: category.id, disabled: disabled)
    }

    private func runCategoryToggle(categoryID: UUID, disabled: Bool) {
        busyCategoryID = categoryID
        saveState = .saving
        Task { @MainActor in
            let saved = await viewModel.setCategory(id: categoryID, disabled: disabled)
            busyCategoryID = nil
            saveState = saved ? .saved : .failed
        }
    }

    private func disableMessage(for request: CategoryDisableConfirmation) -> String {
        if request.itemCount == 1 {
            return "1 item in this category will become uncategorized."
        }
        return "\(request.itemCount) items in this category will become uncategorized."
    }
}

private struct CategorySettingsRow: View {
    let category: GroceryCategorySummary
    let disabled: Bool
    let itemCount: Int
    let isBusy: Bool
    let onToggleDisabled: (Bool) -> Void
    let onDrag: () -> NSItemProvider

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: category.colorHex) ?? Color.secondary.opacity(0.4))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                    Text(metaText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .opacity(disabled ? 0.42 : 1)

            Button {
                guard isBusy == false else { return }
                onToggleDisabled(disabled == false)
            } label: {
                Image(systemName: disabled ? "eye.slash" : "eye")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("category-enabled-toggle-\(category.id.uuidString)")
            .accessibilityLabel(disabled ? "Show \(category.name)" : "Hide \(category.name)")

            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onDrag(onDrag) {
                    dragPreview
                }
                .accessibilityIdentifier("category-drag-handle-\(category.id.uuidString)")
                .accessibilityLabel("Reorder \(category.name)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("category-settings-row-\(category.id.uuidString)")
    }

    private var metaText: String {
        let itemText = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return disabled ? "Disabled for this list · \(itemText)" : "Enabled · \(itemText)"
    }

    private var dragPreview: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: category.colorHex) ?? Color.secondary.opacity(0.4))
                .frame(width: 12, height: 12)
            Text(category.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 180, minHeight: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        .accessibilityIdentifier("category-drag-preview-\(category.id.uuidString)")
    }
}

private struct CategoryReorderDropDelegate: DropDelegate {
    let targetCategoryID: UUID
    @Binding var draggedCategoryID: UUID?
    @Binding var lastTargetCategoryID: UUID?
    @Binding var orderedCategories: [GroceryCategorySummary]
    let onOrderChanged: ([UUID]) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedCategoryID,
            draggedCategoryID != targetCategoryID,
            lastTargetCategoryID != targetCategoryID,
            let sourceIndex = orderedCategories.firstIndex(where: { $0.id == draggedCategoryID }),
            let targetIndex = orderedCategories.firstIndex(where: { $0.id == targetCategoryID })
        else {
            return
        }

        lastTargetCategoryID = targetCategoryID
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            orderedCategories.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
        onOrderChanged(orderedCategories.map(\.id))
    }

    func dropExited(info: DropInfo) {
        if lastTargetCategoryID == targetCategoryID {
            lastTargetCategoryID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedCategoryID = nil
        lastTargetCategoryID = nil
        return true
    }
}

private struct FloatingUndoToastView: View {
    @EnvironmentObject private var l10n: AppLocalization
    let toast: ListUndoToast
    let isBusy: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("list-undo-message")

            Spacer(minLength: 8)

            Button(action: onUndo) {
                if isBusy {
                    ProgressView()
                        .tint(Color(red: 0.17, green: 0.20, blue: 0.24))
                } else {
                    Label(l10n.t("ios.undo.button"), systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .foregroundStyle(Color(red: 0.17, green: 0.20, blue: 0.24))
            .disabled(isBusy)
            .accessibilityIdentifier("list-undo-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.25, green: 0.18, blue: 0.13).opacity(0.96))
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list-undo-toast")
    }
}

private struct SectionHeader: View {
    @EnvironmentObject private var l10n: AppLocalization
    let section: ListDisplaySection
    let title: String
    @Binding var targetedDropSectionID: String?
    let onQuickAdd: (UUID?) -> Void
    let onDropItem: (String, UUID?) -> Void

    private var allowsQuickAdd: Bool {
        switch section.kind {
        case .onSale, .hidden, .checked:
            return false
        case .uncategorized, .category:
            return true
        }
    }

    private var quickAddCategoryID: UUID? {
        switch section.kind {
        case .onSale, .uncategorized, .hidden, .checked:
            return nil
        case let .category(categoryID):
            return categoryID
        }
    }

    private var isDropTargeted: Bool {
        targetedDropSectionID == section.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: section.colorHex) ?? Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
            HStack(spacing: 6) {
                Text(title)
                SectionCountBadge(count: section.itemCount, sectionID: section.id, sectionTitle: title)
            }
            Spacer(minLength: 16)
            if allowsQuickAdd {
                Button {
                    onQuickAdd(quickAddCategoryID)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityIdentifier("quick-add-category-\(section.id)")
                .accessibilityLabel(
                    section.kind == .uncategorized
                        ? l10n.t("ios.list.quick_add_uncategorized")
                        : l10n.t("ios.list.quick_add_to", ["category": title])
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: CompactListLayout.headerHeight,
            alignment: .leading
        )
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .background {
            if allowsQuickAdd {
                ItemCategoryDropInteractionView { isTargeted in
                    if isTargeted {
                        targetedDropSectionID = section.id
                    } else if targetedDropSectionID == section.id {
                        targetedDropSectionID = nil
                    }
                } onDrop: { itemID in
                    onDropItem(itemID, quickAddCategoryID)
                }
            }
        }
        .contentShape(Rectangle())
        .textCase(nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("category-drop-target-\(section.id)")
    }
}

private struct SectionCountBadge: View {
    let count: Int
    let sectionID: String
    let sectionTitle: String

    private var countLabel: String {
        count == 1 ? "1 item" : "\(count) items"
    }

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(Color.secondary.opacity(0.14))
            }
            .accessibilityIdentifier("section-count-badge-\(sectionID)")
            .accessibilityLabel("\(sectionTitle) count, \(countLabel)")
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let item: GroceryItemRecord
    let isOnSaleProjection: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onUndoableAction: (String, @escaping ListUndoAction) -> Void

    private var isHiddenForLater: Bool {
        item.isHiddenForLater()
    }

    private func presentationIdentifier(_ prefix: String) -> String {
        if isOnSaleProjection {
            return "\(prefix)-on-sale-\(item.id.uuidString)"
        }
        return "\(prefix)-\(item.id.uuidString)"
    }

    private var toggleSystemImageName: String {
        if isHiddenForLater {
            return "hourglass.circle"
        }
        return item.checked ? "checkmark.circle.fill" : "circle"
    }

    private var toggleForegroundStyle: Color {
        if isHiddenForLater {
            return .orange
        }
        return item.checked ? .green : .secondary
    }

    private var toggleAccessibilityLabel: String {
        if isHiddenForLater {
            return l10n.t("ios.item.show_hidden", ["name": item.name])
        }
        return item.checked
            ? l10n.t("ios.item.uncheck", ["name": item.name])
            : l10n.t("ios.item.check", ["name": item.name])
    }

    private func restoreHiddenItem(previousHiddenUntil: Date?) async {
        let restored = await viewModel.restoreHiddenItem(item)
        if restored {
            AppHaptics.itemToggle()
            onUndoableAction(
                l10n.t("ios.undo.item_shown_now_named", ["name": item.name]),
                {
                    guard let previousHiddenUntil else { return false }
                    return await viewModel.setHiddenUntil(
                        itemID: item.id,
                        hiddenUntil: previousHiddenUntil
                    )
                }
            )
        }
    }

    private func hideForLater() async {
        let hidden = await viewModel.hideForLater(item)
        if hidden {
            AppHaptics.itemToggle()
            onUndoableAction(
                l10n.t("ios.undo.item_saved_for_later_named", ["name": item.name]),
                {
                    await viewModel.restoreHiddenItem(item)
                }
            )
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if isHiddenForLater {
                        await restoreHiddenItem(previousHiddenUntil: item.hiddenUntil)
                    } else {
                        let wasChecked = item.checked
                        let toggled = await viewModel.toggle(item)
                        if toggled {
                            AppHaptics.itemToggle()
                            onUndoableAction(
                                wasChecked
                                    ? l10n.t("ios.undo.item_unchecked_named", ["name": item.name])
                                    : l10n.t("ios.undo.item_checked_named", ["name": item.name]),
                                {
                                    await viewModel.setChecked(itemID: item.id, checked: wasChecked)
                                }
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: toggleSystemImageName)
                    .font(.title3)
                    .foregroundStyle(toggleForegroundStyle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(presentationIdentifier("toggle-item"))
            .accessibilityLabel(toggleAccessibilityLabel)

            Button(action: onEdit) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .strikethrough(item.checked)
                                .foregroundStyle(item.checked ? .secondary : .primary)

                            if item.isOnSale() {
                                Label(l10n.t("ios.item.on_sale_badge"), systemImage: "tag.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .accessibilityIdentifier(
                                        presentationIdentifier("item-on-sale-badge")
                                    )
                            }
                        }

                        if let quantity = item.quantityText, quantity.isEmpty == false {
                            Text(l10n.t("ios.item.quantity_value", ["quantity": quantity]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let note = item.note, note.isEmpty == false {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(presentationIdentifier("edit-item-row"))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(presentationIdentifier("item-row"))
        .onDrag {
            AppHaptics.dragStart()
            return NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            Text(item.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isHiddenForLater {
                Button {
                    Task {
                        await restoreHiddenItem(previousHiddenUntil: item.hiddenUntil)
                    }
                } label: {
                    Label(l10n.t("ios.item.show_hidden", ["name": item.name]), systemImage: "hourglass.circle")
                }
                .tint(.orange)
                .accessibilityIdentifier(presentationIdentifier("unhide-item"))
            } else if item.checked == false {
                Button {
                    Task {
                        await hideForLater()
                    }
                } label: {
                    Label(l10n.t("ios.item.hide_for_later_short"), systemImage: "hourglass")
                }
                .tint(.orange)
                .accessibilityIdentifier(presentationIdentifier("hide-item"))
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(l10n.t("common.delete"), systemImage: "trash")
            }
            .accessibilityIdentifier(presentationIdentifier("delete-item"))

            Button {
                onEdit()
            } label: {
                Label(l10n.t("common.edit"), systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier(presentationIdentifier("edit-item"))
        }
    }
}

private struct ItemMoveNoticeRow: View {
    @EnvironmentObject private var l10n: AppLocalization
    let notice: ItemMoveNotice
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("ios.item.move_notice", ["name": notice.itemName, "list": notice.targetListName]))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityIdentifier("item-move-notice-message-\(notice.id.uuidString)")

                if let restoreErrorMessage = notice.restoreErrorMessage {
                    Text(restoreErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("item-move-notice-error-\(notice.id.uuidString)")
                }
            }

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("move-item-undo-button-\(notice.id.uuidString)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("item-move-notice-\(notice.id.uuidString)")
    }
}

private struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let initialCategoryID: UUID?
    let onUndoableAction: (String, @escaping ListUndoAction) -> Void
    private let categorySuggestionService: CategorySuggestionService

    private enum FocusedField {
        case name
    }

    @State private var name = ""
    @State private var quantity = ""
    @State private var note = ""
    @State private var categoryID: UUID?
    @State private var isSaving = false
    @State private var isCategorySuggestionAvailable = false
    @State private var isSuggestingCategory = false
    @State private var categorySuggestionMessage: String?
    @FocusState private var focusedField: FocusedField?

    init(
        initialCategoryID: UUID? = nil,
        categorySuggestionService: CategorySuggestionService = .live(),
        onUndoableAction: @escaping (String, @escaping ListUndoAction) -> Void
    ) {
        self.initialCategoryID = initialCategoryID
        self.categorySuggestionService = categorySuggestionService
        self.onUndoableAction = onUndoableAction
        _categoryID = State(initialValue: initialCategoryID)
    }

    private var suggestions: [GroceryItemSuggestion] {
        GroceryItemSuggestionMatcher.suggestions(
            for: name,
            items: viewModel.items,
            categories: viewModel.categories
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(l10n.t("ios.item.item_section")) {
                    TextField(l10n.t("ios.item.name"), text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit(saveItem)
                        .accessibilityIdentifier("add-item-name-field")
                    TextField(l10n.t("ios.item.quantity"), text: $quantity)
                        .accessibilityIdentifier("add-item-quantity-field")
                }

                if suggestions.isEmpty == false {
                    Section(l10n.t("ios.item.suggestions")) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                Task { await useSuggestion(suggestion) }
                            } label: {
                                ItemSuggestionRow(suggestion: suggestion)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .disabled(isSaving)
                            .accessibilityIdentifier("add-item-suggestion-\(suggestion.item.id.uuidString)")
                            .accessibilityLabel(
                                suggestion.item.checked
                                    ? l10n.t("ios.item.add_back_to_list", ["name": suggestion.item.name])
                                    : l10n.t("ios.item.add_to_list", ["name": suggestion.item.name])
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Section(l10n.t("ios.item.category_section")) {
                    NavigationLink {
                        CategorySelectionScreen(
                            selectedCategoryID: $categoryID,
                            categories: viewModel.categories,
                            items: viewModel.items,
                            categoryOrder: viewModel.categoryOrder
                        )
                    } label: {
                        SelectedCategorySummary(
                            category: selectedCategory,
                            itemCount: selectedCategoryItemCount
                        )
                    }
                    .accessibilityIdentifier("add-item-category-link")

                    if isCategorySuggestionAvailable {
                        Button {
                            Task { await suggestCategory() }
                        } label: {
                            if isSuggestingCategory {
                                HStack {
                                    ProgressView()
                                    Text(l10n.t("ios.item.suggesting_category"))
                                }
                            } else {
                                Label(
                                    l10n.t("ios.item.suggest_category"),
                                    systemImage: "apple.intelligence"
                                )
                            }
                        }
                        .disabled(
                            isSaving
                                || isSuggestingCategory
                                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("add-item-suggest-category-button")

                        if let categorySuggestionMessage {
                            Text(categorySuggestionMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("add-item-category-suggestion-status")
                        }
                    }
                }

                Section(l10n.t("ios.item.notes_section")) {
                    TextField(l10n.t("ios.item.note"), text: $note, axis: .vertical)
                        .accessibilityIdentifier("add-item-note-field")
                }
            }
            .navigationTitle(l10n.t("ios.item.add_title"))
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.18), value: suggestions.map(\.id))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("add-item-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("common.save")) {
                        saveItem()
                    }
                    .disabled(canSave == false)
                    .accessibilityIdentifier("add-item-save-button")
                }
            }
        }
        .task {
            categoryID = initialCategoryID
            isCategorySuggestionAvailable = categorySuggestionService.isAvailable
            try? await Task.sleep(nanoseconds: 250_000_000)
            focusedField = .name
        }
        .accessibilityIdentifier("add-item-sheet")
    }

    private var selectedCategory: GroceryCategorySummary? {
        guard let categoryID else { return nil }
        return viewModel.categories.first { $0.id == categoryID }
    }

    private var selectedCategoryItemCount: Int {
        if let categoryID {
            return viewModel.items.filter { $0.categoryID == categoryID }.count
        }
        return GroceryCategorySelectionBuilder.uncategorizedItemCount(items: viewModel.items)
    }

    private var canSave: Bool {
        isSaving == false
            && isSuggestingCategory == false
            && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @MainActor
    private func suggestCategory() async {
        guard isSuggestingCategory == false else { return }
        let request = GroceryCategorySuggestionRequest(
            name: name,
            quantity: quantity,
            note: note
        )
        guard request.name.isEmpty == false else { return }

        let categories = ListCategoryPresentation.availableCategories(
            categories: viewModel.categories,
            disabledCategoryIDs: viewModel.disabledCategoryIDs
        )
        isSuggestingCategory = true
        categorySuggestionMessage = nil
        defer { isSuggestingCategory = false }

        do {
            let suggestedCategoryID = try await categorySuggestionService.suggestCategory(
                request: request,
                categories: categories
            )
            guard let suggestedCategory = categories.first(where: { $0.id == suggestedCategoryID }) else {
                throw CategorySuggestionService.SuggestionError.invalidResponse
            }
            categoryID = suggestedCategoryID
            categorySuggestionMessage = l10n.t(
                "ios.item.category_suggested",
                ["category": suggestedCategory.name]
            )
            AppHaptics.confirmation()
        } catch {
            categorySuggestionMessage = l10n.t("ios.item.category_suggestion_failed")
        }
    }

    private func saveItem() {
        guard canSave else { return }
        isSaving = true
        Task {
            let saved = await viewModel.addItem(
                name: name,
                quantity: quantity,
                note: note,
                categoryID: categoryID
            )
            if saved {
                AppHaptics.confirmation()
                dismiss()
            } else {
                isSaving = false
            }
        }
    }

    @MainActor
    private func useSuggestion(_ suggestion: GroceryItemSuggestion) async {
        guard isSaving == false else { return }
        isSaving = true

        let saved: Bool
        if suggestion.item.checked {
            saved = await viewModel.toggle(suggestion.item)
        } else {
            saved = await viewModel.addItem(
                name: suggestion.item.name,
                quantity: suggestion.item.quantityText ?? "",
                note: suggestion.item.note ?? "",
                categoryID: suggestion.item.categoryID
            )
        }

        if saved {
            AppHaptics.confirmation()
            if suggestion.item.checked {
                onUndoableAction(
                    l10n.t("ios.undo.item_added_back_named", ["name": suggestion.item.name]),
                    {
                        await viewModel.setChecked(itemID: suggestion.item.id, checked: true)
                    }
                )
            }
            dismiss()
        } else {
            isSaving = false
        }
    }

}

private struct ItemSuggestionRow: View {
    @EnvironmentObject private var l10n: AppLocalization
    let suggestion: GroceryItemSuggestion

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: suggestion.category?.colorHex) ?? Color.secondary.opacity(0.35))
                .frame(width: 4, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(suggestion.item.checked ? .secondary : .primary)
                    .strikethrough(suggestion.item.checked)
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var metaText: String {
        var parts: [String] = []
        if let quantity = suggestion.item.quantityText, quantity.isEmpty == false {
            parts.append(l10n.t("ios.item.quantity_value", ["quantity": quantity]))
        }
        let categoryName = suggestion.category?.name ?? l10n.t("ios.list.uncategorized")
        parts.append(categoryName)
        if suggestion.item.checked {
            parts.append(l10n.t("ios.list.checked_off"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct SelectedCategorySummary: View {
    @EnvironmentObject private var l10n: AppLocalization

    let category: GroceryCategorySummary?
    let itemCount: Int

    var body: some View {
        HStack(spacing: 12) {
            CategoryColorSwatch(colorHex: category?.colorHex)
            VStack(alignment: .leading, spacing: 3) {
                Text(category?.name ?? l10n.t("ios.list.uncategorized"))
                    .foregroundStyle(.primary)
                Text(l10n.t("ios.item.item_count", ["count": "\(itemCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CategorySelectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: AppLocalization

    @Binding var selectedCategoryID: UUID?
    let categories: [GroceryCategorySummary]
    let items: [GroceryItemRecord]
    let categoryOrder: [ListCategoryOrderEntry]

    @State private var query = ""
    @State private var sort: GroceryCategorySelectionSort = .listOrder

    private var options: [GroceryCategorySelectionOption] {
        GroceryCategorySelectionBuilder.options(
            categories: categories,
            items: items,
            categoryOrder: categoryOrder,
            query: query,
            sort: sort
        )
    }

    var body: some View {
        List {
            Section {
                TextField(l10n.t("ios.item.category_search"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("category-search-field")

                Picker(l10n.t("ios.item.category_sort"), selection: $sort) {
                    ForEach(GroceryCategorySelectionSort.allCases, id: \.self) { sortOption in
                        Text(sortShortTitle(sortOption))
                            .tag(sortOption)
                            .accessibilityLabel(sortTitle(sortOption))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("category-sort-picker")
            }

            Section(l10n.t("ios.item.categories")) {
                Button {
                    selectCategory(nil)
                } label: {
                    CategorySelectionRow(
                        title: l10n.t("ios.list.uncategorized"),
                        colorHex: nil,
                        itemCount: GroceryCategorySelectionBuilder.uncategorizedItemCount(items: items),
                        isSelected: selectedCategoryID == nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("category-option-uncategorized")

                ForEach(options) { option in
                    Button {
                        selectCategory(option.category.id)
                    } label: {
                        CategorySelectionRow(
                            title: option.category.name,
                            colorHex: option.category.colorHex,
                            itemCount: option.itemCount,
                            isSelected: selectedCategoryID == option.category.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category-option-\(option.category.name)")
                    .accessibilityLabel(
                        l10n.t(
                            "ios.item.category_option_accessibility",
                            ["name": option.category.name, "count": "\(option.itemCount)"]
                        )
                    )
                }

                if options.isEmpty {
                    Text(l10n.t("ios.item.no_categories_found"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(l10n.t("ios.item.category"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("category-selection-screen")
    }

    private func selectCategory(_ categoryID: UUID?) {
        selectedCategoryID = categoryID
        dismiss()
    }

    private func sortShortTitle(_ sort: GroceryCategorySelectionSort) -> String {
        switch sort {
        case .listOrder:
            return l10n.t("ios.item.category_sort_list_short")
        case .nameAscending:
            return "A-Z"
        case .nameDescending:
            return "Z-A"
        case .mostUsed:
            return l10n.t("ios.item.category_sort_used_short")
        }
    }

    private func sortTitle(_ sort: GroceryCategorySelectionSort) -> String {
        switch sort {
        case .listOrder:
            return l10n.t("ios.item.category_sort_list")
        case .nameAscending:
            return "A-Z"
        case .nameDescending:
            return "Z-A"
        case .mostUsed:
            return l10n.t("ios.item.category_sort_used")
        }
    }
}

private struct CategorySelectionRow: View {
    @EnvironmentObject private var l10n: AppLocalization

    let title: String
    let colorHex: String?
    let itemCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryColorSwatch(colorHex: colorHex)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(l10n.t("ios.item.item_count", ["count": "\(itemCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct CategoryColorSwatch: View {
    let colorHex: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: colorHex) ?? Color.secondary.opacity(0.35))
            .frame(width: 14, height: 32)
    }
}

private struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let item: GroceryItemRecord
    let onUndoableAction: (String, @escaping ListUndoAction) -> Void
    let onMoved: (ItemMoveNotice) -> Void

    @State private var name: String
    @State private var quantity: String
    @State private var note: String
    @State private var categoryID: UUID?
    @State private var saleEnabled: Bool
    @State private var saleStartsAt: Date
    @State private var saleEndsAt: Date
    @State private var history: GroceryItemEditHistory
    @State private var lastSavedPayload: GroceryItemEditPayload
    @State private var saveTask: Task<Void, Never>?
    @State private var saveStatus: SaveStatus = .saved
    @State private var suppressHistoryRecording = false
    @State private var isMoving = false
    @State private var didMoveItem = false

    private enum SaveStatus: Equatable {
        case saved
        case saving
        case offline
        case invalidName
        case invalidSaleWindow

        var labelKey: String {
            switch self {
            case .saved:
                return "ios.item.status_saved"
            case .saving:
                return "ios.item.status_saving"
            case .offline:
                return "ios.item.status_saved_offline"
            case .invalidName:
                return "ios.item.status_name_required"
            case .invalidSaleWindow:
                return "ios.item.status_sale_window_invalid"
            }
        }

        var accessibilityValue: String {
            switch self {
            case .saved:
                return "saved"
            case .saving:
                return "saving"
            case .offline:
                return "saved-offline"
            case .invalidName:
                return "invalid-name"
            case .invalidSaleWindow:
                return "invalid-sale-window"
            }
        }

        var systemImage: String {
            switch self {
            case .saved:
                return "checkmark.circle"
            case .saving:
                return "arrow.triangle.2.circlepath"
            case .offline:
                return "icloud.slash"
            case .invalidName, .invalidSaleWindow:
                return "exclamationmark.triangle"
            }
        }

        var isInvalid: Bool {
            switch self {
            case .invalidName, .invalidSaleWindow:
                return true
            case .saved, .saving, .offline:
                return false
            }
        }
    }

    init(
        item: GroceryItemRecord,
        onUndoableAction: @escaping (String, @escaping ListUndoAction) -> Void,
        onMoved: @escaping (ItemMoveNotice) -> Void
    ) {
        self.item = item
        self.onUndoableAction = onUndoableAction
        self.onMoved = onMoved
        let payload = GroceryItemEditPayload(item: item)
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantityText ?? "")
        _note = State(initialValue: item.note ?? "")
        _categoryID = State(initialValue: item.categoryID)
        let saleDefaultNow = Date()
        let defaultSaleStart = item.saleStartsAt ?? saleDefaultNow.addingTimeInterval(-60 * 60)
        let defaultSaleEndReference = item.saleStartsAt ?? saleDefaultNow
        _saleEnabled = State(initialValue: item.saleStartsAt != nil && item.saleEndsAt != nil)
        _saleStartsAt = State(initialValue: defaultSaleStart)
        _saleEndsAt = State(
            initialValue: item.saleEndsAt
                ?? Calendar.current.date(byAdding: .day, value: 7, to: defaultSaleEndReference)
                ?? defaultSaleEndReference.addingTimeInterval(7 * 24 * 60 * 60)
        )
        _history = State(initialValue: Self.loadHistory(itemID: item.id))
        _lastSavedPayload = State(initialValue: payload)
    }

    private var isHiddenForLater: Bool {
        item.isHiddenForLater()
    }

    var body: some View {
        NavigationStack {
            Form {
                itemDetailsSection
                categorySection
                moveSection
                notesSection
                saleSection
                saveStatusSection
                hiddenForLaterSection
            }
            .navigationTitle(l10n.t("ios.item.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ControlGroup {
                        Button {
                            applyUndo()
                        } label: {
                            Label(l10n.t("common.undo"), systemImage: "arrow.uturn.backward")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("edit-item-undo-button")
                        .disabled(history.canUndo == false)

                        Button {
                            applyRedo()
                        } label: {
                            Label(l10n.t("common.redo"), systemImage: "arrow.uturn.forward")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("edit-item-redo-button")
                        .disabled(history.canRedo == false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        flushCurrentEdit()
                        dismiss()
                    } label: {
                        Label(l10n.t("common.done"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("edit-item-close-button")
                }
            }
        }
        .onChange(of: name) { _ in scheduleAutosave() }
        .onChange(of: quantity) { _ in scheduleAutosave() }
        .onChange(of: note) { _ in scheduleAutosave() }
        .onChange(of: categoryID) { _ in scheduleAutosave() }
        .onChange(of: saleEnabled) { _ in scheduleAutosave() }
        .onChange(of: saleStartsAt) { _ in scheduleAutosave() }
        .onChange(of: saleEndsAt) { _ in scheduleAutosave() }
        .onDisappear {
            persistHistory()
            if didMoveItem == false {
                flushCurrentEdit()
            }
        }
        .accessibilityIdentifier("edit-item-sheet")
    }

    private var itemDetailsSection: some View {
        Section(l10n.t("ios.item.item_section")) {
            TextField(l10n.t("ios.item.name"), text: $name)
                .accessibilityIdentifier("edit-item-name-field")
            TextField(l10n.t("ios.item.quantity"), text: $quantity)
                .accessibilityIdentifier("edit-item-quantity-field")
        }
    }

    private var categorySection: some View {
        Section(l10n.t("ios.item.category_section")) {
            NavigationLink {
                CategorySelectionScreen(
                    selectedCategoryID: $categoryID,
                    categories: viewModel.categories,
                    items: viewModel.items,
                    categoryOrder: viewModel.categoryOrder
                )
            } label: {
                SelectedCategorySummary(
                    category: selectedCategory,
                    itemCount: selectedCategoryItemCount
                )
            }
            .accessibilityIdentifier("edit-item-category-link")
        }
    }

    @ViewBuilder
    private var moveSection: some View {
        if moveTargets.count > 1 {
            Section(l10n.t("ios.item.move_section")) {
                ForEach(moveTargets) { list in
                    moveTargetRow(for: list)
                }

                if isMoving {
                    Label(l10n.t("ios.item.moving"), systemImage: "arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func moveTargetRow(for list: GroceryListSummary) -> some View {
        if list.id == item.listID {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                    Text(l10n.t("ios.item.current_list"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .accessibilityIdentifier("edit-item-current-list-\(list.id.uuidString)")
        } else {
            Button {
                move(to: list.id)
            } label: {
                HStack(spacing: 12) {
                    Text(list.name)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .disabled(isMoving)
            .accessibilityIdentifier("edit-item-move-list-\(list.id.uuidString)")
            .accessibilityLabel(l10n.t("ios.item.move_to_list_named", ["list": list.name]))
        }
    }

    private var notesSection: some View {
        Section(l10n.t("ios.item.notes_section")) {
            TextField(l10n.t("ios.item.note"), text: $note, axis: .vertical)
                .accessibilityIdentifier("edit-item-note-field")
        }
    }

    private var saleSection: some View {
        Section {
            saleControls
        } header: {
            Text(l10n.t("ios.item.sale_section"))
        } footer: {
            Text(l10n.t("ios.item.sale_explanation"))
        }
    }

    @ViewBuilder
    private var saleControls: some View {
        Toggle(l10n.t("ios.item.sale_enabled"), isOn: $saleEnabled)
            .accessibilityIdentifier("edit-item-sale-toggle")

        if saleEnabled {
            DatePicker(
                l10n.t("ios.item.sale_starts_at"),
                selection: $saleStartsAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("edit-item-sale-start-picker")

            DatePicker(
                l10n.t("ios.item.sale_ends_at"),
                selection: $saleEndsAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("edit-item-sale-end-picker")

            if saleStartsAt >= saleEndsAt {
                Label(l10n.t("ios.item.sale_window_invalid"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("edit-item-sale-window-error")
            }
        }
    }

    private var saveStatusSection: some View {
        Section {
            Label(l10n.t(saveStatus.labelKey), systemImage: saveStatus.systemImage)
                .font(.footnote)
                .foregroundStyle(saveStatus.isInvalid ? .red : .secondary)
                .accessibilityIdentifier("edit-item-save-status")
                .accessibilityValue(saveStatus.accessibilityValue)
        }
    }

    @ViewBuilder
    private var hiddenForLaterSection: some View {
        if item.checked == false {
            Section {
                Button {
                    performHiddenForLaterAction()
                } label: {
                    Label(
                        isHiddenForLater
                            ? l10n.t("ios.item.show_now_action")
                            : l10n.t("ios.item.save_for_later_action"),
                        systemImage: isHiddenForLater ? "hourglass.circle" : "hourglass"
                    )
                }
                .foregroundStyle(.orange)
                .accessibilityIdentifier(
                    isHiddenForLater
                        ? "edit-item-restore-hidden-button"
                        : "edit-item-hide-for-later-button"
                )
            }
        }
    }

    private var currentPayload: GroceryItemEditPayload {
        GroceryItemEditPayload(
            name: name,
            quantityText: quantity,
            note: note,
            categoryID: categoryID,
            saleStartsAt: saleEnabled ? saleStartsAt : nil,
            saleEndsAt: saleEnabled ? saleEndsAt : nil
        )
    }

    private var moveTargets: [GroceryListSummary] {
        viewModel.moveTargetLists(for: item)
    }

    private var selectedCategory: GroceryCategorySummary? {
        guard let categoryID else { return nil }
        return viewModel.categories.first { $0.id == categoryID }
    }

    private var selectedCategoryItemCount: Int {
        if let categoryID {
            return viewModel.items.filter { $0.categoryID == categoryID }.count
        }
        return GroceryCategorySelectionBuilder.uncategorizedItemCount(items: viewModel.items)
    }

    private static func historyKey(itemID: UUID) -> String {
        "planini.itemEditHistory.\(itemID.uuidString)"
    }

    private static func loadHistory(itemID: UUID) -> GroceryItemEditHistory {
        guard
            let data = UserDefaults.standard.data(forKey: historyKey(itemID: itemID)),
            let decoded = try? JSONDecoder().decode(GroceryItemEditHistory.self, from: data)
        else {
            return GroceryItemEditHistory()
        }
        return decoded
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey(itemID: item.id))
    }

    private func scheduleAutosave() {
        scheduleAutosave(recordHistory: suppressHistoryRecording == false)
    }

    private func scheduleAutosave(recordHistory: Bool) {
        saveTask?.cancel()
        let payload = currentPayload
        guard payload.name.isEmpty == false else {
            saveStatus = .invalidName
            return
        }
        guard payload.isValid else {
            saveStatus = .invalidSaleWindow
            return
        }
        if recordHistory {
            history.record(previous: lastSavedPayload, current: payload)
        }
        persistHistory()
        saveStatus = .saving
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard Task.isCancelled == false else { return }
            let saved = await viewModel.saveEdit(item: item, payload: payload)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                if saved {
                    lastSavedPayload = payload
                    saveStatus = viewModel.hasPendingEdit(for: item.id) ? .offline : .saved
                } else {
                    saveStatus = .invalidSaleWindow
                }
            }
        }
    }

    private func apply(_ payload: GroceryItemEditPayload) {
        suppressHistoryRecording = true
        name = payload.name
        quantity = payload.quantityText ?? ""
        note = payload.note ?? ""
        categoryID = payload.categoryID
        if let startsAt = payload.saleStartsAt, let endsAt = payload.saleEndsAt {
            saleStartsAt = startsAt
            saleEndsAt = endsAt
            saleEnabled = true
        } else {
            saleEnabled = false
        }
        persistHistory()
        scheduleAutosave(recordHistory: false)
        DispatchQueue.main.async {
            suppressHistoryRecording = false
        }
    }

    private func applyUndo() {
        guard let payload = history.undo(current: currentPayload) else { return }
        apply(payload)
    }

    private func applyRedo() {
        guard let payload = history.redo(current: currentPayload) else { return }
        apply(payload)
    }

    private func performHiddenForLaterAction() {
        flushCurrentEdit()
        let previousHiddenUntil = item.hiddenUntil
        Task {
            let didChange: Bool
            if isHiddenForLater {
                didChange = await viewModel.restoreHiddenItem(item)
            } else {
                didChange = await viewModel.hideForLater(item)
            }
            guard didChange else { return }
            await MainActor.run {
                AppHaptics.itemToggle()
                if isHiddenForLater {
                    onUndoableAction(
                        l10n.t("ios.undo.item_shown_now_named", ["name": item.name]),
                        {
                            guard let previousHiddenUntil else { return false }
                            return await viewModel.setHiddenUntil(itemID: item.id, hiddenUntil: previousHiddenUntil)
                        }
                    )
                } else {
                    onUndoableAction(
                        l10n.t("ios.undo.item_saved_for_later_named", ["name": item.name]),
                        {
                            await viewModel.restoreHiddenItem(item)
                        }
                    )
                }
                dismiss()
            }
        }
    }

    private func move(to targetListID: UUID) {
        guard targetListID != item.listID, isMoving == false else { return }
        guard let targetList = moveTargets.first(where: { $0.id == targetListID }) else {
            return
        }

        saveTask?.cancel()
        let payload = currentPayload
        guard payload.isValid else {
            saveStatus = payload.name.isEmpty ? .invalidName : .invalidSaleWindow
            return
        }

        isMoving = true
        saveStatus = .saving
        Task {
            let movedItem = await viewModel.move(item: item, to: targetListID, payload: payload)
            await MainActor.run {
                isMoving = false
                guard let movedItem else {
                    saveStatus = .saved
                    return
                }

                didMoveItem = true
                lastSavedPayload = payload
                persistHistory()
                onMoved(
                    ItemMoveNotice(
                        id: item.id,
                        sourceListID: item.listID,
                        targetListID: targetListID,
                        targetListName: targetList.name,
                        sourceItem: item.applyingEditPayload(payload),
                        movedItem: movedItem,
                        isExpiring: false
                    )
                )
                AppHaptics.confirmation()
                dismiss()
            }
        }
    }

    private func flushCurrentEdit() {
        saveTask?.cancel()
        let payload = currentPayload
        guard payload.isValid, payload != lastSavedPayload else { return }
        Task {
            _ = await viewModel.saveEdit(item: item, payload: payload)
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private enum AppHaptics {
    static func dragStart() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.42)
        #endif
    }

    static func itemDrop() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
        #endif
    }

    static func itemToggle() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
        #endif
    }

    static func confirmation() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
        #endif
    }

    static func destructiveAction() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #endif
    }
}

private extension GroceryCategorySelectionSort {
    var shortTitle: String {
        switch self {
        case .listOrder:
            return "List"
        case .nameAscending:
            return "A-Z"
        case .nameDescending:
            return "Z-A"
        case .mostUsed:
            return "Used"
        }
    }

    var title: String {
        switch self {
        case .listOrder:
            return "List order"
        case .nameAscending:
            return "A-Z"
        case .nameDescending:
            return "Z-A"
        case .mostUsed:
            return "Most used"
        }
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
