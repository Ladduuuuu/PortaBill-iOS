import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = LoginViewModel()
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        @Bindable var vm = vm

        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Replace the symbol with your logo asset when you have one.
                    ZStack {
                        Circle().fill(Theme.primary).frame(width: 84, height: 84)
                        Image(systemName: "bolt.fill").font(.system(size: 38)).foregroundStyle(.white)
                    }

                    VStack(spacing: 6) {
                        Text("PortaBill").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                        Text("\(AppConfig.productSubtitle) · \(AppConfig.organizationName)")
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome back").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("Sign in with your domain account to start today's readings.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        fieldContainer(focused: focus == .username) {
                            Image(systemName: "person").foregroundStyle(Theme.muted)
                            TextField("Staff ID", text: $vm.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.next)
                                .focused($focus, equals: .username)
                                .onSubmit { focus = .password }
                        }

                        fieldContainer(focused: focus == .password) {
                            Image(systemName: "lock").foregroundStyle(Theme.muted)
                            Group {
                                if vm.isPasswordHidden {
                                    SecureField("Password", text: $vm.password)
                                } else {
                                    TextField("Password", text: $vm.password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                            }
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit { signIn() }

                            Button {
                                vm.isPasswordHidden.toggle()
                            } label: {
                                Image(systemName: vm.isPasswordHidden ? "eye" : "eye.slash").foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    if !vm.errorMessage.isEmpty {
                        Text(vm.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        signIn()
                    } label: {
                        if vm.isBusy {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Signing in…")
                            }
                        } else {
                            Text("Sign in")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!vm.canLogin)

                    Text("Readings are stored on the device and synced securely.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 24)

                    VStack(spacing: 2) {
                        Text("© \(String(Calendar.current.component(.year, from: Date()))) \(AppConfig.organizationName)")
                        Text(AppConfig.appVersion)
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func signIn() {
        focus = nil
        Task { await vm.login(env: env) }
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(focused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Theme.primary : Theme.border, lineWidth: focused ? 1.5 : 1)
            )
    }
}
