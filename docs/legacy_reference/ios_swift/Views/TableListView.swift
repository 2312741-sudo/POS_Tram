import SwiftUI

struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    @State private var showingMenu = false
    
    var body: some View {
        ZStack {
            TabView {
                TableListView(showingMenu: $showingMenu)
                    .tabItem { Label("Sơ đồ", systemImage: "square.grid.2x2") }
                
                KitchenView()
                    .tabItem { Label("Bếp", systemImage: "flame") }
                    
                OnlineOrderView()
                    .tabItem { Label("Đơn Online", systemImage: "globe") }
            }
            .accentColor(.orange)
            
            if showingMenu {
                // A very simple Sidebar Menu overlay
                GeometryReader { _ in
                    HStack(spacing: 0) {
                        SettingsView(isLoggedIn: $isLoggedIn)
                            .frame(width: 300)
                            .background(Color(UIColor.systemBackground))
                            .shadow(radius: 5)
                        
                        Color.black.opacity(0.3)
                            .onTapGesture {
                                withAnimation { showingMenu = false }
                            }
                    }
                }
                .edgesIgnoringSafeArea(.all)
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
    }
}

struct TableListView: View {
    @Binding var showingMenu: Bool
    @StateObject private var viewModel = TableViewModel()
    @State private var selectedZone: String? = nil
    
    // Add Table State
    @State private var showingAddTable = false
    @State private var newTableName = ""
    @State private var newTableZone = "Khu A"
    
    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 15)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Button(action: { withAnimation { showingMenu.toggle() } }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Trạm App - Sơ đồ")
                            .font(.headline)
                            .padding(.leading, 10)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    
                    // Zone Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ZoneChip(title: "Tất cả", isSelected: selectedZone == nil) { selectedZone = nil }
                            ForEach(Array(Set(viewModel.tables.map { $0.zone })).sorted(), id: \.self) { zone in
                                ZoneChip(title: zone, isSelected: selectedZone == zone) { selectedZone = zone }
                            }
                        }
                        .padding()
                    }
                    .background(Color(UIColor.systemBackground))
                    
                    Divider()
                    
                    // Table Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 15) {
                            let filtered = viewModel.filterTables(by: selectedZone, inUse: nil)
                            ForEach(filtered) { table in
                                NavigationLink(destination: OrderDetailView(table: table)) {
                                    TableCard(table: table)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
                
                // FAB for Adding Table
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingAddTable = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddTable) {
                NavigationView {
                    Form {
                        Section(header: Text("Thông tin bàn mới")) {
                            TextField("Tên bàn", text: $newTableName)
                            TextField("Khu vực (VD: Tầng 1, Sân vườn)", text: $newTableZone)
                        }
                    }
                    .navigationTitle("Thêm Bàn")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Hủy") { showingAddTable = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Lưu") {
                                let table = Table(name: newTableName, zone: newTableZone, inUse: false)
                                FirebaseManager.shared.updateTable(table)
                                showingAddTable = false
                                newTableName = ""
                            }
                            .disabled(newTableName.isEmpty)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ZoneChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.orange : Color(UIColor.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
            .onTapGesture(perform: action)
    }
}

struct TableCard: View {
    let table: Table
    var body: some View {
        VStack {
            Text(table.name)
                .font(.headline)
                .foregroundColor(table.inUse ? .white : .primary)
            Text(table.zone)
                .font(.caption)
                .foregroundColor(table.inUse ? .white : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(table.inUse ? Color.green : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
