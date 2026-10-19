"""Génère assets/campaign/campaign.json (outil d'écriture de la campagne).

    python tool/gen_campaign.py

Le JSON produit est la source de vérité ; ce script évite les erreurs de
syntaxe à la main et factorise les déblocages (récompenses → verrous).
"""
import json
import os

rewards = {
    "m1": {"buildings": ["tower"]},
    "m2": {"units": ["archer"], "buildings": ["forge"]},
    "m3": {"buildings": ["market", "wall"]},
    "m4": {"units": ["iron_warrior"]},
    "m5": {"units": ["horseman"], "buildings": ["stable"]},
    "m6": {"units": ["catapult"], "buildings": ["siege_workshop"]},
    "m7": {},
}
order = ["m1", "m2", "m3", "m4", "m5", "m6", "m7"]


def locked_for(mid):
    """Éléments verrouillés : récompenses de cette mission et des suivantes."""
    i = order.index(mid)
    units, blds = [], []
    for later in order[i:]:
        units += rewards[later].get("units", [])
        blds += rewards[later].get("buildings", [])
    return {"units": units, "buildings": blds}


def P(frm, dx=0, dy=0):
    return {"from": frm, "dx": dx, "dy": dy}


def spawn(owner, unit, count, at, tag=None, to=None, scale=None):
    a = {"kind": "spawn", "owner": owner, "unit": unit, "count": count, "at": at}
    if tag:
        a["tag"] = tag
    if to:
        a["to"] = to
    if scale is not None:
        a["scale"] = scale
    return a


def dialog(*lines):
    return {"kind": "dialog", "lines": [{"speaker": s, "text": t} for s, t in lines]}


def hint(t):
    return {"kind": "hint", "text": t}


def obj_show(i):
    return {"kind": "objective", "id": i}


def C(k, **kw):
    return dict(kind=k, **kw)


missions = []

# ───── M1 : tutoriel ─────
missions.append({
    "id": "m1", "title": "Les premiers feux", "subtitle": "Tutoriel",
    "kingdom": [10, 70],
    "briefing": [
        "Le royaume du Fleuve renaît de ses cendres. Mbarga, héritier du trône, doit rebâtir un village capable de nourrir et de défendre son peuple.",
        "Cette première mission vous guide pas à pas : villageois, huttes, récolte, champs et premiers soldats."],
    "map": {"size": 64, "seed": 11, "style": 0},
    "players": [{"clan": "fleuve", "ai": -1, "age": 0,
                 "resources": {"food": 300, "wood": 300}, "locked": locked_for("m1")}],
    "objectives": [
        {"id": "villagers", "label": "Entraîner 3 villageois (centre-ville)", "done": C("units", unit="villager", count=7)},
        {"id": "hut", "label": "Bâtir une hutte (population)", "hidden": True, "done": C("build", building="hut", count=1)},
        {"id": "wood", "label": "Récolter 150 de bois", "hidden": True, "done": C("gather", res="wood", amount=150)},
        {"id": "field", "label": "Aménager un champ", "hidden": True, "done": C("build", building="field", count=1)},
        {"id": "barracks", "label": "Bâtir une caserne", "hidden": True, "done": C("build", building="barracks", count=1)},
        {"id": "spears", "label": "Entraîner 3 lanciers", "hidden": True, "done": C("units", unit="spearman", count=3)},
    ],
    "triggers": [
        {"id": "intro", "when": C("always"), "do": [
            dialog(("Mbarga", "Nos greniers sont vides et nos huttes en ruine. Commençons par renforcer le village."),
                   ("Ancêtre", "Sélectionne le centre-ville, puis choisis « Villageois » dans le panneau d’actions.")),
            hint("Cliquez sur le centre-ville, puis sur « Villageois » (3 fois). Clic droit sur une ressource pour récolter.")]},
        {"id": "t_hut", "when": C("objective", id="villagers"), "do": [
            obj_show("hut"),
            dialog(("Ancêtre", "Chaque hutte loge 5 habitants. Sans hutte, plus de nouveaux villageois.")),
            hint("Sélectionnez un villageois, choisissez « Hutte » puis cliquez sur le sol pour la placer.")]},
        {"id": "t_wood", "when": C("objective", id="hut"), "do": [
            obj_show("wood"),
            hint("Sélectionnez des villageois et faites un clic droit sur un arbre : ils coupent le bois et le rapportent seuls.")]},
        {"id": "t_field", "when": C("objective", id="wood"), "do": [
            obj_show("field"),
            {"kind": "give", "resources": {"wood": 200, "food": 100}},
            dialog(("Ancêtre", "Le gibier ne dure pas. Un champ nourrit ton peuple tant que tu le replantes.")),
            hint("Choisissez « Champ » avec un villageois, placez-le près du centre-ville, puis envoyez-y des villageois.")]},
        {"id": "t_barracks", "when": C("objective", id="field"), "do": [
            obj_show("barracks"),
            {"kind": "give", "resources": {"wood": 250, "food": 150}},
            dialog(("Mbarga", "Un village sans défense est une proie. Il nous faut une caserne.")),
            hint("Choisissez « Caserne » avec un villageois et placez-la à l’écart des champs.")]},
        {"id": "t_spears", "when": C("objective", id="barracks"), "do": [
            obj_show("spears"),
            {"kind": "give", "resources": {"food": 200, "wood": 100}},
            hint("Sélectionnez la caserne puis entraînez 3 lanciers. Ils protégeront le village.")]},
        {"id": "t_end", "when": C("objective", id="spears"), "do": [
            dialog(("Mbarga", "Le feu brille de nouveau dans nos huttes. Nous sommes prêts."),
                   ("Ancêtre", "Les vagues d’Amougou approchent déjà… Prépare tes lanciers.")),
            hint("")]},
    ],
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 900, "maxLosses": 0},
    "rewards": rewards["m1"],
})

