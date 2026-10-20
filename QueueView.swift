import SwiftUI

struct QueueView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: QueueViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    QueueContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Queued logs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if vm == nil { vm = QueueViewModel(env: env) }
            await vm?.load()
        }
        // Keep the list fresh as the sync engine works through it.
        .onChange(of: env.pendingCount) { _, _ in
            Task { await vm?.load() }
        }
        .onChange(of: env.selectedTab) { _, tab in
            if tab == .queue { Task { await vm?.load() } }
        }
    }
}

private struct QueueContent: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: QueueViewModel
    @State private var notice: Notice?

    var body: some View {
        Group {
            if !vm.hasItems {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.success)
                    Text("All caught up!").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("No readings waiting to sync").font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary
                        ForEach(vm.readings) { reading in
                            QueuedRow(reading: reading)
                                .contextMenu {
                                    if reading.isRejected {
                                        Button(role: .destructive) {
                                            Task { await vm.delete(reading) }
                                        } label: { Label("Discard", systemImage: "trash") }
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await vm.load() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { notice = await vm.submitAll() }
                } label: {
                    if vm.isSyncing || env.sync.isSyncing {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(vm.isSyncing || env.sync.isSyncing)
            }
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice?.message ?? "")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.pendingCount > 0 {
                Label(vm.pendingCountText, systemImage: "clock")
                    .foregroundStyle(Theme.primary)
            }
            if vm.rejectedCount > 0 {
                Label(vm.rejectedCountText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
            if !env.network.isOnline {
                Label("Offline — readings stay safely queued until you're back online.", systemImage: "wifi.slash")
                    .foregroundStyle(Theme.muted)
            } else if vm.pendingCount > 0 {
                Text("Pull down or tap Sync to send").foregroundStyle(Theme.muted)
            }
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct QueuedRow: View {
    let reading: QueuedReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: reading.category.symbol)
                    .foregroundStyle(reading.category.color)
                    .frame(width: 38, height: 38)
                    .background(reading.category.tint, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.category.displayName).font(.headline).foregroundStyle(Theme.ink)
                    Text("Acc: \(reading.accountNo) · Meter: \(reading.meterNo)")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Text(reading.readingText).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                StatusPill(text: reading.statusText,
                           color: reading.isRejected ? Theme.danger : Theme.primary,
                           tint: reading.isRejected ? Theme.dangerTint : Theme.primaryTint)
            }

            HStack(spacing: 12) {
                Label(DateFormatter.make("dd MMM, HH:mm").string(from: reading.createdDate), systemImage: "clock")
                if reading.hasFile { Label("1 photo", systemImage: "paperclip") }
            }
            .font(.caption).foregroundStyle(Theme.muted)

            if reading.isRejected, let message = reading.rejectionMessage {
                Text(message)
                    .font(.footnote).foregroundStyle(Theme.danger)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.dangerTint, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
    }
}
