import Foundation

/// Черновик профиля: то, что стоит в колёсах и переключателях «Профиля», пока
/// человек их крутит.
///
/// Нужен затем, что между профилем и экраном нет прямого соответствия. Профиль
/// хранит килограммы и сантиметры дробными, колёса работают целыми десятыми;
/// вес на экране берётся не из профиля, а из последнего взвешивания; норма жира
/// подрезается по границам, а норма на сухую массу помнит, задавали её руками
/// или она подобрана. Этот перевод туда и обратно жил на экране двумя копиями —
/// в `init` и в `apply` — и обязан был совпадать слово в слово.
///
/// Он и не совпал: `init` снимал профиль, когда профиля ещё не было (экран
/// строится раньше, чем человек проходит онбординг), оставался с умолчаниями,
/// а первое же касание любой строки записывало эти умолчания в хранилище —
/// поверх введённых роста, веса и возраста. Теперь перевод один, и разойтись
/// ему не с чем.
///
/// Значение, а не объект: `@State` с ним даёт `$draft.weightTenths` даром, а
/// `Equatable` — сравнение «изменилось ли», на котором держится запись в
/// хранилище.
struct ProfileDraft: Equatable {
    var weightTenths: Int
    /// Рост в десятых долях сантиметра: 1805 — это 180.5.
    var heightTenths: Int
    var ageInt: Int
    /// Дата рождения, если она известна. У профилей, заведённых до того, как
    /// её стали спрашивать, её нет — тогда строка показывает число лет и
    /// предлагает дату, а не выдумывает её.
    var birthDate: Date?
    var proteinTenths: Int
    var proteinBasis: ProteinBasis
    var proteinLeanTenths: Int
    /// Задавали ли норму на сухую массу руками. Пока нет — при первом переходе
    /// подгоняем её так, чтобы граммы не изменились.
    var proteinLeanIsSet: Bool
    var fatTenths: Int
    var sex: Sex
    var activityLevel: ActivityLevel
    var goal: Goal

    /// Вес берётся из последнего взвешивания, а не из профиля: взвешиваются
    /// каждое утро, а профиль правят раз в полгода.
    init(profile: UserProfile?, latestWeightKg: Double?) {
        let wKg = latestWeightKg ?? profile?.weightKg ?? 70.0
        weightTenths = max(300, Int((wKg * 10).rounded()))
        // Профиль хранит сантиметры, колесо работает в десятых.
        let hCm = Int(((profile?.heightCm ?? 170) * 10).rounded())
        heightTenths = hCm > 0 ? hCm : 1700
        ageInt = profile?.age ?? 25
        birthDate = profile?.birthDate
        let pKg = profile?.proteinPerKg ?? UserProfile.defaultProteinPerKg
        proteinTenths = max(10, Int((pKg * 10).rounded()))
        proteinBasis = profile?.proteinBasis ?? .bodyweight
        let pLean = profile?.storedProteinPerLeanKg
        proteinLeanTenths = max(10, Int(((pLean ?? UserProfile.defaultProteinPerLeanKg) * 10).rounded()))
        proteinLeanIsSet = pLean != nil
        let fKg = profile?.fatPerKg ?? MacroTargets.fatPerKg
        fatTenths = min(max(Int((fKg * 10).rounded()),
                            Int(MacroTargets.fatFloorPerKg * 10)),
                        Int(MacroTargets.fatCeilingPerKg * 10))
        sex = profile?.sex ?? .male
        activityLevel = profile?.activityLevel ?? .moderate
        goal = profile?.goal ?? .maintenance
    }

    /// Профиль, который получится, если сохранить черновик как есть.
    var profile: UserProfile {
        UserProfile(
            weightKg: Double(weightTenths) / 10.0,
            heightCm: Double(heightTenths) / 10,
            age: ageInt,
            birthDate: birthDate,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: Double(proteinTenths) / 10.0,
            proteinPerLeanKg: Double(proteinLeanTenths) / 10.0,
            proteinBasis: proteinBasis,
            fatPerKg: Double(fatTenths) / 10.0
        )
    }

    var weightKg: Double { Double(weightTenths) / 10.0 }

    /// Норма белка, которую сейчас правят: у каждой основы своё число.
    var activeProteinTenths: Int {
        proteinBasis == .leanMass ? proteinLeanTenths : proteinTenths
    }

    /// Смена основы не должна менять норму: она меняет то, от чего норма
    /// считается. Поэтому при первом переходе на сухую массу число подбирается
    /// так, чтобы граммы остались прежними — дальше его правят руками, и оно
    /// живёт своей жизнью.
    mutating func seedLeanProteinIfNeeded(leanMassKg: Double?) {
        guard !proteinLeanIsSet, let lean = leanMassKg, lean > 0 else { return }
        let grams = Double(proteinTenths) / 10.0 * weightKg
        proteinLeanTenths = min(50, max(10, Int((grams / lean * 10).rounded())))
        proteinLeanIsSet = true
    }
}