# ───── M2 : vagues ─────
waves = [(90, 5), (180, 6), (270, 8), (360, 10)]
trg = [{"id": "intro", "when": C("always"), "do": [
    dialog(("Éclaireur", "Mbarga ! Des guerriers d’Amougou marchent sur nous. Ils viendront par vagues."),
           ("Mbarga", "Tenez bon. Bâtissez des casernes et gardez vos lanciers près du centre-ville.")),
    hint("Survivez 7 minutes. Entraînez des lanciers à la caserne et gardez-les groupés autour du centre-ville.")]}]
for i, (t, n) in enumerate(waves):
    trg.append({"id": "wave%d" % (i + 1), "when": C("tick", seconds=t), "do": [
        spawn(1, "spearman", n, P("p1"), tag="raiders", to=P("p0", -3, -3)),
        dialog(("Éclaireur", "Vague %d en approche !" % (i + 1)))]})
trg.append({"id": "half", "when": C("tick", seconds=210),
            "do": [dialog(("Mbarga", "Encore trois minutes. Ne lâchez rien !"))]})
missions.append({
    "id": "m2", "title": "La première vague", "subtitle": "Défense", "requires": ["m1"],
    "kingdom": [24, 52],
    "briefing": ["Amougou, seigneur des plaines, convoite notre fleuve. Ses guerriers déferleront par vagues successives.",
                 "Résistez sept minutes : vous recevrez des renforts de l’Ancêtre."],
    "map": {"size": 64, "seed": 23, "style": 0},
    "players": [{"clan": "fleuve", "ai": -1, "age": 0,
                 "resources": {"food": 500, "wood": 600, "stone": 100}, "locked": locked_for("m2")},
                {"clan": "forgerons", "ai": -1, "base": False, "age": 0}],
    "placements": [{"owner": 0, "unit": "spearman", "count": 4, "at": P("p0", 5, 5), "tag": "guards"}],
    "objectives": [
        {"id": "survive", "label": "Survivre 7 minutes", "done": C("tick", seconds=420)},
        {"id": "kills", "label": "Éliminer 25 guerriers", "optional": True, "done": C("killed", owner=0, count=25)},
    ],
    "triggers": trg,
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 460, "maxLosses": 12},
    "rewards": rewards["m2"],
})

# ───── M3 : villages à protéger ─────
trg = [{"id": "intro", "when": C("always"), "do": [
    dialog(("Mama Sanaga", "Deux hameaux du fleuve dépendent de vous, Mbarga. Les corbeaux les guettent."),
           ("Mbarga", "Aucun hameau ne tombera. Gardez au moins trois huttes debout.")),
    hint("Les hameaux alliés sont à protéger des pillards : au moins trois huttes sur quatre doivent survivre.")]}]
raids = [(70, 4, P("p0", 14, -6)), (150, 5, P("p0", -12, 10)), (230, 6, P("p0", 14, -6))]
for i, (t, n, at) in enumerate(raids):
    trg.append({"id": "raid%d" % (i + 1), "when": C("tick", seconds=t), "do": [
        spawn(1, "iron_warrior" if i == 2 else "spearman", n, P("p1"), tag="raiders", to=at),
        dialog(("Éclaireur", "Des pillards approchent d’un hameau ! (raid %d)" % (i + 1)))]})
