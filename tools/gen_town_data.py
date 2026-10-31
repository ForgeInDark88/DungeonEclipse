#!/usr/bin/env python3
"""Writes the town's data: data/buildings/*.tres (BuildingData) and
data/npcs/*.tres (NpcData). Edit the tables below and run from the project
root:  python3 tools/gen_town_data.py
(Hand edits of the .tres files are fine too; this script overwrites them.)
"""
from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def gd_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return q(v)
    if isinstance(v, dict):
        return "{" + ", ".join("%s: %s" % (q(k), gd_value(x)) for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    raise TypeError(v)


# id: name, slot, width, start, max, action, texture, chimney, resident, boss, blueprint_lvl,
#     costs (per level), level texts, description
BUILDINGS = [
    ("temple", "Храм", 10, 5, 0, 3, "temple", "chapel", (0, 0), "healer", "", 3,
     [{"gold": 80, "stone": 6, "herbs": 3}, {"gold": 200, "stone": 8, "herbs": 6}, {"gold": 450, "stone": 10, "crystal": 2}],
     ["Лечение бесплатно, снятие проклятий за золото.", "Продаёт свитки воскрешения.", "Благословение: +10% здоровья в каждом походе."],
     "Мира лечит раны и снимает проклятия с вещей."),
    ("shop", "Лавка", 22, 6, 1, 3, "shop", "shop", (0, 0), "", "", 3,
     [{}, {"gold": 150, "wood": 6, "stone": 4}, {"gold": 400, "wood": 8, "iron": 6, "crystal": 1}],
     ["Самое нужное: зелья, бомбы, свитки.", "Товары с глубин открытых регионов.", "Редкие товары и скидка 10%."],
     "Торговец покупает добычу и продаёт снаряжение."),
    ("alchemist", "Алхимик", 34, 5, 0, 3, "alchemist", "alchemist", (14, 4), "alchemist", "", 3,
     [{"gold": 100, "herbs": 5, "stone": 3}, {"gold": 220, "herbs": 8, "crystal": 1}, {"gold": 420, "herbs": 10, "crystal": 2}],
     ["Лавка зелий и эликсиров.", "Больше зелий, редкие эликсиры.", "Зелье здоровья в дорогу перед каждым походом."],
     "Квинт варит зелья из трав, что вы приносите."),
    ("tavern", "Таверна", 47, 7, 0, 3, "tavern", "tavern", (20, 6), "innkeeper", "", 0,
     [{"gold": 60, "wood": 8}, {"gold": 180, "wood": 10, "stone": 4}, {"gold": 380, "wood": 12, "iron": 4}],
     ["Слухи: знаки на всей карте следующего похода.", "Найм спутника на поход.", "Слухи бесплатно, спутники дешевле."],
     "Хельга слышит всё, что говорят путники."),
    ("quests", "Доска заданий", 58, 2, 1, 1, "quests", "quest_board", (0, 0), "", "", 0,
     [{}], ["Задания гильдии с наградами."], "Цели на поход от гильдии."),
    ("library", "Библиотека", 67, 5, 0, 3, "library", "library", (0, 0), "", "", 3,
     [{"gold": 70, "wood": 4, "stone": 4}, {"gold": 160, "wood": 6, "stone": 6}, {"gold": 350, "stone": 8, "crystal": 2}],
     ["Бестиарий и энциклопедия находок.", "Каталог чертежей и бесплатное опознание.", "+10% опыта в походах."],
     "Летописец собирает знания о подземельях."),
    ("smithy", "Кузница", 79, 6, 0, 3, "smith", "smithy", (64, 8), "blacksmith", "", 3,
     [{"gold": 80, "wood": 4, "iron": 4}, {"gold": 200, "iron": 8, "stone": 4}, {"gold": 450, "iron": 12, "crystal": 2}],
     ["Ремонт, улучшение, зачарование, переплавка.", "Работа кузнеца на 15% дешевле.", "Работа кузнеца на 30% дешевле."],
     "Брам, сын Торна, раздувает отцовский горн."),
    ("warehouse", "Склад", 91, 5, 0, 3, "warehouse", "warehouse", (0, 0), "", "", 0,
     [{"gold": 50, "wood": 6}, {"gold": 150, "wood": 8, "iron": 3}, {"gold": 300, "wood": 10, "iron": 6}],
     ["Сейф на 4 предмета: они переживут гибель героя.", "Сейф на 8 предметов.", "Сейф на 12 предметов."],
     "Вещи на складе не уходят в поход и не теряются."),
    ("hall", "Зал славы", 103, 5, 0, 3, "hall", "hall", (0, 0), "", "bone_king", 0,
     [{"gold": 120, "stone": 8}, {"gold": 260, "stone": 10, "iron": 4}, {"gold": 500, "stone": 12, "crystal": 3}],
     ["3 места для трофеев.", "6 мест для трофеев.", "9 мест для трофеев."],
     "Трофеи на витрине дают силу каждому походу: +4 к здоровью и +1 к урону за каждый."),
    ("sanctum", "Святилище Затмения", 114, 4, 1, 1, "sanctum", "sanctum", (0, 0), "", "", 0,
     [{}], ["Постоянные улучшения за осколки Затмения."], "Осколки Затмения превращаются здесь в силу."),
    ("scout_tower", "Башня разведчиков", 124, 2, 0, 3, "scout", "scout_tower", (0, 0), "", "", 0,
     [{"gold": 90, "wood": 5, "stone": 6}, {"gold": 200, "stone": 10, "iron": 3}, {"gold": 380, "stone": 12, "crystal": 1}],
     ["Типы узлов видны на 1 шаг дальше.", "На 2 шага дальше.", "На 3 шага дальше."],
     "С вершины видно, что ждёт на дороге."),
]

# requirement for the last level (boss) besides hall's first
LAST_LEVEL_BOSS = {"temple": "illusionist", "library": "illusionist", "alchemist": "drowned_bell"}

NPCS = [
    dict(id="elder", name="Староста Гвен", prof="Староста", order=0, start=True, home="", discount=0.0, build=0.0, depth=1,
         rescue="",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Ты вернулся живым — уже хорошо. Город почти пуст: кто сбежал, кого держат в клетках слуги Затмения. Приводи людей, приноси дерево, камень и железо — и мы отстроимся.",
                  options=[dict(text="Что строить первым?", reply="Склад, библиотеку и башню можно ставить хоть сейчас. Кузню, храм, таверну и лавку зелий — только когда вернутся их мастера. Ищи пленников на карте похода."),
                           dict(text="Я пойду.", reply="Ворота — в конце улицы. Береги себя.")]),
             dict(id="bone_king", when="boss:bone_king", once=True,
                  text="Король костей пал! Люди шепчутся об этом у колодца. Теперь можно строить Зал славы: пусть все видят, что тьму можно бить.",
                  options=[dict(text="Это только начало.", reply="Тогда возвращайся с новыми трофеями.")]),
             dict(id="growing", when="expeditions:3", once=True,
                  text="Город оживает: снова дымят трубы. Чем больше построек и жителей, тем щедрее купцы и тем больше узнаёшь о дороге.",
                  options=[dict(text="Спасибо, Гвен.", reply="Тебе спасибо.")]),
             dict(id="idle", when="", once=False,
                  text="Каждый новый дом — новая надежда. Возвращайся с добычей.",
                  options=[dict(text="Что дальше?", reply="Загляни в здания: каждое можно улучшить, если хватит материалов.")]),
         ]),
    dict(id="blacksmith", name="Брам", prof="Кузнец", order=1, start=False, home="smithy", discount=0.0, build=0.0, depth=1,
         rescue="Ты открыл клетку? Я Брам, сын кузнеца Торна. Отец сгинул внизу, у лавовых кузен. Дай мне горн в городе — и я скую тебе клинок не хуже отцовского.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Отец писал матери письма, которые так и не отправил. Я нашёл одно в руинах. Он верил, что чародейка зажжёт новое солнце. Я верю в железо.",
                  options=[dict(text="Построим кузню.", reply="Нужны дерево и железо. И немного золота на уголь.")]),
             dict(id="forge", when="building:smithy:1", once=False,
                  text="Горн горит. Неси руду — и железо станет оружием.",
                  options=[dict(text="Чем ещё помочь?", reply="Больше железа — лучше кузня. На третьем уровне нужен чертёж отца: стражи держат такие у себя.")]),
             dict(id="idle", when="", once=False, text="Без горна я просто сильный парень с молотом.", options=[]),
         ]),
    dict(id="healer", name="Мира", prof="Травница", order=2, start=False, home="temple", discount=0.0, build=0.0, depth=2,
         rescue="Мою тетрадь растащили по пещерам... Спасибо, что пришёл. Я умею лечить — дай мне крышу над головой, и в храме снова будут молиться.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Грибы под городом растут на свете, который падает вниз. Я писала об этом, пока меня не схватили. Если найдёшь листы моей тетради — читай их Летописцу.",
                  options=[dict(text="Я поищу.", reply="И принеси трав: в храме всегда нужны бинты и отвары.")]),
             dict(id="idle", when="", once=False, text="Раны лечатся, проклятия снимаются. Только не приходи с проклятием на сердце.", options=[]),
         ]),
    dict(id="innkeeper", name="Хельга", prof="Хозяйка таверны", order=3, start=False, home="tavern", discount=0.05, build=0.0, depth=1,
         rescue="Ох, свобода! Я Хельга. Была у меня таверна — была, пока не пришли эти твари. Отстрой её, и у тебя будет лучшая похлёбка и самые свежие слухи.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Путники болтают, а я слушаю. Кто где видел клетку, где блестело золото, где лучше не ходить — всё через мою стойку.",
                  options=[dict(text="Расскажешь мне?", reply="За кружку и пару монет — конечно. Заходи в таверну перед походом.")]),
             dict(id="idle", when="", once=False, text="Пиво сегодня тёмное, как Затмение. Шучу. Почти.", options=[]),
         ]),
    dict(id="alchemist", name="Квинт", prof="Алхимик", order=4, start=False, home="alchemist", discount=0.0, build=0.0, depth=4,
         rescue="Осторожнее с этими колбами! Ах, это вы меня освободили... Квинт, алхимик. Мне нужна лаборатория и травы — много трав.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Свет Затмения меняет травы: они растут быстрее и лечат сильнее. Опасно? Безусловно. Полезно? Чрезвычайно.",
                  options=[dict(text="Сваришь мне зелий?", reply="Постройте лабораторию — и я обеспечу вас зельями на любой поход.")]),
             dict(id="idle", when="", once=False, text="Не нюхайте синюю колбу. Просто не нюхайте.", options=[]),
         ]),
    dict(id="cartographer", name="Рен", prof="Картограф", order=5, start=False, home="scout_tower", discount=0.0, build=0.0, depth=3,
         rescue="Карты! Мои карты целы? Я Рен, картограф. Я знаю дороги под городом лучше, чем свои пять пальцев — и теперь все знаки на карте ваши.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Теперь, когда я в городе, на карте похода видны все знаки: где опасность, где золото, где кровь. И что ждёт в каждом месте — я подскажу точно.",
                  options=[dict(text="А башня?", reply="Постройте башню разведчиков — и вы увидите, какие места ждут на несколько шагов дальше.")]),
             dict(id="idle", when="", once=False, text="Дорога никогда не бывает прямой. Особенно под землёй.", options=[]),
         ]),
    dict(id="mason", name="Ульф", prof="Каменщик", order=6, start=False, home="warehouse", discount=0.0, build=0.2, depth=2,
         rescue="Наконец-то! Ульф, каменщик. Меня заставляли таскать камни для их алтарей. Теперь буду таскать для нас — и дешевле, чем кто-либо.",
         dialogs=[
             dict(id="intro", when="", once=True,
                  text="Пока я в городе, любая стройка обходится на пятую часть дешевле. Камень я знаю: где класть, где тесать, где не трогать.",
                  options=[dict(text="Отлично.", reply="Неси камень — и город встанет.")]),
             dict(id="idle", when="", once=False, text="Хороший фундамент — половина дома.", options=[]),
         ]),
]


