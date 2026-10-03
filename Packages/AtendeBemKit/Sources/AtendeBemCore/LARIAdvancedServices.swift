import Foundation

public enum LARIAdvancedError: Error, LocalizedError, Equatable, Sendable {
    case permission, consent, invalidAudio, invalidTranscript, invalidPrinciples, invalidReport, staleConsultation
    public var errorDescription: String? {
        switch self {
        case .permission: "Seu perfil nesta clínica não permite esta consulta."
        case .consent: "Confirme a autorização para gravar e processar o áudio antes de continuar."
        case .invalidAudio: "O áudio está vazio, excede o limite ou tem um formato não aceito. Grave novamente sem ultrapassar 15 minutos."
        case .invalidTranscript: "A resposta não trouxe uma transcrição válida. Nenhum texto foi acrescentado à consulta."
        case .invalidPrinciples: "Revise a lista: informe de 2 a 50 princípios ativos distintos, um por linha, com até 200 caracteres cada."
        case .invalidReport: "A resposta não trouxe dados consistentes para este relatório. Nenhum resultado será estimado."
        case .staleConsultation: "A consulta mudou. Suas anotações foram preservadas. Abra novamente a transcrição para aplicar à versão atual."
        }
    }
}

public enum LARIAdvancedAccess {
    public static func clinical(_ user: User) -> Bool {
        user.papeis.contains { ["medico", "enfermeiro", "fisioterapeuta", "dentista", "psicologo", "fonoaudiologo", "nutricionista"].contains($0) }
    }
    public static func analytics(_ user: User) -> Bool { user.papeis.contains { ["gestor", "medico"].contains($0) } }
    public static func require(api: APIClient, context: UUID) async throws {
        guard await api.requestContextID() == context else { throw APIError.contextChanged }
        try Task.checkCancellation()
    }
}

public struct ConsultationAudioRequest: Encodable, Sendable {
    public static let maximumBase64Characters = 27 * 1024 * 1024
    public static let maximumBytes = maximumBase64Characters / 4 * 3
    public let audioB64: String
    public let mimeType: String
    public init(data: Data, mimeType: String, consent: Bool) throws {
        guard consent else { throw LARIAdvancedError.consent }
        guard data.count >= 48, data.count <= Self.maximumBytes,
              ["audio/webm", "audio/ogg", "audio/mp4", "audio/mpeg", "audio/wav", "audio/x-wav"].contains(mimeType) else {
            throw LARIAdvancedError.invalidAudio
        }
        self.audioB64 = data.base64EncodedString(); self.mimeType = mimeType
    }
}

