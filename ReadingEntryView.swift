import SwiftUI
import PhotosUI

struct ReadingEntryView: View {
    let accountGid: String
    let initialCategory: MeterCategory?

    @Environment(AppEnvironment.self) private var env
    @State private var vm: ReadingEntryViewModel?

    var body: some View {
        Group {
            if let vm {
                if vm.account == nil && !vm.loadError.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.danger)
                        Text(vm.loadError).foregroundStyle(Theme.ink)
                    }
                } else if vm.account != nil {
                    ReadingEntryContent(vm: vm)
                } else {
                    ProgressView()
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.background)
        .task {
            if vm == nil {
                let model = ReadingEntryViewModel(env: env, accountGid: accountGid, requestedCategory: initialCategory)
                vm = model
                await model.load()
            }
        }
        .onDisappear { vm?.turnOffFlashlight() }
    }
}

// MARK: - Content

private struct ReadingEntryContent: View {
    @Bindable var vm: ReadingEntryViewModel

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showHistory = false
    @State private var showContacts = false
    @State private var showMarginConfirm = false
    @State private var marginMessage = ""
    @State private var showCommentEditor = false
    @FocusState private var readingFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if vm.hasMultipleCategories { categoryTabs }
                accountCard
                readingCard
                photoCard

                Toggle("Go to next account when all readings are saved", isOn: $vm.goToNextAccount)
                    .font(.footnote)
                    .tint(Theme.primary)
                    .padding(.horizontal, 4)