def write_buildings() -> None:
    out_dir = os.path.join(ROOT, "data", "buildings")
    os.makedirs(out_dir, exist_ok=True)
    for i, b in enumerate(BUILDINGS):
        (bid, name, slot, width, start, mx, action, tex, chimney, resident, boss, bp, costs, texts, desc) = b
        boss = LAST_LEVEL_BOSS.get(bid, boss)
        costs_s = "Array[Dictionary]([" + ", ".join(gd_value(c) for c in costs) + "])"
        texts_s = "Array[String]([" + ", ".join(q(t) for t in texts) + "])"
        with open(os.path.join(out_dir, bid + ".tres"), "w", encoding="utf-8") as f:
            f.write(f'''[gd_resource type="Resource" script_class="BuildingData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/data/building_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/town/{tex}.png" id="2"]

[resource]
script = ExtResource("1")
id = &"{bid}"
display_name = {q(name)}
description = {q(desc)}
order = {i}
slot = {slot}
width = {width}
start_level = {start}
max_level = {mx}
costs = {costs_s}
requires_resident = &"{resident}"
requires_boss = &"{boss}"
boss_level = {1 if bid == "hall" else 0}
blueprint_level = {bp}
level_texts = {texts_s}
action = &"{action}"
texture = ExtResource("2")
chimney = Vector2({chimney[0]}, {chimney[1]})
prosperity = 3
''')


def write_npcs() -> None:
    out_dir = os.path.join(ROOT, "data", "npcs")
    os.makedirs(out_dir, exist_ok=True)
    for n in NPCS:
        dialogs = "Array[Dictionary]([" + ", ".join(gd_value(d) for d in n["dialogs"]) + "])"
        with open(os.path.join(out_dir, n["id"] + ".tres"), "w", encoding="utf-8") as f:
            f.write(f'''[gd_resource type="Resource" script_class="NpcData" load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/data/npc_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/npc/{n["id"]}.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/sprites/portraits/npc_{n["id"]}.png" id="3"]

[resource]
script = ExtResource("1")
id = &"{n["id"]}"
display_name = {q(n["name"])}
profession = {q(n["prof"])}
order = {n["order"]}
resident_from_start = {gd_value(n["start"])}
home = &"{n["home"]}"
sprite = ExtResource("2")
portrait = ExtResource("3")
discount = {n["discount"]}
build_discount = {n["build"]}
depth_min = {n["depth"]}
rescue_text = {q(n["rescue"])}
dialogs = {dialogs}
''')


if __name__ == "__main__":
    write_buildings()
    write_npcs()
