import Foundation

enum BibleBooks {

    static let all: [String] = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms",
        "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
        "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
        "James", "1 Peter", "2 Peter", "1 John", "2 John",
        "3 John", "Jude", "Revelation"
    ]

    static let oldTestament: [String] = Array(all[0..<39])
    static let newTestament: [String] = Array(all[39..<66])

    static let chapterCounts: [String: Int] = [
        "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
        "Joshua": 24, "Judges": 21, "Ruth": 4, "1 Samuel": 31, "2 Samuel": 24,
        "1 Kings": 22, "2 Kings": 25, "1 Chronicles": 29, "2 Chronicles": 36,
        "Ezra": 10, "Nehemiah": 13, "Esther": 10, "Job": 42, "Psalms": 150,
        "Proverbs": 31, "Ecclesiastes": 12, "Song of Solomon": 8, "Isaiah": 66, "Jeremiah": 52,
        "Lamentations": 5, "Ezekiel": 48, "Daniel": 12, "Hosea": 14, "Joel": 3,
        "Amos": 9, "Obadiah": 1, "Jonah": 4, "Micah": 7, "Nahum": 3,
        "Habakkuk": 3, "Zephaniah": 3, "Haggai": 2, "Zechariah": 14, "Malachi": 4,
        "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28,
        "Romans": 16, "1 Corinthians": 16, "2 Corinthians": 13, "Galatians": 6, "Ephesians": 6,
        "Philippians": 4, "Colossians": 4, "1 Thessalonians": 5, "2 Thessalonians": 3,
        "1 Timothy": 6, "2 Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13,
        "James": 5, "1 Peter": 5, "2 Peter": 3, "1 John": 5, "2 John": 1,
        "3 John": 1, "Jude": 1, "Revelation": 22
    ]

    /// Returns the canonical sort index for a book name, or nil if not found.
    static func sortIndex(for bookName: String) -> Int? {
        all.firstIndex(of: bookName)
    }

    /// Returns the testament for a book name.
    static func testament(for bookName: String) -> Testament? {
        guard let index = all.firstIndex(of: bookName) else { return nil }
        return index < 39 ? .old : .new
    }

    // MARK: - Localized Book Names

    private static let russianNames: [String: String] = [
        "Genesis": "Бытие", "Exodus": "Исход", "Leviticus": "Левит",
        "Numbers": "Числа", "Deuteronomy": "Второзаконие",
        "Joshua": "Иисус Навин", "Judges": "Судей", "Ruth": "Руфь",
        "1 Samuel": "1 Царств", "2 Samuel": "2 Царств",
        "1 Kings": "3 Царств", "2 Kings": "4 Царств",
        "1 Chronicles": "1 Паралипоменон", "2 Chronicles": "2 Паралипоменон",
        "Ezra": "Ездра", "Nehemiah": "Неемия", "Esther": "Есфирь",
        "Job": "Иов", "Psalms": "Псалтирь",
        "Proverbs": "Притчи", "Ecclesiastes": "Екклесиаст",
        "Song of Solomon": "Песня Песней", "Isaiah": "Исаия",
        "Jeremiah": "Иеремия", "Lamentations": "Плач Иеремии",
        "Ezekiel": "Иезекииль", "Daniel": "Даниил",
        "Hosea": "Осия", "Joel": "Иоиль", "Amos": "Амос",
        "Obadiah": "Авдий", "Jonah": "Иона", "Micah": "Михей",
        "Nahum": "Наум", "Habakkuk": "Аввакум", "Zephaniah": "Софония",
        "Haggai": "Аггей", "Zechariah": "Захария", "Malachi": "Малахия",
        "Matthew": "Матфея", "Mark": "Марка", "Luke": "Луки",
        "John": "Иоанна", "Acts": "Деяния",
        "Romans": "Римлянам", "1 Corinthians": "1 Коринфянам",
        "2 Corinthians": "2 Коринфянам", "Galatians": "Галатам",
        "Ephesians": "Ефесянам", "Philippians": "Филиппийцам",
        "Colossians": "Колоссянам", "1 Thessalonians": "1 Фессалоникийцам",
        "2 Thessalonians": "2 Фессалоникийцам",
        "1 Timothy": "1 Тимофею", "2 Timothy": "2 Тимофею",
        "Titus": "Титу", "Philemon": "Филимону", "Hebrews": "Евреям",
        "James": "Иакова", "1 Peter": "1 Петра", "2 Peter": "2 Петра",
        "1 John": "1 Иоанна", "2 John": "2 Иоанна", "3 John": "3 Иоанна",
        "Jude": "Иуды", "Revelation": "Откровение"
    ]

    /// Returns the localized display name for a book.
    /// - Parameters:
    ///   - canonicalName: The English canonical book name (e.g. "Genesis")
    ///   - language: Language code ("en", "ru", etc.)
    /// - Returns: The localized name, or the canonical name as fallback.
    static func localizedName(for canonicalName: String, language: String) -> String {
        if language.hasPrefix("ru") {
            return russianNames[canonicalName] ?? canonicalName
        }
        return canonicalName
    }
}
