import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct TableQRView: View {
    let table: Table
    @Environment(\.presentationMode) var presentationMode
    
    @AppStorage("BILL_PRINTER_IP") private var billPrinterIp: String = ""
    
    var qrUrl: String {
        let safeTable = table.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? table.name
        let safeZone = table.zone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? table.zone
        return "https://ungdungdidong-94edd.web.app/?table=\(safeTable)&zone=\(safeZone)"
    }
    
    // CoreImage filter for QR generation
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(string.data(using: .ascii), forKey: "inputMessage")
        
        if let outputImage = filter?.outputImage {
            // Scale up the image to make it crisp
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgimg = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Bàn: \(table.name) - \(table.zone)")
                    .font(.title2)
                    .bold()
                
                Image(uiImage: generateQRCode(from: qrUrl))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                
                Text(qrUrl)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .padding()
                
                HStack(spacing: 20) {
                    Button(action: {
                        UIPasteboard.general.string = qrUrl
                    }) {
                        Label("Copy Link", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        // Print QR via TCP
                        TcpPrinter.shared.printTableQR(ip: billPrinterIp, table: table, qrUrl: qrUrl)
                    }) {
                        Label("In mã QR", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Mã QR Đặt Món")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}
