import SwiftUI

struct PaymentView: View {
    let table: Table
    @ObservedObject var viewModel: OrderViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var paymentMethod: String = "Tiền mặt"
    @State private var cashGivenStr: String = ""
    @State private var printBill: Bool = true
    @State private var printQR: Bool = false
    
    // Bank Settings from AppStorage
    @AppStorage("BANK_ID") private var bankId: String = "MB"
    @AppStorage("BANK_ACCOUNT") private var bankAccount: String = ""
    @AppStorage("ACCOUNT_NAME") private var accountName: String = ""
    @AppStorage("BILL_PRINTER_IP") private var billPrinterIp: String = ""
    
    let paymentMethods = ["Tiền mặt", "Chuyển khoản", "Tiền mặt + CK"]
    
    var totalAmount: Int { viewModel.getTotalAmount() }
    
    var cashGiven: Int {
        Int(cashGivenStr.replacingOccurrences(of: ",", with: "")) ?? 0
    }
    
    var transferNeeded: Int {
        if paymentMethod == "Chuyển khoản" { return totalAmount }
        if paymentMethod == "Tiền mặt" { return 0 }
        return max(0, totalAmount - cashGiven)
    }
    
    var changeAmount: Int {
        if paymentMethod == "Tiền mặt + CK" { return 0 }
        return max(0, cashGiven - totalAmount)
    }
    
    var qrUrl: String? {
        if transferNeeded <= 0 { return nil }
        let cleanBankId = bankId.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        let cleanBankAccount = bankAccount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if cleanBankId.isEmpty || cleanBankAccount.isEmpty { return nil }
        
        let safeName = accountName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let orderInfo = "\(table.name) THANH TOAN".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://img.vietqr.io/image/\(cleanBankId)-\(cleanBankAccount)-compact2.png?amount=\(transferNeeded)&addInfo=\(orderInfo)&accountName=\(safeName)"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chi tiết thanh toán")) {
                    HStack {
                        Text("Tổng tiền:")
                        Spacer()
                        Text("\(totalAmount)đ").font(.title3).bold().foregroundColor(.orange)
                    }
                    
                    Picker("Phương thức", selection: $paymentMethod) {
                        ForEach(paymentMethods, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 8)
                }
                
                if paymentMethod == "Tiền mặt" || paymentMethod == "Tiền mặt + CK" {
                    Section(header: Text("Khách đưa tiền mặt")) {
                        TextField("Nhập số tiền", text: $cashGivenStr)
                            .keyboardType(.numberPad)
                            .foregroundColor(.green)
                            .font(.headline)
                        
                        if paymentMethod == "Tiền mặt" && changeAmount > 0 {
                            HStack {
                                Text("Tiền thừa trả khách:")
                                Spacer()
                                Text("\(changeAmount)đ").foregroundColor(.red)
                            }
                        }
                    }
                }
                
                if (paymentMethod == "Chuyển khoản" || paymentMethod == "Tiền mặt + CK") && transferNeeded > 0 {
                    Section(header: Text("Chuyển khoản phần còn lại: \(transferNeeded)đ")) {
                        if bankAccount.isEmpty {
                            Text("Chưa cấu hình tài khoản ngân hàng.\nVui lòng vào Cài đặt để thiết lập.")
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                        } else if let urlString = qrUrl, let url = URL(string: urlString) {
                            HStack {
                                Spacer()
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable()
                                             .scaledToFit()
                                             .frame(height: 250)
                                    } else if phase.error != nil {
                                        Text("Lỗi tải mã QR. Vui lòng kiểm tra lại thông tin ngân hàng.")
                                            .foregroundColor(.red)
                                    } else {
                                        ProgressView()
                                    }
                                }
                                Spacer()
                            }
                        } else {
                            Text("Cấu hình ngân hàng không hợp lệ.")
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                
                Section {
                    Toggle("In hóa đơn", isOn: $printBill)
                    if printBill {
                        Toggle("Kèm mã QR vào bill", isOn: $printQR)
                    }
                }
                
                Section {
                    Button(action: processPayment) {
                        Text("XÁC NHẬN THANH TOÁN")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .navigationTitle("Thanh toán Bàn \(table.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
    
    private func processPayment() {
        let history = OrderHistory(
            tableName: table.name,
            itemsJson: table.currentOrderJson ?? "[]",
            totalAmount: totalAmount,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            cashierName: "Nhân viên",
            paymentMethod: paymentMethod // Added to model
        )
        
        // 1. Push History
        FirebaseManager.shared.pushHistory(history)
        
        // 2. Clear Table
        var updatedTable = table
        updatedTable.inUse = false
        updatedTable.currentOrderJson = "[]"
        FirebaseManager.shared.updateTable(updatedTable)
        
        // 3. Print
        if printBill && !billPrinterIp.isEmpty {
            var qrText: String? = nil
            if printQR {
                qrText = TcpPrinter.shared.generateVietQRText(
                    bankId: bankId,
                    accountNo: bankAccount,
                    accountName: accountName,
                    amount: transferNeeded,
                    memo: "\(table.name) THANH TOAN"
                )
            }
            TcpPrinter.shared.printBill(ip: billPrinterIp, history: history, qrText: qrText)
        }
        
        // Clean Cart & Close
        viewModel.cart.removeAll()
        presentationMode.wrappedValue.dismiss()
        
        // Close Order Detail too by posting notification or binding
        NotificationCenter.default.post(name: NSNotification.Name("CloseOrderDetails"), object: nil)
    }
}
