import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var confirmsDeleteAll = false
    @State private var deleteFailed = false
    @State private var isDeleting = false

    var body: some View {
        Form {
            Section("Offline režim") {
                Text("SpotGear funguje bez internetu, účtu i serveru. Fotografie, sbírka i jejich zpracování zůstávají v tomto zařízení.")
            }
            .listRowBackground(Theme.panel)

            Section("Identifikace aut") {
                identificationStatus
                Text("Odstranění pozadí probíhá lokálně pomocí systémového rozhraní Vision, pokud jej zařízení podporuje. Jinak karta použije fotografický výřez.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.panel)

            Section("Pixel art") {
                Text("Pixelové karty vznikají přímo ve vašem zařízení zmenšením vlastní fotografie a omezením barev. Nic se negeneruje ani neodesílá a původní fotografie zůstává beze změny.")
            }
            .listRowBackground(Theme.panel)

            Section("Data a zálohy") {
                Text("Sbírka je uložena v datech aplikace v tomto zařízení. Může být součástí systémové zálohy do iCloudu nebo počítače. Odinstalováním aplikace se sbírka smaže.")
            }
            .listRowBackground(Theme.panel)

            Section {
                Button(role: .destructive) {
                    confirmsDeleteAll = true
                } label: {
                    HStack {
                        Label("Smazat celou sbírku", systemImage: "trash")
                        if isDeleting { Spacer(); PixelLoadingIndicator() }
                    }
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("settings.deleteAll")
            } footer: {
                if deleteFailed {
                    Text("Sbírku se nepodařilo smazat. Data zůstala beze změny.")
                        .foregroundStyle(Theme.danger)
                }
            }
            .listRowBackground(Theme.panel)
        }
        .pixelListBackground()
        .navigationTitle("Nastavení")
        .confirmationDialog("Smazat celou sbírku?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Smazat všechna auta a fotografie", role: .destructive, action: deleteAll)
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Odstraní se všechny karty, poznámky i uložené fotografie. Tuto akci nelze vrátit.")
        }
    }

    @ViewBuilder
    private var identificationStatus: some View {
        switch services.identifier.availability {
        case .available where services.identifier.descriptor.providerID.hasPrefix("debug."):
            Label("Ladicí sestavení: testovací návrhy, nejde o skutečné rozpoznávání.", systemImage: "testtube.2")
        case .available where services.identifier.descriptor.providerID == SystemModelVehicleIdentifier.providerID:
            Label("Návrhy značky a modelu vytváří Apple Intelligence přímo v zařízení, bez odesílání fotografií. Mohou být nepřesné, proto je vždy potvrzujete sami.", systemImage: "checkmark.circle")
        case .available:
            Label("Lokální identifikační model je k dispozici. Návrhy vždy potvrzujete sami.", systemImage: "checkmark.circle")
        case .unavailable(let reason):
            Label { IdentificationUnavailableText(reason: reason) } icon: { Image(systemName: "info.circle") }
        }
    }

    private func deleteAll() {
        isDeleting = true
        deleteFailed = false
        Task {
            do {
                try await services.library.deleteAll()
            } catch {
                deleteFailed = true
            }
            isDeleting = false
        }
    }
}