trg.append({"id": "over", "when": C("all", conds=[C("tick", seconds=300), C("no_units", owner=1, tag="raiders")]),
            "do": [{"kind": "flag", "name": "raids_over"},
                   dialog(("Mama Sanaga", "Les corbeaux se retirent. Le fleuve respire."))]})
missions.append({
    "id": "m3", "title": "Les villages du fleuve", "subtitle": "Protection", "requires": ["m2"],
    "kingdom": [38, 40],
    "briefing": ["Les hameaux du fleuve, alliés de longue date, n’ont pour toute défense que quelques lances.",
                 "Envoyez vos soldats les protéger : perdre plus d’une hutte serait un désastre."],
    "map": {"size": 64, "seed": 37, "style": 4},
    "players": [{"clan": "fleuve", "ai": -1, "age": 1,
                 "resources": {"food": 600, "wood": 700, "stone": 300, "gold": 200}, "locked": locked_for("m3")},
                {"clan": "corbeaux", "ai": -1, "base": False, "team": 1},
                {"clan": "pecheurs", "ai": -1, "base": False, "team": 0}],
    "placements": [
        {"owner": 2, "building": "hut", "count": 2, "at": P("p0", 14, -6), "tag": "village"},
        {"owner": 2, "building": "hut", "count": 2, "at": P("p0", -12, 10), "tag": "village"},
        {"owner": 0, "unit": "spearman", "count": 6, "at": P("p0", 6, 0), "tag": "guards"}],
    "objectives": [
        {"id": "protect", "label": "Repousser les raids en gardant 3 huttes au moins",
         "done": C("flag", name="raids_over"),
         "fail": C("not", cond=C("tag_alive", tag="village", atLeast=3))},
        {"id": "all", "label": "Ne perdre aucune hutte", "optional": True,
         "done": C("all", conds=[C("flag", name="raids_over"), C("tag_alive", tag="village", atLeast=4)])},
    ],
    "triggers": trg,
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 420, "maxLosses": 10},
    "rewards": rewards["m3"],
})

# ───── M4 : mines et embuscade ─────
missions.append({
    "id": "m4", "title": "Les mines d’Ékom", "subtitle": "Économie et embuscade", "requires": ["m3"],
    "kingdom": [52, 58],
    "briefing": ["Pour forger des armes, le royaume a besoin de fer et d’or. Les mines d’Ékom sont riches mais les routes ne sont pas sûres.",
                 "Bâtissez un camp minier, extrayez le métal… et méfiez-vous des embuscades."],
    "map": {"size": 80, "seed": 41, "style": 3},
    "players": [{"clan": "fleuve", "ai": -1, "age": 1,
                 "resources": {"food": 500, "wood": 600, "stone": 200}, "locked": locked_for("m4")},
                {"clan": "corbeaux", "ai": -1, "base": False, "team": 1}],
    "placements": [{"owner": 0, "unit": "spearman", "count": 5, "at": P("p0", 5, 4), "tag": "guards"}],
    "objectives": [
        {"id": "camp", "label": "Bâtir un camp minier", "done": C("build", building="mining_camp", count=1)},
        {"id": "iron", "label": "Extraire 300 de fer", "done": C("gather", res="iron", amount=300)},
        {"id": "gold", "label": "Extraire 200 d’or", "done": C("gather", res="gold", amount=200)},
        {"id": "ambush", "label": "Repousser l’embuscade", "hidden": True,
         "done": C("no_units", owner=1, tag="ambush")},
    ],
    "triggers": [
        {"id": "intro", "when": C("always"), "do": [
            dialog(("Mbarga", "Le fer d’Ékom fera nos lames. Que les mineurs se mettent au travail."),
                   ("Éclaireur", "Des traces de pillards sont visibles près des galeries…")),
            hint("Construisez un camp minier près d’une mine, puis envoyez-y des villageois.")]},
        {"id": "ambush", "when": C("gather", res="iron", amount=120), "do": [
            spawn(1, "spearman", 5, P("p0", 12, 12), tag="ambush", to=P("p0", 2, 2)),
            spawn(1, "spearman", 3, P("p0", -12, 12), tag="ambush", to=P("p0", 2, 2)),
            obj_show("ambush"),
            dialog(("Éclaireur", "Une embuscade ! Ils sortent des galeries !"))]},
    ],
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 780, "maxLosses": 6},
    "rewards": rewards["m4"],
})

