import Foundation

enum DisplayCurrency: String, CaseIterable, Codable {
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case gbp = "GBP"
    case cny = "CNY"

    var menuTitle: String {
        switch self {
        case .usd: "USD ($)"
        case .eur: "EUR (€)"
        case .jpy: "JPY (¥)"
        case .gbp: "GBP (£)"
        case .cny: "CNY (CN¥)"
        }
    }

    var symbol: String {
        switch self {
        case .usd: "$"
        case .eur: "€"
        case .jpy: "¥"
        case .gbp: "£"
        case .cny: "CN¥"
        }
    }
}

struct MoneyFormat: Equatable {
    let currency: DisplayCurrency
    let usdRate: Double

    static let usd = MoneyFormat(currency: .usd, usdRate: 1)

    func money(_ usdValue: Double) -> String {
        let value = usdValue * usdRate
        if currency == .jpy { return currency.symbol + String(format: "%.0f", value) }
        if value < 0.01, value > 0 { return currency.symbol + String(format: "%.4f", value) }
        if value < 1_000 { return currency.symbol + String(format: "%.2f", value) }
        return currency.symbol + Format.compact(value)
    }

    func chartMoney(_ usdValue: Double) -> String {
        let value = usdValue * usdRate
        if value == 0 { return currency.symbol + "0" }
        if value >= 1_000 { return currency.symbol + Format.compact(value) }
        if currency == .jpy || value >= 10 { return currency.symbol + String(format: "%.0f", value) }
        if value >= 1 { return currency.symbol + String(format: "%.1f", value) }
        return currency.symbol + String(format: "%.2f", value)
    }
}

struct CurrencyRates: Codable, Equatable {
    let fetchedAt: Date
    let usdRates: [String: Double]

    static func parseECB(data: Data, fetchedAt: Date = Date()) throws -> CurrencyRates {
        let delegate = ECBRatesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? CurrencyError.invalidResponse
        }
        guard let usdPerEuro = delegate.rates[DisplayCurrency.usd.rawValue], usdPerEuro > 0 else {
            throw CurrencyError.invalidResponse
        }

        var rates = [DisplayCurrency.usd.rawValue: 1.0]
        for currency in DisplayCurrency.allCases where currency != .usd {
            let perEuro = currency == .eur ? 1 : delegate.rates[currency.rawValue]
            guard let perEuro, perEuro > 0 else { throw CurrencyError.invalidResponse }
            rates[currency.rawValue] = perEuro / usdPerEuro
        }
        return CurrencyRates(fetchedAt: fetchedAt, usdRates: rates)
    }
}

@MainActor
final class CurrencyStore {
    private static let ratesURL = URL(
        string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
    )!
    private static let maximumAge: TimeInterval = 24 * 60 * 60

    private let cacheURL: URL
    private var rates: CurrencyRates?
    private(set) var isRefreshing = false
    private(set) var error: String?
    var onChange: (() -> Void)?

    private(set) var selected: DisplayCurrency {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "currency") }
    }

    var money: MoneyFormat {
        guard selected != .usd,
              let rate = rates?.usdRates[selected.rawValue]
        else { return .usd }
        return MoneyFormat(currency: selected, usdRate: rate)
    }

    init(cacheURL: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheURL = cacheURL ?? caches
            .appendingPathComponent("com.duarteocarmo.pi-helicopter/currency.plist")
        selected = DisplayCurrency(
            rawValue: UserDefaults.standard.string(forKey: "currency") ?? ""
        ) ?? .usd
        rates = Self.loadCache(from: self.cacheURL)
        refreshIfNeeded()
    }

    func select(currency: DisplayCurrency) {
        selected = currency
        error = nil
        onChange?()
        refreshIfNeeded()
    }

    func refreshIfNeeded() {
        guard selected != .usd,
              !isRefreshing,
              rates.map({ Date().timeIntervalSince($0.fetchedAt) >= Self.maximumAge }) ?? true
        else { return }

        isRefreshing = true
        error = nil
        onChange?()
        Task { [weak self] in
            do {
                let rates = try await Self.fetchRates()
                guard let self else { return }
                self.rates = rates
                try self.save(rates: rates)
                self.isRefreshing = false
                self.onChange?()
            } catch {
                guard let self else { return }
                self.error = error.localizedDescription
                self.isRefreshing = false
                self.onChange?()
            }
        }
    }

    private nonisolated static func fetchRates() async throws -> CurrencyRates {
        let (data, response) = try await URLSession.shared.data(from: ratesURL)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { throw CurrencyError.invalidResponse }
        return try CurrencyRates.parseECB(data: data)
    }

    private nonisolated static func loadCache(from url: URL) -> CurrencyRates? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(CurrencyRates.self, from: data)
    }

    private func save(rates: CurrencyRates) throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(rates).write(to: cacheURL, options: .atomic)
    }
}

private final class ECBRatesParser: NSObject, XMLParserDelegate {
    var rates: [String: Double] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Cube",
              let currency = attributeDict["currency"],
              let value = attributeDict["rate"],
              let rate = Double(value)
        else { return }
        rates[currency] = rate
    }
}

private enum CurrencyError: Error {
    case invalidResponse
}
