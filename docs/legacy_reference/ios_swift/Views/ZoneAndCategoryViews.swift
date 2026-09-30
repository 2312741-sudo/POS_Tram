import SwiftUI

struct ZoneManagementView: View {
    @State private var zones: [Zone] = []
    
    @State private var showingAddZone = false
    @State private var newName = ""
    
    @State private var selectedZone: Zone? = nil
    @State private var showingEditZone = false
    @State private var editName = ""
    
    var body: some View {
        List {
            ForEach(zones) { zone in
                HStack {
                    Text(zone.name)
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedZone = zone
                    editName = zone.name
                    showingEditZone = true
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let zone = zones[index]
                    FirebaseManager.shared.deleteZone(id: zone.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Khu vực")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddZone = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddZone) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin khu vực mới")) {
                        TextField("Tên khu vực", text: $newName)
                    }
                }
                .navigationTitle("Thêm Khu Vực")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingAddZone = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            let zone = Zone(name: newName)
                            FirebaseManager.shared.pushZone(zone)
                            showingAddZone = false
                            newName = ""
                        }
                        .disabled(newName.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditZone) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin khu vực")) {
                        TextField("Tên khu vực", text: $editName)
                    }
                }
                .navigationTitle("Sửa Khu Vực")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingEditZone = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            if var zone = selectedZone {
                                zone.name = editName
                                FirebaseManager.shared.updateZone(zone)
                            }
                            showingEditZone = false
                        }
                        .disabled(editName.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            FirebaseManager.shared.listenToZones { fetched in
                DispatchQueue.main.async {
                    self.zones = fetched
                }
            }
        }
    }
}

struct CategoryManagementView: View {
    @State private var categories: [Category] = []
    
    @State private var showingAddCategory = false
    @State private var newName = ""
    
    @State private var selectedCategory: Category? = nil
    @State private var showingEditCategory = false
    @State private var editName = ""
    
    var body: some View {
        List {
            ForEach(categories) { category in
                HStack {
                    Text(category.name)
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedCategory = category
                    editName = category.name
                    showingEditCategory = true
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let category = categories[index]
                    FirebaseManager.shared.deleteCategory(id: category.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Danh mục")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddCategory = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin danh mục mới")) {
                        TextField("Tên danh mục", text: $newName)
                    }
                }
                .navigationTitle("Thêm Danh Mục")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingAddCategory = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            let category = Category(name: newName)
                            FirebaseManager.shared.pushCategory(category)
                            showingAddCategory = false
                            newName = ""
                        }
                        .disabled(newName.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditCategory) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin danh mục")) {
                        TextField("Tên danh mục", text: $editName)
                    }
                }
                .navigationTitle("Sửa Danh Mục")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingEditCategory = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            if var category = selectedCategory {
                                category.name = editName
                                FirebaseManager.shared.updateCategory(category)
                            }
                            showingEditCategory = false
                        }
                        .disabled(editName.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            FirebaseManager.shared.listenToCategories { fetched in
                DispatchQueue.main.async {
                    self.categories = fetched
                }
            }
        }
    }
}
