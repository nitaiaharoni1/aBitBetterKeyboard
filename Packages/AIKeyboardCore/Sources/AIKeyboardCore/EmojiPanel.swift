import SwiftUI

/// Emoji as plain Unicode. Nothing is bundled as an image, so the system renders
/// whatever the user's iOS version draws and the app stays small.
public enum EmojiCatalog {

    public struct Category: Identifiable, Sendable {
        public let id: String
        public let icon: String
        public let emoji: [String]
    }

    public static let categories: [Category] = [
        Category(
            id: "Smileys", icon: "face.smiling",
            emoji: [
                "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
                "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙",
                "😋", "😛", "😜", "🤪", "😝", "🤗", "🤭", "🤫", "🤔", "🤐",
                "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌", "😔", "😪",
                "🤤", "😴", "😷", "🤒", "🤕", "🥳", "🥺", "😢", "😭", "😤",
                "😠", "😡", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥"
            ]),
        Category(
            id: "People", icon: "hand.raised",
            emoji: [
                "👍", "👎", "👌", "🤌", "✌️", "🤞", "🤟", "🤙", "👈", "👉",
                "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤝", "🙏",
                "💪", "🦾", "👏", "🙌", "👐", "🤲", "✍️", "💅", "👀", "🧠",
                "👶", "🧒", "👦", "👧", "🧑", "👨", "👩", "🧓", "👴", "👵",
                "🙋", "🤦", "🤷", "💁", "🙆", "🙅", "🧑‍💻", "👨‍💼", "👩‍💼", "🕺"
            ]),
        Category(
            id: "Nature", icon: "leaf",
            emoji: [
                "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
                "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦆", "🦅",
                "🦉", "🐴", "🦄", "🐝", "🦋", "🐌", "🐞", "🐢", "🐍", "🐙",
                "🌵", "🎄", "🌲", "🌳", "🌴", "🌱", "🌿", "☘️", "🍀", "🌷",
                "🌹", "🌺", "🌸", "🌼", "🌻", "🌞", "🌝", "🌚", "⭐️", "🌟"
            ]),
        Category(
            id: "Food", icon: "fork.knife",
            emoji: [
                "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
                "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦",
                "🥕", "🌽", "🌶️", "🥒", "🥬", "🧄", "🧅", "🍄", "🥜", "🌰",
                "🍞", "🥐", "🥖", "🫓", "🥨", "🧀", "🥚", "🍳", "🥞", "🧇",
                "🍕", "🍔", "🌭", "🥪", "🌮", "🌯", "🥙", "🧆", "🍝", "🍣",
                "🍰", "🎂", "🧁", "🍫", "🍬", "☕️", "🍵", "🧃", "🍺", "🍷"
            ]),
        Category(
            id: "Activity", icon: "figure.run",
            emoji: [
                "⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸",
                "🥅", "⛳️", "🏹", "🎣", "🥊", "🥋", "🎽", "🛹", "🛼", "🏂",
                "🏋️", "🤸", "🤺", "⛹️", "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊",
                "🚴", "🚵", "🎯", "🎮", "🕹️", "🎲", "🧩", "🎨", "🎭", "🎤",
                "🎧", "🎸", "🥁", "🎹", "🎺", "🎻", "🏆", "🥇", "🥈", "🥉"
            ]),
        Category(
            id: "Travel", icon: "car",
            emoji: [
                "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐",
                "🛻", "🚚", "🚛", "🚜", "🛵", "🏍️", "🛺", "🚲", "🛴", "✈️",
                "🚀", "🛸", "🚁", "⛵️", "🚤", "🛥️", "🚢", "🚂", "🚆", "🚊",
                "🗺️", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟️", "🎡", "🎢", "🎠",
                "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️", "🌅", "🌄"
            ]),
        Category(
            id: "Objects", icon: "lightbulb",
            emoji: [
                "⌚️", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "💽", "💾", "📀",
                "📷", "📹", "🎥", "📞", "☎️", "📟", "📺", "📻", "🧭", "⏱️",
                "⏰", "🔋", "🔌", "💡", "🔦", "🕯️", "🧯", "🛢️", "💸", "💵",
                "💳", "🧾", "✉️", "📩", "📨", "📦", "📪", "📝", "📅", "📊",
                "📈", "📉", "📌", "📎", "🔑", "🔒", "🔓", "🔨", "🧰", "🧪"
            ]),
        Category(
            id: "Symbols", icon: "heart",
            emoji: [
                "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
                "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "✨", "⚡️",
                "🔥", "💥", "💫", "⭐️", "🌟", "☀️", "🌈", "☁️", "❄️", "💧",
                "✅", "❌", "⭕️", "❗️", "❓", "💯", "🔔", "🔕", "♻️", "⚠️",
                "🕎", "✡️", "☪️", "✝️", "☯️", "🔆", "🔅", "➕", "➖", "🟰"
            ]),
        Category(
            id: "Flags", icon: "flag",
            emoji: [
                "🇮🇱", "🇺🇸", "🇬🇧", "🇨🇦", "🇦🇺", "🇩🇪", "🇫🇷", "🇪🇸", "🇮🇹", "🇳🇱",
                "🇵🇹", "🇬🇷", "🇹🇷", "🇷🇺", "🇺🇦", "🇵🇱", "🇸🇪", "🇳🇴", "🇩🇰", "🇫🇮",
                "🇨🇭", "🇦🇹", "🇧🇪", "🇮🇪", "🇮🇳", "🇨🇳", "🇯🇵", "🇰🇷", "🇧🇷", "🇦🇷",
                "🇲🇽", "🇿🇦", "🇪🇬", "🇦🇪", "🇸🇦", "🏳️‍🌈", "🏴", "🏁", "🚩", "🎌"
            ])
    ]
}