                Button {
                    save()
                } label: {
                    if vm.isSaving {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Saving reading...") }
                    } else {
                        Text(vm.saveButtonText)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: vm.category.color))
                .disabled(vm.isSaving || vm.isProcessingImage || vm.newReadingText.isEmpty)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Reading (#\(vm.account?.rowNumber ?? 0))")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.newReadingText) { _, _ in vm.readingTextChanged() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await vm.handlePicked(image, saveToLibrary: false)
                } else {
                    vm.notice = Notice(title: "Error", message: "Error selecting image: the photo could not be loaded.")
                }
                pickerItem = nil
            }
        }
        .alert(vm.notice?.title ?? "", isPresented: Binding(get: { vm.notice != nil }, set: { if !$0 { vm.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.notice?.message ?? "")
        }
        .confirmationDialog("Warning", isPresented: $showMarginConfirm, titleVisibility: .visible) {
            Button("Yes") { Task { await vm.commitSave() } }
            Button("No", role: .cancel) {}
        } message: {
            Text(marginMessage)
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet(vm: vm)
        }
        .sheet(isPresented: $showContacts) {
            ContactsSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await vm.handlePicked(image, saveToLibrary: true) } }
            }
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { readingFocused = false }
            }
        }
    }

    // MARK: Pieces

    private var categoryTabs: some View {
        HStack(spacing: 8) {
            ForEach(vm.account?.readings ?? [], id: \.category) { reading in
                let selected = reading.category == vm.category
                Button {
                    Task { await vm.select(reading.category) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: reading.isCompleted ? "checkmark.circle.fill" : reading.category.symbol)
                        Text(reading.category.shortName)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? Color.white : (reading.isCompleted ? Theme.success : reading.category.color))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? reading.category.color : reading.category.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PREMISES").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    Text(vm.account?.premisesName ?? "").font(.headline).foregroundStyle(Theme.ink)
                }
                Spacer()
                HStack(spacing: 8) {
                    toolButton("phone.fill", tint: Theme.success) { showContacts = true }
                    toolButton("clock.arrow.circlepath", tint: Theme.primary) { showHistory = true }
                    toolButton("square.and.pencil", tint: Theme.warning) {
                        vm.beginEditingComment()
                        showCommentEditor = true
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    field("Meter No", vm.account?.meterNo ?? "")
                    field("Account No", vm.account?.accountNo ?? "")
                }
                GridRow {
                    field("Category", vm.account?.tariffCategory ?? "")
                    field("X-Factor", vm.xFactorText)
                }
                GridRow {
                    field("VO", vm.account?.visitingOrderNo ?? "")
                    Color.clear.frame(height: 1)
                }
            }

            if let comment = vm.account?.quickComment, !comment.isEmpty {
                Label(comment, systemImage: "note.text")
                    .font(.footnote).foregroundStyle(Theme.ink)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warningTint, in: RoundedRectangle(cornerRadius: 10))
            }

            if let alert = vm.account?.alertMessage, !alert.isEmpty {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.danger)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.dangerTint, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
        .alert("Quick Comment", isPresented: $showCommentEditor) {
            TextField("Enter a quick comment for this account", text: $vm.quickCommentDraft)
            Button("Save") { Task { await vm.saveComment() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(vm.category.displayName, systemImage: vm.category.symbol)
                    .font(.headline).foregroundStyle(vm.category.color)
                Spacer()
                Text("Measured in \(vm.category.unit)").font(.footnote).foregroundStyle(Theme.muted)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Previous").font(.caption).foregroundStyle(Theme.muted)
                    Text(vm.previousReadingText).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                Text(vm.previousReadingDateText).font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))

            TextField("Enter new reading", text: $vm.newReadingText)
                .keyboardType(vm.category.allowsDecimals ? .decimalPad : .numberPad)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .focused($readingFocused)
                .padding(.horizontal, 14)
                .frame(height: 60)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(vm.errorMessage.isEmpty ? (readingFocused ? vm.category.color : Theme.border) : Theme.danger, lineWidth: 1.5))

            if !vm.errorMessage.isEmpty {
                Text(vm.errorMessage).font(.footnote).foregroundStyle(Theme.danger)
            } else if vm.isValidReading {
                HStack {
                    Text(vm.totalUnitsText)
                    Spacer()
                    Text(vm.avgUnitsText)
                }
                .font(.footnote.weight(.medium)).foregroundStyle(Theme.ink)

                if let margin = vm.marginText {
                    Label(margin, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.warningTint, in: Capsule())
                }
            }
        }
        .card()
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.category.photoHint).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)

            if let image = vm.previewImage {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(height: 180).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Button { vm.removeImage() } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2)
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .padding(8)
                    }
            } else if vm.isProcessingImage {
                HStack(spacing: 8) { ProgressView(); Text("Processing image in background...").font(.footnote) }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 10) {
                photoButton("camera.fill", "Camera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        vm.notice = Notice(title: "Not Supported", message: "The camera is not available on this device.")
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    photoLabel("photo.on.rectangle", "Gallery")
                }
                photoButton(vm.isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill", "Torch") {
                    vm.toggleFlashlight()
                }
            }
        }
        .card()
    }

    // MARK: Helpers

    private func save() {
        readingFocused = false
        switch vm.validateForSave() {
        case .invalid(let message):
            vm.notice = Notice(title: "Error", message: message)
        case .needsConfirmation(let message):
            marginMessage = message
            showMarginConfirm = true
        case .ready:
            Task { await vm.commitSave() }
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func photoButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { photoLabel(symbol, title) }
            .buttonStyle(.plain)
    }

    private func photoLabel(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Theme.primaryTint, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Sheets

private struct HistorySheet: View {
    let vm: ReadingEntryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(Theme.muted)
                        Text("No History").font(.headline)
                        Text("No \(vm.category.displayName.lowercased()) bill history available for this account.")
                            .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Bill Ref").frame(maxWidth: .infinity, alignment: .leading)
                                Text("Usage").frame(maxWidth: .infinity, alignment: .trailing)
                                Text("Avg/Day").frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        ForEach(vm.history) { entry in
                            HStack {
                                Text(entry.billRef).frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.consumption.readingText(maxDecimals: 2)).frame(maxWidth: .infinity, alignment: .trailing)
                                Text(String(format: "%.2f", entry.avgCons)).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(vm.category.displayName) Bill History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .top) {
                if let account = vm.account {
                    Text("Account: \(account.accountNo)  ·  Meter: \(account.meterNo)")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Theme.background)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ContactsSheet: View {
    let vm: ReadingEntryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.contacts.isEmpty {
                    Text("No contact numbers are available for this account.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding()
                } else {
                    List(vm.contacts) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.title).font(.caption).foregroundStyle(Theme.muted)
                                Text(contact.name.isEmpty ? "—" : contact.name).font(.subheadline.weight(.semibold))
                                Text(contact.number).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button { vm.contact(via: "sms", number: contact.number) } label: {
                                Image(systemName: "message.fill")
                            }
                            .buttonStyle(.borderless)
                            Button { vm.contact(via: "tel", number: contact.number) } label: {
                                Image(systemName: "phone.fill").foregroundStyle(Theme.success)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Contact Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
