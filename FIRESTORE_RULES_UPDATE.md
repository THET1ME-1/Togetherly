# Инструкция по обновлению правил Firestore

## Проблема
Таймеры не сохранялись в базу данных, потому что в правилах Firestore не было разрешений для коллекции `groups`.

## Решение
Необходимо обновить правила Firestore в Firebase Console.

## Шаги для развертывания правил:

### Вариант 1: Через Firebase Console (рекомендуется, если нет Firebase CLI)

1. Откройте [Firebase Console](https://console.firebase.google.com/)
2. Выберите проект **togetherly-d4856**
3. В меню слева выберите **Firestore Database**
4. Перейдите на вкладку **Rules** (Правила)
5. Скопируйте содержимое файла `firestore.rules` и вставьте в редактор правил
6. Нажмите **Publish** (Опубликовать)

### Вариант 2: Через Firebase CLI

Если у вас установлен Firebase CLI:

```bash
firebase deploy --only firestore:rules
```

## Что было изменено

Добавлены правила для коллекции `groups`:

```javascript
// ── Группы: читать/писать только участникам группы ──
match /groups/{groupId} {
  allow read: if request.auth != null 
              && request.auth.uid in resource.data.members;
  allow create: if request.auth != null;
  allow update: if request.auth != null 
                && request.auth.uid in resource.data.members;
  allow delete: if request.auth != null 
                && request.auth.uid in resource.data.members;

  // Подколлекции внутри группы
  match /memories/{memoryId} {
    allow read: if request.auth != null;
    allow write: if request.auth != null;
  }

  match /moodCalendar/{userId}/{document=**} {
    allow read: if request.auth != null;
    allow write: if request.auth != null && request.auth.uid == userId;
  }
}
```

## Дополнительные улучшения

В коде также были сделаны следующие улучшения:

1. **Добавлено подробное логирование** в `timer_service.dart` и `firebase_service.dart` для отслеживания сохранения таймеров
2. **Улучшена обработка ошибок** в методе `saveTimers()` - теперь при ошибке update пробуется set с merge
3. **Добавлена информация о состоянии** - логи показывают, когда и сколько таймеров сохраняется

## Проверка

После развертывания правил:

1. Запустите приложение
2. Создайте новый таймер
3. Проверьте логи в консоли - должны появиться сообщения:
   - "TimerService: сохраняю N таймеров в Firestore для группы {groupId}"
   - "FirebaseService: сохраняю N таймеров в группу {groupId}"
   - "FirebaseService: таймеры успешно сохранены"
4. Перезапустите приложение - таймеры должны загрузиться из базы данных

## Важно

Убедитесь, что вы вошли в аккаунт и создали пару с партнером. Таймеры синхронизируются только когда:
- Пользователь авторизован
- Пользователь состоит в паре/группе (groupId не пустой)