public struct EmojiPanel: View {

    @ObservedObject var controller: KeyboardController
    @State private var selectedCategory: String = EmojiCatalog.categories[0].id

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                grid
                categoryBar
            }
        }
        // Emoji read left to right regardless of the keyboard language.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                if selectedCategory == "Recent" {
                    ForEach(controller.recentEmoji, id: \.self) { cell($0) }
                } else if let category = EmojiCatalog.categories.first(where: { $0.id == selectedCategory }) {
                    ForEach(category.emoji, id: \.self) { cell($0) }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xxs)
        }
        .frame(maxHeight: .infinity)
    }

    private func cell(_ emoji: String) -> some View {
        Button {
            controller.insertEmoji(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 29))
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .pressable(scale: 0.85)
        .accessibilityLabel(emoji)
    }

    // MARK: Category bar

    private var categoryBar: some View {
        HStack(spacing: 0) {
            Button {
                controller.show(.none)
            } label: {
                // Off the catalogue, not off a two-way test: this key said "ABC"
                // under twelve of the fourteen keyboards, including the Greek and
                // Cyrillic ones whose letters plane has no A, B or C in it.
                Text(controller.language.lettersPlaneLabel)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.Keys.label)
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .pressable()
            .accessibilityLabel("Back to letters")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    categoryTab(id: "Recent", icon: "clock")
                    ForEach(EmojiCatalog.categories) { category in
                        categoryTab(id: category.id, icon: category.icon)
                    }
                }
            }

            Button {
                controller.deleteBackward()
            } label: {
                Image(systemName: "delete.left")
                    .font(Theme.Glyph.font(17))
                    .foregroundStyle(Theme.Keys.label)
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .pressable()
            .accessibilityLabel("Delete")
        }
        .background(Theme.Keys.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Keys.secondaryLabel.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    private func categoryTab(id: String, icon: String) -> some View {
        let isSelected = selectedCategory == id
        return Button {
            Feedback.modifierPress()
            selectedCategory = id
        } label: {
            Image(systemName: icon)
                .font(Theme.Glyph.font(15))
                .foregroundStyle(isSelected ? Theme.Brand.solid : Theme.Keys.secondaryLabel)
                .frame(width: 40, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Theme.Brand.solid.opacity(0.14) : .clear)
                        .padding(3)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel(id)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
