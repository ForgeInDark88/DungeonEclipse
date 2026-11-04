# Заглушки графики: что заменить

Значки карты (медальоны с символами), иконки ресурсов, клетка пленника и
свитки больше не заглушки: их рисует `python3 tools/gen_quality_art.py`
(вызывается и из `gen_placeholders.py loop`). Здания, руины, флаги, жители (с
двумя кадрами дыхания `npc/<id>_idle.png`), портреты, иконки зданий
`ui/buildings/<id>.png` и декорации событий — пиксель-арт в стиле города из
`python3 tools/gen_town_loop_art.py` (на тех же деталях, что `gen_town.py`).
Замените PNG тем же именем и размером (или крупнее, тогда поправьте
размеры в коде, где они указаны).

## Карта похода — `assets/ui/map/`
| Файл | Размер | Что это |
|---|---|---|
| `node_level.png`, `node_elite.png`, `node_special.png`, `node_camp.png`, `node_rescue.png`, `node_event.png`, `node_lair.png`, `node_boss.png` | 16×16 | Иконки типов узлов (круглая печать на пергаменте) |
| `node_cache.png`, `node_mine.png`, `node_crypt.png` | 16×16 | Особые места: тайник, шахта, склеп |
| `node_unknown.png` | 16×16 | Узел в тумане («?») |
| `hint_danger.png`, `hint_gold.png`, `hint_blood.png` | 8×8 | Знаки над узлами |
| `hero_marker.png` | 12×16 | Флажок-фигурка героя на карте |

## Город — `assets/sprites/town/`
| Файл | Размер | Что это |
|---|---|---|
| `alchemist.png` | 64×66 | Лаборатория алхимика |
| `library.png` | 72×70 | Библиотека |
| `sanctum.png` | 64×80 | Святилище Затмения |
| `warehouse.png` | 76×58 | Склад |
| `scout_tower.png` | 30×96 | Башня разведчиков |
| `hall.png` | 80×72 | Зал славы |
| `ruins.png` | 64×26 | Руины на пустом фундаменте |
| `banner_red.png`, `banner_blue.png`, `banner_gold.png` | 8×16 | Флаги улучшенных зданий |

Храм, лавка, таверна, кузня, доска заданий, дома и фонари — прежние спрайты
города (`tools/gen_town.py`).

## Жители — `assets/sprites/npc/` и `assets/sprites/portraits/`
| Файл | Размер | Что это |
|---|---|---|
| `npc/<id>.png` (`elder`, `blacksmith`, `healer`, `innkeeper`, `alchemist`, `cartographer`, `mason`) | 20×30 | Житель на улице (одна поза; можно сделать лист анимации) |
| `portraits/npc_<id>.png` | 48×48 | Портрет в окне диалога (рисуется ×2) |
| `npc/townsfolk_a.png`, `npc/townsfolk_b.png` | 20×30 | Прохожие (запас на будущее) |

## Ресурсы и предметы
| Файл | Размер | Что это |
|---|---|---|
| `ui/res/wood.png`, `stone.png`, `iron.png`, `herbs.png`, `crystal.png` | 10×10 | Значки ресурсов города |
| `sprites/items/revive_scroll.png` | 16×16 | Свиток воскрешения (храм) |
| `sprites/world/cage.png` | 28×36 | Клетка пленника (узел «Пленник») |
| `sprites/road_events/<prop>.png` | до 48×44 | Декорации событий в их залах (`EventData.prop`) |
