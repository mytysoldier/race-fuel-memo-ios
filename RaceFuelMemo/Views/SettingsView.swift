import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(String(localized: "settings.section.app")) {
                NavigationLink {
                    AppInformationView()
                } label: {
                    Label(String(localized: "settings.row.app_information"), systemImage: "info.circle")
                }

                LabeledContent(
                    String(localized: "settings.row.version"),
                    value: appVersion
                )
            }

            Section(String(localized: "settings.section.policy")) {
                Text(String(localized: "settings.policy.summary"))
                    .foregroundStyle(.secondary)

                NavigationLink {
                    DisclaimerView()
                } label: {
                    Label(String(localized: "settings.row.disclaimer"), systemImage: "exclamationmark.triangle")
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label(String(localized: "settings.row.privacy_policy"), systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "settings.action.done")) {
                    dismiss()
                }
            }
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, build != shortVersion else {
            return shortVersion
        }

        return "\(shortVersion) (\(build))"
    }
}

private struct AppInformationView: View {
    var body: some View {
        List {
            Section(String(localized: "settings.info.section.about")) {
                Text(String(localized: "settings.info.about"))
            }

            Section(String(localized: "settings.info.section.features")) {
                ForEach(features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle")
                }
            }

            Section(String(localized: "settings.info.section.storage")) {
                Text(String(localized: "settings.info.storage"))
            }
        }
        .navigationTitle(String(localized: "settings.row.app_information"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var features: [String] {
        [
            String(localized: "settings.info.feature.race_plan"),
            String(localized: "settings.info.feature.pace"),
            String(localized: "settings.info.feature.fueling"),
            String(localized: "settings.info.feature.checklist"),
            String(localized: "settings.info.feature.memo")
        ]
    }
}

private struct DisclaimerView: View {
    var body: some View {
        List {
            Section(String(localized: "settings.disclaimer.section.purpose")) {
                Text(String(localized: "settings.disclaimer.purpose"))
            }

            Section(String(localized: "settings.disclaimer.section.health")) {
                Text(String(localized: "settings.disclaimer.health"))
            }

            Section(String(localized: "settings.disclaimer.section.responsibility")) {
                Text(String(localized: "settings.disclaimer.responsibility"))
            }
        }
        .navigationTitle(String(localized: "settings.row.disclaimer"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section(String(localized: "settings.privacy.section.collection")) {
                Text(String(localized: "settings.privacy.collection"))
            }

            Section(String(localized: "settings.privacy.section.storage")) {
                Text(String(localized: "settings.privacy.storage"))
            }

            Section(String(localized: "settings.privacy.section.third_party")) {
                Text(String(localized: "settings.privacy.third_party"))
            }
        }
        .navigationTitle(String(localized: "settings.row.privacy_policy"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
