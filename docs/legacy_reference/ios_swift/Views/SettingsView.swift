import SwiftUI

struct SettingsView: View {
    @Binding var isLoggedIn: Bool
    
    // Printer Settings
    @AppStorage("BILL_PRINTER_IP") private var billPrinterIp: String = ""
    @AppStorage("KITCHEN_PRINTER_IP") private var kitchenPrinterIp: String = ""
    @AppStorage("AUTO_PRINT_KITCHEN") private var autoPrintKitchen: Bool = true
    
    // Bank Settings
    @AppStorage("BANK_ID") private var bankId: String = "MB"
    @AppStorage("BANK_ACCOUNT") private var bankAccount: String = ""
    @AppStorage("ACCOUNT_NAME") private var accountName: String = ""
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Nghiệp vụ")) {
                    NavigationLink(destination: HistoryView()) {
                        Label("Lịch sử đơn hàng", systemImage: "clock.fill")
                    }
                    NavigationLink(destination: QRCodeView()) {
                        Label("Mã QR Cửa hàng", systemImage: "qrcode")
                    }
                }
                
                Section(header: Text("Quản lý")) {
                    NavigationLink(destination: MenuManagementView()) {
                        Label("Quản lý Thực đơn", systemImage: "list.bullet.rectangle.fill")
                    }
                    NavigationLink(destination: CategoryManagementView()) {
                        Label("Quản lý Danh mục", systemImage: "folder.fill")
                    }
                    NavigationLink(destination: TableManagementView()) {
                        Label("Quản lý Bàn", systemImage: "square.grid.3x3.fill")
                    }
                    NavigationLink(destination: ZoneManagementView()) {
                        Label("Quản lý Khu vực", systemImage: "map.fill")
                    }
                    NavigationLink(destination: UserManagementView()) {
                        Label("Quản lý Nhân viên", systemImage: "person.3.fill")
                    }
                }
                
                Section(header: Text("Máy in (Mạng LAN)")) {
                    HStack {
                        Label("IP Máy in Bill", systemImage: "printer.fill")
                        Spacer()
                        TextField("VD: 192.168.1.100", text: $billPrinterIp)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    HStack {
                        Label("IP Máy in Bếp", systemImage: "printer.dotmatrix.fill")
                        Spacer()
                        TextField("VD: 192.168.1.101", text: $kitchenPrinterIp)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    Toggle(isOn: $autoPrintKitchen) {
                        Label("Tự động in Bếp khi đặt món", systemImage: "bolt.fill")
                    }
                }
                
                Section(header: Text("Thông tin Ngân hàng (VietQR)")) {
                    HStack {
                        Text("Ngân hàng (Mã)")
                        Spacer()
                        TextField("VD: MB, VCB, ACB", text: $bankId)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Số tài khoản")
                        Spacer()
                        TextField("Số tài khoản", text: $bankAccount)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Tên chủ thẻ")
                        Spacer()
                        TextField("Viết hoa không dấu", text: $accountName)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button(action: {
                        isLoggedIn = false
                    }) {
                        Label("Đăng xuất", systemImage: "arrow.right.square.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Menu")
        }
        .navigationViewStyle(.stack)
    }
}
