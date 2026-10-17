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

struct BrowserScreen: View {
    @StateObject private var model = BrowserModel()
    @State private var showDiagnostics = false
    @State private var showHelp = false
    @FocusState private var editing: Bool
    private let mint = Color(red: 0.47, green: 0.88, blue: 0.73)
    var body: some View {
        VStack(spacing: 0) {
            if !model.controlsHidden {
                HStack {
                    Image(systemName: "link").foregroundStyle(mint)
                    Text("LinkCapture").font(.headline).lineLimit(1)
                    Spacer()
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Ajuda")
                    Button { showDiagnostics = true } label: { Image(systemName: "waveform.path.ecg") }.accessibilityLabel("Diagnóstico")
                }.padding(.horizontal).padding(.vertical, 12)
                HStack(spacing: 8) {
                    TextField("https://endereço", text: $model.address)
                        .font(.system(size: 16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).submitLabel(.go).focused($editing)
                        .onSubmit { editing = false; model.open() }.accessibilityIdentifier("address")
                    Button { model.address = UIPasteboard.general.string ?? model.address } label: { Image(systemName: "doc.on.clipboard") }.accessibilityLabel("Colar")
                    Button { editing = false; model.open() } label: { Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(mint) }.accessibilityLabel("Abrir link").accessibilityIdentifier("go")
                }.padding(12).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal).padding(.bottom, 10)
            }
            ZStack {
                NativeWebView(view: model.webView).id(ObjectIdentifier(model.webView))
                if model.originalURL.isEmpty || model.webView.isHidden {
                    VStack(spacing: 18) {
                        Image(systemName: "link.circle").font(.system(size: 64)).foregroundStyle(mint)
                        Text("Seus links, aqui dentro.").font(.title2.weight(.semibold))
                        Text("Navegador nativo experimental\nWKWebView · sem servidor remoto").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Testar 62qpix.vip") { editing = false; model.open("https://62qpix.vip") }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.04, green: 0.06, blue: 0.09))
                }
                if model.recovering {
                    VStack(spacing: 16) {
                        ProgressView().tint(mint)
                        Text("REABRINDO LINK... AGUARDE").font(.footnote.weight(.semibold))
                        Button("Cancelar") { model.stop() }.font(.footnote).tint(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.92))
                }
            }
            if !model.controlsHidden {
                if model.loading && !model.recovering { ProgressView().tint(mint).frame(height: 12) }
                if !model.recovering { Text(model.message).font(.caption2).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal).padding(.top, 5) }
                HStack {
                    nav("chevron.left", "Voltar", disabled: !model.canGoBack) { model.back() }
                    Spacer(); nav("chevron.right", "Avançar", disabled: !model.canGoForward) { model.forward() }
                    Spacer(); nav("house", "Início") { model.home() }
                    Spacer(); nav(model.loading ? "xmark" : "arrow.clockwise", model.loading ? "Parar" : "Atualizar") { model.loading ? model.stop() : model.reload() }
                    Spacer(); nav("viewfinder", "Recolher controles") { editing = false; model.controlsHidden = true }
                }.padding(.horizontal, 22).padding(.vertical, 8)
            } else {
                Button { model.controlsHidden = false } label: { Image(systemName: "chevron.up").frame(width: 60, height: 28) }.accessibilityLabel("Mostrar controles")
            }
        }.background(Color(red: 0.06, green: 0.08, blue: 0.12)).tint(mint)
            .sheet(isPresented: $showDiagnostics) { DiagnosticScreen(model: model) }
            .sheet(isPresented: $showHelp) { help }
    }
    private func nav(_ symbol: String, _ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.disabled(disabled).accessibilityLabel(label)
    }
    private var help: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("Navegação independente").font(.title2.bold())
            Text("A página abre no WKWebView deste app. Nenhum VPS ou notebook é usado durante a navegação. DNS alternativo é consultado por um proxy local no iPhone quando necessário.")
            Text("Versão experimental").font(.headline)
            Text("Um único app para iOS 16 ou superior. No iOS 16, há reteste direto e diagnóstico DNS informativo; não há recuperação por proxy do WKWebView. No iOS 17+, o proxy experimental usa APIs públicas. Ainda precisa de validação: dados DNS não garantem acesso, TLS válido não garante conteúdo e WebKit pode se comportar diferente do Android/Chromium.")
            Text("Assinatura gratuita").font(.headline)
            Text("AltStore Classic exige renovação da assinatura normalmente a cada 7 dias. O Windows precisa estar disponível para instalar/renovar, mas pode ficar desligado enquanto você navega com assinatura válida.")
            Text("Privacidade e capturas").font(.headline)
            Text("Cookies ficam na sessão em memória. O último endereço fica salvo neste iPhone. Diagnósticos podem conter URLs completas e parâmetros: revise antes de compartilhar. DNS envia hostnames a Cloudflare/Google. Capturas usam os botões nativos do iPhone; recolha os controles se desejar.")
            Text("O proxy experimental admite TCP nas portas 80/443 e destinos públicos. Não intercepta TLS, não ignora certificado e não fornece VPN, UDP/QUIC ou acesso à rede local. Apps externos e pop-ups automáticos são bloqueados. Reconstruir a view para recuperar pode perder o histórico voltar/avançar; cookies da sessão são mantidos pelo data store.")
        }.padding() }.navigationTitle("Sobre o LinkCapture").toolbar { Button("Fechar") { showHelp = false } } }
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
