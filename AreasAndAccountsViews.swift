import SwiftUI

// MARK: - Assigned areas

struct AreasView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: AreasViewModel?

    var body: some View {
        Group {
            if let vm {
                AreasContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .task {
            if vm == nil {
                let model = AreasViewModel(env: env)
                vm = model
                await model.load()
            }
        }
    }
}

private struct AreasContent: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: AreasViewModel
    @State private var showRefreshConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dayStrip
                heroStats

                if !vm.errorMessage.isEmpty {
                    Text(vm.errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.dangerTint, in: RoundedRectangle(cornerRadius: 12))
                }

                if vm.areas.isEmpty && !vm.isLoading {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(vm.areas) { area in
                            Button {
                                env.areasPath.append(.accounts(area))
                            } label: {
                                AreaCard(area: area)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("My Areas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRefreshConfirm = true } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .overlay { if vm.isLoading && vm.areas.isEmpty { ProgressView() } }
        .refreshable { await vm.reloadProgress(); if vm.areas.isEmpty { await vm.load() } }
        .task { await vm.reloadProgress() }
        .confirmationDialog("Refresh Data", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
            Button("Refresh", role: .destructive) { Task { await vm.refreshFromServer() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all local data and refresh from server?")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(vm.greeting),").font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
            Text("Assigned areas — \(DateFormatter.make("EEE, dd MMM").string(from: vm.selectedDate))")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vm.monthLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if !vm.isTodaySelected {
                    Button("Today") { Task { await vm.goToToday() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.days) { day in
                            let selected = Calendar.current.isDate(day.date, inSameDayAs: vm.selectedDate)
                            Button {
                                Task { await vm.select(day) }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(day.weekday).font(.caption2.weight(.medium))
                                    Text(day.day).font(.headline)
                                    Circle().fill(day.isToday ? (selected ? Color.white : Theme.primary) : .clear)
                                        .frame(width: 5, height: 5)
                                }
                                .foregroundStyle(selected ? Color.white : Theme.ink)
                                .frame(width: 52, height: 68)
                                .background(selected ? Theme.primary : Color.white,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selected ? Color.clear : Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .id(day.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    if let today = vm.days.first(where: { $0.isToday }) {
                        proxy.scrollTo(today.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.overallPercentText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(vm.completedSummary).font(.footnote).foregroundStyle(Theme.primaryLight)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(vm.areaCount)").font(.title.weight(.bold))
                    Text("areas").font(.footnote).foregroundStyle(Theme.primaryLight)
                }
            }
            ProgressBar(value: vm.overallProgress, tint: .white, height: 8)
                .background(Color.white.opacity(0.2), in: Capsule())
            HStack {
                Text("\(vm.accountsTotal) accounts")
                Spacer()
                Text("\(vm.accountsRemaining) left")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.primaryLight)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "map").font(.system(size: 36)).foregroundStyle(Theme.muted)
            Text("No areas assigned for this day").font(.headline).foregroundStyle(Theme.ink)
            Text("Pick another date above or pull down to refresh")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct AreaCard: View {
    let area: AreaAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(area.orderNumber)")
                    .font(.headline)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primaryTint, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.areaName).font(.headline).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text("\(area.accountCount) accounts · \(area.remaining) left")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
                StatusPill(text: area.statusText, color: area.statusColor, tint: area.statusTint)
            }
            HStack(spacing: 10) {
                ProgressBar(value: area.progress, tint: area.statusColor)
                Text(area.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }
}

// MARK: - Accounts in an area

struct AccountsView: View {
    let area: AreaAssignment
    @Environment(AppEnvironment.self) private var env
    @State private var vm: AccountsViewModel?

    var body: some View {
        Group {
            if let vm {
                AccountsContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(area.areaName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                let model = AccountsViewModel(env: env, area: area)
                vm = model
                await model.load()
            } else {
                await vm?.reloadLocal()
            }
        }
    }
}

private struct AccountsContent: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: AccountsViewModel
    @State private var showRefreshConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                summary

                if !vm.errorMessage.isEmpty {
                    Text(vm.errorMessage)
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.dangerTint, in: RoundedRectangle(cornerRadius: 12))
                }

                if vm.filtered.isEmpty && !vm.isLoading {
                    Text("No accounts found in this area")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }

                ForEach(vm.filtered) { account in
                    AccountRow(account: account,
                               openAccount: { env.areasPath.append(.reading(accountGid: account.gid, category: nil)) },
                               openCategory: { category in env.areasPath.append(.reading(accountGid: account.gid, category: category)) })
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Account, meter or premises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRefreshConfirm = true } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .overlay { if vm.isLoading && vm.accounts.isEmpty { ProgressView() } }
        .refreshable { await vm.reloadLocal() }
        .confirmationDialog("Refresh Data", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
            Button("Refresh", role: .destructive) { Task { await vm.refreshFromServer() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all local data for this area and refresh from server?")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(vm.completedAccounts) of \(vm.totalAccounts) accounts read")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(vm.completionPercentText).font(.subheadline.weight(.bold)).foregroundStyle(Theme.primary)
            }
            ProgressBar(value: vm.completionProgress)
        }
        .card()
    }
}

private struct AccountRow: View {
    let account: AccountMeter
    let openAccount: () -> Void
    let openCategory: (MeterCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: openAccount) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(account.isFullyCompleted ? Theme.successTint : Theme.primaryTint)
                        if account.isFullyCompleted {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.success)
                        } else {
                            Text("\(account.rowNumber)").font(.footnote.weight(.bold)).foregroundStyle(Theme.primary)
                        }
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.premisesName).font(.headline).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Group {
                            Text("Account No: \(account.accountNo)")
                            Text("Mtr No: \(account.meterNo)")
                            Text("Tariff: \(account.tariffCategory)  ·  VO No: \(account.visitingOrderNo)")
                        }
                        .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)

            if !account.alertMessage.isEmpty {
                Label(account.alertMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.dangerTint, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                ForEach(account.readings, id: \.category) { reading in
                    Button { openCategory(reading.category) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: reading.isCompleted ? "checkmark.circle.fill" : reading.category.symbol)
                            Text(reading.category.shortName)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reading.isCompleted ? Theme.success : reading.category.color)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(reading.isCompleted ? Theme.successTint : reading.category.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if account.hasMultipleCategories {
                    Text(account.completionText).font(.caption).foregroundStyle(Theme.muted)
                }
                if account.isFullyCompleted && !account.isFullySynced {
                    Image(systemName: "icloud.and.arrow.up").font(.caption).foregroundStyle(Theme.warning)
                }
            }
        }
        .card()
    }
}
