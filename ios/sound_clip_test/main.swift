// Проверка SoundClipCore на macOS: прогон ios-sound-clip.yml вырезает ядро из
// AppDelegate.swift и собирает его вместе с этим файлом.
// Аргумент — папка с образцами tone.mp3, tone.m4a, tone.wav.
import AVFoundation
import Foundation

var failures = 0

func check(_ ok: Bool, _ text: String) {
  print(ok ? "ок: \(text)" : "ПРОВАЛ: \(text)")
  if !ok { failures += 1 }
}

let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let temporary = NSTemporaryDirectory()

do {
  for name in ["tone.mp3", "tone.m4a", "tone.wav"] {
    let path = "\(folder)/\(name)"
    let probe = try SoundClipCore.probe(path)
    let duration = probe["durationMs"] as? Int ?? -1
    check((4850...5150).contains(duration), "\(name): длительность \(duration) мс")

    let bars = try SoundClipCore.waveform(path, buckets: 48)
    check(bars.count == 48, "\(name): столбиков \(bars.count)")
    check(bars.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(name): волна в 0..1")
    check(abs((bars.max() ?? 0) - 1) < 1e-9, "\(name): волна нормирована")
    check((bars.min() ?? 1) < 0.8, "\(name): громкость образца плавает")

    let out = "\(temporary)cut_\(name).m4a"
    let result = try SoundClipCore.clip(path, startMs: 1000, endMs: 3000, fadeMs: 200, outPath: out)
    let cut = result["durationMs"] as? Int ?? -1
    check((1880...2120).contains(cut), "\(name): кусок \(cut) мс")
    let peaks = result["peaks"] as? [Double] ?? []
    check(peaks.count == 40, "\(name): пиков \(peaks.count)")
    check(peaks.count == 40 && peaks[0] < peaks[20], "\(name): края затухают")
    let again = try SoundClipCore.probe(out)["durationMs"] as? Int ?? -1
    check((1850...2150).contains(again), "\(name): кусок читается снова, \(again) мс")
  }

  let tail = try SoundClipCore.clip("\(folder)/tone.m4a", startMs: 4000, endMs: 9000, fadeMs: 100, outPath: "\(temporary)tail.m4a")
  let tailMs = tail["durationMs"] as? Int ?? -1
  check((850...1100).contains(tailMs), "кусок у конца обрезан по концу, \(tailMs) мс")

  let tagged = try SoundClipCore.probe("\(folder)/tone.mp3")
  check(tagged["title"] as? String == "Проба", "название из тегов mp3")
  check(tagged["artist"] as? String == "Togetherly", "исполнитель из тегов mp3")
} catch {
  check(false, "исключение \(error)")
}

let fake = "\(temporary)fake.mp3"
try? "это не песня".write(toFile: fake, atomically: true, encoding: .utf8)
do {
  _ = try SoundClipCore.probe(fake)
  check(false, "текстовый файл принят за песню")
} catch SoundClipFailure.unsupported {
  check(true, "текстовый файл — unsupported")
} catch {
  check(false, "текстовый файл: не та ошибка \(error)")
}

print(failures == 0 ? "ВСЁ ЧИСТО" : "провалов: \(failures)")
exit(failures == 0 ? 0 : 1)
