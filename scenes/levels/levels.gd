class_name Levels
extends RefCounted

## The levels of the game, world by world (see DESIGN.md): each world opens
## with runs through its land, on which the hero meets its opponents one by
## one, and ends with its boss. The player plays them in order: a level opens once the one before
## it is finished (see Profile), and he may play any open level again.
##
## A run is a rhythm level (see Run): a song with its chart of sections of
## obstacles (each by its moves, see Chart), and the opponents whom the hero
## meets on the road: he crashes into each, and they box freely (see Brawl)
## until one goes down. The boss of a world waits at its end, in a level of
## his own (see Fight). Each world has its hero (see RiggedFigure.HEROES) and
## its surroundings (see Scenery).

## The worlds, in order: their title, their hero, and their look.
const WORLDS := [
    {"id": "ice_age", "title": "ICE AGE", "hero": "prehistoric"},
    {"id": "switzerland", "title": "SWITZERLAND", "hero": "classic"},
    {"id": "winter", "title": "WINTER", "hero": "samichlaus"},
]

## The opponents whom the hero meets on the road of a run (four a run, eight
## before the boss of a world, each in random colors of his own, see
## Looks.recolor), and the bosses (see Brawl): his look (see Looks), his
## title, where his guard opens for the player's punches ("straight",
## "hook", "uppercut"; see Opponent.open_for), the attacks he throws
## ("jab", dodged with the cover; "hook", from either side, dodged with a
## slip; see Opponent.perform), whether he is a boss
## (faster, tougher, and throwing two in a row now and then), and his lines:
## while he fights, when the player's punch hits his guard, and when his
## attack lands. A fight has no jumps and no ducks: they are the runs'.
const OPPONENTS := {
    "sabre_tiger":
    {
        "look": "sabre_tiger",
        "title": "THE SABRE-TOOTH TIGER",
        "openings": ["hook"],
        "attacks": ["jab", "hook"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Rrrrrr!",
                "Snack time!",
                "Nice and tender!",
                "These teeth cost a fortune!",
                "Here, kitty kitty? I am the kitty!",
            ],
            "blocked": ["Ha, whiskers!", "Purrfect miss!", "Nine lives, monkey!"],
            "landed": ["Scratched!", "Clawed!", "Mine!"],
        },
    },
    "mammoth":
    {
        "look": "mammoth",
        "title": "THE MAMMOTH",
        "openings": ["straight", "hook"],
        "attacks": ["jab"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "TOOOROOOO!",
                "This valley is mine since the Ice Age!",
                "Mind my feet, little monkey!",
                "We were here first!",
                "I never forget. Never!",
            ],
            "blocked": ["Too slow, monkey!", "Ha! Thick skin!", "Was that a fly?"],
            "landed": ["Stomped!", "Trunk mail!", "Ice cold!"],
        },
    },
    "cave_bear":
    {
        "look": "cave_bear",
        "title": "THE CAVE BEAR",
        "openings": ["straight", "hook", "uppercut"],
        "attacks": ["jab", "hook"],
        "boss": true,
        "lines":
        {
            "taunt":
            [
                "This is MY cave!",
                "Hibernation is over!",
                "I eat mammoths for breakfast!",
                "Grrrrooaaar!",
                "Go back to your tree!",
            ],
            "blocked": ["Grrr, missed!", "Bear-ly touched me!", "Ha!"],
            "landed": ["Bear hug!", "Pawed!", "Hibernate, monkey!"],
        },
    },
    "bunzli":
    {
        "look": "bunzli",
        "title": "THE BÜNZLI",
        "openings": ["straight", "hook"],
        "attacks": ["jab"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "It is MY laundry day!",
                "Quiet hours after ten!",
                "You did not separate your recycling!",
                "Rules are rules!",
                "I am calling the Hauswart!",
            ],
            "blocked": ["Not in this order!", "Form 27b, please!", "Tsk tsk tsk."],
            "landed": ["Fined!", "Noted in the house book!", "Order must be!"],
        },
    },
    "nationalist":
    {
        "look": "nationalist",
        "title": "THE NATIONALIST",
        "openings": ["hook", "uppercut"],
        "attacks": ["hook"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Foreign punches are banned!",
                "Even my cheese has a passport!",
                "That move is not Swiss enough!",
                "My grandfather's grandfather was also angry!",
                "Neutral? Never heard of it!",
            ],
            "blocked": ["A true Swiss never misses!", "Ha! Border closed!", "Too foreign!"],
            "landed": ["Back to the queue!", "Rejected!", "Stamped!"],
        },
    },
    "scientist":
    {
        "look": "scientist",
        "title": "THE ROCHARTIS SCIENTIST",
        "openings": ["uppercut", "straight"],
        "attacks": ["jab", "hook"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Time for your check-up!",
                "This won't hurt. Much.",
                "Side effects may include bruising.",
                "Take your medicine!",
                "The trial is not over!",
            ],
            "blocked": ["Missed me!", "Ha! Placebo punch!", "Too slow!"],
            "landed": ["Billed to your insurance!", "Side effects!", "Next patient!"],
        },
    },
    "ceo":
    {
        "look": "ceo",
        "title": "THE ROCHARTIS CEO",
        "openings": ["straight", "hook", "uppercut"],
        "attacks": ["jab", "hook"],
        "boss": true,
        "lines":
        {
            "taunt":
            [
                "Profits up, you down!",
                "Shareholders first!",
                "Your health is our business!",
                "I have a golden parachute!",
                "Bonus time!",
            ],
            "blocked": ["Too expensive for you!", "Ha! Patented!", "Not covered!"],
            "landed": ["That will be 49.90!", "Price increase!", "Dividend!"],
        },
    },
    "bunzli_shovel":
    {
        "look": "bunzli_shovel",
        "title": "THE SNOW-SHOVEL BÜNZLI",
        "openings": ["straight", "uppercut"],
        "attacks": ["jab"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Who shovels at 7:01?! I shovel at 7:00!",
                "Your path is two centimeters too wide!",
                "Salt is for the road, not for you!",
                "Snow belongs on YOUR side!",
                "I measured the snowfall. It was too much.",
            ],
            "blocked": ["Not on my path!", "Swept away!", "Too slippery for you?"],
            "landed": ["Shovelled!", "Cleared!", "Winter duty!"],
        },
    },
    "bunzli_hedge":
    {
        "look": "bunzli_hedge",
        "title": "THE HEDGE BÜNZLI",
        "openings": ["hook"],
        "attacks": ["jab", "hook"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Your hedge is two centimeters too high!",
                "I have it measured!",
                "My garden gnome saw everything!",
                "Leaves on MY lawn?!",
                "The municipality will hear of this!",
            ],
            "blocked": ["Trimmed!", "Not by the rules!", "Out of line!"],
            "landed": ["Pruned!", "Cut to size!", "1.20 meters, no more!"],
        },
    },
    "white_sheep":
    {
        "look": "white_sheep",
        "title": "THE WHITE SHEEP",
        "openings": ["uppercut", "hook"],
        "attacks": ["hook"],
        "boss": false,
        "lines":
        {
            "taunt":
            [
                "Baaa! Stay in line!",
                "We are all the same, baaa!",
                "Conform! Baaa!",
                "Our meadow, our rules! Baaa!",
                "Baaa! The herd decides!",
            ],
            "blocked": ["Baaa-d luck!", "Ha! Woolly miss!", "Baaa!"],
            "landed": ["Herd mentality!", "Baaa-m!", "Fleeced!"],
        },
    },
    "norgeli":
    {
        "look": "norgeli",
        "title": "THE NÖRGELI",
        "openings": ["straight", "hook", "uppercut"],
        "attacks": ["jab", "hook"],
        "boss": true,
        "lines":
        {
            "taunt":
            [
                "Everything was better before!",
                "Your stance is wrong!",
                "Too loud! Too fast! Too young!",
                "Who taught you that?",
                "In my day we boxed uphill!",
            ],
            "blocked": ["Typical!", "I knew it!", "Tsk. Young people."],
            "landed": ["I told you so!", "Serves you right!", "Complaint filed!"],
        },
    },
}

