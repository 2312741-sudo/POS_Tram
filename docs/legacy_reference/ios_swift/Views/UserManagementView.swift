import SwiftUI

struct UserManagementView: View {
    @State private var users: [User] = []
    
    @State private var showingAddUser = false
    @State private var newFullName = ""
    @State private var newUsername = ""
    @State private var newPin = ""
    @State private var newRole = "STAFF"
    
    @State private var selectedUser: User? = nil
    @State private var showingEditUser = false
    @State private var editFullName = ""
    @State private var editUsername = ""
    @State private var editPin = ""
    @State private var editRole = ""
    
    let roles = ["STAFF", "MANAGER", "KITCHEN"]
    
    var body: some View {
        List {
            ForEach(users) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.fullName).font(.headline)
                        Text("Tài khoản: \(user.username) - Vai trò: \(user.role)").font(.subheadline).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedUser = user
                    editFullName = user.fullName
                    editUsername = user.username
                    editPin = user.pin
                    editRole = user.role
                    showingEditUser = true
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let user = users[index]
                    FirebaseManager.shared.deleteUser(id: user.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Nhân viên")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddUser = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddUser) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin nhân viên mới")) {
                        TextField("Họ và tên", text: $newFullName)
                        TextField("Tên đăng nhập", text: $newUsername)
                        TextField("Mã PIN (Đăng nhập)", text: $newPin).keyboardType(.numberPad)
                        Picker("Vai trò", selection: $newRole) {
                            ForEach(roles, id: \.self) { role in
                                Text(role).tag(role)
                            }
                        }
                    }
                }
                .navigationTitle("Thêm Nhân Viên")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingAddUser = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            let user = User(fullName: newFullName, username: newUsername, pin: newPin, role: newRole)
                            FirebaseManager.shared.pushUser(user)
                            showingAddUser = false
                            newFullName = ""; newUsername = ""; newPin = ""; newRole = "STAFF"
                        }
                        .disabled(newFullName.isEmpty || newUsername.isEmpty || newPin.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditUser) {
            NavigationView {
                Form {
                    Section(header: Text("Thông tin nhân viên")) {
                        TextField("Họ và tên", text: $editFullName)
                        TextField("Tên đăng nhập", text: $editUsername)
                        TextField("Mã PIN (Đăng nhập)", text: $editPin).keyboardType(.numberPad)
                        Picker("Vai trò", selection: $editRole) {
                            ForEach(roles, id: \.self) { role in
                                Text(role).tag(role)
                            }
                        }
                    }
                }
                .navigationTitle("Sửa Nhân Viên")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showingEditUser = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            if var user = selectedUser {
                                user.fullName = editFullName
                                user.username = editUsername
                                user.pin = editPin
                                user.role = editRole
                                FirebaseManager.shared.updateUser(user)
                            }
                            showingEditUser = false
                        }
                        .disabled(editFullName.isEmpty || editUsername.isEmpty || editPin.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            FirebaseManager.shared.listenToUsers { fetched in
                DispatchQueue.main.async {
                    self.users = fetched
                }
            }
        }
    }
}
