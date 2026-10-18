import SwiftUI
import WebKit

@main struct LinkCaptureApp: App {
    var body: some Scene { WindowGroup { BrowserScreen().preferredColorScheme(.dark) } }
}

struct NativeWebView: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor struct BrowserScreen: View {
    @StateObject private var model: BrowserModel
    @State private var showDiagnostics = false
    @State private var showConnection = false
    @State private var showHelp = false
    @State private var editingAddress = false
    @FocusState private var addressFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.47, green: 0.88, blue: 0.73)
    private let chrome = Color(red: 0.12, green: 0.13, blue: 0.14)
    private let field = Color(red: 0.19, green: 0.20, blue: 0.21)

    init() { _model = StateObject(wrappedValue: BrowserModel()) }
    // UI tests inject the same navigation model to verify the real web view frame.
    init(model: BrowserModel) { _model = StateObject(wrappedValue: model) }

    private var currentURL: String { model.webView.url?.absoluteString ?? model.address }
    private var displayAddress: String {
        guard let url = URL(string: currentURL), let host = url.host else { return currentURL }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    private var isHome: Bool { model.originalURL.isEmpty || model.webView.isHidden }

    var body: some View {
        VStack(spacing: 0) {
            if !model.controlsHidden { addressBar }
            ZStack {
                NativeWebView(view: model.webView).id(ObjectIdentifier(model.webView))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isHome { home }
                if model.recovering { recovery }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if !model.controlsHidden {
                if !model.loading && !model.recovering && model.result == "Falha ou inconclusivo" {
                    HStack(spacing: 10) {
                        Text("Não foi possível confirmar a abertura.").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Detalhes") { showDiagnostics = true }.font(.caption.weight(.semibold))
                    }.padding(.horizontal, 16).padding(.vertical, 8).background(chrome)
                }
                bottomBar
            } else {
                Button { setControlsHidden(false) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }.accessibilityLabel("Mostrar controles").background(chrome)
            }
        }
        .background(chrome.ignoresSafeArea(.container, edges: [.top, .bottom]))
        .tint(accent)
        .onChange(of: addressFocused) { focused in if !focused { editingAddress = false } }
        .sheet(isPresented: $showDiagnostics) { DiagnosticScreen(model: model) }
        .sheet(isPresented: $showConnection) { connection }
        .sheet(isPresented: $showHelp) { help }
    }

    private var addressBar: some View {
        HStack(spacing: 0) {
            Group {
                if model.loading { ProgressView().controlSize(.small).tint(accent) }
                else { Image(systemName: "globe").foregroundStyle(.secondary) }
            }.frame(width: 36).accessibilityHidden(true)
            if editingAddress {
                TextField("Pesquisar ou digitar URL", text: $model.address)
                    .font(.system(size: 16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).submitLabel(.go).focused($addressFocused)
                    .onSubmit { openAddress() }.accessibilityLabel("Endereço")
                    .accessibilityIdentifier("address")
                    .task { addressFocused = true }
            } else {
                Button { beginEditing() } label: {
                    Text(displayAddress.isEmpty ? "Digite um endereço" : displayAddress)
                        .font(.system(size: 16)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Editar endereço")
                    .accessibilityValue(currentURL).accessibilityIdentifier("addressDisplay")
            }
            if editingAddress {
                Button { openAddress() } label: {
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel("Abrir link").accessibilityIdentifier("go")
            } else {
                Button { model.loading ? model.stop() : model.reload() } label: {
                    Image(systemName: model.loading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                }.foregroundStyle(.primary).accessibilityLabel(model.loading ? "Parar carregamento" : "Atualizar página")
            }
        }
        .background(field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12).padding(.vertical, 6).background(chrome)
        .accessibilityIdentifier("addressBar")
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            nav("chevron.left", "Voltar", disabled: !model.canGoBack) { finishEditing(); model.back() }
            nav("chevron.right", "Avançar", disabled: !model.canGoForward) { finishEditing(); model.forward() }
            nav("house", "Página inicial") { finishEditing(); model.home() }
            nav(model.loading ? "xmark" : "arrow.clockwise", model.loading ? "Parar" : "Atualizar") {
                finishEditing(); model.loading ? model.stop() : model.reload()
            }
            Menu {
                Button { model.diagnoseDNS(); showDiagnostics = true } label: { Label("Diagnóstico DNS", systemImage: "waveform.path.ecg") }
                Button { showConnection = true } label: { Label("Informações da conexão", systemImage: "network") }
                Button { UIPasteboard.general.string = currentURL } label: { Label("Copiar URL", systemImage: "doc.on.doc") }
                if let url = URL(string: currentURL) { ShareLink(item: url) { Label("Compartilhar", systemImage: "square.and.arrow.up") } }
                Button { model.address = UIPasteboard.general.string ?? model.address; beginEditing(preserveDraft: true) } label: { Label("Colar endereço", systemImage: "doc.on.clipboard") }
                Button { finishEditing(); model.reload() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                Button { setControlsHidden(true) } label: { Label("Recolher controles", systemImage: "viewfinder") }
                Button { showHelp = true } label: { Label("Ajuda", systemImage: "questionmark.circle") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 56).contentShape(Rectangle())
            }.accessibilityLabel("Menu de opções").accessibilityIdentifier("options")
        }
        .foregroundStyle(Color(white: 0.88)).background(chrome)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
        .accessibilityIdentifier("bottomBar")
    }

    private func nav(_ symbol: String, _ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 56).contentShape(Rectangle())
        }.disabled(disabled).opacity(disabled ? 0.28 : 1).accessibilityLabel(label)
    }
    private func beginEditing(preserveDraft: Bool = false) {
        if !preserveDraft { model.address = currentURL }
        editingAddress = true
    }
    private func finishEditing() { addressFocused = false; editingAddress = false }
    private func openAddress() { finishEditing(); model.open() }
    private func setControlsHidden(_ hidden: Bool) {
        finishEditing()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.controlsHidden = hidden }
    }
    private var home: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill").font(.system(size: 42, weight: .light)).foregroundStyle(accent)
            Text("Seu próximo destino").font(.title2.weight(.semibold))
            Text("Digite ou cole um endereço para navegar.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Digitar endereço") { beginEditing() }.buttonStyle(.bordered).tint(accent)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }
    private var recovery: some View {
        VStack(spacing: 16) {
            ProgressView().tint(accent)
            Text("REABRINDO LINK... AGUARDE").font(.footnote.weight(.semibold))
            Button("Cancelar") { model.stop() }.font(.footnote).tint(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.92))
    }
    private var connection: some View {
        NavigationStack {
            List {
                LabeledContent("Rede", value: model.connectionType)
                LabeledContent("Estratégia", value: model.mode)
                LabeledContent("Tentativas", value: String(model.attempt))
                LabeledContent("HTTP", value: model.httpStatus.map { String($0) } ?? "Não observado")
                Text("URL atual: \(currentURL)").textSelection(.enabled)
                Text("Resultado: \(model.result)")
                Text("Erro: \(model.identifiedError)")
            }.navigationTitle("Conexão").toolbar { Button("Fechar") { showConnection = false } }
        }
    }
    private var help: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("Navegação independente").font(.title2.bold())
            Text("Os sites abrem dentro deste aplicativo. Use o menu para consultar a conexão e o diagnóstico, compartilhar o endereço ou recolher os controles antes de uma captura nativa do iPhone.")
            Text("Recuperação experimental").font(.headline)
            Text("No iOS 16 há reteste direto e diagnóstico DNS informativo. No iOS 17+, a recuperação por proxy local usa APIs públicas e mantém a validação HTTPS. Dados DNS não garantem acesso nem conteúdo correto. Certificados inválidos não são ignorados.")
            Text("Assinatura gratuita").font(.headline)
            Text("AltStore Classic normalmente exige renovação a cada sete dias. O Windows é necessário para instalar/renovar, mas pode ficar desligado durante a navegação com assinatura válida.")
            Text("Privacidade").font(.headline)
            Text("Cookies ficam na sessão em memória. O último endereço fica salvo no iPhone. Diagnósticos podem conter URLs e parâmetros: revise antes de compartilhar. DNS envia hostnames a Cloudflare/Google. O proxy só admite TCP 80/443 e destinos públicos; não fornece VPN ou ignora certificados. Recuperação pode recriar a view e perder o histórico voltar/avançar.")
        }.padding() }.navigationTitle("Ajuda").toolbar { Button("Fechar") { showHelp = false } } }
    }
}

