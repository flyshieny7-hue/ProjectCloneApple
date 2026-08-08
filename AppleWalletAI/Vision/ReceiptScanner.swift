import Foundation
import Vision
import VisionKit
import UIKit
import CoreImage

/// VisionKit OCR для автоматического парсинга чеков
@available(iOS 26.0, *)
public final class ReceiptScanner: ObservableObject {

    // MARK: - Published State
    @Published public var scannedReceipt: ScannedReceipt?
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0.0
    @Published public var recognizedText: String = ""
    @Published public var items: [ReceiptLineItem] = []
    @Published public var totalAmount: Double?
    @Published public var merchantName: String?
    @Published public var date: Date?
    @Published public var error: ScanError?

    // MARK: - Vision
    private let textRecognizer: VNRecognizeTextRequest
    private let barcodeDetector: VNDetectBarcodesRequest
    private let queue = DispatchQueue(label: "com.applewallet.receiptscan", qos: .userInitiated)

    // MARK: - ML Enhancement (Placeholder)
    private var receiptParserModel: VNCoreMLModel?

    public init() {
        self.textRecognizer = VNRecognizeTextRequest()
        self.barcodeDetector = VNDetectBarcodesRequest()
        setupVision()
        loadMLModel()
    }

    private func setupVision() {
        textRecognizer.recognitionLevel = .accurate
        textRecognizer.usesLanguageCorrection = true
        textRecognizer.recognitionLanguages = ["en-US", "ru-RU"]
        textRecognizer.minimumTextHeight = 0.01

        barcodeDetector.symbologies = [.qr, .ean13, .ean8, .code128]
    }

    private func loadMLModel() {
        // Placeholder: загрузка CoreML модели для парсинга чеков
        // if let modelURL = Bundle.main.url(forResource: "ReceiptParser", withExtension: "mlmodelc"),
        //    let model = try? VNCoreMLModel(for: MLModel(contentsOf: modelURL)) {
        //     self.receiptParserModel = model
        // }
        print("[ReceiptScanner] CoreML receipt parser placeholder — используется rule-based OCR + regex")
    }

    // MARK: - Public API

