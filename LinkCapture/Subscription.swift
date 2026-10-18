import SwiftUI
import UserNotifications

struct RenewalPreferences: Codable, Equatable {
    var expiration: Date?
    var enabled = false
    var daily = true
    var urgent = true
    var hour = 10
    var minute = 0
}

struct RenewalReminder: Equatable {
    let identifier: String
    let date: Date
    let days: Int
    let message: String
    let sound: Bool
}

enum RenewalPlan {
    static let prefix = "linkcapture.renewal."
    static let messages = [
        6: "Faltam 6 dias para renovar o LinkCapture.",
        5: "Faltam 5 dias para renovar o LinkCapture.",
        4: "Faltam 4 dias para renovar o LinkCapture.",
        3: "Faltam 3 dias para renovar o LinkCapture.",
        2: "Faltam apenas 2 dias! Prepare a renovação pelo AltStore.",
        1: "ATENÇÃO! Seu LinkCapture vence amanhã. Renove pelo AltStore.",
        0: "Hoje é o dia de renovar sua assinatura do LinkCapture!"
    ]
    static func daysRemaining(_ expiration: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiration)).day ?? 0
    }
    static func make(_ prefs: RenewalPreferences, now: Date = Date(), calendar: Calendar = .current) -> [RenewalReminder] {
        guard prefs.enabled, let expiration = prefs.expiration, expiration > now,
              (0...23).contains(prefs.hour), (0...59).contains(prefs.minute) else { return [] }
        return (0...6).reversed().compactMap { days in
            guard days <= 2 ? prefs.urgent : prefs.daily,
                  let day = calendar.date(byAdding: .day, value: -days, to: expiration),
                  let preferred = calendar.date(bySettingHour: prefs.hour, minute: prefs.minute, second: 0, of: day) else { return nil }
            // Never schedule after the supplied expiration. A day-zero alert may
            // run earlier than the configured hour; pre-expiration alerts matter most.
            let fire = days == 0 ? min(preferred, expiration.addingTimeInterval(-60)) : preferred
            guard fire > now, calendar.isDate(fire, inSameDayAs: day) else { return nil }
            return RenewalReminder(identifier: prefix + String(days), date: fire, days: days,
                                   message: messages[days]!, sound: days <= 2)
        }
    }
}

// Serializes replacement operations, including asynchronous notification adds.
// A later preference change always replaces the complete earlier plan.
actor RenewalScheduler {
    private let center = UNUserNotificationCenter.current()
    private var tail: Task<Void, Never>?
    func replace(with plan: [RenewalReminder]) async throws {
        let previous = tail
        let center = self.center
        let operation = Task {
            await previous?.value
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(RenewalPlan.prefix) })
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(RenewalPlan.prefix) })
            for reminder in plan {
                let content = UNMutableNotificationContent()
                content.title = reminder.days <= 2 ? "Renovação do LinkCapture" : "Lembrete do LinkCapture"
                content.body = reminder.message
                if reminder.sound { content.sound = .default }
                content.interruptionLevel = .active // No critical/time-sensitive entitlement.
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                components.timeZone = Calendar.current.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
            }
        }
        tail = Task { _ = try? await operation.value }
        try await operation.value
    }
}

struct Catalog: Decodable {
    struct App: Decodable {
        struct Version: Decodable { let version: String; let buildVersion: String; let downloadURL: String; let size: Int }
        let bundleIdentifier: String
        let versions: [Version]
    }
    let apps: [App]
    func latest(for identifier: String) -> App.Version? { apps.first { $0.bundleIdentifier == identifier }?.versions.first }
    static func isNewer(version: String, build: String, than currentVersion: String, currentBuild: String) -> Bool {
        let comparison = version.compare(currentVersion, options: .numeric)
        return comparison == .orderedDescending || (comparison == .orderedSame && build.compare(currentBuild, options: .numeric) == .orderedDescending)
    }
}

