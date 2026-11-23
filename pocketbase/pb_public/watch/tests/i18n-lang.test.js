// Язык комнаты и ленты: `?lang=` от приложения, выбор человека, язык браузера.
//
// Бразилец с португальским приложением видел комнату по-английски: словарь
// знал только ru и en, а язык брался из системы (16.11.2026).
//
// Запуск: node pocketbase/pb_public/watch/tests/i18n-lang.test.js
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'i18n.js'), 'utf8');

// Поднять i18n.js в песочнице с заданным адресом, сохранённым выбором и
// языками браузера; вернуть его I18N.
function load({ search = '', saved = null, languages = ['en-US'] } = {}) {
  const store = saved ? { 'togetherly.watch.lang': saved } : {};
  const window = {};
  const sandbox = {
    window,
    location: { search },
    URLSearchParams,
    localStorage: {
      getItem: (k) => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
    },
    navigator: { languages, language: languages[0] },
    document: {
      documentElement: {},
      querySelectorAll: () => [],
      dispatchEvent: () => {},
    },
    CustomEvent: function CustomEvent() {},
  };
  vm.runInNewContext(SOURCE, sandbox);
  return window.I18N;
}

let failed = 0;
function check(name, fn) {
  try {
    fn();
    console.log('ok   ' + name);
  } catch (e) {
    failed++;
    console.log('FAIL ' + name + '\n     ' + e.message);
  }
}

check('приложение передаёт pt — комната по-португальски', () => {
  const i = load({ search: '?name=S%C3%A1vio&lang=pt', languages: ['en-US'] });
  assert.strictEqual(i.lang, 'pt');
  assert.strictEqual(i.t('room.empty'), 'Cole o link de um vídeo');
  assert.strictEqual(i.t('room.alone'), 'só você');
  assert.strictEqual(i.t('room.viewers', { n: 2 }), 'assistindo: 2');
});

check('язык из адреса важнее сохранённого выбора', () => {
  assert.strictEqual(load({ search: '?lang=pt', saved: 'ru' }).lang, 'pt');
});

check('незнакомый язык из адреса не мешает остальным правилам', () => {
  assert.strictEqual(load({ search: '?lang=ja', saved: 'ru' }).lang, 'ru');
  assert.strictEqual(load({ search: '?lang=ja', languages: ['ja-JP'] }).lang, 'en');
});

// До 23.11.2026 словарь знал только ru, en и pt: украинец, китаец, немец,
// француз, испанец и итальянец видели комнату по-английски.
check('все языки приложения: из адреса и из браузера', () => {
  const room = {
    uk: 'Вставте посилання на відео', zh: '粘贴视频链接',
    de: 'Füge einen Videolink ein', fr: 'Colle un lien vers une vidéo',
    es: 'Pega el enlace de un vídeo', it: 'Incolla il link di un video',
  };
  for (const [lang, text] of Object.entries(room)) {
    const fromApp = load({ search: '?lang=' + lang, languages: ['en-US'] });
    assert.strictEqual(fromApp.lang, lang);
    assert.strictEqual(fromApp.t('room.empty'), text);
    assert.strictEqual(load({ languages: [lang + '-XX', 'en'] }).lang, lang);
  }
  assert.strictEqual(load({ languages: ['zh-TW'] }).lang, 'zh');
  assert.strictEqual(load({ languages: ['en-GB', 'de-AT'] }).lang, 'de');
});

check('каждый язык покрывает все ключи английского', () => {
  const en = load({ search: '?lang=en' });
  const keys = fs.readFileSync(path.join(__dirname, '..', 'i18n.js'), 'utf8')
    .match(/^ {6}'([a-z0-9.]+)':/gm).map((s) => s.trim().slice(1, -2));
  for (const lang of ['uk', 'zh', 'de', 'fr', 'es', 'it']) {
    const i = load({ search: '?lang=' + lang });
    const same = [...new Set(keys)].filter((k) => i.t(k) === en.t(k)
      && !['foot.github', 'gate.yandex', 'room.chat', 'room.pauseNow', 'nav.app',
        'foot.col.app', 'gate.email', 'gate.pass', 'room.offline', 'room.message',
        'room.fileSource', 'privacy.title', 'nav.privacy', 'foot.privacy'].includes(k));
    // Совпасть с английским могут только слова, одинаковые в обоих языках.
    assert.ok(same.length <= 3, lang + ': как в английском — ' + same.join(', '));
  }
});

check('старая сборка без lang: португальский браузер — португальский', () => {
  assert.strictEqual(load({ languages: ['pt-BR', 'en-US'] }).lang, 'pt');
});

check('русский браузер остаётся русским', () => {
  assert.strictEqual(load({ languages: ['en-US', 'ru-RU'] }).lang, 'ru');
});

check('португальский словарь покрывает все ключи английского', () => {
  const i = load({ search: '?lang=pt' });
  const en = load({ search: '?lang=en' });
  // Ключи берутся из исходника: каждый 'ключ': в блоке en.
  const enBlock = SOURCE.slice(SOURCE.indexOf('    en: {'), SOURCE.indexOf('    pt: {'));
  const keys = [...enBlock.matchAll(/^\s+'([a-z0-9.]+[A-Za-z0-9.]*)':/gm)].map((m) => m[1]);
  assert.ok(keys.length > 100, 'ключей английского: ' + keys.length);
  const same = keys.filter((k) => i.t(k) === en.t(k) && !/^(foot\.github|gate\.yandex|nav\.app|foot\.col\.app|room\.chat)$/.test(k));
  assert.deepStrictEqual(same, [], 'не переведено: ' + same.join(', '));
});

check('set() принимает pt и помнит выбор', () => {
  const i = load({ languages: ['en-US'] });
  i.set('pt');
  assert.strictEqual(i.lang, 'pt');
  i.set('xx');
  assert.strictEqual(i.lang, 'pt');
});

if (failed) {
  console.log(`\n${failed} не прошло`);
  process.exit(1);
}
console.log('\nвсё прошло');
