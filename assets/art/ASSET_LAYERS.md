# Photoreal Chest & Scroll Layers

Layered transparent PNG assets replace the previous flat SVG placeholders.

## Chest (`assets/art/chest/`)

| File | Role |
|------|------|
| `chest_closed.png` | Primary idle closed plate |
| `chest_open.png` | Open plate with velvet + glow |
| `chest_base.png` | Body without lid |
| `chest_lid.png` | Curved lid for hinge rotation |
| `chest_interior.png` | Burgundy velvet lining |
| `chest_lock.png` | Ornate padlock |
| `chest_latch.png` | Metal latch/hasp |
| `chest_front_trim.png` | Decorative metal trim |
| `chest_inner_glow.png` | Warm magical interior light |
| `chest_contact_shadow.png` | Ground contact shadow |
| `chest_highlight.png` | Specular highlight wash |

Aliases kept for older references: `chest_glow.png`, `chest_shadow.png`, `chest_trim.png`.

## Scroll (`assets/art/scroll/`)

| File | Role |
|------|------|
| `scroll_rolled.png` | Tightly rolled scroll |
| `scroll_top_roller.png` | Top wooden/brass roller |
| `scroll_bottom_roller.png` | Bottom wooden/brass roller |
| `scroll_parchment_center.png` | Aged vellum body |
| `scroll_left_edge.png` | Curled left edge |
| `scroll_right_edge.png` | Curled right edge |
| `scroll_shadow.png` | Soft cast shadow |
| `scroll_highlight.png` | Soft highlight wash |
| `scroll_mini.png` / `scroll_mini_unread.png` | Archive icons |

Alias: `scroll_parchment.png` → center parchment.

## Open frames (lid animation)

Frame-based opening (preferred for front-facing renders):

- `chest_closed.png`
- `chest_ajar.png`
- `chest_half.png`
- `chest_open.png`
- `chest_front_lip.png` — masks rising scroll

Z-order while scroll is inside: InteriorGlow(1) < Frames(2) < RolledScroll(3) < ForegroundLip(4) < Latch/Lock(5) < Particles(10+)