# ───── M5 : caravane ─────
missions.append({
    "id": "m5", "title": "La caravane du marché", "subtitle": "Escorte", "requires": ["m4"],
    "kingdom": [66, 40],
    "briefing": ["Une caravane chargée de sel doit rejoindre le comptoir de l’autre côté de la plaine.",
                 "Escortez-la : les bandits du corbeau savent qu’elle passe."],
    "map": {"size": 80, "seed": 53, "style": 2},
    "players": [{"clan": "fleuve", "ai": -1, "age": 1,
                 "resources": {"food": 500, "wood": 500, "iron": 150, "gold": 100}, "locked": locked_for("m5")},
                {"clan": "corbeaux", "ai": -1, "base": False, "team": 1}],
    "placements": [
        {"owner": 0, "unit": "villager", "count": 1, "at": P("p0", 5, 5), "tag": "caravan"},
        {"owner": 0, "unit": "spearman", "count": 4, "at": P("p0", 6, 5), "tag": "escort"},
        {"owner": 0, "unit": "spearman", "count": 3, "at": P("p0", 5, 7), "tag": "escort"}],
    "objectives": [
        {"id": "arrive", "label": "Mener la caravane au comptoir",
         "done": C("unit_in_area", owner=0, tag="caravan", at=P("p1", 4, 4), radius=6),
         "fail": C("not", cond=C("tag_alive", tag="caravan", atLeast=1))},
        {"id": "bandits", "label": "Éliminer 8 bandits", "optional": True, "done": C("killed", owner=0, count=8)},
    ],
    "triggers": [
        {"id": "intro", "when": C("always"), "do": [
            dialog(("Mama Sanaga", "La caravane est lente et fragile. Gardez-la au milieu de vos lances."),
                   ("Mbarga", "Elle ne s’arrêtera pas avant le comptoir.")),
            hint("Sélectionnez la caravane (villageois), clic droit à destination, escorte groupée autour d’elle.")]},
        {"id": "ambush1", "when": C("unit_in_area", owner=0, tag="caravan", at=P("center", 0, 0), radius=14), "do": [
            spawn(1, "spearman", 5, P("center", -10, 6), tag="bandits", to=P("center", 0, 0)),
            dialog(("Éclaireur", "Des bandits au milieu de la plaine !"))]},
        {"id": "ambush2", "when": C("unit_in_area", owner=0, tag="caravan", at=P("p1", 0, 0), radius=22), "do": [
            spawn(1, "archer", 4, P("p1", 8, -4), tag="bandits", to=P("p1", 4, 4)),
            spawn(1, "spearman", 4, P("p1", -6, 6), tag="bandits", to=P("p1", 4, 4)),
            dialog(("Éclaireur", "Le comptoir est en vue, mais des archers nous attendent !"))]},
    ],
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 600, "maxLosses": 3},
    "rewards": rewards["m5"],
})

# ───── M6 : duel d'armées ─────
missions.append({
    "id": "m6", "title": "Le duel des armées", "subtitle": "Bataille", "requires": ["m5"],
    "kingdom": [80, 52],
    "briefing": ["Le seigneur Amougou a rassemblé son armée et marche sur le fleuve. L’heure du duel est venue.",
                 "Deux armées, deux villages : brisez la sienne avant qu’elle ne brise la vôtre."],
    "map": {"size": 80, "seed": 61, "style": 1},
    "players": [{"clan": "fleuve", "ai": -1, "age": 2,
                 "resources": {"food": 800, "wood": 800, "stone": 300, "iron": 400, "gold": 300},
                 "locked": locked_for("m6")},
                {"clan": "forgerons", "ai": 1, "age": 2, "team": 1,
                 "resources": {"food": 600, "wood": 600, "stone": 200, "iron": 300, "gold": 100}}],
    "placements": [
        {"owner": 0, "unit": "spearman", "count": 8, "at": P("p0", 6, 6), "tag": "mine"},
        {"owner": 0, "unit": "archer", "count": 6, "at": P("p0", 4, 8), "tag": "mine"},
        {"owner": 0, "unit": "iron_warrior", "count": 4, "at": P("p0", 8, 4), "tag": "mine"},
        {"owner": 1, "unit": "iron_warrior", "count": 8, "at": P("p1", -6, -6), "tag": "enemy_army"},
        {"owner": 1, "unit": "spearman", "count": 6, "at": P("p1", -4, -8), "tag": "enemy_army"}],
    "objectives": [
        {"id": "army", "label": "Anéantir l’armée de départ ennemie", "done": C("no_units", owner=1, tag="enemy_army")},
        {"id": "tc", "label": "Détruire le centre-ville d’Amougou", "done": C("no_buildings", owner=1, building="town_center")},
    ],
    "triggers": [
        {"id": "intro", "when": C("always"), "do": [
            dialog(("Mbarga", "Voici l’armée d’Amougou. Ne la laissez pas se regrouper."),
                   ("Éclaireur", "Il reconstruit déjà des casernes. Il faut frapper vite.")),
            hint("Regroupez vos troupes (glisser pour sélectionner), utilisez les pouvoirs (Z X C V) et le tambour (F5–F8).")]},
    ],
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "stars": {"seconds": 1200, "maxLosses": 14},
    "rewards": rewards["m6"],
})

