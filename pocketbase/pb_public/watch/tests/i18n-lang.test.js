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
  assert.strictEqual(load({ search: '?lang=de', saved: 'ru' }).lang, 'ru');
  assert.strictEqual(load({ search: '?lang=de', languages: ['de-DE'] }).lang, 'en');
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
