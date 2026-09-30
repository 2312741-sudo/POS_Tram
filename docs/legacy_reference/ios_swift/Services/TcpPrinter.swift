import Foundation
import Network

class TcpPrinter {
    static let shared = TcpPrinter()
    private var connection: NWConnection?
    
    // Commands for ESC/POS
    private let ESC_INIT: [UInt8] = [0x1B, 0x40]
    private let GS_CUT: [UInt8] = [0x1D, 0x56, 0x41, 0x10]
    
    func printData(ipAddress: String, text: String) {
        let host = NWEndpoint.Host(ipAddress)
        let port = NWEndpoint.Port(rawValue: 9100)!
        
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendPrintCommand(text: text)
            case .failed(let error):
                print("Lỗi kết nối máy in: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: .global())
    }
    
    private func sendPrintCommand(text: String) {
        // Init printer
        var data = Data(ESC_INIT)
        
        // Convert text to non-accented if needed (Vietnamese accents often don't print well on raw ESC/POS without specific code pages)
        let asciiText = text.folding(options: .diacriticInsensitive, locale: .current)
        if let textData = asciiText.data(using: .utf8) {
            data.append(textData)
        }
        
        // Line feeds and cut
        data.append(contentsOf: [0x0A, 0x0A, 0x0A])
        data.append(contentsOf: GS_CUT)
        
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Lỗi gửi dữ liệu in: \(error)")
            } else {
                print("Đã gửi lệnh in thành công")
            }
            self?.connection?.cancel()
        })
    }
    
    func encodeText(_ text: String) -> [UInt8] {
        return Array(text.data(using: .utf8) ?? Data())
    }

    func printTableQR(ip: String, table: Table, qrUrl: String) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(rawValue: 9100)!
        let qrConnection = NWConnection(host: host, port: port, using: .tcp)
        
        qrConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var data = Data()
                data.append(contentsOf: [0x1B, 0x40]) // Init
                
                data.append(contentsOf: [0x1B, 0x61, 0x01]) // Center
                data.append(contentsOf: [0x1D, 0x21, 0x11])
                data.append(contentsOf: Array("MA QR DAT MON\n".utf8))
                
                data.append(contentsOf: [0x1D, 0x21, 0x00])
                data.append(contentsOf: Array("--------------------------------\n".utf8))
                
                data.append(contentsOf: [0x1B, 0x61, 0x00]) // Left
                let safeName = table.name.folding(options: .diacriticInsensitive, locale: .current)
                let safeZone = table.zone.folding(options: .diacriticInsensitive, locale: .current)
                data.append(contentsOf: Array("Ban: \(safeName)\n".utf8))
                data.append(contentsOf: Array("Khu vuc: \(safeZone)\n".utf8))
                data.append(contentsOf: Array("--------------------------------\n".utf8))
                
                data.append(contentsOf: [0x1B, 0x61, 0x01]) // Center
                let qrBytes = Array(qrUrl.utf8)
                let pL = UInt8((qrBytes.count + 3) % 256)
                let pH = UInt8((qrBytes.count + 3) / 256)
                
                data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]) // Model 2
                data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06])      // Size 6
                data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31])      // Level M (15%)
                data.append(contentsOf: [0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30])          // Store data
                data.append(contentsOf: qrBytes)
                data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30])      // Print
                
                data.append(contentsOf: Array("\n\nQuet ma QR de dat mon!\n".utf8))
                data.append(contentsOf: [0x0A, 0x0A, 0x0A])
                data.append(contentsOf: [0x1D, 0x56, 0x41, 0x00])
                
                qrConnection.send(content: data, completion: .contentProcessed { _ in
                    qrConnection.cancel()
                })
            default: break
            }
        }
        qrConnection.start(queue: .global())
    }
    
    func printBill(ip: String, history: OrderHistory, qrText: String? = nil) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(rawValue: 9100)!
        let billConnection = NWConnection(host: host, port: port, using: .tcp)
        
        billConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var data = Data()
                data.append(contentsOf: [0x1B, 0x40]) // Init
                
                // Header
                data.append(contentsOf: [0x1B, 0x61, 0x01]) // Center
                data.append(contentsOf: [0x1D, 0x21, 0x11]) // Big text
                data.append(contentsOf: Array("HOA DON THANH TOAN\n".utf8))
                
                data.append(contentsOf: [0x1D, 0x21, 0x00]) // Normal
                let safeTable = history.tableName.folding(options: .diacriticInsensitive, locale: .current)
                data.append(contentsOf: Array("Ban: \(safeTable)\n".utf8))
                data.append(contentsOf: Array("--------------------------------\n".utf8))
                
                // Items
                data.append(contentsOf: [0x1B, 0x61, 0x00]) // Left
                if let itemsData = history.itemsJson.data(using: .utf8),
                   let items = try? JSONDecoder().decode([Product].self, from: itemsData) {
                    for item in items {
                        let safeName = item.name.folding(options: .diacriticInsensitive, locale: .current)
                        let paddedName = safeName.padding(toLength: 20, withPad: " ", startingAt: 0)
                        let qty = String(item.quantity)
                        let total = String(item.price * item.quantity)
                        let paddedQty = String(repeating: " ", count: max(0, 3 - qty.count)) + qty
                        let paddedTotal = String(repeating: " ", count: max(0, 8 - total.count)) + total
                        let line = "\(paddedName) \(paddedQty) \(paddedTotal)\n"
                        data.append(contentsOf: Array(line.utf8))
                    }
                }
                
                data.append(contentsOf: Array("--------------------------------\n".utf8))
                data.append(contentsOf: [0x1D, 0x21, 0x01]) // Double height
                data.append(contentsOf: Array("TONG: \(history.totalAmount) VND\n".utf8))
                data.append(contentsOf: [0x1D, 0x21, 0x00])
                
                if let method = history.paymentMethod?.folding(options: .diacriticInsensitive, locale: .current) {
                    data.append(contentsOf: Array("(\(method))\n".utf8))
                }
                
                // Print QR if present
                if let qrText = qrText {
                    data.append(contentsOf: [0x1B, 0x61, 0x01]) // Center
                    data.append(contentsOf: Array("\nMa QR Thanh toan:\n".utf8))
                    let qrBytes = Array(qrText.utf8)
                    let pL = UInt8((qrBytes.count + 3) % 256)
                    let pH = UInt8((qrBytes.count + 3) / 256)
                    data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]) // Model 2
                    data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06])      // Size 6
                    data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31])      // Level M (15%)
                    data.append(contentsOf: [0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30])          // Store data
                    data.append(contentsOf: qrBytes)
                    data.append(contentsOf: [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30])      // Print
                    data.append(contentsOf: Array("\n".utf8))
                }
                
                // Cut
                data.append(contentsOf: [0x0A, 0x0A, 0x0A])
                data.append(contentsOf: [0x1D, 0x56, 0x41, 0x00])
                
                billConnection.send(content: data, completion: .contentProcessed { _ in
                    billConnection.cancel()
                })
            default: break
            }
        }
        billConnection.start(queue: .global())
    }
    
    // MARK: - VietQR helper functions for printing
    
    private func removeAccent(_ string: String) -> String {
        let temp = string.folding(options: .diacriticInsensitive, locale: .current)
        let replaced = temp.replacingOccurrences(of: "đ", with: "d")
                           .replacingOccurrences(of: "Đ", with: "D")
                           .replacingOccurrences(of: "đ", with: "d")
        return replaced.filter { $0.isASCII }.map { String($0) }.joined()
    }
    
    private func mapBankIdToBin(_ id: String) -> String {
        let cleanedId = id.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedId.range(of: "^\\d{6}$", options: .regularExpression) != nil {
            return cleanedId
        }
        switch cleanedId {
        case "MB", "MBBANK": return "970422"
        case "VCB", "VIETCOMBANK": return "970436"
        case "VTB", "VIETINBANK": return "970415"
        case "BIDV": return "970418"
        case "AGRIBANK": return "970405"
        case "ACB": return "970416"
        case "TPB", "TPBANK": return "970423"
        case "VPB", "VPBANK": return "970432"
        case "TCB", "TECHCOMBANK": return "970407"
        case "HDB", "HDBANK": return "970437"
        case "VIB": return "970441"
        case "STB", "SACOMBANK": return "970403"
        case "SHB": return "970443"
        case "MSB": return "970426"
        case "LPB": return "970449"
        case "OCB": return "970448"
        default: return "970422"
        }
    }
    
    private func crc16(_ data: String) -> String {
        var crc: UInt16 = 0xFFFF
        let bytes = Array(data.utf8)
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return String(format: "%04X", crc)
    }
    
    func generateVietQRText(bankId: String, accountNo: String, accountName: String, amount: Int, memo: String) -> String {
        let bin = mapBankIdToBin(bankId)
        let safeAcc = accountNo.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        var safeName = removeAccent(accountName).uppercased()
        safeName = safeName.filter { $0.isLetter || $0.isNumber || $0 == " " }
        safeName = safeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeName.isEmpty { safeName = "TRAM APP" }
        
        var cleanMemo = removeAccent(memo).uppercased()
        cleanMemo = cleanMemo.filter { $0.isLetter || $0.isNumber || $0 == " " }
        cleanMemo = cleanMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var sb = ""
        sb.append("000201")
        sb.append("010212")
        
        var pspData = ""
        pspData.append("0006\(bin)")
        pspData.append(String(format: "01%02d%@", safeAcc.count, safeAcc))
        
        var f38Value = ""
        f38Value.append("0010A000000727")
        f38Value.append(String(format: "01%02d%@", pspData.count, pspData))
        f38Value.append("0208QRIBFTTA")
        
        sb.append(String(format: "38%02d%@", f38Value.count, f38Value))
        sb.append("52040000")
        sb.append("5303704")
        
        if amount > 0 {
            let sAmount = String(amount)
            sb.append(String(format: "54%02d%@", sAmount.count, sAmount))
        }
        sb.append("5802VN")
        sb.append(String(format: "59%02d%@", safeName.count, safeName))
        
        if !cleanMemo.isEmpty {
            var finalMemo = cleanMemo
            if finalMemo.count > 25 {
                finalMemo = String(finalMemo.prefix(25))
            }
            let memoSub = String(format: "08%02d%@", finalMemo.count, finalMemo)
            sb.append(String(format: "62%02d%@", memoSub.count, memoSub))
        }
        sb.append("6304")
        let payload = sb
        return payload + crc16(payload)
    }
}