@MainActor final class SubscriptionModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let sourceURL = URL(string: "https://largartozaulnj.github.io/linkcapture-ios-native/source.json")!
    static let pageURL = URL(string: "https://largartozaulnj.github.io/linkcapture-ios-native/")!
    static let bundleID = "org.linkcapture.experimental"
    static let preferencesKey = "linkcapture.renewal.preferences.v1"
    @Published var preferences: RenewalPreferences
    @Published var notificationStatus = "Ainda não consultado"
    @Published var scheduledCount = 0
    @Published var updateStatus = "Toque em Verificar atualizações."
    @Published var checking = false
    @Published var error: String?
    private let defaults: UserDefaults
    private let scheduler = RenewalScheduler()
    private var syncTask: Task<Void, Never>?
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var remaining: Int? { preferences.expiration.map { RenewalPlan.daysRemaining($0, now: Date(), calendar: .current) } }
    var expired: Bool { preferences.expiration.map { $0 <= Date() } ?? false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.preferencesKey).flatMap { try? JSONDecoder().decode(RenewalPreferences.self, from: $0) } ?? RenewalPreferences()
        super.init()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    func refresh() async {
        UNUserNotificationCenter.current().delegate = self
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: notificationStatus = "Permitidas"
        case .provisional: notificationStatus = "Entrega silenciosa"
        case .ephemeral: notificationStatus = "Permissão temporária"
        case .denied: notificationStatus = "Bloqueadas nos Ajustes"
        case .notDetermined: notificationStatus = "Permissão ainda não solicitada"
        @unknown default: notificationStatus = "Status desconhecido"
        }
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        do {
            try await scheduler.replace(with: allowed ? RenewalPlan.make(preferences) : [])
            scheduledCount = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix(RenewalPlan.prefix) }.count
        } catch { self.error = "Não foi possível agendar todos os lembretes: \(error.localizedDescription)" }
    }
    func save() {
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: Self.preferencesKey) }
        catch { self.error = "Não foi possível salvar as preferências." }
        syncTask?.cancel()
        syncTask = Task { await refresh() }
    }
    func setExpiration(_ date: Date) { preferences.expiration = date; save() }
    func authorize() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            preferences.enabled = granted; save()
        } catch { self.error = "Não foi possível solicitar permissão: \(error.localizedDescription)" }
    }
    func checkForUpdates() async {
        guard !checking else { return }; checking = true
        defer { checking = false }
        do {
            let request = URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
                  let version = try JSONDecoder().decode(Catalog.self, from: data).latest(for: Self.bundleID),
                  version.size > 0, version.downloadURL.hasPrefix("https://github.com/largartozaulnj/linkcapture-ios-native/releases/download/") else { throw URLError(.cannotParseResponse) }
            updateStatus = Catalog.isNewer(version: version.version, build: version.buildVersion, than: currentVersion, currentBuild: currentBuild)
                ? "Disponível: \(version.version) (\(version.buildVersion)). Abra o AltStore para revisar e autorizar a atualização."
                : "Versão atual: \(currentVersion) (\(currentBuild)). Nenhuma versão mais nova no catálogo."
        } catch { updateStatus = "Catálogo indisponível: \(error.localizedDescription). Tente novamente com internet." }
    }
    func openAltStore() {
        UIApplication.shared.open(URL(string: "altstore-classic://")!, options: [:]) { opened in
            if !opened { UIApplication.shared.open(URL(string: "altstore://")!, options: [:]) { fallback in
                if !fallback { Task { @MainActor in self.error = "Não foi possível abrir o AltStore. Abra-o pela tela inicial do iPhone." } }
            } }
        }
    }
}

