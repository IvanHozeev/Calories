import SwiftUI

struct MyFoodView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingNewFood = false
    @State private var showingNewDish = false
    @State private var editingDish: Dish? = nil
    @State private var showingScanner = false

    var body: some View {
        List {
            dishesSection
            productsSection
        }
        .navigationTitle("Моя еда")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewFood = true } label: {
                        Label("Новый продукт", systemImage: "plus")
                    }
                    Button { showingNewDish = true } label: {
                        Label("Новое блюдо", systemImage: "fork.knife")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewFood) {
            NewFoodSheet(store: store)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNewDish) {
            NewDishSheet(store: store)
        }
        .sheet(item: $editingDish) { dish in
            NewDishSheet(store: store, editingDish: dish)
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerSheet(store: store)
        }
    }

    private func foodSubtitle(_ food: FoodItem) -> String {
        let g = food.defaultGrams > 0 ? food.defaultGrams : 100
        let kcal = Int((Double(food.caloriesPer100g) * g / 100).rounded())
        let macros = food.macrosPer100g.scaled(by: g)
        let gramsLabel = g == 100 ? "100 г" : "\(Int(g)) г"
        return "Б\(Int(macros.protein)) Ж\(Int(macros.fat)) У\(Int(macros.carbs)) · \(kcal) ккал / \(gramsLabel)"
    }

    private var dishesSection: some View {
        Section {
            ForEach(store.dishes) { dish in
                VStack(alignment: .leading, spacing: 2) {
                    Text(dish.name)
                    Text("\(dish.ingredients.count) ингр. · \(dish.totalCalories) ккал · Б\(Int(dish.totalMacros.protein)) Ж\(Int(dish.totalMacros.fat)) У\(Int(dish.totalMacros.carbs))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteDish(dish)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingDish = dish
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }

        } header: {
            Text("Мои блюда")
        }
    }

    private var productsSection: some View {
        Section {
            ForEach(store.customFoods) { food in
                NavigationLink {
                    FoodDetailView(food: food, store: store)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name)
                        Text(foodSubtitle(food))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteCustomFood(food)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }

        } header: {
            Text("Мои продукты")
        }
    }
}
