# UI Overlay Art Spec

## Scope

Read this document only when the task directly involves one or more of the following:

- battle or map `overlay` visuals;
- terrain/board decorative textures that interact with overlay readability;
- tile/overlay shader work;
- visual effect asset generation for fire, fog, smoke, water, grass, bush, or similar board-surface effects;
- board-layer draw order, occlusion, or readability problems.

Do not load this document for unrelated rules, combat logic, economy, localization, or general scripting tasks.

## Layer Semantics

Keep these concepts separate:

- `decoration`: pure art dressing, no gameplay meaning;
- `overlay`: gameplay-bearing visual layer attached to a cell or area, may animate, react, and combine with shaders;
- `tile`: base ground state that defines movement, terrain semantics, and board structure.

Never solve an overlay request by turning it into a tile-looking texture unless the task explicitly asks for tile art.

## Primary Goals

Overlay visuals must:

- communicate gameplay state before decoration;
- stay readable underneath battle UI and unit sprites;
- avoid stealing focus from units, HP bars, intent badges, and actionable highlights;
- feel like part of one restrained visual language rather than separate VFX packs.

## Occlusion Rules

Overlay assets must be designed with unit overlap in mind.

- Do not assume a unit should either fully cover an overlay or be fully covered by it.
- Prefer a two-pass overlay model for vertical assets such as grass, reeds, flames, and foreground fog:
  - `back pass`: behind units, for roots, base haze, burn marks, low flame bed, back blades.
  - `front pass`: in front of units but only for low-height foreground coverage such as grass tips at ankles, shallow fog strands, or low flame tongues.
- Front-pass overlays must not cover the unit torso, face, intent badge, HP bar, or status icons.
- When an overlay visually surrounds a unit, the unit body should remain readable at a glance.
- If the effect cannot tolerate split occlusion, redesign the asset before increasing opacity.

## Color And Saturation

Board overlays should be quieter than character art and HUD.

- Default toward low-to-mid saturation.
- Prefer dusty, muted, gray-shifted palettes over neon or candy colors.
- Use value contrast and silhouette more than raw saturation to differentiate overlay types.
- Reserve the highest visual heat for truly dangerous states, and even then keep bright areas compact.

Recommended palette direction:

- grass / bush overlays: sage, dusty olive, gray-green, charcoal-brown linework;
- poison fog: sickly muted green or gray-cyan, airy and translucent;
- toxic smoke: dirtier, heavier, more polluted than poison fog; may shift toward gray-violet, swamp-olive, or bruised brown-green;
- poison puddle / toxic water: shallow, contaminated liquid read; muted teal-olive or gray-green; low profile and broken edges;
- fire: ember red, burnt orange, warm amber, with small controlled yellow-hot accents only at the hottest core;
- water or conductive shimmer: cool cyan-blue, cleaner than poison effects, still subordinate to units.

## Shape Language

Overlay type should be legible from silhouette first.

- grass: sparse vertical blades, visible negative space, growth-friendly clustering;
- bush / dense grass: denser and taller than grass, but still not a filled hedge unless explicitly requested;
- poison fog: drifting volume, soft body, broken edge, not a solid blob;
- toxic smoke: thicker and dirtier than poison fog, with slower heavier massing;
- puddle / polluted water: low flat body, liquid silhouette, broken rim, not a sludge mound;
- fire: clear tongues, core, and burn base; avoid becoming an orange cloud.

Avoid:

- full-tile carpet fills unless the effect is intentionally a blanket surface;
- lush JRPG foliage when the request is for tactical overlay readability;
- large glowing masses that flatten the board;
- a single centered effect body that reads like a small decorative tile placed on top of the cell;
- symmetry that makes the overlay feel stamped into the middle of each diamond;
- bright pure green poison, bright pure red danger, or oversaturated magical VFX unless explicitly required.

## Animation Strategy

Choose animation style by effect type instead of defaulting to one method.

### Good shader-first candidates

- grass sway;
- poison fog drift;
- toxic smoke pulse and crawl;
- water shimmer;
- low-intensity haze, distortion, or alpha breathing.

Use shaders when motion should feel continuous, systemic, and low-key.

### Good sprite-first or hybrid candidates

- fire tongues;
- ember flicker;
- effects that need strong silhouette recognition on a single frame.

Use sprite-first or flipbook-plus-shader when shape readability matters more than fluid noise.

### Animation restraints

- Motion must support readability, not become a screen saver.
- Overlay animation should usually be slower and less contrasty than combat-hit VFX.
- Base of a vertical asset should move less than the tip.
- Avoid synchronized motion across every cell; add phase variation when possible.

## Grass-Specific Rules

When asked for grass-like overlays:

- treat them as growable gameplay masks, not floor cover;
- keep generous negative space between blades;
- keep saturation low;
- support future shader sway by preserving clean silhouettes and separated blade groups;
- provide density tiers through height, spacing, and overlap, not just scale.

Preferred progression:

- sparse sprouts;
- medium patch;
- tall patch;
- thicket / dense cover transition.

## Fire / Fog Design Rules

When asked for fire, poison fog, or related overlays:

- first decide whether the effect is best expressed as `shader-first`, `sprite-first`, or `hybrid`;
- document that decision briefly before implementation if the task is exploratory or the visual language is being set for the project;
- bias the visible mass toward edge growth, seep, lick, drift, or low-front coverage instead of a centered tile-like blob;
- ensure each effect has a distinct role in both color and motion:
  - poison fog: lighter, more drifting, more breathable;
  - toxic smoke: heavier, dirtier, more stagnant;
  - fire: sharpest read, hottest local contrast, strongest danger cue.

## Integration Rules

When adding or revising overlay visuals:

- check draw order against units, props, outlines, badges, HP bars, and highlights;
- verify the effect both on empty cells and on occupied cells;
- test whether multiple neighboring cells create noise or still tile/read cleanly;
- avoid letting overlay art fight with selection, move-range, danger, or target highlights;
- prefer adding a dedicated renderer path or split pass over forcing a single texture to do every job.

## Delivery Expectations

For overlay art tasks, the implementation should usually include some combination of:

- asset files;
- shader files or material parameters;
- renderer integration;
- a short note explaining occlusion strategy and animation choice.

If the task is still in exploration mode, pause after the design proposal and confirm direction before mass-producing assets.

## Current Project Decisions

These choices are already established for the battle board and should be preserved unless the visual direction is deliberately revised:

- grass and bush use sparse transparent sprites, a tip-weighted GPU sway shader, per-cell phase variation, and split back/front drawing;
- poison fog and toxic smoke use continuously drifting shader-backed textures, with fog lighter and faster and smoke heavier and slower;
- fire uses a four-frame low-flame atlas plus restrained procedural drift, because changing flame silhouettes read better than noise-only deformation;
- fire intensity decreases through scale and opacity as its remaining duration falls;
- poison puddles do not draw a second filled puddle body; they add disconnected contaminated glints, ripples, and seep marks over existing water;
- asset density and transparent-edge constraints are guarded by `scripts/tests/overlay_asset_contract_test.gd`;
- shader presence and the back/unit/front ordering contract are guarded by `scripts/tests/overlay_render_contract_test.gd`.
