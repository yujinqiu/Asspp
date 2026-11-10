//
//  AccountView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import SwiftUI

struct AccountView: View {
    @State private var vm = AppStore.this
    @State private var addAccount = false
    @State private var selectedID: AppStore.UserAccount.ID?
    @State private var navigationPath = NavigationPath()
    @State private var isImporting = false
    @State private var importError = ""
    @State private var showImportError = false

    var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    #if os(macOS)
        private var macOSBody: some View {
            NavigationStack(path: $navigationPath) {
                Group {
                    if vm.accounts.isEmpty {
                        ContentUnavailableView(
                            label: {
                                Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                            },
                            description: {
                                Text("Add an Apple ID to start downloading IPA packages.")
                            },
                            actions: {
                                Button("Add Account") { addAccount.toggle() }
                            },
                        )
                        .padding()
                    } else {
                        accountsTable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                    AccountDetailView(accountId: id)
                }
                .navigationTitle("Accounts")
                .toolbar { macToolbar }
            }
            .sheet(isPresented: $addAccount) {
                AddAccountView()
                    .frame(minWidth: 480, idealWidth: 520, minHeight: 340, idealHeight: 380)
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .alert("Unable to Import Login", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError) }
        }

        private var accountsTable: some View {
            Table(vm.accounts, selection: $selectedID) {
                TableColumn("Email") { account in
                    Text(account.account.email)
                        .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 240, ideal: 400, max: .infinity)

                TableColumn("Region") { account in
                    Text(account.account.store)
                }
                .width(min: 72, ideal: 88, max: 100)

                TableColumn("Storefront") { account in
                    Text(ApplePackage.Configuration.countryCode(for: account.account.store) ?? String(localized: "Unknown"))
                }
                .width(min: 56, ideal: 64, max: 80)

                TableColumn("") { account in
                    Button {
                        navigationPath.append(account.id)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .width(32)
            }
            .contextMenu(forSelectionType: AppStore.UserAccount.ID.self) { ids in
                if let id = ids.first {
                    Button("View Details") {
                        navigationPath.append(id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var footer: some View {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                Text("Accounts are stored securely in your Keychain and can be removed at any time from the detail view.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        @ToolbarContentBuilder
        private var macToolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isImporting = true
                        defer { isImporting = false }
                        do {
                            let session = try await StoreAuthenticator()
                            let account = try await session.importAccount()
                            try vm.save(email: account.email, account: account)
                        } catch {
                            importError = error.localizedDescription
                            showImportError = true
                        }
                    }
                } label: {
                    Label("Import Existing Login", systemImage: "person.crop.circle.badge.checkmark")
                }
                .help("Import the ipatool account already signed in on this Mac.")
                .disabled(isImporting)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAccount.toggle()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
    #endif

    #if !os(macOS)
        private var iOSBody: some View {
            NavigationStack(path: $navigationPath) {
                Group {
                    if vm.accounts.isEmpty {
                        ContentUnavailableView(
                            label: {
                                Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
                            },
                            description: {
                                Text("Add an Apple ID to start downloading IPA packages.")
                            },
                            actions: {
                                Button("Add Account") { addAccount.toggle() }
                            },
                        )
                    } else {
                        Form {
                            Section {
                                ForEach(vm.accounts) { account in
                                    NavigationLink(value: account.id) {
                                        HStack {
                                            Text(account.account.email)
                                                .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                                            Spacer()
                                        }
                                        .badge(ApplePackage.Configuration.countryCode(for: account.account.store) ?? account.account.store)
                                    }
                                }
                            } header: {
                                Text("Apple IDs")
                            } footer: {
                                Text("Your accounts are saved in your Keychain and will be synced across devices with the same iCloud account signed in.")
                            }
                        }
                        .formStyle(.grouped)
                    }
                }
                .navigationDestination(for: AppStore.UserAccount.ID.self) { id in
                    AccountDetailView(accountId: id)
                }
                .navigationTitle("Accounts")
                .toolbar {
                    ToolbarItem {
                        Button {
                            addAccount.toggle()
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $addAccount) {
                NavigationStack {
                    AddAccountView()
                }
            }
        }
    #endif
}
