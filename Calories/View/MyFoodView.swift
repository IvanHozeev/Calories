import SwiftUI

struct MyFoodView: View {
    @ObservedObject var store: CalorieStore
    @State private var showingNewFood = false
    @State private var editingFood: FoodItem? = nil
    @State private var showingNewDish = false
    @State private var editingDish: Dish? = nil

    var body: some View {
        List {
            dishesSection
            productsSection
        }
        .navigationTitle("Моя еда")
        .sheet(isPresented: $showingNewFood) {
            NewFoodSheet(store: store)
                .presentationDetents([.medium])
        }
        .sheet(item: $editingFood) { food in
            NewFoodSheet(store: store, editingFood: food)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNewDish) {
            NewDishSheet(store: store)
        }
        .sheet(item: $editingDish) { dish in
            NewDishSheet(store: store, editingDish: dish)
        }
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

            Button {
                showingNewDish = true
            } label: {
                Label("Новое блюдо", systemImage: "plus")
            }
        } header: {
            Text("Мои блюда")
        }
    }

    private var productsSection: some View {
        Section {
            ForEach(store.customFoods) { food in
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                    Text("Б\(Int(food.macrosPer100g.protein)) Ж\(Int(food.macrosPer100g.fat)) У\(Int(food.macrosPer100g.carbs)) · \(food.caloriesPer100g) ккал/100 г")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteCustomFood(food)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingFood = food
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }

            Button {
                showingNewFood = true
            } label: {
                Label("Новый продукт", systemImage: "plus")
            }
        } header: {
            Text("Мои продукты")
        }
    }
}
