import SwiftUI

/// Секция параметров тела: пол, вес, рост, возраст, замеры.
///
/// Правят редко — поэтому секция находится ниже расчёта в списке профиля.
struct BodyParametersSection: View {
    @Binding var sex: Sex
    let useImperial: Bool
    let weightText: String
    let weightTrend: (points: [Double], caption: String)?
    let onWeightTapped: () -> Void
    let heightText: String
    @Binding var heightTenths: Int
    @Binding var showHeightPicker: Bool
    let onHeightTapped: () -> Void
    @Binding var ageInt: Int
    @Binding var showAgePicker: Bool
    let onAgeTapped: () -> Void
    let latestMeasurement: BodyMeasurement?
    let onMeasurementsTapped: () -> Void

    var body: some View {
        Section("Параметры тела") {
            Picker(selection: $sex) {
                ForEach(Sex.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Пол", systemImage: "person")
            }

            // Вес ведёт на свой экран, а не открывает колесо: он меняется
            // взвешиваниями с датой, и колесо тут же расходилось бы с историей.
            // Динамика переехала туда же — отдельной строке рядом делать нечего.
            NavigationLink {
                // Открывается вызывающей стороной через onWeightTapped
            } label: {
                HStack {
                    Image(systemName: "scalemass")
                    Text(weightText)
                    Spacer()
                    if let trend = weightTrend {
                        Text(trend.caption)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        WeightSparkline(points: trend.points)
                            .frame(width: 44, height: 18)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openWeight")
            .onTapGesture { onWeightTapped() }

            HStack {
                Image(systemName: "arrow.up.and.down")
                Text(LocalizedStringKey(useImperial ? "Рост, фт+дюйм" : "Рост, см"))
                Spacer()
                Text(heightText)
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHeightPicker.toggle()
                    if showHeightPicker { onHeightTapped() }
                }
            }
            if showHeightPicker {
                Picker("Рост", selection: $heightTenths) {
                    ForEach(Array(stride(from: 1000, through: 2500, by: 1)), id: \.self) { v in
                        Text(heightDisplayText(v)).tag(v)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }

            HStack {
                Image(systemName: "calendar")
                Text("Возраст")
                Spacer()
                Text("\(ageInt) лет")
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAgePicker.toggle()
                    if showAgePicker { onAgeTapped() }
                }
            }
            if showAgePicker {
                Picker("Возраст", selection: $ageInt) {
                    ForEach(5...100, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }

            // Замеры — пятой строкой, рядом с ростом и весом: это такой же
            // параметр тела, просто снимаемый лентой. В тулбаре их искали
            // глазами, потому что иконка линейки ничего не обещает.
            NavigationLink {
                // Открывается вызывающей стороной через onMeasurementsTapped
            } label: {
                HStack {
                    Image(systemName: "ruler")
                    Text("Замеры")
                    Spacer()
                    if let last = latestMeasurement {
                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openMeasurementsRow")
            .onTapGesture { onMeasurementsTapped() }
        }
    }

    private func heightDisplayText(_ tenths: Int) -> String {
        let cm = Double(tenths) / 10.0
        if useImperial {
            let inches = cm / 2.54
            let feet = Int(inches / 12)
            let remainingInches = Int(inches.truncatingRemainder(dividingBy: 12))
            return "\(feet) ft \(remainingInches) in"
        }
        return String(format: "%.1f см", cm)
    }
}
