class_name Metal
extends RefCounted
## Static definitions for the allomantic metals.
##
## This is the single source of truth for metal ids, names, colours and
## burn rates. Every system (HUD, allomancer, AI, pickups) refers to metals by
## the `Metal.Type` enum.

enum Type {
	STEEL,   ## External physical pusher: Push on nearby metals.
	IRON,    ## External physical puller: Pull on nearby metals.
	PEWTER,  ## Internal physical pusher: strength, speed, balance, durability.
	TIN,     ## Internal physical puller: enhanced senses, see through the mists.
	ZINC,    ## External mental puller: Riot (inflame) emotions.
	BRASS,   ## External mental pusher: Soothe (dampen) emotions.
	COPPER,  ## Internal mental puller: Coppercloud, hides allomantic pulses.
	BRONZE,  ## Internal mental pusher: Seeker, senses allomantic pulses.
	ATIUM,   ## God metal: see a few moments into the future (enemy shadows).
	DURALUMIN, ## Enhancement: burns away all other burning metals in one huge flare.
}

const COUNT := 10

## Display name for each metal.
const NAMES := {
	Type.STEEL: "Steel",
	Type.IRON: "Iron",
	Type.PEWTER: "Pewter",
	Type.TIN: "Tin",
	Type.ZINC: "Zinc",
	Type.BRASS: "Brass",
	Type.COPPER: "Copper",
	Type.BRONZE: "Bronze",
	Type.ATIUM: "Atium",
	Type.DURALUMIN: "Duralumin",
}

## UI / VFX colour for each metal.
const COLORS := {
	Type.STEEL: Color(0.45, 0.65, 1.0),
	Type.IRON: Color(0.75, 0.45, 0.35),
	Type.PEWTER: Color(0.62, 0.62, 0.66),
	Type.TIN: Color(0.85, 0.87, 0.92),
	Type.ZINC: Color(0.55, 0.75, 0.70),
	Type.BRASS: Color(0.90, 0.72, 0.30),
	Type.COPPER: Color(0.85, 0.48, 0.25),
	Type.BRONZE: Color(0.72, 0.52, 0.28),
	Type.ATIUM: Color(0.95, 0.95, 0.80),
	Type.DURALUMIN: Color(0.80, 0.85, 0.95),
}

## Reserve units burned per second at normal burn. Flaring multiplies this.
const BURN_RATE := {
	Type.STEEL: 1.0,
	Type.IRON: 1.0,
	Type.PEWTER: 1.2,
	Type.TIN: 0.35,
	Type.ZINC: 0.8,
	Type.BRASS: 0.8,
	Type.COPPER: 0.4,
	Type.BRONZE: 0.3,
	Type.ATIUM: 10.0,
	Type.DURALUMIN: 100.0,
}

## Maximum reserve units a single allomancer can hold of each metal.
const MAX_RESERVE := 100.0

## Multiplier applied to burn rate and effect strength while flaring.
const FLARE_BURN_MULT := 2.5
const FLARE_EFFECT_MULT := 1.6

## Metals an allomancer can target at external objects (Push/Pull lines).
const LINE_METALS := [Type.STEEL, Type.IRON]


static func name_of(t: Type) -> String:
	return NAMES.get(t, "?")


static func color_of(t: Type) -> Color:
	return COLORS.get(t, Color.WHITE)
