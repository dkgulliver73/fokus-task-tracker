# Focus

Локальный HTML-прототип таск-трекера. Всё приложение находится в `index.html` и не требует сборки.

## Локальный запуск

```bash
python3 -m http.server 4174
```

Откройте `http://127.0.0.1:4174/`.

## Хранение и Supabase

Задачи, проекты и настройки всегда сохраняются локально. После входа по email состояние автоматически синхронизируется с Supabase.

1. Создайте Supabase-проект.
2. Примените `supabase/migrations/20260824000000_focus_state.sql` через SQL Editor или Supabase CLI.
3. Вставьте Project URL и publishable/anon key в `supabase-config.js`.
4. В Authentication → URL Configuration добавьте локальный и опубликованный URL в Redirect URLs.

В таблице `focus_state` включён RLS: каждый авторизованный пользователь видит и изменяет только свои данные.
