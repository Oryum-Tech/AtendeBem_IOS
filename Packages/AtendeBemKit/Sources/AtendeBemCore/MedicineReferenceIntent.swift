import Foundation

/// Extracts an editable search term from a single explicit reference request.
/// This does not identify a product, retrieve a leaflet or authorize a search.
public enum MedicineReferenceIntent {
    public static func searchTerm(from command: String) -> String? {
        guard command.utf16.count <= 400,
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let text = command.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(?:(?:consultar|consulte|ver|mostrar|mostre|buscar|busque|abrir|abra)\s+(?:a\s+)?)?bula\s+(?:de|do|da)\s+(?:(?:medicamento|rem[eé]dio|f[aá]rmaco)\s+)?(.+)$"#,
            #"^(?:(?:consultar|consulte|ver|mostrar|mostre|buscar|busque)\s+(?:as?\s+)?)?indica[cç](?:[aã]o|[oõ]es)\s+(?:de|do|da)\s+(?:medicamento|rem[eé]dio|f[aá]rmaco)\s+(.+)$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return validatedTerm(String(text[range]))
        }
        return nil
    }

    private static func validatedTerm(_ value: String) -> String? {
        var term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.last == "." || term.last == "?" { term.removeLast() }
        term = term.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (2...120).contains(term.utf16.count), term.split(separator: " ").count <= 8,
              term.range(of: #"^[\p{L}\p{N}][\p{L}\p{N} /%.,-]*$"#, options: .regularExpression) != nil,
              term.range(of: #"(?<![0-9])[.,]|[.,](?![0-9])|//"#, options: .regularExpression) == nil else { return nil }
        let normalized = term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        // Prefer an empty editable field over forwarding patient details, alternatives or a second instruction.
        let mixedRequest = #"\b(para|pra|pro|com|sem|paciente|pacientes|meu|minha|dele|dela|ele|ela|eu|voce|tome|tomar|dose|posologia|receita|prescreva|prescrever|emita|emitir|envie|enviar|mande|mandar|agende|agendar|consulte|consultar|analise|analisar|ignore|ignorar|mostre|mostrar|e|ou|depois|entao|tambem|mas|ainda|porque|qual|quanto|como|pode|posso|devo|usar|uso|assine|assinar|nao|nunca)\b"#
        guard normalized.range(of: mixedRequest, options: .regularExpression) == nil,
              normalized.range(of: #"\p{L}"#, options: .regularExpression) != nil else { return nil }
        return term
    }
}