struct SubscriptionScreen: View {
    @ObservedObject var model: SubscriptionModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDate = false
    @State private var showReminderSettings = false
    @State private var proposedDate = Date()
    @State private var confirmDate = false
    var body: some View {
        NavigationStack {
            List {
                Section("Assinatura") {
                    LabeledContent("Versão atual", value: "\(model.currentVersion) (\(model.currentBuild))")
                    if let expiration = model.preferences.expiration {
                        LabeledContent("Vencimento informado") { Text(expiration, format: .dateTime.day().month().year().hour().minute()) }
                        Label(model.expired ? "Prazo informado vencido" : "\(max(0, model.remaining ?? 0)) dias restantes no calendário", systemImage: model.expired ? "exclamationmark.circle.fill" : "calendar")
                            .foregroundStyle(model.expired || (model.remaining ?? 7) <= 2 ? Color.orange : Color.secondary)
                    } else { Text("Data de vencimento desconhecida. Informe a data exibida no AltStore.").foregroundStyle(.secondary) }
                    Button("RENOVEI PELO ALTSTORE") { proposedDate = model.preferences.expiration ?? Date(); showDate = true }
                    Text("Data manual confirmada por você. Abrir o app não muda o vencimento. Não há leitura automática confiável da validade do AltStore nesta versão.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Lembretes locais") {
                    LabeledContent("Notificações", value: model.notificationStatus)
                    LabeledContent("Agendados", value: String(model.scheduledCount))
                    Button("Configurar lembretes") { showReminderSettings = true }
                    Text("Avisos de 6 a 0 dias, com prioridade para 2 e 1 dia antes. Não dependem de internet depois de agendados. Foco e ajustes do iOS podem silenciá-los.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Atualizações") {
                    Button { Task { await model.checkForUpdates() } } label: { HStack { Text("Verificar atualizações"); if model.checking { ProgressView() } } }.disabled(model.checking)
                    Text(model.updateStatus).font(.footnote).foregroundStyle(.secondary)
                    Button("Abrir AltStore") { model.openAltStore() }
                    Link("Adicionar fonte oficial", destination: SubscriptionModel.pageURL)
                    Text("O catálogo não renova nem instala sozinho. Revise a atualização e autorize-a no AltStore; a assinatura gratuita pode exigir AltServer.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.orange) } }
            }.navigationTitle("Assinatura e Atualizações").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Fechar") { dismiss() } }
                .task { await model.refresh() }
                .sheet(isPresented: $showReminderSettings) { reminderSettings }
                .sheet(isPresented: $showDate) { dateEditor }
        }
    }
    private var dateEditor: some View {
        NavigationStack {
            Form {
                Text("Consulte o vencimento no AltStore e confirme a data e hora. Nenhum prazo de sete dias será calculado automaticamente.")
                DatePicker("Vencimento", selection: $proposedDate, displayedComponents: [.date, .hourAndMinute])
                Button("Confirmar nova data") { confirmDate = true }
            }.navigationTitle("Vencimento").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Cancelar") { showDate = false } }
                .alert("Confirmar vencimento informado?", isPresented: $confirmDate) {
                    Button("Salvar e reagendar") { model.setExpiration(proposedDate); showDate = false }
                    Button("Cancelar", role: .cancel) {}
                } message: { Text(proposedDate.formatted(date: .complete, time: .shortened)) }
        }
    }
    private var reminderSettings: some View {
        NavigationStack {
            Form {
                Toggle("Ativar lembretes", isOn: Binding(get: { model.preferences.enabled }, set: { model.preferences.enabled = $0; model.save() }))
                Toggle("Lembretes diários: 6 a 3 dias", isOn: Binding(get: { model.preferences.daily }, set: { model.preferences.daily = $0; model.save() }))
                Toggle("Alertas urgentes: 2, 1 e 0 dias", isOn: Binding(get: { model.preferences.urgent }, set: { model.preferences.urgent = $0; model.save() }))
                DatePicker("Horário", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: model.preferences.hour, minute: model.preferences.minute, second: 0, of: Date()) ?? Date()
                }, set: { date in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                    model.preferences.hour = components.hour ?? 10; model.preferences.minute = components.minute ?? 0; model.save()
                }), displayedComponents: .hourAndMinute)
                Button("Solicitar permissão de notificações") { Task { await model.authorize() } }
                Button("Abrir Ajustes de notificações") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                Text("Urgentes são avisos locais comuns com som, sem alertas críticos e sem contornar o modo Foco. No dia final, o horário pode ser antecipado para antes do vencimento informado. Se mudar de fuso, abra o app para reagendar.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Lembretes").navigationBarTitleDisplayMode(.inline).toolbar { Button("Fechar") { showReminderSettings = false } }
        }
    }
}
