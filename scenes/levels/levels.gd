class_name Levels
extends RefCounted

## The levels of the game, world by world (see DESIGN.md): each world opens
## with a run through its land, then its opponents one by one, and ends with
## its boss. The player plays them in order: a level opens once the one before
## it is finished (see Profile), and he may play any open level again.
##
## A level is a rhythm level (see Fight): a song with its chart of sections
## (each by its moves, see Chart), and either an opponent to box in the ring
## ("fight") or a run through the land with obstacles ("run"). Each world has
## its hero (see RiggedFigure.HEROES) and its surroundings (see Scenery).

## The worlds, in order: their title, their hero, and their look.
const WORLDS := [
    {"id": "ice_age", "title": "ICE AGE", "hero": "prehistoric"},
    {"id": "switzerland", "title": "SWITZERLAND", "hero": "classic"},
    {"id": "winter", "title": "WINTER", "hero": "samichlaus"},
]

## The moves of a section which mixes them all.
const ALL := "straight,hook,uppercut,duck,jump,slip,cover"

## The levels, in the order of play. Each has: its id, its world, its kind
## ("run" or "fight"), its title, the opponent ("" in a run; see Opponent),
## the tempo, the chord progression and the key of its song (see BeatSynth),
## its sections (see Chart), its surroundings (see Scenery), and the lines of
## the opponent: as each section starts, when the player misses, and when the
## opponent lands.
const ALL_LEVELS := [
    {
        "id": "jungle",
        "scenery": "jungle",
        "world": "ice_age",
        "kind": "run",
        "title": "THROUGH THE JUNGLE",
        "opponent": "",
        "bpm": 90.0,
        "progression": 3,
        "transpose": 0,
        "sections": ["steer", "jump", "duck", "steer,jump,duck", "straight,steer,jump,duck"],
        "lines": {},
    },
    {
        "id": "mammoth",
        "scenery": "ice",
        "world": "ice_age",
        "kind": "fight",
        "title": "THE MAMMOTH",
        "opponent": "mammoth",
        "bpm": 86.0,
        "progression": 0,
        "transpose": -2,
        "sections": ["straight", "jump", "duck", "straight,jump,duck", "straight,jump,duck"],
        "lines":
        {
            "section":
            [
                "TOOOROOOO!",
                "This valley is mine since the Ice Age!",
                "Mind my feet, little monkey!",
                "We were here first!",
                "I never forget. Never!",
            ],
            "missed": ["Too slow, monkey!", "Ha! Thick skin!", "Was that a fly?"],
            "landed": ["Stomped!", "Trunk mail!", "Ice cold!"],
        },
    },
    {
        "id": "sabre_tiger",
        "scenery": "savannah",
        "world": "ice_age",
        "kind": "fight",
        "title": "THE SABRE-TOOTH TIGER",
        "opponent": "sabre_tiger",
        "bpm": 92.0,
        "progression": 2,
        "transpose": 0,
        "sections": ["hook", "slip", "cover", "hook,slip,cover", "straight,hook,slip,cover"],
        "lines":
        {
            "section":
            [
                "Rrrrrr!",
                "Snack time!",
                "Nice and tender!",
                "These teeth cost a fortune!",
                "Here, kitty kitty? I am the kitty!",
            ],
            "missed": ["Ha, whiskers!", "Purrfect miss!", "Nine lives, monkey!"],
            "landed": ["Scratched!", "Clawed!", "Mine!"],
        },
    },
    {
        "id": "cave",
        "scenery": "cave",
        "world": "ice_age",
        "kind": "run",
        "title": "THROUGH THE CAVE",
        "opponent": "",
        "bpm": 92.0,
        "progression": 2,
        "transpose": -3,
        "sections":
        ["steer", "duck", "jump", "steer,duck,jump", "straight,uppercut,steer,duck,jump"],
        "lines": {},
    },
    {
        "id": "cave_bear",
        "scenery": "cave",
        "world": "ice_age",
        "kind": "fight",
        "title": "THE CAVE BEAR",
        "opponent": "cave_bear",
        "bpm": 94.0,
        "progression": 0,
        "transpose": -5,
        "sections": ["uppercut", "straight,hook,uppercut", "duck,jump,slip", ALL, ALL],
        "lines":
        {
            "section":
            [
                "This is MY cave!",
                "Hibernation is over!",
                "I eat mammoths for breakfast!",
                "Grrrrooaaar!",
                "Go back to your tree!",
            ],
            "missed": ["Grrr, missed!", "Bear-ly touched me!", "Ha!"],
            "landed": ["Bear hug!", "Pawed!", "Hibernate, monkey!"],
        },
    },
    {
        "id": "street",
        "scenery": "city",
        "world": "switzerland",
        "kind": "run",
        "title": "THROUGH THE STREETS",
        "opponent": "",
        "bpm": 92.0,
        "progression": 1,
        "transpose": 2,
        "sections": ["steer", "jump", "duck", "hook,steer,jump", "straight,hook,steer,jump,duck"],
        "lines": {},
    },
    {
        "id": "bunzli",
        "scenery": "city",
        "world": "switzerland",
        "kind": "fight",
        "title": "THE BÜNZLI",
        "opponent": "bunzli",
        "bpm": 88.0,
        "progression": 3,
        "transpose": 2,
        "sections":
        ["straight", "cover", "duck", "straight,cover,duck", "straight,hook,cover,duck"],
        "lines":
        {
            "section":
            [
                "It is MY laundry day!",
                "Quiet hours after ten!",
                "You did not separate your recycling!",
                "Rules are rules!",
                "I am calling the Hauswart!",
            ],
            "missed": ["Not in this order!", "Form 27b, please!", "Tsk tsk tsk."],
            "landed": ["Fined!", "Noted in the house book!", "Order must be!"],
        },
    },
    {
        "id": "nationalist",
        "scenery": "city",
        "world": "switzerland",
        "kind": "fight",
        "title": "THE NATIONALIST",
        "opponent": "nationalist",
        "bpm": 96.0,
        "progression": 3,
        "transpose": 0,
        "sections": ["hook", "slip", "jump", "hook,slip,jump", "straight,hook,uppercut,slip,jump"],
        "lines":
        {
            "section":
            [
                "Foreign punches are banned!",
                "Even my cheese has a passport!",
                "That move is not Swiss enough!",
                "My grandfather's grandfather was also angry!",
                "Neutral? Never heard of it!",
            ],
            "missed": ["A true Swiss never misses!", "Ha! Border closed!", "Too foreign!"],
            "landed": ["Back to the queue!", "Rejected!", "Stamped!"],
        },
    },
    {
        "id": "rochartis",
        "scenery": "lab",
        "world": "switzerland",
        "kind": "fight",
        "title": "THE ROCHARTIS SCIENTIST",
        "opponent": "scientist",
        "bpm": 98.0,
        "progression": 0,
        "transpose": 0,
        "sections": ["uppercut", "duck", "cover", "uppercut,duck,cover", ALL],
        "lines":
        {
            "section":
            [
                "Time for your check-up!",
                "This won't hurt. Much.",
                "Side effects may include bruising.",
                "Take your medicine!",
                "The trial is not over!",
            ],
            "missed": ["Missed me!", "Ha! Placebo punch!", "Too slow!"],
            "landed": ["Billed to your insurance!", "Side effects!", "Next patient!"],
        },
    },
    {
        "id": "ceo",
        "scenery": "lab",
        "world": "switzerland",
        "kind": "fight",
        "title": "THE ROCHARTIS CEO",
        "opponent": "ceo",
        "bpm": 100.0,
        "progression": 2,
        "transpose": 3,
        "sections": ["straight,hook,uppercut", "duck,slip,cover", ALL, ALL, ALL],
        "lines":
        {
            "section":
            [
                "Profits up, you down!",
                "Shareholders first!",
                "Your health is our business!",
                "I have a golden parachute!",
                "Bonus time!",
            ],
            "missed": ["Too expensive for you!", "Ha! Patented!", "Not covered!"],
            "landed": ["That will be 49.90!", "Price increase!", "Dividend!"],
        },
    },
    {
        "id": "garden",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "run",
        "title": "THROUGH THE GARDENS",
        "opponent": "",
        "bpm": 90.0,
        "progression": 1,
        "transpose": -3,
        "sections":
        ["steer", "jump", "duck", "uppercut,steer,jump", "straight,uppercut,steer,jump,duck"],
        "lines": {},
    },
    {
        "id": "bunzli_shovel",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "fight",
        "title": "THE SNOW-SHOVEL BÜNZLI",
        "opponent": "bunzli_shovel",
        "bpm": 88.0,
        "progression": 1,
        "transpose": 5,
        "sections": ["straight", "duck", "jump", "straight,duck,jump", "straight,hook,duck,jump"],
        "lines":
        {
            "section":
            [
                "Who shovels at 7:01?! I shovel at 7:00!",
                "Your path is two centimeters too wide!",
                "Salt is for the road, not for you!",
                "Snow belongs on YOUR side!",
                "I measured the snowfall. It was too much.",
            ],
            "missed": ["Not on my path!", "Swept away!", "Too slippery for you?"],
            "landed": ["Shovelled!", "Cleared!", "Winter duty!"],
        },
    },
    {
        "id": "bunzli_hedge",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "fight",
        "title": "THE HEDGE BÜNZLI",
        "opponent": "bunzli_hedge",
        "bpm": 92.0,
        "progression": 3,
        "transpose": -2,
        "sections":
        ["hook", "cover", "slip", "hook,cover,slip", "straight,hook,uppercut,cover,slip"],
        "lines":
        {
            "section":
            [
                "Your hedge is two centimeters too high!",
                "I have it measured!",
                "My garden gnome saw everything!",
                "Leaves on MY lawn?!",
                "The municipality will hear of this!",
            ],
            "missed": ["Trimmed!", "Not by the rules!", "Out of line!"],
            "landed": ["Pruned!", "Cut to size!", "1.20 meters, no more!"],
        },
    },
    {
        "id": "white_sheep",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "fight",
        "title": "THE WHITE SHEEP",
        "opponent": "white_sheep",
        "bpm": 96.0,
        "progression": 3,
        "transpose": 0,
        "sections":
        ["uppercut", "slip", "jump", "uppercut,slip,jump", "straight,hook,uppercut,slip,jump"],
        "lines":
        {
            "section":
            [
                "Baaa! Stay in line!",
                "We are all the same, baaa!",
                "Conform! Baaa!",
                "Our meadow, our rules! Baaa!",
                "Baaa! The herd decides!",
            ],
            "missed": ["Baaa-d luck!", "Ha! Woolly miss!", "Baaa!"],
            "landed": ["Herd mentality!", "Baaa-m!", "Fleeced!"],
        },
    },
    {
        "id": "norgeli",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "fight",
        "title": "THE NÖRGELI",
        "opponent": "norgeli",
        "bpm": 100.0,
        "progression": 2,
        "transpose": -2,
        "sections":
        ["hook", "uppercut", "slip", "hook,uppercut,slip", "straight,hook,uppercut,slip,duck"],
        "lines":
        {
            "section":
            [
                "Everything was better before!",
                "Your stance is wrong!",
                "Too loud! Too fast! Too young!",
                "Who taught you that?",
                "In my day we boxed uphill!",
            ],
            "missed": ["Typical!", "I knew it!", "Tsk. Young people."],
            "landed": ["I told you so!", "Serves you right!", "Complaint filed!"],
        },
    },
]