## The levels, in the order of play. Each has: its id, its world, its kind
## ("run": a run through the land, with the opponents whom the hero meets on
## the road, in order; "boss": the boss of the world, in a level of his own),
## its title, the opponents (see OPPONENTS), the tempo, the chord progression
## and the key of its song (see BeatSynth), its sections (the obstacles of a
## run, see Chart), its surroundings (see Scenery), and the boosters on the
## road of a run (see Boosters: each of its own look, by the land), and its
## barriers (see Barriers: the one in the middle of the run, and the one at
## its end).
const ALL_LEVELS := [
    {
        "id": "jungle",
        "scenery": "jungle",
        "world": "ice_age",
        "kind": "run",
        "title": "THROUGH THE JUNGLE",
        "opponents": ["sabre_tiger", "mammoth", "sabre_tiger", "mammoth"],
        "bpm": 90.0,
        "progression": 3,
        "transpose": 0,
        "sections": ["steer", "jump", "duck", "steer,jump", "steer,jump,duck"],
        "boosters": ["banana", "berries", "steak"],
        "barriers": ["palisade", "stone_wall"],
    },
    {
        "id": "glacier",
        "scenery": "ice",
        "world": "ice_age",
        "kind": "run",
        "title": "OVER THE GLACIER",
        "opponents": ["mammoth", "sabre_tiger", "mammoth", "sabre_tiger"],
        "bpm": 90.0,
        "progression": 0,
        "transpose": 2,
        "sections": ["steer", "jump", "duck", "steer,duck", "steer,jump,duck"],
        "boosters": ["fish", "fur", "steak"],
        "barriers": ["ice_wall", "palisade"],
    },
    {
        "id": "cave_bear",
        "scenery": "cave",
        "world": "ice_age",
        "kind": "boss",
        "title": "THE CAVE BEAR",
        "opponents": ["cave_bear"],
        "bpm": 94.0,
        "progression": 0,
        "transpose": -5,
        "sections": ["straight", "hook", "uppercut", "slip", "cover"],
    },
    {
        "id": "street",
        "scenery": "city",
        "world": "switzerland",
        "kind": "run",
        "title": "THROUGH THE STREETS",
        "opponents": ["bunzli", "nationalist", "bunzli", "nationalist"],
        "bpm": 92.0,
        "progression": 1,
        "transpose": 2,
        "sections": ["steer", "jump", "duck", "steer,jump", "steer,jump,duck"],
        "boosters": ["espresso", "apple", "chocolate"],
        "barriers": ["laundry", "car"],
    },
    {
        "id": "campus",
        "scenery": "city",
        "world": "switzerland",
        "kind": "run",
        "title": "TO THE ROCHARTIS CAMPUS",
        "opponents": ["scientist", "bunzli", "nationalist", "scientist"],
        "bpm": 96.0,
        "progression": 3,
        "transpose": 0,
        "sections": ["steer", "duck", "jump", "steer,duck", "steer,jump,duck"],
        "boosters": ["espresso", "helmet", "chocolate"],
        "barriers": ["crates", "gate"],
    },
    {
        "id": "ceo",
        "scenery": "lab",
        "world": "switzerland",
        "kind": "boss",
        "title": "THE ROCHARTIS CEO",
        "opponents": ["ceo"],
        "bpm": 100.0,
        "progression": 2,
        "transpose": 3,
        "sections": ["straight", "hook", "uppercut", "slip", "cover"],
    },
    {
        "id": "garden",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "run",
        "title": "THROUGH THE GARDENS",
        "opponents": ["bunzli_shovel", "bunzli_hedge", "bunzli_shovel", "bunzli_hedge"],
        "bpm": 90.0,
        "progression": 1,
        "transpose": -3,
        "sections": ["steer", "jump", "duck", "steer,duck", "steer,jump,duck"],
        "boosters": ["grittibaenz", "mandarin", "scarf"],
        "barriers": ["hedge", "car"],
    },
    {
        "id": "meadow",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "run",
        "title": "PAST THE MEADOW",
        "opponents": ["white_sheep", "bunzli_hedge", "bunzli_shovel", "white_sheep"],
        "bpm": 96.0,
        "progression": 3,
        "transpose": 0,
        "sections": ["steer", "duck", "jump", "steer,jump", "steer,jump,duck"],
        "boosters": ["mandarin", "grittibaenz", "peanuts"],
        "barriers": ["hedge", "poster"],
    },
    {
        "id": "norgeli",
        "scenery": "suburbs",
        "world": "winter",
        "kind": "boss",
        "title": "THE NÖRGELI",
        "opponents": ["norgeli"],
        "bpm": 100.0,
        "progression": 2,
        "transpose": -2,
        "sections": ["straight", "hook", "uppercut", "slip", "cover"],
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
    elif moves.size() >= 5:
        title = "EVERYTHING"
    else:
        var names := PackedStringArray()
        for move in moves:
            names.append(MOVE_TITLES[move][1])
        title = " + ".join(names)
    if not run and section == sections.size() - 1:
        title = "FINAL ROUND: " + title
    return title


## The opponent of the id (see OPPONENTS).
static func opponent(id: String) -> Dictionary:
    return OPPONENTS.get(id, OPPONENTS["scientist"])


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