struct DiagnosticScreen: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Navegação") {
                    LabeledContent("Tentativas", value: String(model.attempt))
                    LabeledContent("Estratégia", value: model.mode)
                    Text(model.proxyCapability)
                    LabeledContent("Rede", value: model.connectionType)
                    Text("Original: \(model.originalURL)").textSelection(.enabled)
                    Text("URL atual/final: \(model.finalURL)").textSelection(.enabled)
                    Text("Erro: \(model.identifiedError)")
                    Text("Resultado: \(model.result)")
                    Button("Confirmo que o conteúdo correto está visível") { model.confirmVisibleContent() }
                }
                Section("Testes e recuperação") {
                    Button("Consultar DNS alternativo (informativo)") { model.diagnoseDNS() }
                    if #available(iOS 17.0, *) {
                        Button("Reabrir usando proxy local + DNS alternativo") { model.open(forceDNS: true); dismiss() }
                    } else {
                        Text("Proxy local exige iOS 17+. No iOS 16, use o reteste direto e ajuste o DNS do Wi-Fi se necessário.").font(.footnote).foregroundStyle(.secondary)
                        Button("Reabrir com conexão normal") { model.open(); dismiss() }
                    }
                    Button("Voltar ao modo direto") { model.normalMode(); dismiss() }
                    Button("Reabrir caso real 62qpix.vip") { model.open("https://62qpix.vip"); dismiss() }
                    Button("Testar /launch explicitamente") { model.open("https://62qpix.vip/launch"); dismiss() }
                }
                Section("Relatório local — revise URLs antes de copiar") {
                    Button("Copiar relatório") { UIPasteboard.general.string = model.report }
                    Text(model.report).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }
            }.navigationTitle("Diagnóstico").toolbar { Button("Fechar") { dismiss() } }
        }
    }
}

