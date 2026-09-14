import SwiftUI

struct NotesWidget: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.notes)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
                    .padding(8)

                if store.notes.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 13)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { focused = true }

            HStack {
                Text(wordCountLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if !store.notes.isEmpty {
                    PillButton(title: "Copy", symbol: "doc.on.doc", tint: Theme.secondaryText) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.notes, forType: .string)
                    }
                    PillButton(title: "Clear", symbol: "trash", tint: Theme.secondaryText) {
                        store.notes = ""
                    }
                }
            }
        }
    }

    private var wordCountLabel: String {
        let words = store.notes.split { $0.isWhitespace || $0.isNewline }.count
        return words == 1 ? "1 word" : "\(words) words"
    }
}