public struct ConsultationTranscription: Decodable, Sendable {
    public struct Line: Decodable, Sendable {
        public let quem: String?
        public let texto: String
    }
    public let linhas: [Line]
    public let texto: String
    public let disclaimer: String
    public func validate() throws {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, texto.utf16.count <= 80_000,
              !disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !linhas.isEmpty, linhas.count <= 10_000,
              linhas.allSatisfy({ ($0.quem == nil || ["med", "pac"].contains($0.quem!)) && !$0.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              linhas.map(\.texto).joined(separator: "\n") == texto else { throw LARIAdvancedError.invalidTranscript }
    }
}

public enum ConsultationTranscriptMerge {
    /// Appends only to the explicitly chosen section. No diagnosis, signature, or persistence.
    public static func append(_ reviewed: String, sectionID: String, baseline: ConsultationContent, current: ConsultationContent) throws -> ConsultationContent {
        guard baseline == current else { throw LARIAdvancedError.staleConsultation }
        let text = reviewed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 20_000, current.displayedSections.contains(where: { $0.id == sectionID }) else {
            throw LARIAdvancedError.invalidTranscript
        }
        var result = current
        let original = current.notes[sectionID] ?? ""
        guard original.utf16.count + text.utf16.count + 2 <= 80_000 else { throw LARIAdvancedError.invalidTranscript }
        if original != text && !original.hasSuffix("\n\n" + text) {
            result.notes[sectionID] = original.isEmpty ? text : original + "\n\n" + text
        }
        return result
    }
}

public struct CuratedInteraction: Decodable, Sendable, Identifiable {
    public let a: String
    public let b: String
    public let gravidade: String
    public let descricao: String
    public let fonte: String
    public let revisadoEm: String
    public var id: String { [a, b, descricao, fonte, revisadoEm].joined(separator: "|") }
}

public struct CuratedInteractionReport: Sendable {
    public let principles: [String]
    public let alerts: [CuratedInteraction]
    public static let limitation = "Esta base cobre um conjunto limitado de interações críticas e não é uma base farmacológica completa licenciada. Ausência de alerta não confirma segurança. A checagem não avalia alergias, dose, função renal, gestação ou todas as medicações do paciente."
    public func text() -> String {
        let details = alerts.isEmpty ? "Nenhum alerta encontrado na base consultada." : alerts.map {
            "\($0.gravidade.uppercased()): \($0.a) × \($0.b)\n\($0.descricao)\nFonte: \($0.fonte)\nRevisão: \($0.revisadoEm)"
        }.joined(separator: "\n\n")
        return "Princípios consultados: \(principles.joined(separator: ", "))\n\n\(details)\n\n\(Self.limitation)"
    }
}

public struct CuratedInteractionService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    public static func principles(from text: String) throws -> [String] {
        let values = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let keys = values.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")) }
        guard (2...50).contains(values.count), values.allSatisfy({ $0.utf16.count <= 200 }), Set(keys).count == values.count else {
            throw LARIAdvancedError.invalidPrinciples
        }
        return values
    }
    public func check(text: String, user: User, context: UUID) async throws -> CuratedInteractionReport {
        guard LARIAdvancedAccess.clinical(user) else { throw LARIAdvancedError.permission }
        let inputs = try Self.principles(from: text)
        try await LARIAdvancedAccess.require(api: api, context: context)
        let alerts: [CuratedInteraction] = try await api.post(["medicamentos", "interacoes"], body: ["principios": inputs], expectedContext: context)
        try await LARIAdvancedAccess.require(api: api, context: context)
        guard alerts.count <= 10_000, Set(alerts.map(\.id)).count == alerts.count,
              alerts.allSatisfy({ alert in
                  inputs.contains(alert.a) && inputs.contains(alert.b) && alert.a != alert.b && ["grave", "moderada"].contains(alert.gravidade) &&
                  !alert.descricao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && alert.fonte.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 &&
                  LARIAnalyticsService.validDay(alert.revisadoEm)
              }) else { throw LARIAdvancedError.invalidReport }
        return .init(principles: inputs, alerts: alerts)
    }
}

public struct LARISeasonality: Decodable, Sendable {
    public struct Period: Decodable, Sendable { public let de: String; public let ate: String; public let dias: Int; public let fuso: String }
    public struct Profile: Decodable, Sendable, Identifiable {
        public let diaSemana: Int?
        public let mes: Int?
        public let nome: String
        public let totalConsultas: Int
        public let mediaConsultasDia: Double
        public var id: String { diaSemana.map { "weekday-\($0)" } ?? "month-\(mes ?? -1)" }
    }
    public let disclaimerCfm: String
    public let escopo: String
    public let escopoObservacao: String?
    public let periodo: Period
    public let totalConsultas: Int
    public let perfilSemanal: [Profile]
    public let perfilMensal: [Profile]
    public let avisos: [String]
    public func validate() throws {
        guard escopo == "clinica", !disclaimerCfm.isEmpty, LARIAnalyticsService.validDay(periodo.de), LARIAnalyticsService.validDay(periodo.ate),
              periodo.de <= periodo.ate, periodo.dias > 0, TimeZone(identifier: periodo.fuso) != nil, (0...1_000_000_000).contains(totalConsultas),
              Set(perfilSemanal.compactMap(\.diaSemana)) == Set(0...6), perfilSemanal.count == 7,
              Set(perfilMensal.compactMap(\.mes)) == Set(1...12), perfilMensal.count == 12,
              (perfilSemanal + perfilMensal).allSatisfy({ !$0.nome.isEmpty && $0.totalConsultas >= 0 && $0.totalConsultas <= 1_000_000_000 && $0.mediaConsultasDia.isFinite && $0.mediaConsultasDia >= 0 }),
              perfilSemanal.reduce(0, { $0 + $1.totalConsultas }) == totalConsultas,
              perfilMensal.reduce(0, { $0 + $1.totalConsultas }) == totalConsultas else { throw LARIAdvancedError.invalidReport }
    }
    public func text(clinic: String) -> String {
        let profiles = [("Dias da semana", perfilSemanal), ("Meses do histórico", perfilMensal)].map { title, values in
            title + "\n" + values.map { "\($0.nome): \($0.totalConsultas) consultas; média diária \($0.mediaConsultasDia.formatted(.number.precision(.fractionLength(0...2))))" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return "Agenda da clínica \(clinic)\nPeríodo da fonte: \(periodo.de) a \(periodo.ate); \(periodo.dias) dias; fuso \(periodo.fuso).\nTotal: \(totalConsultas) consultas\nFonte: histórico agregado de agenda (serviço Analytics). Esta leitura mostra perfis descritivos de volume; não faz previsão nem interpreta correlações CID × ambiente.\n\n\(profiles)\n\n\(escopoObservacao ?? "Escopo: toda a clínica.")\n\(disclaimerCfm)\n\(avisos.joined(separator: "\n"))"
    }
}

public struct LARIGeography: Decodable, Sendable {
    public struct Census: Decodable, Sendable {
        public let populacao: Double?
        public let areaKm2: Double?
        public let densidadeHabKm2: Double?
        public let saude: [String: Double?]?
    }
    public struct Municipality: Decodable, Sendable, Identifiable {
        public let cidade: String
        public let uf: String
        public let codigoIbge: String?
        public let total: Int
        public let pct: Double
        public let ibge: Census?
        public let penetracao: Double?
        public var id: String { cidade + "|" + uf }
    }
    public let municipios: [Municipality]
    public let totalPacientes: Int
    public let comCidade: Int
    public let semCidade: Int
    public let avisos: [String]
    public let fontes: [String]
    public let atualizadoEm: String
    public func validate() throws {
        guard (0...1_000_000_000).contains(totalPacientes), (0...1_000_000_000).contains(comCidade), (0...1_000_000_000).contains(semCidade), totalPacientes == comCidade + semCidade,
              municipios.count <= 10_000, Set(municipios.map(\.id)).count == municipios.count,
              municipios.allSatisfy({ (0...1_000_000_000).contains($0.total) }),
              municipios.reduce(0, { $0 + $1.total }) == comCidade,
              (!municipios.contains(where: { $0.ibge != nil }) || !fontes.isEmpty),
              ClinicClock.parseInstant(atualizadoEm) != nil,
              municipios.allSatisfy({ municipality in
                  !municipality.cidade.isEmpty && municipality.total >= 0 && municipality.pct.isFinite && (0...1).contains(municipality.pct) &&
                  (municipality.penetracao.map { $0.isFinite && $0 >= 0 } ?? true) &&
                  ([municipality.ibge?.populacao, municipality.ibge?.areaKm2, municipality.ibge?.densidadeHabKm2].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }) &&
                  (municipality.ibge?.saude?.values.compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 } ?? true)
              }) else { throw LARIAdvancedError.invalidReport }
    }
    public func text(clinic: String) -> String {
        let cities = municipios.map { city in
            let population = city.ibge?.populacao.map { "População municipal: \($0.formatted(.number.precision(.fractionLength(0)))) (Censo, conforme fonte)." } ?? "População municipal indisponível."
            let labels = [("idadeMediana", "Idade mediana municipal"), ("indiceEnvelhecimento", "Índice de envelhecimento municipal"), ("razaoSexo", "Razão de sexo municipal")]
            let demographics = labels.compactMap { key, title -> String? in
                guard let wrapped = city.ibge?.saude?[key], let value = wrapped else { return nil }
                return "\(title): \(value.formatted(.number.precision(.fractionLength(0...2))))."
            }.joined(separator: " ")
            return "\(city.cidade)/\(city.uf): \(city.total) pacientes; \(city.pct.formatted(.percent.precision(.fractionLength(1)))) da carteira com cidade. \(population) \(demographics)"
        }.joined(separator: "\n")
        return "Carteira da clínica \(clinic) por município\nAtualização da fonte: \(atualizadoEm)\n\(totalPacientes) pacientes; \(comCidade) com cidade; \(semCidade) sem cidade.\n\n\(cities)\n\nDados agregados do cadastro. Não representam prevalência de doença ou localização individual. Indicadores do Censo descrevem o município, não os pacientes.\n\nFontes:\n\(fontes.joined(separator: "\n"))\n\nAvisos:\n\(avisos.joined(separator: "\n"))"
    }
}

public struct LARIAnalyticsService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func seasonality(user: User, context: UUID) async throws -> LARISeasonality {
        guard LARIAdvancedAccess.analytics(user) else { throw LARIAdvancedError.permission }
        try await LARIAdvancedAccess.require(api: api, context: context)
        let result: LARISeasonality = try await api.get(["analytics", "demanda", "sazonalidade"])
        try await LARIAdvancedAccess.require(api: api, context: context)
        try result.validate(); return result
    }
    public func geography(user: User, context: UUID) async throws -> LARIGeography {
        guard LARIAdvancedAccess.analytics(user) else { throw LARIAdvancedError.permission }
        try await LARIAdvancedAccess.require(api: api, context: context)
        let result: LARIGeography = try await api.get(["analytics", "geo", "mapa"])
        try await LARIAdvancedAccess.require(api: api, context: context)
        try result.validate(); return result
    }
    static func validDay(_ value: String) -> Bool {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}
