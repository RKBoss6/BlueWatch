//
//  Modifiers.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat
    var backgroundColor: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            return AnyView(
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .background(
                        backgroundColor.opacity(colorScheme == .dark ? 0.2 : 0.3),
                        in: shape
                    )
                    .clipShape(shape)
                    .overlay(
                        shape
                            .strokeBorder(.secondary.opacity(colorScheme == .dark ? 0.1:0.2), lineWidth: 1)
                    )
            )
        } else {
            return AnyView(
                content
                    .background(in: .rect(cornerRadius: cornerRadius))
            )
        }
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 24,
        backgroundColor: Color = .clear
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                backgroundColor: backgroundColor
            )
        )
    }
}
struct LiquidGlassFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        return AnyView(
            content
                .padding()
                .liquidGlass(cornerRadius: 24)
                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
        )
    }
}

extension View {
    func liquidGlassButton() -> some View {
        self.modifier(
            LiquidGlassButtonModifier()
        )
    }
}
struct LiquidGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return AnyView(
                content
                    .buttonStyle(.glassProminent)
            )
        } else {
            return AnyView(
                content
                    .buttonStyle(.borderedProminent)
            )
        }
    }
}

extension View {
    func liquidGlassFormItem() -> some View{
        self.modifier(
            LiquidGlassFormModifier()
        )
    }
}
extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else { return nil }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else { return "[]" }
        return result
    }
}


struct ReorderableString: Identifiable, Codable {
    var id: String
    var value: String

    init(_ value: String) {
        self.id = value
        self.value = value
    }
}

// 2. Create a clean container struct to hold the array
struct ReorderableListContainer: Codable, RawRepresentable {
    var items: [ReorderableString]
    
    // Conforming to RawRepresentable safely inside an internal struct
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([ReorderableString].self, from: data) else {
            return nil
        }
        self.items = result
    }
    
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(items),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return result
    }
    
    // Provide a convenient initializer for default values
    init(_ items: [ReorderableString]) {
        self.items = items
    }
}

@available(iOS 27.0, *)
extension ReorderableListContainer {
    mutating func apply(difference: ReorderDifference<ReorderableString.ID, ReorderableSingleCollectionIdentifier>) {
        guard let sourceID = difference.sources.first,
              let sourceIndex = items.firstIndex(where: { $0.id == sourceID }) else { return }
        
        let targetIndex: Int
        switch difference.destination.position {
        case .before(let targetID):
            guard let idx = items.firstIndex(where: { $0.id == targetID }) else { return }
            targetIndex = idx
        case .end:
            targetIndex = items.count
        @unknown default:
            return
        }
        
        let movedElement = items.remove(at: sourceIndex)
        let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        items.insert(movedElement, at: destinationIndex)
    }
}

