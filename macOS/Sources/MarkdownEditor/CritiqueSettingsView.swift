import MarkdownEditorCore
import MarkdownEditorUI
import SwiftUI

/// One place for everything the critique needs: who writes it, with what key,
/// using which model, and in which face.
///
/// Combined rather than split between a settings window and the rail's own
/// menu. There were two places to change the handwriting and none to enter a
/// key, and a reader who has just been asked for a key should not have to find
/// a different window to change the model it will be spent on.
struct CritiqueSettingsView: View {
    @AppStorage(CritiqueProvider.storageKey) private var providerRaw =
        CritiqueProvider.openAI.rawValue
    @AppStorage(CritiqueHand.storageKey) private var handRaw =
        CritiqueHand.initial.rawValue

    /// Held here rather than read from the Keychain on every redraw: a
    /// Keychain lookup per keystroke is both slow and pointless.
    @State private var key = ""
    @State private var model = ""
    @State private var savedKeyExists = false
    @State private var justSaved = false
    @StateObject private var skill = KonvoSkillModel()
    @State private var testOutcome: CritiqueConnectionTest.Outcome?
    @State private var isTesting = false
    /// Its own service, not a document's. A test belongs to the settings
    /// window and must not cancel, or be cancelled by, a critique in progress.
    @State private var tester = CritiqueService()

    private var provider: CritiqueProvider {
        CritiqueProvider(rawValue: providerRaw) ?? .openAI
    }

    private var hand: CritiqueHand {
        CritiqueHand(rawValue: handRaw) ?? .sans
    }

