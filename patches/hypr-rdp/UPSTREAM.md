# hypr-rdp: compositor keyboard layout policy — исследование и фикс

Дата: 2026-08-06. Версия: hypr-rdp 0.1.3 (git afec3bd, HEAD upstream `main`), Hyprland 0.56.1.
Патч: `0001-fix-make-compositor-keyboard-layout-policy-follow-la.patch` (в этой папке),
один коммит `4d4a193` поверх upstream `main`.
**PR #23 закрыт вместе со старым форком; актуальные PR: #24–#28, см. дополнение в конце файла.**

## Проблема

С `keyboard_layout_policy = "compositor"` переключение раскладки не работает:
`hyprctl switchxkblayout all next` переключает физические клавиатуры, но ввод по RDP
остаётся в `us`; Alt+Shift внутри сессии срабатывает через раз и «слетает» при первом
же Shift. Это ровно то, о чём upstream issue
[#14](https://github.com/MuNeNICK/hypr-rdp/issues/14) — оно закрыто коммитом
`a6b0e43` («fix: preserve keyboard layout state»), но фикс нерабочий.

## Причины (все доказаны экспериментально)

### 1. Wayland никогда не доставляет `wl_keyboard.modifiers` бесповерхностному клиенту

Фикс `a6b0e43` берёт активную группу из событий `wl_keyboard::Event::Modifiers`
(`src/input/wayland.rs`). Но по протоколу Wayland события `modifiers` шлются после
`enter`, т.е. только клиенту, чья поверхность имеет фокус клавиатуры. У hypr-rdp
нет ни одной поверхности — события не приходят никогда, `wl_state.keyboard_group`
вечно равен 0.

Доказательство (клиент без поверхности: bind `wl_seat` → `get_keyboard`, слушаем 4с,
в это время дважды переключаются раскладки):

```
EVENT keymap fmt=1 size=38219
EVENT repeat_info rate=25 delay=600
SUMMARY keymap=1 enter=0 modifiers=0 repeat_info=1
```

Ни одного события `modifiers`. Юнит-тесты апстрима это не ловят — там
`keyboard_group` выставляется в структуру руками.

### 2. Каждое изменение модификаторов сбрасывает группу

При любом изменении состояния модификаторов (нажатие/отпускание Shift, Alt, Ctrl,
а также `KeyboardEvent::Synchronize`, который mstsc шлёт при каждом фокусе окна)
уходит `zwp_virtual_keyboard_v1.modifiers(..., group=<трекер>)` — а трекер из-за
п.1 навсегда на группе 0. Композитор принудительно возвращает виртуальной
клавиатуре группу 0. Отсюда «то работает, то нет»: Alt+Shift, дошедший до сервера,
переключает xkb-группу виртуальной клавиатуры внутри Hyprland, но первое же
следующее нажатие Shift (заглавная буква!) шлёт modifiers со старой группой и
откатывает раскладку.

### 3. Hyprland молча игнорирует `switchxkblayout` для виртуальных клавиатур

```
$ hyprctl switchxkblayout hl-virtual-keyboard-hypr-rdp next
ok
# active_layout_index не меняется, событие activelayout не эмитится
```

При `switchxkblayout all next` события `activelayout>>...` приходят для всех
физических клавиатур, но не для виртуальной. Также Hyprland не эмитит
`activelayout` при xkb-переключении группы виртуальной клавиатуры (Alt+Shift,
пришедший по RDP). Т.е. группу виртуальной клавиатуры может выставить только сам
её владелец через `modifiers(depressed, latched, locked, group)`.

## Фикс

Мёртвая синхронизация через `wl_keyboard.modifiers` удаляется и заменяется двумя
механизмами:

1. **Внешние переключения** (`hyprctl switchxkblayout`, Alt+Shift на физической
   клавиатуре у машины): подписка на события `activelayout` через Hyprland IPC
   socket2 (модуль `src/hyprland.rs` с `EventStream` в репо уже есть). Имя
   раскладки из события резолвится в индекс группы по именам раскладок
   скомпилированного keymap («Russian» → 1), группа немедленно отправляется
   виртуальной клавиатуре.
2. **Переключение изнутри RDP-сессии** (Alt+Shift, переданный клиентом):
   `KeyboardStateTracker` ведёт реплику `xkb_state` на том же keymap и
   прогоняет через неё каждую клавишу. Опции вроде `grp:alt_shift_toggle`
   переключают группу реплики синхронно с тем, как Hyprland переключает группу
   виртуальной клавиатуры на том же потоке клавиш — отправляемый group всегда
   совпадает, откатов больше нет.

Оба источника пишут в один трекер; guard не даёт петель и лишних отправок.
Поведение политики `client` (дефолт) не затронуто. Новых зависимостей нет.
(`xkb::State` не `Send` в крейте — обёрнут `SendXkbState` с `unsafe impl Send`;
доступ сериализован мьютексом `InputState`, у libxkbcommon нет привязки к потоку.)

### Проверка

- `cargo test`: 377 тестов — все проходят (в т.ч. новые:
  `alt_shift_toggles_layout_group`, `external_group_switch_composes_with_alt_shift_toggle`,
  `layout_index_by_name_resolves_group_indices`, `activelayout_data_parses_layout_name`).
- Живой A/B (v1-механизм): стоковый и патченный инстансы бок о бок,
  `hyprctl switchxkblayout all next` / `all 0`:

```
--- after switch to next:
  hl-virtual-keyboard-hypr-rdp     -> English (US)   (сток: баг)
  hl-virtual-keyboard-hypr-rdp-1   -> Russian        (патч: следует за композитором)
```

- В бою: переключения пользователя из RDP-сессии отражаются в devices и в логе
  (`Switched virtual keyboard layout group group=1/0`).

## Ограничения

- `hyprctl switchxkblayout current next` не сработает, если main-клавиатура —
  виртуальная (Hyprland её игнорирует). Использовать `all` или имя физической.
- Alt+Shift внутри сессии работает, если RDP-клиент форвардит комбинацию
  (проверено с реальным клиентом — форвардит; локальная ОС клиента при совпадающей
  комбинации переключит и свою раскладку тоже — они меняются в ногу).
- Если физических клавиатур нет вообще, событий `activelayout` не будет —
  но внутрисессионный механизм (п.2) от них не зависит.

## Как отправить апстриму

Патч — один чистый conventional-коммит поверх свежего `main` (afec3bd), конфликтов
нет, стиль репо соблюдён. Это нормальный вид PR, стесняться нечего.

```bash
# 1. Форкнуть https://github.com/MuNeNICK/hypr-rdp на GitHub (кнопка Fork)
git clone https://github.com/<ВАШ_НИК>/hypr-rdp
cd hypr-rdp
git checkout -b fix/compositor-layout-switch
git am ~/hypr-rdp-fix/0001-fix-make-compositor-keyboard-layout-policy-follow-la.patch
cargo test        # убедиться: 377 passed
git push -u origin fix/compositor-layout-switch
# 2. На GitHub открыть Pull Request из этой ветки в MuNeNICK/hypr-rdp:main
```

### Черновик текста issue (если сначала issue, потом PR — сослаться друг на друга)

---

**Title:** `keyboard_layout_policy = "compositor"` never follows layout switches — wl_keyboard.modifiers is unreachable for a surfaceless client

**Body:**

With `keyboard_layout_policy = "compositor"`, switching layouts on the server
(`hyprctl switchxkblayout all next`) has no effect on RDP input, and Alt+Shift
inside the session snaps back to group 0 on the first modifier press. This is the
behavior #14 was about; the fix in `a6b0e43` cannot work in practice:

1. `wl_state.keyboard_group` is only updated from `wl_keyboard::Event::Modifiers`,
   but Wayland delivers `modifiers` only after `enter`, i.e. to the client whose
   surface holds keyboard focus. hypr-rdp has no surfaces, so the event never
   arrives. Verified with a minimal surfaceless client: over 4s with layouts being
   switched it receives `keymap=1, enter=0, modifiers=0, repeat_info=1`.
   (The unit tests pass because they set `keyboard_group` on the struct directly.)
2. As a result every modifier change (and every `KeyboardEvent::Synchronize` mstsc
   sends on window focus) emits `zwp_virtual_keyboard_v1.modifiers(..., group=0)`,
   resetting whatever layout the user or the compositor switched to — including
   group toggles Hyprland itself performs on the virtual keyboard when the client
   forwards Alt+Shift.
3. Hyprland silently ignores `switchxkblayout` for virtual keyboards (returns `ok`,
   index unchanged) and emits no `activelayout` events for them, so the only way to
   switch the virtual keyboard's group is the virtual-keyboard protocol itself.

Proposed fix (PR attached): replace the unreachable wl_keyboard sync with two
mechanisms under the `compositor` policy: (a) subscribe to Hyprland socket2
`activelayout` events via the existing `hyprland::EventStream` and mirror external
switches onto the virtual keyboard; (b) replicate per-key XKB state processing in
`KeyboardStateTracker` so group toggle options (e.g. `grp:alt_shift_toggle`)
forwarded by the RDP client switch the tracked group in lockstep with the
compositor's own processing. `client` policy behavior is unchanged; all tests pass;
verified live (side-by-side stock vs patched, plus real-session switching).

---

## Локальная установка (уже сделано / для повторения)

```bash
# пакет собран makepkg из pkg/aur-git с патчем:
sudo pacman -U hypr-rdp-git-0.1.3.r2.g476ed35-1-x86_64.pkg.tar.zst
# (установленный g476ed35 идентичен PR-коммиту 4d4a193 по коду,
#  отличие только в author-метаданных)
# в ~/.config/hypr-rdp/config.toml добавить:
#   keyboard_layout_policy = "compositor"
# перезапустить hypr-rdp
```

---

# Дополнение 2026-08-06 (вечер): ещё три фикса и разбор issue #21

Локальная ветка теперь содержит 5 коммитов поверх upstream `main` (afec3bd):

| Коммит | Что | Статус апстрим |
|---|---|---|
| 4d4a193 | fix: compositor layout policy (activelayout + xkb-реплика) | **PR #23 отправлен** |
| 5a451b2 | feat: session hooks (on_client_connect/disconnect, счётчик сессий) | не отправлен |
| 9f71acf | fix: сходимость переговоров о размере (letterbox вместо аспект-подгонки) | не отправлен |
| ba70b0a | feat: опция encoder = auto/software/vaapi | не отправлен |
| e57ee62 | fix: packed headers для VA-API — **это фикс issue #21** | не отправлен |

## Разбор issue #21 (белый экран с VA-API)

Цепочка доказательств (всё офлайн, без RDP-клиента, тест `vaapi_encode_probe`):

1. Поток hypr-rdp с radeonsi: 30 кадров = 2 КБ, ffmpeg не декодирует ни одного
   кадра. Все NAL-ы слайсов имеют **нулевой байт заголовка** (`00 88 80 40 02…`
   вместо `65 88 80 40 02…` у эталонного ffmpeg-потока на том же iGPU).
2. Причина в Mesa (radeon_vcn_enc.c / picture_h264_enc.c): драйвер требует
   packed headers (`VAConfigAttribEncPackedHeaders = SEQUENCE|PICTURE|SLICE|…`).
   `nal_ref_idc`/`nal_unit_type` слайса и поля slice header он **парсит из
   packed slice header, который обязано подать приложение**. hypr-rdp не
   подавал ничего — драйвер писал слайсы с пустым заголовком, а SPS/PPS
   hypr-rdp клеил на CPU, и они не соответствовали слайсам.
3. Intel iHD собирает заголовки сам — поэтому у мейнтейнера всё работало,
   а у репортера #21 (RX 9070 XT) и на Raphael iGPU — белый экран.
4. Фикс: запрос VAConfigAttribEncPackedHeaders при создании кодировщика;
   на IDR подаются packed SPS+PPS, на каждый кадр — packed slice header
   (генератор на их же BitWriter). После фикса: поток = IDR + 29 P-слайсов,
   декодируется в эталонный красный (253,0,0).

Побочный факт: `LIBVA_DRIVER_NAME=nvidia` из hyprland.lua у юзера маскировал
проблему при ручных запусках (VA-проба падала → софтверный кодировщик), а
systemd-юнит эту переменную не наследует — так белый экран и всплыл.

## Разбор ресайз-лавины (зеркальный режим)

`normalize_to_source_aspect_bounds` подгоняла размер клиента под точный аспект
источника + округление до чётного. mstsc перезапрашивает применённый размер,
сервер снова подгоняет — «лестница» 728x408→724x408→724x406→…→704x396 с
перезапуском capture+encoder на каждом шаге (белые вспышки, окно ужимается).
Фикс: принимать запрошенный размер (только чётность и лимиты H.264 —
идемпотентно), несовпадение пропорций закрывает штатный letterbox
(fill_black_bars + маппинг указателя уже это умели). Регрессионный тест
`physical_output_size_negotiation_reaches_fixed_point_immediately`.

## Про хуки (вопрос «идеальное ли решение»)

Прецедент индустрии: Sunshine `prep-cmd` (do/undo при старте/конце сессии) —
ровно эта модель. Альтернативы рассмотрены и отвергнуты: зеркальный headless
через Hyprland `mirror` не решает читаемость (копирует фреймбуфер, не
перерисовывает в другом масштабе); демон-наблюдатель снаружи — лишний юнит и
гонки. Ограничение дизайна: `on_accept` в ironrdp срабатывает до аутентификации
— одиночный порт-скан в простое дёрнет хуки (сканы во время сессии отфильтрованы
счётчиком). Для LAN приемлемо; для идеала нужен колбэк «после аутентификации»
в ironrdp (может стать отдельным PR в их форк IronRDP).

## Отправка PR 2-5

Каждый коммит независим. Для отдельных PR: cherry-pick нужного коммита на
свежий `main` в отдельную ветку (fix/resize-convergence, feat/session-hooks,
feat/encoder-option, fix/vaapi-packed-headers → «Fixes #21»). Патчи можно
регенерировать из локального клона или ветки форка.

---

# Статус PR (пересозданы 2026-08-06 после удаления форка)

Форк пересоздан, каждая ветка = один коммит на свежем upstream main (afec3bd):

- PR #24 fix/compositor-layout-policy — раскладка (замена закрытого #23)
- PR #25 fix/presentation-size-convergence — ресайз-лавина
- PR #26 fix/vaapi-packed-headers — фикс issue #21 (Fixes #21; в тексте кредит и сравнение с конкурирующим #22)
- PR #27 feat/session-hooks — хуки подключения/отключения
- PR #28 feat/encoder-option — encoder = auto/software/vaapi

Рабочая копия: ~/src/hypr-rdp (origin=форк, upstream=MuNeNICK; ветка fix/compositor-layout-switch — полный стек 5 коммитов для локальной сборки пакета).
