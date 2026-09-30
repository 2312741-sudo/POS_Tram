import SwiftUI

struct MenuManagementView: View {
    @State private var products: [Product] = []
    
    @State private var showingAddProduct = false
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var newUnit = "Cái"
    @State private var newCategory = "Đồ ăn"
    
    @State private var selectedProduct: Product? = nil
    @State private var showingEditProduct = false
    @State private var editName = ""
    @State private var editPrice = ""
    @State private var editUnit = ""
    @State private var editCategory = ""
    
    var body: some View {
        List {
            ForEach(products) { product in
                HStack(spacing: 12) {
                    if let resourceName = product.imageResourceName, !resourceName.isEmpty {
                        Image(resourceName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.headline)
                        Text("\(product.price)đ - \(product.category)").font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedProduct = product
                    editName = product.name
                    editPrice = String(product.price)
                    editUnit = product.unit
                    editCategory = product.category
                    showingEditProduct = true
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let product = products[index]
                    FirebaseManager.shared.deleteProduct(id: product.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Thực đơn")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddProduct = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProduct) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin Món mới")) {
                        TextField("Tên món", text: $newName)
                        TextField("Giá tiền", text: $newPrice).keyboardType(.numberPad)
                        TextField("Đơn vị (Ly, Cái, Đĩa)", text: $newUnit)
                        TextField("Danh mục", text: $newCategory)
                    }
                }
                .navigationTitle("Thêm Món")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingAddProduct = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            let price = Int(newPrice) ?? 0
                            let prod = Product(name: newName, price: price, unit: newUnit, category: newCategory)
                            FirebaseManager.shared.pushProduct(prod)
                            showingAddProduct = false
                            newName = ""; newPrice = ""
                        }
                        .disabled(newName.isEmpty || newPrice.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditProduct) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin món")) {
                        TextField("Tên món", text: $editName)
                        TextField("Giá tiền", text: $editPrice).keyboardType(.numberPad)
                        TextField("Đơn vị (Ly, Cái, Đĩa)", text: $editUnit)
                        TextField("Danh mục", text: $editCategory)
                    }
                }
                .navigationTitle("Sửa Món")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingEditProduct = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            if var product = selectedProduct {
                                product.name = editName
                                product.price = Int(editPrice) ?? 0
                                product.unit = editUnit
                                product.category = editCategory
                                FirebaseManager.shared.updateProduct(product)
                            }
                            showingEditProduct = false
                        }
                        .disabled(editName.isEmpty || editPrice.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            FirebaseManager.shared.listenToProducts { fetched in
                DispatchQueue.main.async {
                    self.products = fetched
                }
            }
        }
    }
}

struct TableManagementView: View {
    @State private var tables: [Table] = []
    
    @State private var showingAddTable = false
    @State private var newName = ""
    @State private var newZone = "Khu A"
    
    @State private var selectedTable: Table? = nil
    @State private var showingEditTable = false
    @State private var editName = ""
    @State private var editZone = ""
    
    var body: some View {
        List {
            ForEach(tables) { table in
                HStack {
                    VStack(alignment: .leading) {
                        Text(table.name).font(.headline)
                        Text("Khu vực: \(table.zone)").font(.subheadline).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTable = table
                    editName = table.name
                    editZone = table.zone
                    showingEditTable = true
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let table = tables[index]
                    if let key = table.firebaseKey {
                        FirebaseManager.shared.deleteTable(key: key)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Quản lý Bàn")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddTable = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTable) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin bàn mới")) {
                        TextField("Tên bàn", text: $newName)
                        TextField("Khu vực (VD: Tầng 1, Sân vườn)", text: $newZone)
                    }
                }
                .navigationTitle("Thêm Bàn")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingAddTable = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            let table = Table(name: newName, zone: newZone, inUse: false)
                            FirebaseManager.shared.pushTable(table)
                            showingAddTable = false
                            newName = ""
                        }
                        .disabled(newName.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditTable) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin bàn")) {
                        TextField("Tên bàn", text: $editName)
                        TextField("Khu vực (VD: Tầng 1, Sân vườn)", text: $editZone)
                    }
                }
                .navigationTitle("Sửa Bàn")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingEditTable = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            if var table = selectedTable {
                                table.name = editName
                                table.zone = editZone
                                FirebaseManager.shared.updateTable(table)
                            }
                            showingEditTable = false
                        }
                        .disabled(editName.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            FirebaseManager.shared.listenToTables { fetched in
                DispatchQueue.main.async {
                    self.tables = fetched
                }
            }
        }
    }
}