    var body: some View {
        Form {
            Section("AI Assisted Critique") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(CritiqueProvider.allCases) { candidate in
                        Text(candidate.title).tag(candidate.rawValue)
                    }
                }
                .onChange(of: providerRaw) { _ in load() }

                if provider.needsAPIKey {
                    // Secure, so a key does not sit in plain sight on a screen
                    // somebody might be sharing.
                    SecureField("API key", text: $key)
                        .onSubmit(save)
                    HStack {
                        if let origin = provider.keyOrigin {
                            Text("Keys come from \(origin)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if justSaved {
                            Label("Saved", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if savedKeyExists {
                            Text("A key is stored")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Save Key", action: save)
                            .disabled(key.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                        Button("Remove") {
                            CritiqueCredentials.remove(for: provider)
                            key = ""
                            savedKeyExists = false
                            justSaved = false
                        }
                        .disabled(!savedKeyExists)
                    }

                    Picker("Model", selection: $model) {
                        ForEach(provider.models, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: model) { chosen in
                        CritiqueCredentials.setModel(chosen, for: provider)
                    }
                    Text(
                        "The first model in the list is the inexpensive one, "
                            + "and is enough for a critique: it reads a draft "
                            + "and returns a page of findings."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    // Where the draft goes, said plainly. This used to read
                    // "a model already available on this Mac… nothing is
                    // billed", which was wrong on both counts and is the one
                    // sentence a privacy-minded writer reads before trusting
                    // the feature with an unpublished draft.
                    Text(
                        "Sends the draft to a model through the GitHub account "
                            + "this Mac is signed in with. No key is stored "
                            + "here; each critique counts against that "
                            + "account's plan."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                testRow
            }

            Section("Appearance") {
                // "Notes", because that is what the rail calls them.
                Picker("Notes are written in", selection: $handRaw) {
                    // `available`, not `allCases`: macOS makes several of the
                    // system faces optional downloads and any face can be
                    // switched off in Font Book. Offering one that is not there
                    // means picking it silently draws something else, which
                    // looks like the app ignoring you.
                    //
                    // Shown in its own face, because the names mean nothing:
                    // nobody knows what "Caveat" looks like.
                    Text(CritiqueHand.sans.title)
                        .font(CritiqueTypography.named(.sans, size: 13))
                        .tag(CritiqueHand.sans.rawValue)
                    Divider()
                    Section("Bundled") {
                        ForEach(CritiqueHand.available.filter(\.isBundled)) { candidate in
                            Text(candidate.title)
                                .font(CritiqueTypography.named(candidate, size: 13))
                                .tag(candidate.rawValue)
                        }
                    }
                    let system = CritiqueHand.available.filter {
                        !$0.isBundled && $0 != .sans
                    }
                    if !system.isEmpty {
                        Section("From your Mac") {
                            ForEach(system) { candidate in
                                Text(candidate.title)
                                    .font(CritiqueTypography.named(candidate, size: 13))
                                    .tag(candidate.rawValue)
                            }
                        }
                    }
                }
                Text(
                    hand == .sans
                        ? "The system face, which is the most legible at length."
                        : "A hand. Slower to read than the system face, and it "
                            + "makes the rail feel written rather than generated."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            konvoSkillSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
    }

    /// Prove the connection works before spending a critique on finding out.
    ///
    /// A critique takes the better part of a minute, and until it fails there
    /// is no way to tell a mistyped key from a model the account cannot reach
    /// from a network that is down — all three arrive as the same shrug at the
    /// end of a long wait. This asks for one word on the same path a critique
    /// uses.
    @ViewBuilder
    private var testRow: some View {
        HStack {
            Button("Test") { runTest() }
                .disabled(isTesting)
            if isTesting {
                ProgressView().controlSize(.small)
                Text("Asking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let outcome = testOutcome {
                Text(outcome.detail)
                    .font(.caption)
                    .foregroundStyle(outcome.didPass ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        testOutcome = nil
        Task {
            let outcome = await tester.testConnection()
            await MainActor.run {
                testOutcome = outcome
                isTesting = false
            }
        }
    }

    /// Which copy of the skill the critique is actually running against.
    ///
    /// The critique's whole shape — the severities, the categories, the rule
    /// that quotes come back character for character, which every highlight in
    /// the document depends on — comes from the skill rather than from this
    /// app. When a critique starts returning something the rail cannot draw,
    /// this is the first thing worth knowing, and there was nowhere to look.
    @ViewBuilder
    private var konvoSkillSection: some View {
        Section("KONVO Skill") {
            switch skill.state {
            case .unread, .reading:
                Text("Reading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .installed(let installed):
                LabeledContent("Version") {
                    Text(KonvoSkill.summary(for: installed))
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .help(installed.subject)
                }
                // The commit's subject line is not shown under the version any
                // more: it is a note one maintainer left another ("Tighten
                // the critique pass's quote rule"), which reads as noise to a
                // writer. It is still there for anyone who wants it, as the
                // version's tooltip.
                if installed.isModified {
                    // Said plainly, because an update will refuse rather than
                    // discard the edits — and "the button did nothing" is a
                    // worse answer than knowing why.
                    Text(
                        "This checkout has local edits. An update will stop "
                            + "rather than overwrite them."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

            case .missing(let absence):
                Text(absence.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Update") { skill.update() }
                    .disabled(skill.isUpdating || !canUpdateSkill)
                if skill.isUpdating {
                    ProgressView().controlSize(.small)
                }
                if let outcome = skill.lastUpdate {
                    Text(outcome.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(
                "Humanish critiques your draft using this skill. Update pulls the "
                    + "latest version of it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only when there is a checkout to pull into. Offering the button
    /// otherwise is offering something that cannot work.
    private var canUpdateSkill: Bool {
        if case .installed = skill.state { return true }
        return false
    }

    private func load() {
        skill.read()
        // A result from the previous provider would describe a connection the
        // reader is no longer looking at.
        testOutcome = nil
        // The picker has to show the provider the critique will actually use.
        //
        // `@AppStorage` cannot express this default because it is not a
        // constant — with nothing chosen it is the Copilot CLI when the CLI is
        // installed, and OpenAI when it is not. Left to the literal above, the
        // picker said "OpenAI" while every critique went through the CLI, which
        // is the same bug the hand picker had: a control describing a state the
        // app is not in.
        if UserDefaults.standard.string(forKey: CritiqueProvider.storageKey) == nil {
            providerRaw = CritiqueCredentials.provider.rawValue
        }
        savedKeyExists = CritiqueCredentials.key(for: provider) != nil
        // Never read back into the field: showing a stored secret buys nothing
        // and puts it on screen. The line beside it says one is held.
        key = ""
        justSaved = false
        model = CritiqueCredentials.model(for: provider)
    }

    private func save() {
        guard CritiqueCredentials.store(key, for: provider) else { return }
        savedKeyExists = true
        justSaved = true
        key = ""
    }
}
