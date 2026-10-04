import '../models/app_models.dart';

class SeedData {
  static List<TableModel> get defaultTables => [
    // Khu A
    TableModel(name: 'A1', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A2', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A3', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A4', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A5', zone: 'Khu A', capacity: 4),
    // Khu B
    TableModel(name: 'B1', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B2', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B3', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B4', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B5', zone: 'Khu B', capacity: 4),
    // Khu C
    TableModel(name: 'C1', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C2', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C3', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C4', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C5', zone: 'Khu C', capacity: 4),
    // Khu D
    TableModel(name: 'D1', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D2', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D3', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D4', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D5', zone: 'Khu D', capacity: 4),
    // Mang về
    TableModel(name: 'Mang về', zone: 'Mang về', capacity: 2),
  ];

  static List<CategoryModel> get defaultCategories => [
    CategoryModel(name: "Bánh Lăn Nướng"),
    CategoryModel(name: "Bánh Tam Giác Nướng"),
    CategoryModel(name: "Bánh Tart"),
    CategoryModel(name: "Bánh Waffle"),
    CategoryModel(name: "Bơ Coco"),
    CategoryModel(name: "CAFE Việt Nam"),
    CategoryModel(name: "Sữa Hạt Tươi"),
    CategoryModel(name: "Topping"),
    CategoryModel(name: "Trà Olong Trái Cây"),
    CategoryModel(name: "Trà Sữa Tươi"),
  ];

  static List<ZoneModel> get defaultZones => [
    ZoneModel(name: 'Khu A'),
    ZoneModel(name: 'Khu B'),
    ZoneModel(name: 'Khu C'),
    ZoneModel(name: 'Khu D'),
    ZoneModel(name: 'Mang về'),
  ];

  static List<ProductModel> get defaultProducts => [
    ProductModel(id: 22, name: "Bánh lăn choco chip - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_22.jpg"),
    ProductModel(id: 23, name: "Bánh lăn choco chip - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_23.jpg"),
    ProductModel(id: 24, name: "Bánh lăn choco chip - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_24.jpg"),
    ProductModel(id: 25, name: "Bánh lăn cốm déo - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_25.jpg"),
    ProductModel(id: 26, name: "Bánh lăn cốm déo - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_26.jpg"),
    ProductModel(id: 27, name: "Bánh lăn cốm déo - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_27.jpg"),
    ProductModel(id: 19, name: "Bánh lăn phô mai chảy - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_19.jpg"),
    ProductModel(id: 20, name: "Bánh lăn phô mai chảy - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_20.jpg"),
    ProductModel(id: 21, name: "Bánh lăn phô mai chảy - Size 50", price: 50000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_21.jpg"),
    ProductModel(id: 17, name: "Bánh lăn truyền thống - Size 15", price: 15000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_17.jpg"),
    ProductModel(id: 18, name: "Bánh lăn truyền thống - Size 30", price: 30000, unit: "Cái", category: "Bánh Lăn Nướng", imageResourceName: "assets/images/products/product_18.jpg"),
    ProductModel(id: 29, name: "Bánh tart chuối choco", price: 20000, unit: "Cái", category: "Bánh Tart", imageResourceName: "assets/images/products/product_29.jpg"),
    ProductModel(id: 28, name: "Bánh tart trứng", price: 18000, unit: "Cái", category: "Bánh Tart", imageResourceName: "assets/images/products/product_28.jpg"),
    ProductModel(id: 35, name: "Bánh waffle bơ cay chà bông", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_35.jpg"),
    ProductModel(id: 36, name: "Bánh waffle cốm dẻo", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_36.jpg"),
    ProductModel(id: 37, name: "Bánh waffle kem choco", price: 25000, unit: "Cái", category: "Bánh Waffle", imageResourceName: "assets/images/products/product_37.jpg"),
    ProductModel(id: 34, name: "Bơ coco", price: 35000, unit: "Ly", category: "Bơ Coco", imageResourceName: "assets/images/products/product_34.jpg"),
    ProductModel(id: 32, name: "Bạc xỉu", price: 25000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_32.jpg"),
    ProductModel(id: 33, name: "Cà phê kem trứng", price: 30000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_33.jpg"),
    ProductModel(id: 31, name: "Cà phê sữa", price: 20000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_31.jpg"),
    ProductModel(id: 30, name: "Cà phê đen", price: 18000, unit: "Ly", category: "CAFE Việt Nam", imageResourceName: "assets/images/products/product_30.jpg"),
    ProductModel(id: 2, name: "Sữa bò tươi - Bí đỏ Đậu phộng", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_2.jpg"),
    ProductModel(id: 4, name: "Sữa bò tươi - Bắp non", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_4.png"),
    ProductModel(id: 3, name: "Sữa bò tươi - Cốm rang", price: 25000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_3.jpg"),
    ProductModel(id: 1, name: "Sữa bò tươi - Đậu nành hạt điều", price: 18000, unit: "Ly", category: "Sữa Hạt Tươi", imageResourceName: "assets/images/products/product_1.jpg"),
    ProductModel(id: 14, name: "Tam giác - nhân phô mai", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_14.jpg"),
    ProductModel(id: 13, name: "Tam giác - nhân sữa", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_13.jpg"),
    ProductModel(id: 15, name: "Tam giác - nhân trứng muối", price: 20000, unit: "Cái", category: "Bánh Tam Giác Nướng", imageResourceName: "assets/images/products/product_15.jpg"),
    ProductModel(id: 0, name: "Thạch chanh", price: 5000, unit: "Phần", category: "Topping", imageResourceName: "assets/images/products/product_0.jpg"),
    ProductModel(id: 7, name: "Trà Olong - Chanh dây", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_7.jpg"),
    ProductModel(id: 5, name: "Trà Olong - Chanh tươi", price: 20000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_5.jpg"),
    ProductModel(id: 45, name: "Trà Olong - Mãng cầu", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_45.jpg"),
    ProductModel(id: 8, name: "Trà Olong - Quả mọng", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_8.jpg"),
    ProductModel(id: 42, name: "Trà Olong - Xoài", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_42.jpg"),
    ProductModel(id: 10, name: "Trà Olong - Đào", price: 30000, unit: "Ly", category: "Trà Olong Trái Cây", imageResourceName: "assets/images/products/product_10.jpg"),
    ProductModel(id: 12, name: "Trà sữa tươi - Olong gạo rang", price: 35000, unit: "Ly", category: "Trà Sữa Tươi", imageResourceName: "assets/images/products/product_12.jpg"),
    ProductModel(id: 11, name: "Trà sữa tươi - Olong matcha", price: 30000, unit: "Ly", category: "Trà Sữa Tươi", imageResourceName: "assets/images/products/product_11.jpg"),
  ];
}