    /// Сканирует UIImage чека
    public func scan(image: UIImage) {
        isScanning = true
        scanProgress = 0.0
        error = nil

        queue.async { [weak self] in
            guard let self = self else { return }

            guard let cgImage = image.cgImage else {
                self.handleError(.invalidImage)
                return
            }

            let requestHandler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: .init(image.imageOrientation),
                options: [:]
            )

            do {
                try requestHandler.perform([self.textRecognizer])

                guard let results = self.textRecognizer.results as? [VNRecognizedTextObservation] else {
                    self.handleError(.noTextFound)
                    return
                }

                let recognizedStrings = results.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let fullText = recognizedStrings.joined(separator: "\n")

                DispatchQueue.main.async {
                    self.recognizedText = fullText
                    self.scanProgress = 0.5
                }

                // Парсим структурированные данные
                let parsed = self.parseReceipt(text: fullText, observations: results)

                DispatchQueue.main.async {
                    self.items = parsed.items
                    self.totalAmount = parsed.total
                    self.merchantName = parsed.merchant
                    self.date = parsed.date
                    self.scannedReceipt = ScannedReceipt(
                        merchantName: parsed.merchant,
                        date: parsed.date,
                        total: parsed.total,
                        items: parsed.items,
                        rawText: fullText,
                        tax: parsed.tax,
                        tip: parsed.tip
                    )
                    self.scanProgress = 1.0
                    self.isScanning = false
                }

            } catch {
                self.handleError(.visionError(error))
            }
        }
    }

    /// Сканирует через VNDocumentCameraViewController (Live)
    public func scanFromCamera() -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        // scanner.delegate = self // Нужен UIViewController delegate
        return scanner
    }

    /// Batch сканирование нескольких чеков
    public func scanBatch(images: [UIImage]) async -> [ScannedReceipt] {
        var receipts: [ScannedReceipt] = []
        for (index, image) in images.enumerated() {
            await withCheckedContinuation { continuation in
                scan(image: image)
                // Ждем завершения через observation
                var cancellable: AnyCancellable?
                cancellable = self.$isScanning
                    .filter { !$0 }
                    .first()
                    .sink { _ in
                        if let receipt = self.scannedReceipt {
                            receipts.append(receipt)
                        }
                        cancellable?.cancel()
                        continuation.resume()
                    }
            }
            await MainActor.run {
                self.scanProgress = Double(index + 1) / Double(images.count)
            }
        }
        return receipts
    }

    /// Улучшает качество изображения перед OCR
    public func preprocess(image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let ciImage = CIImage(cgImage: cgImage)

        // Контраст + резкость
        let filters: [CIFilter] = [
            CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputContrastKey: 1.2,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0 // Grayscale
            ])!,
            CIFilter(name: "CIUnsharpMask", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputRadiusKey: 2.5,
                kCIInputIntensityKey: 0.8
            ])!
        ]

        var output = ciImage
        for filter in filters {
            filter.setValue(output, forKey: kCIInputImageKey)
            if let result = filter.outputImage {
                output = result
            }
        }

        let context = CIContext()
        guard let processedCGImage = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return UIImage(cgImage: processedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Receipt Parsing Logic

    private func parseReceipt(text: String, observations: [VNRecognizedTextObservation]) -> ParsedReceipt {
        let lines = text.components(separatedBy: .newlines)

        var items: [ReceiptLineItem] = []
        var total: Double?
        var merchant: String?
        var date: Date?
        var tax: Double?
        var tip: Double?

        // 1. Извлекаем мерчанта (обычно в верхней части чека)
        merchant = extractMerchant(from: lines)

        // 2. Извлекаем дату
        date = extractDate(from: text)

        // 3. Извлекаем items и total
        let (parsedItems, parsedTotal, parsedTax, parsedTip) = extractItemsAndTotal(from: lines)
        items = parsedItems
        total = parsedTotal
        tax = parsedTax
        tip = parsedTip

        // 4. Fallback: если total не найден, ищем по паттернам
        if total == nil {
            total = extractTotalFallback(from: text)
        }

        return ParsedReceipt(
            merchant: merchant,
            date: date,
            total: total,
            items: items,
            tax: tax,
            tip: tip
        )
    }

    private func extractMerchant(from lines: [String]) -> String? {
        // Мерчант обычно в первых 3 строках
        let candidates = lines.prefix(3)

        for line in candidates {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Исключаем адреса и телефоны
            if trimmed.count > 2 && trimmed.count < 40,
               !trimmed.contains("Tel"),
               !trimmed.contains("Phone"),
               !trimmed.contains("@"),
               !trimmed.contains("www"),
               !trimmed.contains("STREET"),
               !trimmed.contains("AVE"),
               !trimmed.contains("BLVD") {
                return trimmed
            }
        }

        return candidates.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDate(from text: String) -> Date? {
        let patterns = [
            "(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})",
            "(\d{4})[/-](\d{1,2})[/-](\d{1,2})",
            "(\d{1,2})\.(\d{1,2})\.(\d{2,4})"
        ]

        let formatter = DateFormatter()

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                let groups = (1..<match.numberOfRanges).compactMap { i -> String? in
                    guard let range = Range(match.range(at: i), in: text) else { return nil }
                    return String(text[range])
                }

                if groups.count == 3 {
                    // Пробуем разные форматы
                    for dateFormat in ["MM/dd/yyyy", "yyyy/MM/dd", "dd.MM.yyyy", "MM-dd-yyyy"] {
                        formatter.dateFormat = dateFormat
                        if let date = formatter.date(from: groups.joined(separator: "/")) ??
                                      formatter.date(from: groups.joined(separator: ".")) ??
                                      formatter.date(from: groups.joined(separator: "-")) {
                            return date
                        }
                    }
                }
            }
        }

        return nil
    }

    private func extractItemsAndTotal(from lines: [String]) -> ([ReceiptLineItem], Double?, Double?, Double?) {
        var items: [ReceiptLineItem] = []
        var total: Double?
        var tax: Double?
        var tip: Double?

        var inItemsSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Определяем секции
            if lower.contains("subtotal") || lower.contains("item") || lower.contains("qty") {
                inItemsSection = true
                continue
            }

            if lower.contains("total") && !lower.contains("subtotal") {
                total = extractAmount(from: trimmed)
                inItemsSection = false
                continue
            }

            if lower.contains("tax") {
                tax = extractAmount(from: trimmed)
                continue
            }

            if lower.contains("tip") || lower.contains("gratuity") {
                tip = extractAmount(from: trimmed)
                continue
            }

            // Парсим item
            if inItemsSection {
                if let item = parseItemLine(trimmed) {
                    items.append(item)
                }
            }
        }

        return (items, total, tax, tip)
    }

    private func parseItemLine(_ line: String) -> ReceiptLineItem? {
        // Паттерны:
        // "Item Name $12.99"
        // "2 x Coffee $5.98"
        // "Item    12.99"

        let amountPattern = "([\d,]+\.\d{2})$"
        guard let regex = try? NSRegularExpression(pattern: amountPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let amount = Double(line[range].replacingOccurrences(of: ",", with: "")) else {
            return nil
        }

        let nameEndIndex = line.index(line.startIndex, offsetBy: match.range.location)
        let name = String(line[..<nameEndIndex]).trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty, name.count < 100 else { return nil }

        // Пытаемся извлечь количество
        var quantity = 1
        let qtyPattern = "^(\d+)\s*[xX\*]"
        if let qtyRegex = try? NSRegularExpression(pattern: qtyPattern),
           let qtyMatch = qtyRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let qtyRange = Range(qtyMatch.range(at: 1), in: name),
           let qty = Int(name[qtyRange]) {
            quantity = qty
        }

        return ReceiptLineItem(
            name: name,
            amount: amount,
            quantity: quantity,
            unitPrice: amount / Double(quantity)
        )
    }

    private func extractAmount(from line: String) -> Double? {
        let pattern = "([\d,]+\.\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let cleaned = line[range].replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func extractTotalFallback(from text: String) -> Double? {
        // Ищем самую большую сумму в чеке
        let pattern = "([\d,]+\.\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let amounts = matches.compactMap { match -> Double? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let cleaned = text[range].replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }

        // Фильтруем разумные суммы (> $1)
        let validAmounts = amounts.filter { $0 > 1.0 }
        return validAmounts.max()
    }

    private func handleError(_ scanError: ScanError) {
        DispatchQueue.main.async { [weak self] in
            self?.error = scanError
            self?.isScanning = false
            self?.scanProgress = 0.0
        }
    }

    // MARK: - Receipt Validation

    public func validateReceipt(_ receipt: ScannedReceipt) -> ReceiptValidation {
        var issues: [ReceiptValidationIssue] = []

        if receipt.merchantName == nil || receipt.merchantName!.isEmpty {
            issues.append(.missingMerchant)
        }

        if receipt.total == nil || receipt.total! <= 0 {
            issues.append(.missingTotal)
        }

        if receipt.items.isEmpty {
            issues.append(.noItems)
        } else if let total = receipt.total {
            let itemsTotal = receipt.items.reduce(0) { $0 + $1.amount }
            if abs(itemsTotal - total) > 1.0 {
                issues.append(.totalMismatch(expected: total, actual: itemsTotal))
            }
        }

        return ReceiptValidation(isValid: issues.isEmpty, issues: issues)
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
public struct ScannedReceipt: Identifiable {
    public let id = UUID()
    public let merchantName: String?
    public let date: Date?
    public let total: Double?
    public let items: [ReceiptLineItem]
    public let rawText: String
    public let tax: Double?
    public let tip: Double?

    public var subtotal: Double? {
        guard let total = total else { return nil }
        let taxAmount = tax ?? 0
        let tipAmount = tip ?? 0
        return total - taxAmount - tipAmount
    }
}

@available(iOS 26.0, *)
public struct ReceiptLineItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let amount: Double
    public let quantity: Int
    public let unitPrice: Double

    public var displayName: String {
        name.prefix(40).trimmingCharacters(in: .whitespaces)
    }
}

@available(iOS 26.0, *)
struct ParsedReceipt {
    let merchant: String?
    let date: Date?
    let total: Double?
    let items: [ReceiptLineItem]
    let tax: Double?
    let tip: Double?
}

@available(iOS 26.0, *)
public enum ScanError: Error, LocalizedError {
    case invalidImage
    case noTextFound
    case visionError(Error)
    case parsingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Не удалось обработать изображение"
        case .noTextFound: return "Текст не распознан. Попробуйте лучшее освещение."
        case .visionError(let error): return "Ошибка Vision: \(error.localizedDescription)"
        case .parsingFailed: return "Не удалось распарсить чек"
        }
    }
}

@available(iOS 26.0, *)
public struct ReceiptValidation {
    public let isValid: Bool
    public let issues: [ReceiptValidationIssue]
}

@available(iOS 26.0, *)
public enum ReceiptValidationIssue {
    case missingMerchant
    case missingTotal
    case noItems
    case totalMismatch(expected: Double, actual: Double)

    public var description: String {
        switch self {
        case .missingMerchant: return "Мерчант не распознан"
        case .missingTotal: return "Итоговая сумма не найдена"
        case .noItems: return "Товары не распознаны"
        case .totalMismatch(let expected, let actual):
            return "Несоответствие сумм: ожидалось \(expected), по товарам \(actual)"
        }
    }
}