# ───── M7 : siège et boss ─────
missions.append({
    "id": "m7", "title": "Le siège de Mbeng", "subtitle": "Siège et boss", "requires": ["m6"],
    "kingdom": [92, 34],
    "briefing": ["Kaba le Corbeau s’est retranché dans la forteresse de Mbeng, entouré de tours et de ses fidèles.",
                 "Les catapultes du fleuve brisent les murs ; Kaba, lui, ne tombera qu’au prix du sang."],
    "map": {"size": 96, "seed": 71, "style": 3},
    "players": [{"clan": "fleuve", "ai": -1, "age": 2,
                 "resources": {"food": 1500, "wood": 1500, "stone": 800, "iron": 1000, "gold": 600}},
                {"clan": "corbeaux", "ai": 1, "age": 2, "team": 1,
                 "resources": {"food": 600, "wood": 600, "stone": 600, "iron": 300, "gold": 200}},
                {"clan": "pecheurs", "ai": -1, "base": False, "team": 0}],
    "placements": [
        {"owner": 0, "unit": "spearman", "count": 8, "at": P("p0", 6, 6), "tag": "mine"},
        {"owner": 0, "unit": "archer", "count": 6, "at": P("p0", 4, 8), "tag": "mine"},
        {"owner": 0, "unit": "catapult", "count": 3, "at": P("p0", 8, 3), "tag": "mine"},
        {"owner": 1, "building": "fortress", "at": P("p1", -8, -8), "tag": "fortress"},
        {"owner": 1, "building": "tower", "count": 3, "at": P("p1", -14, -4), "tag": "towers"},
        {"owner": 1, "unit": "iron_warrior", "count": 6, "at": P("p1", -6, -10), "tag": "guards"},
        {"owner": 2, "building": "hut", "at": P("p0", 10, -12), "tag": "elder"}],
    "objectives": [
        {"id": "fortress", "label": "Détruire la forteresse de Mbeng",
         "done": C("no_buildings", owner=1, building="fortress")},
        {"id": "boss", "label": "Vaincre Kaba le Corbeau", "hidden": True,
         "done": C("no_units", owner=1, tag="boss")},
        {"id": "towers", "label": "Abattre les trois tours", "optional": True,
         "done": C("no_buildings", owner=1, building="tower")},
    ],
    "triggers": [
        {"id": "intro", "when": C("always"), "do": [
            dialog(("Mbarga", "Mbeng. Les murs sont hauts, mais les nôtres sont plus têtus."),
                   ("Mama Sanaga", "Les catapultes d’abord, Mbarga. Les lances ensuite.")),
            hint("Les catapultes (Atelier de siège) détruisent les bâtiments. Gardez-les protégées par vos lanciers.")]},
        {"id": "boss", "when": C("tick", seconds=300), "do": [
            spawn(1, "hero_kaba", 1, P("p1", -8, -6), tag="boss", scale=False),
            obj_show("boss"),
            dialog(("Kaba", "Vous osez frapper à ma porte ? Les corbeaux se nourriront de votre fleuve !"),
                   ("Mbarga", "Qu’il vienne. Aujourd’hui, le Corbeau chute."))]},
    ],
    "lose": [C("no_buildings", owner=0, building="town_center")],
    "endings": [
        {"id": "glorious", "when": C("objective", id="towers"),
         "text": "Les tours de Mbeng en ruine, le doyen est sauvé et le royaume entier acclame Mbarga : l’ère du Fleuve commence."},
        {"id": "bitter",
         "text": "Kaba est tombé, mais Mbeng brûle encore. Le royaume est sauvé, au prix de lourds sacrifices."}],
    "stars": {"seconds": 1500, "maxLosses": 20},
    "rewards": rewards["m7"],
})

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "campaign", "campaign.json")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump({"missions": missions}, f, ensure_ascii=False, indent=1)
print(len(missions), "missions écrites dans", os.path.normpath(out))
