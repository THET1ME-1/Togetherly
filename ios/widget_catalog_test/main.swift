// Проверка смены фото партнёра в виджете iPhone (обращение 284): прогон
// ios-widget-catalog.yml вырезает PhotoCatalog из PhotoWidgets.swift и
// собирает его вместе с этим файлом на macOS.
import Foundation

var failures = 0

func check(_ ok: Bool, _ text: String) {
  print(ok ? "ок: \(text)" : "ПРОВАЛ: \(text)")
  if !ok { failures += 1 }
}

let folder = NSTemporaryDirectory() + "catalog_\(UUID().uuidString)"
try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
var files: [String] = []
for index in 0..<4 {
  let path = "\(folder)/ios_partner_\(index).jpg"
  FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xD8, 0xFF]))
  files.append(path)
}
let missing = "\(folder)/пропал.jpg"

func json(_ paths: [String]) -> String {
  let items = paths.enumerated().map { ["id": "ios_partner_\($0.offset)", "label": "Фото", "path": $0.element] }
  let data = try! JSONSerialization.data(withJSONObject: items)
  return String(data: data, encoding: .utf8)!
}

// Каталог читается, пропавший файл пропускается
let read = PhotoCatalog.paths(json([files[0], missing, files[1], files[2], files[3]]))
check(read == files, "каталог без пропавшего файла: \(read.count) из 4")
check(PhotoCatalog.paths("не json").isEmpty, "битый каталог пуст")
check(PhotoCatalog.paths("").isEmpty, "пустой каталог пуст")

// Соседние записи таймлайна (через 15 минут) берут соседние снимки
let start = Date(timeIntervalSince1970: 1_760_800_000)
var seen: [String] = []
for step in 0..<8 {
  if let pick = PhotoCatalog.pick(files, at: start.addingTimeInterval(Double(step) * 900)) {
    seen.append(pick)
  }
}
check(seen.count == 8, "снимок выбран для каждой записи")
check(Set(seen.prefix(4)) == Set(files), "за час показаны все четыре снимка")
check(Array(seen.prefix(4)) == Array(seen.suffix(4)), "через час круг повторяется")
check(zip(seen, seen.dropFirst()).allSatisfy { $0 != $1 }, "соседние записи не повторяют снимок")

// Внутри одной четверти часа снимок не меняется
let a = PhotoCatalog.pick(files, at: start)
let b = PhotoCatalog.pick(files, at: start.addingTimeInterval(899 - start.timeIntervalSince1970.truncatingRemainder(dividingBy: 900)))
check(a == b, "внутри четверти часа тот же снимок")

// Один снимок или ни одного — смены нет, виджет берёт прежний ключ
check(PhotoCatalog.pick([files[0]], at: start) == nil, "один снимок не листается")
check(PhotoCatalog.pick([], at: start) == nil, "пустой каталог не листается")

try? FileManager.default.removeItem(atPath: folder)
print(failures == 0 ? "ВСЁ ЧИСТО" : "провалов: \(failures)")
exit(failures == 0 ? 0 : 1)
