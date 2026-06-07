import PlaniniCore
import SwiftUI
#if canImport(UIKit)
import UIKit
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

private struct AddItemPresentation: Identifiable {
    let id = UUID()
    let categoryID: UUID?
}

private typealias ListUndoAction = @MainActor () async -> Bool

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

    var body: some View {
        Group {
            if viewModel.authToken == nil {
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
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FavoriteListTab()
            }
            .tabItem {
                Label(
                    viewModel.favoriteList?.name ?? l10n.t("ios.tabs.favorite"),
                    systemImage: viewModel.favoriteListID == nil ? "star" : "star.fill"
                )
            }
            .tag(AppTab.favorite)
            .accessibilityIdentifier("tab-favorite")

            NavigationStack(path: $listNavigationPath) {
                ListsTab(selectedTab: $selectedTab)
                    .navigationDestination(for: UUID.self) { listID in
                        ListDetailScreen(listID: listID, showsFavoriteButton: true)
                    }
            }
            .tabItem {
                Label(l10n.t("ios.tabs.lists"), systemImage: "rectangle.grid.1x2")
            }
            .tag(AppTab.lists)
            .accessibilityIdentifier("tab-lists")

            NavigationStack {
                SettingsTab()
            }
            .tabItem {
                Label(l10n.t("common.settings"), systemImage: "gearshape")
            }
            .tag(AppTab.settings)
            .accessibilityIdentifier("tab-settings")
        }
        .accessibilityIdentifier("main-tab-view")
    }

    private var authenticatedApp: some View {
        VStack(spacing: 0) {
            if let offlineStatusMessage = viewModel.offlineStatusMessage {
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
                    TextField(l10n.t("ios.item.name"), text: $registrationDisplayName)
                        .textContentType(.name)
                        .accessibilityIdentifier("registration-display-name-field")

                    TextField(l10n.t("ios.onboarding.email"), text: $registrationEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
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
                            Label(l10n.t("ios.onboarding.create_account"), systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .disabled(busyAction != nil || trimmedName.isEmpty || trimmedEmail.isEmpty)
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

    var body: some View {
        Group {
            if let favoriteList = viewModel.favoriteList {
                ListDetailScreen(listID: favoriteList.id, showsFavoriteButton: false)
            } else {
                EmptyStateView(
                    title: l10n.t("ios.favorite.empty_title"),
                    systemImage: "star",
                    message: l10n.t("ios.favorite.empty_message")
                )
                .navigationTitle(l10n.t("ios.tabs.favorite"))
            }
        }
    }
}

private struct ListsTab: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    @Binding var selectedTab: AppTab

    private var householdSections: [(name: String, lists: [GroceryListSummary])] {
        Dictionary(grouping: viewModel.lists, by: \.householdName)
            .map { key, value in
                (name: key, lists: value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
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
        }
        .navigationTitle(l10n.t("ios.tabs.lists"))
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

            Section(l10n.t("ios.settings.account")) {
                LabeledContent(l10n.t("settings.signed_in_as"), value: viewModel.displayName ?? l10n.t("ios.settings.unknown"))
                if let favoriteList = viewModel.favoriteList {
                    LabeledContent(l10n.t("ios.favorite.favorite_list"), value: favoriteList.name)
                }
                NavigationLink {
                    HouseholdManagementScreen()
                } label: {
                    Label(l10n.t("ios.households.settings_row"), systemImage: "house")
                }
                .accessibilityIdentifier("settings-household-management-link")
                Button(l10n.t("ios.settings.sign_out"), role: .destructive) {
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
                LabeledContent(l10n.t("ios.settings.backend"), value: viewModel.backendDisplayName)
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
    @State private var invite: HouseholdInviteLink?
    @State private var isCreatingInvite = false

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

                if let invite {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(invite.inviteURL)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("household-invite-url-value")

                        if let expiresAtText = formattedExpiration(for: invite) {
                            Text(l10n.t("ios.households.expires_at", ["date": expiresAtText]))
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
                    .padding(.vertical, 4)
                }
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
        .accessibilityIdentifier("household-detail-management-screen")
    }

    @MainActor
    private func createInvite() async {
        guard isCreatingInvite == false else { return }
        isCreatingInvite = true
        defer { isCreatingInvite = false }

        if let createdInvite = await viewModel.createInvite(householdID: householdID) {
            invite = createdInvite
            AppHaptics.confirmation()
        }
    }

    private func formattedExpiration(for invite: HouseholdInviteLink) -> String? {
        guard let expiresAt = invite.expiresAt else { return nil }
        return inviteExpirationFormatter.string(from: expiresAt)
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

    @State private var displayedListID: UUID
    @State private var editingItem: GroceryItemRecord?
    @State private var addItemPresentation: AddItemPresentation?
    @State private var undoToast: ListUndoToast?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var isRunningUndo = false
    @State private var showingListSettings = false

    init(listID: UUID, showsFavoriteButton: Bool) {
        self.listID = listID
        self.showsFavoriteButton = showsFavoriteButton
        _displayedListID = State(initialValue: listID)
    }

    private var currentList: GroceryListSummary? {
        viewModel.lists.first { $0.id == displayedListID }
    }

    private var listSwitchSections: [(name: String, lists: [GroceryListSummary])] {
        Dictionary(grouping: viewModel.lists, by: \.householdName)
            .map { key, value in
                (name: key, lists: value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleItemIDs: [UUID] {
        viewModel.sections.flatMap { section in
            section.items.map(\.id)
        }
    }

    var body: some View {
        List {
            if let list = currentList {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(list.householdName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(list.name)
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("list-detail-title")
                        Text(
                            l10n.t(
                                "ios.list.item_summary",
                                [
                                    "items": viewModel.sections.reduce(0) { $0 + $1.itemCount },
                                    "sections": viewModel.sections.count,
                                ]
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if viewModel.sections.isEmpty {
                Section {
                    EmptyStateView(
                        title: l10n.t("ios.list.empty_title"),
                        systemImage: "basket",
                        message: l10n.t("ios.list.empty_message")
                    )
                }
            } else {
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            ItemRow(item: item) {
                                editingItem = item
                            } onUndoableAction: { message, action in
                                showUndoToast(message: message, action: action)
                            }
                        }
                    } header: {
                        SectionHeader(section: section, title: localizedTitle(for: section)) { categoryID in
                            addItemPresentation = AddItemPresentation(categoryID: categoryID)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentList?.name ?? l10n.t("ios.list.fallback_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.lists.count > 1 {
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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingListSettings = true
                } label: {
                    Label("List settings", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("list-settings-button")
                .disabled(currentList == nil)
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
            await viewModel.selectList(id: displayedListID)
        }
        .onChange(of: listID) { newValue in
            displayedListID = newValue
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
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
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: visibleItemIDs)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: undoToast?.id)
        .onDisappear {
            undoDismissTask?.cancel()
        }
        .accessibilityIdentifier("list-detail-screen")
    }

    private func showUndoToast(message: String, action: @escaping ListUndoAction) {
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

    private func localizedTitle(for section: GroceryItemSection) -> String {
        switch section.kind {
        case .uncategorized:
            return l10n.t("ios.list.uncategorized")
        case .checked:
            return l10n.t("ios.list.checked_off")
        case .category:
            return section.title
        }
    }

    private func switchList(to listID: UUID) {
        guard displayedListID != listID else { return }
        displayedListID = listID
        Task { await viewModel.selectList(id: listID) }
    }
}

private struct ListSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    let listID: UUID

    @State private var name = ""
    @State private var isSavingName = false
    @State private var saveState: ListSettingsSaveState = .saved
    @State private var nameSaveTask: Task<Void, Never>?
    @State private var busyCategoryID: UUID?
    @State private var isSavingCategoryOrder = false
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Label(saveState.title, systemImage: saveState.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(saveState.tint)
                            .accessibilityIdentifier("list-settings-save-state")
                    }
                }
        }
        .onAppear(perform: syncName)
        .onChange(of: currentList?.name ?? "") { _ in syncName() }
        .onChange(of: name) { _ in scheduleNameAutosave() }
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
        Form {
            listNameSection
            categoriesSection
        }
        .environment(\.editMode, .constant(.active))
    }

    private var listNameSection: some View {
        Section("List name") {
            TextField("List name", text: $name)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit(saveNameNow)
                .accessibilityIdentifier("list-name-field")
        }
    }

    private var categoriesSection: some View {
        let categories = viewModel.categoriesForSettings
        return Section {
            if categories.isEmpty {
                Label("No categories available", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categories) { category in
                    categoryRow(category: category)
                }
                .onMove(perform: moveCategories)
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Disabled categories stay hidden from item pickers for this list.")
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

    private func moveCategories(from source: IndexSet, to destination: Int) {
        guard isSavingCategoryOrder == false else { return }
        var categoryIDs = viewModel.categoriesForSettings.map(\.id)
        categoryIDs.move(fromOffsets: source, toOffset: destination)
        isSavingCategoryOrder = true
        saveState = .saving
        Task { @MainActor in
            let saved = await viewModel.saveCategoryOrder(categoryIDs: categoryIDs)
            isSavingCategoryOrder = false
            saveState = saved ? .saved : .failed
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
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("category-settings-row-\(category.id.uuidString)")
    }

    private var metaText: String {
        let itemText = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return disabled ? "Disabled for this list · \(itemText)" : "Enabled · \(itemText)"
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
    let section: GroceryItemSection
    let title: String
    let onQuickAdd: (UUID?) -> Void

    private var allowsQuickAdd: Bool {
        switch section.kind {
        case .checked:
            return false
        case .uncategorized, .category:
            return true
        }
    }

    private var quickAddCategoryID: UUID? {
        switch section.kind {
        case .uncategorized, .checked:
            return nil
        case let .category(categoryID):
            return categoryID
        }
    }

    var body: some View {
        HStack(spacing: 10) {
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
        .textCase(nil)
        .accessibilityIdentifier("section-\(section.id)")
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
    let onEdit: () -> Void
    let onUndoableAction: (String, @escaping ListUndoAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
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
            } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.checked ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle-item-\(item.id.uuidString)")
            .accessibilityLabel(
                item.checked
                    ? l10n.t("ios.item.uncheck", ["name": item.name])
                    : l10n.t("ios.item.check", ["name": item.name])
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)

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
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("item-row-\(item.id.uuidString)")
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    let deleted = await viewModel.delete(item: item)
                    if deleted {
                        AppHaptics.destructiveAction()
                        onUndoableAction(
                            l10n.t("ios.undo.item_deleted_named", ["name": item.name]),
                            {
                                await viewModel.restoreDeleted(item: item)
                            }
                        )
                    }
                }
            } label: {
                Label(l10n.t("common.delete"), systemImage: "trash")
            }

            Button {
                onEdit()
            } label: {
                Label(l10n.t("common.edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

private struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var l10n: AppLocalization
    let initialCategoryID: UUID?
    let onUndoableAction: (String, @escaping ListUndoAction) -> Void

    private enum FocusedField {
        case name
    }

    @State private var name = ""
    @State private var quantity = ""
    @State private var note = ""
    @State private var categoryID: UUID?
    @State private var isSaving = false
    @FocusState private var focusedField: FocusedField?

    init(
        initialCategoryID: UUID? = nil,
        onUndoableAction: @escaping (String, @escaping ListUndoAction) -> Void
    ) {
        self.initialCategoryID = initialCategoryID
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
        isSaving == false && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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

    @State private var name: String
    @State private var quantity: String
    @State private var note: String
    @State private var categoryID: UUID?
    @State private var history: GroceryItemEditHistory
    @State private var lastSavedPayload: GroceryItemEditPayload
    @State private var saveTask: Task<Void, Never>?
    @State private var saveStatus: SaveStatus = .saved
    @State private var suppressHistoryRecording = false

    private enum SaveStatus: Equatable {
        case saved
        case saving
        case offline
        case invalid

        var labelKey: String {
            switch self {
            case .saved:
                return "ios.item.status_saved"
            case .saving:
                return "ios.item.status_saving"
            case .offline:
                return "ios.item.status_saved_offline"
            case .invalid:
                return "ios.item.status_name_required"
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
            case .invalid:
                return "exclamationmark.triangle"
            }
        }
    }

    init(item: GroceryItemRecord) {
        self.item = item
        let payload = GroceryItemEditPayload(item: item)
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantityText ?? "")
        _note = State(initialValue: item.note ?? "")
        _categoryID = State(initialValue: item.categoryID)
        _history = State(initialValue: Self.loadHistory(itemID: item.id))
        _lastSavedPayload = State(initialValue: payload)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(l10n.t("ios.item.item_section")) {
                    TextField(l10n.t("ios.item.name"), text: $name)
                        .accessibilityIdentifier("edit-item-name-field")
                    TextField(l10n.t("ios.item.quantity"), text: $quantity)
                        .accessibilityIdentifier("edit-item-quantity-field")
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
                    .accessibilityIdentifier("edit-item-category-link")
                }

                Section(l10n.t("ios.item.notes_section")) {
                    TextField(l10n.t("ios.item.note"), text: $note, axis: .vertical)
                        .accessibilityIdentifier("edit-item-note-field")
                }

                Section {
                    Label(l10n.t(saveStatus.labelKey), systemImage: saveStatus.systemImage)
                        .font(.footnote)
                        .foregroundStyle(saveStatus == .invalid ? .red : .secondary)
                        .accessibilityIdentifier("edit-item-save-status")
                }
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
                        Label(l10n.t("common.done"), systemImage: "xmark")
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
        .onDisappear {
            persistHistory()
            flushCurrentEdit()
        }
        .accessibilityIdentifier("edit-item-sheet")
    }

    private var currentPayload: GroceryItemEditPayload {
        GroceryItemEditPayload(
            name: name,
            quantityText: quantity,
            note: note,
            categoryID: categoryID
        )
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
        guard payload.isValid else {
            saveStatus = .invalid
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
                    saveStatus = .invalid
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
