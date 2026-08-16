#!/usr/bin/env python3
"""Убирает из бандла виджетов блок экрана блокировки — только для проверки.

Виджетов Togetherly нет в галерее iPhone ни в одной версии начиная с той, что
залита 13 августа 2026. Симулятор показал, чем это выглядит изнутри: система
расширение регистрирует, но список виджетов у него получить не может —
`com.togetherly.love.TogetherlyWidget` висит в `extensionsPendingDescriptorRefetch`
у chronod, а таблицы `Descriptors` и `WidgetMetadata` про наши виджеты пусты.

Подозреваемый — блок `lockWidgets`, появившийся ровно в том окне: он ЦЕЛИКОМ
состоит из `if #available(iOS 16.0, *)`, то есть тип свойства зависит от
условной ветки. Скрипт вырезает его, чтобы собрать сборку-двойник и сравнить,
что скажет chronod.

Ничего не чинит и в релиз не входит: это инструмент опыта.
"""
import re
import sys

PATH = 'ios/TogetherlyWidget/TogetherlyWidgetBundle.swift'


def main() -> int:
    src = open(PATH, encoding='utf-8').read()
    before = src

    # Ссылка на блок внутри body.
    src = src.replace('        lockWidgets\n', '')
    # Само свойство вместе с доксом над ним.
    src = re.sub(
        r'\n    /// Экран блокировки.*?\n    @WidgetBundleBuilder\n'
        r'    var lockWidgets: some Widget \{.*?\n    \}\n',
        '\n',
        src,
        flags=re.S,
    )

    if src == before:
        print('не нашёл, что вырезать — бандл уже без экрана блокировки?')
        return 1
    if 'lockWidgets' in src:
        print('осталось упоминание lockWidgets — вырезано не всё')
        return 1

    open(PATH, 'w', encoding='utf-8').write(src)
    print('lockWidgets вырезан')
    return 0


if __name__ == '__main__':
    sys.exit(main())
