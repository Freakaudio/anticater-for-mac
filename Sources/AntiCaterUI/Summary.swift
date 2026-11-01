import Foundation
import AntiCaterCore

enum Summary {
    static func short(_ binding: Proto.Binding) -> String {
        let names = compactNames(binding)
        guard !names.isEmpty else { return "Sin asignar" }
        if binding.type != .keyboard { return names[0] }
        if let combo = Proto.combo(from: binding) {
            return (combo.modifierCodes + [combo.code])
                .map { KeyNames.compactName(for: $0, type: .keyboard) }
                .joined(separator: "+")
        }
        if names.count <= 10 { return names.joined(separator: " ") }
        return names.prefix(8).joined(separator: " ") + " … \(names.count) pasos en total"
    }
    static func full(_ binding: Proto.Binding) -> String {
        let steps = binding.activeSteps.filter { !$0.isEmpty }
        guard !steps.isEmpty else { return "Sin asignar" }
        return steps.map { step in
            let name = KeyNames.name(for: step.code, type: binding.type)
            return step.delayMs == 0 ? name : "\(name) +\(step.delayMs)ms"
        }.joined(separator: "  ›  ")
    }
    static func compactNames(_ binding: Proto.Binding) -> [String] {
        binding.activeSteps
            .filter { !$0.isEmpty }
            .map { KeyNames.compactName(for: $0.code, type: binding.type) }
    }
}
