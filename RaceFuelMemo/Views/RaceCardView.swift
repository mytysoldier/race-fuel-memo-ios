import SwiftUI
import UIKit

struct RaceCardView: View {
    @Environment(ProStore.self) private var proStore
    let racePlan: RacePlan
    @State private var pacePlanID: UUID?
    @State private var audience = RaceCardAudience.runner
    @State private var format = RaceCardFormat.card
    @State private var output: RaceCardExport?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var action: RaceCardAction?
    @State private var actionError: String?
    @State private var previewPage = 0
    @State private var generationID = UUID()

    init(racePlan: RacePlan) {
        self.racePlan = racePlan
        _pacePlanID = State(initialValue: racePlan.selectedPacePlanID)
    }

    private var document: Result<RaceCardDocument, Error> {
        Result { try RaceCardDocument(plan: racePlan, pacePlanID: pacePlanID, audience: audience) }
    }

    private var selection: String { "\(pacePlanID?.uuidString ?? "basic")/\(audience.rawValue)/\(format.rawValue)" }

    var body: some View {
        Form {
            Section("出力する計画") {
                Picker("ペースプラン", selection: $pacePlanID) {
                    Text("基本計画").tag(Optional<UUID>.none)
                    ForEach(racePlan.pacePlans.sorted(by: { $0.order < $1.order })) { plan in
                        Text(plan.name).tag(Optional(plan.id))
                    }
                }
                Picker("表示対象", selection: $audience) {
                    ForEach(RaceCardAudience.allCases, id: \.self) { audience in
                        Text(audience.title).tag(audience)
                    }
                }
                Picker("形式", selection: $format) {
                    ForEach(RaceCardFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                Text(audience == .runner ? "区間ペースを先に表示します。" : "通過地点・関門・補給と受け取り方法を先に表示します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if format == .paceBand {
                    Text("180 × 55 mmの帯をA4に配置します。100%（実際のサイズ）で印刷し、点線に沿って切り取ってください。内容が多い場合は複数の帯に続きます。")
                        .font(.footnote)
                }
            }

            if case .failure(let error) = document {
                Section {
                    Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            } else if let generationError {
                Section {
                    Text(generationError).foregroundStyle(.red)
                    Button("再作成") { Task { await generate() } }
                }
            } else if isGenerating {
                Section { ProgressView("出力を作成中") }
            }

            if let output, !isGenerating {
                Section("保存・共有") {
                    Button { action = .save(output.imageURLs) } label: {
                        Label("画像をファイルに保存", systemImage: "photo")
                    }
                    Button { action = .share(output.imageURLs) } label: {
                        Label("画像を共有", systemImage: "square.and.arrow.up")
                    }
                    Button { action = .save([output.pdfURL]) } label: {
                        Label("PDFをファイルに保存", systemImage: "doc")
                    }
                    Button { action = .share([output.pdfURL]) } label: {
                        Label("PDFを共有", systemImage: "square.and.arrow.up")
                    }
                    Button { action = .print(output) } label: {
                        Label("PDFを印刷", systemImage: "printer")
                    }
                    .disabled(!UIPrintInteractionController.isPrintingAvailable)
                    if !UIPrintInteractionController.isPrintingAvailable {
                        Text("この環境では印刷を利用できません。PDFを保存・共有してください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("\(output.imageURLs.count)ページ。画像はページごとに保存・共有します。共有先の選択や保存をキャンセルしても計画は変わりません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("出力プレビュー") {
                    if output.imageURLs.count > 1 {
                        Picker("ページ", selection: $previewPage) {
                            ForEach(output.imageURLs.indices, id: \.self) { index in
                                Text("\(index + 1) / \(output.imageURLs.count)").tag(index)
                            }
                        }
                    }
                    if output.imageURLs.indices.contains(previewPage),
                       let image = UIImage(contentsOfFile: output.imageURLs[previewPage].path) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("\(format.title)の\(previewPage + 1)ページ目。内容は下の出力内容からも確認できます。")
                    }
                }
            }
            if case .success(let document) = document {
                Section("出力内容") {
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        DisclosureGroup(section.title) {
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Race Card出力")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selection) { await generate() }
        .sheet(item: $action) { action in
            RaceCardActionView(action: action) { error in
                self.action = nil
                actionError = error
            }
        }
        .alert("出力を完了できませんでした", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .proProtected(.raceCard)
    }

    @MainActor
    private func generate() async {
        guard proStore.canUse(.raceCard) else { return }
        let token = UUID()
        generationID = token
        output?.removeTemporaryFiles()
        output = nil
        previewPage = 0
        generationError = nil
        isGenerating = true
        defer { if generationID == token { isGenerating = false } }
        // Allow SwiftUI to show the progress indicator before synchronous UIKit rendering.
        await Task.yield()
        guard !Task.isCancelled else { return }
        do {
            let renderer = try RaceCardRenderer(document: document.get(), format: format)
            let result = try await renderer.exportForSharing()
            guard generationID == token, !Task.isCancelled, proStore.canUse(.raceCard) else {
                result.removeTemporaryFiles()
                return
            }
            output = result
        } catch is CancellationError {
            // A different selection or closing this screen cancels the obsolete output.
        } catch {
            if generationID == token { generationError = error.localizedDescription }
        }
    }
}

enum RaceCardAction: Identifiable {
    case share([URL]), save([URL]), print(RaceCardExport)

    var id: String {
        switch self {
        case .share: "share"
        case .save: "save"
        case .print: "print"
        }
    }
}

private struct RaceCardActionView: UIViewControllerRepresentable {
    let action: RaceCardAction
    let completion: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIViewController {
        switch action {
        case .share(let urls):
            let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            controller.completionWithItemsHandler = { _, _, _, error in
                completion(error?.localizedDescription)
            }
            // The controller is presented as a SwiftUI sheet, including on iPad.
            return controller
        case .save(let urls):
            let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
            controller.delegate = context.coordinator
            return controller
        case .print(let output):
            let controller = RaceCardPrintController()
            controller.output = output
            controller.completion = completion
            return controller
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (String?) -> Void
        init(completion: @escaping (String?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(nil)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

private final class RaceCardPrintController: UIViewController, UIPrintInteractionControllerDelegate {
    var output: RaceCardExport?
    var completion: ((String?) -> Void)?
    private var hasPresented = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented, let output else { return }
        hasPresented = true
        guard UIPrintInteractionController.isPrintingAvailable,
              UIPrintInteractionController.canPrint(output.pdfURL) else {
            completion?("印刷を利用できません。PDFを保存・共有してください。")
            return
        }
        let printer = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = output.pdfURL.deletingPathExtension().lastPathComponent
        info.outputType = .general
        info.orientation = .portrait
        printer.printInfo = info
        printer.delegate = self
        printer.printPageRenderer = RaceCardPrintRenderer(source: output.renderer)
        let handler: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, error in
            self?.completion?(error?.localizedDescription)
        }
        let presented: Bool
        if traitCollection.userInterfaceIdiom == .pad {
            presented = printer.present(from: CGRect(x: view.bounds.midX, y: view.bounds.midY,
                                                     width: 1, height: 1), in: view,
                                        animated: true, completionHandler: handler)
        } else {
            presented = printer.present(animated: true, completionHandler: handler)
        }
        if !presented { completion?("印刷画面を開けませんでした。PDFを保存・共有してください。") }
    }

    func printInteractionController(_ printInteractionController: UIPrintInteractionController,
                                    choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        let paper = UIPrintPaper.bestPaper(forPageSize: RaceCardRenderer.pageSize, withPapersFrom: paperList)
        if output?.renderer.format == .paceBand,
           paper.printableRect.width < RaceCardRenderer.bandSize.width
            || paper.printableRect.height < RaceCardRenderer.bandSize.height {
            DispatchQueue.main.async { [weak self] in
                printInteractionController.dismiss(animated: true)
                self?.completion?("ペースバンドの原寸印刷に必要な領域がありません。A4用紙に対応するプリンタを選択してください。")
            }
        }
        return paper
    }
}
