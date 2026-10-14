# Cozy vessel markers

Open `scenes/development/StatusMarkersPreview.tscn` and press **F6** to review the
markers with the live stall. Its labelled development controls set up sample
vessel contents; normal play uses the same markers in `TongDayScreen.tscn`.

Each cup or kettle reveals its small group of floating icons only while hovered.
The group fades in, rises slowly and gently bobs and sways together like steam.
Moving away lets it dissolve at its current height while still bobbing;
returning during the fade smoothly brings it back.
Nothing remains floating over an unattended vessel after its fade ends. The icons ignore
mouse input, so they do not intercept placing ingredients, moving vessels or
pouring. Cups keep their own markers when moved onto or off the tray.

## Reading the icons

- The little liquid vessel shows empty, low, partly filled or nearly full.
  Water is blue and brewed liquid is tea-colored. This is a rough fill cue,
  not a recipe-completion check.
- Warmth has cool, warm and hot icons; hot liquid can remain hot after leaving
  the stove. Boiling uses a bubbling icon instead of an additional hot icon.
- Steeping and oversteeping get their own cues. Off-stove steeping uses the same
  real brewing clock. The liquid marker already identifies brewed tea, and the
  stove shows its heat setting, so neither gets a duplicate floating icon.
- Only dirty or used cups get a cleanliness warning. Clean cups have no extra
  sparkle. Emptying a dirty cup does not remove its washing cue.
- Ingredient bubbles reuse the exact `ItemDef.icon` texture used by the pantry.
  Their corner numbers show the amount currently in that vessel, in that
  ingredient's gameplay units. One sugar unit means one spoonful. Infused
  teabags stay in the kettle; the tea-colored liquid cue identifies brewed tea
  in a cup. Mixed ingredients carry their proportional amounts when poured.

Whole units and simple quarter fractions are displayed directly. Other
fractions use a short approximate value; very small positive traces show
`<0.01`, never zero. Display formatting does not change the stored amounts.
New catalog ingredients follow pantry order and reuse their own icons. Missing
art gets a fallback marker and retains its quantity.

The group contains only information used to decide what to do next: fill,
liquid warmth, actual ingredients, and relevant brewing or washing warnings.
A clean empty cup needs one marker; a filled clean cup needs fill and warmth
plus its added ingredients. Every ingredient amount stays available; reducing
clutter never drops ingredients or hides a mistake in the recipe.

Cool tea is information, not a serving rejection. Customer recipe evaluation
and its review consequences belong to the customer system. These markers do not
change any brewing, ingredient, water-supply or serving rules.

## Adjust the presentation

1. Double-click `data/balance/status_markers.tres` in Godot's FileSystem panel.
2. In the Inspector, adjust **Bubble Layout**, **Owner Placement and Hover**,
   **Qualitative Bands** or **Cozy Palette**, then save the resource.
3. Run the review scene again. Check both a single vessel and all six nearby
   cups, including a small window. These settings are shared by the normal
   scene and the review scene.

**Hover Fade In Seconds** controls how quickly icons appear; **Hover Fade Out
Seconds** controls their disappearance after leaving. **Hover Lift** is the
upward reveal distance. **Hover Rise Seconds** controls how slowly the group
rises. The group holds that lift while fading, then resets out of sight.
**Hover Bob Amplitude** and **Hover Sway Amplitude** set the small vertical and
sideways motion; **Hover Bob Period** sets the duration of one bob cycle.
Set both amplitudes to zero for still icons. Motion is bounded, so the group
never drifts away from its vessel and corner amounts remain readable.
Low/high fill settings change only the icon bands. The cool threshold comes
from each vessel's existing brewing configuration; the hot threshold here is
only a presentation boundary.

For an isolated visual experiment, duplicate this `.tres` file, open
`TongDayScreen.tscn`, select **HUDLayer → RootUI → StatusBadges**, and assign
the copy to **Config**. Editing a copy alone does not activate it. Each vessel's
`StatusBadgeAnchor` sets the starting world position; the overlay keeps icons
upright and avoids nearby visible/fading groups and vessel hit areas. Hidden
groups do not occupy space. Crowded groups can
use clear space below the cup rather than crossing another cup. Ingredient artwork is changed in the
item's **Icon** field, which updates the pantry and markers together.