## The names of the moves, for the titles of the sections (alone, and with
## others).
const MOVE_TITLES := {
    "straight": ["JABS", "JAB"],
    "hook": ["HOOKS", "HOOK"],
    "uppercut": ["UPPERCUTS", "UPPERCUT"],
    "duck": ["DUCK", "DUCK"],
    "jump": ["JUMP", "JUMP"],
    "slip": ["SLIP", "SLIP"],
    "cover": ["COVER", "COVER"],
    "steer": ["STEER LEFT AND RIGHT", "STEER"],
}


## The title of a section of a level, from its moves (the last of a fight is
## the final round).
static func section_title(sections: PackedStringArray, section: int, run: bool) -> String:
    var moves := sections[section].split(",")
    var title := ""
    if moves.size() == 1:
        title = MOVE_TITLES[moves[0]][0]
    elif moves.size() >= 7:
        title = "EVERYTHING"
    else:
        var names := PackedStringArray()
        for move in moves:
            names.append(MOVE_TITLES[move][1])
        title = " + ".join(names)
    if not run and section == sections.size() - 1:
        title = "FINAL ROUND: " + title
    return title


## The level of the id (an empty dictionary if none).
static func by_id(id: String) -> Dictionary:
    for level in ALL_LEVELS:
        if level["id"] == id:
            return level
    return {}


## The index of the level of the id (-1 if none).
static func index_of(id: String) -> int:
    for i in range(ALL_LEVELS.size()):
        if ALL_LEVELS[i]["id"] == id:
            return i
    return -1


## The world of the id.
static func world(id: String) -> Dictionary:
    for entry in WORLDS:
        if entry["id"] == id:
            return entry
    return {}


## The hero of a level (his world's).
static func hero_of(level: Dictionary) -> String:
    return world(level["world"]).get("hero", "classic")
