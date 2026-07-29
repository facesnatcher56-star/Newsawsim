# Game Content Organization

The playable sawmill is assembled in `levels/mill_prototype.tscn`.

## Folder responsibilities

- `assets/`: imported source models and their textures.
- `environment/`: world lighting, cameras, sky, and building shells.
- `levels/`: complete playable level assemblies.
- `lumber/`: logs, boards, slabs, bark, and shared lumber data.
- `machines/`: self-contained production machines and their private builders/components.
- `props/`: passive reusable scene objects.
- `shared/`: small reusable helpers used by multiple features.
- `transport/`: conveyors, decks, roller beds, transfer stations, and transport components.

## Scene boundaries

Create a separate scene when an object has independent behavior, is reused, or benefits from isolated editing. Static geometry can remain together when it is edited and loaded as one unit.

Level scenes should configure scene roots through exported properties. Avoid editing deep children of an instanced machine in the level. If an installation needs structural differences, create a named variant scene beside the base machine and instance that variant in the level.

## Current mill overrides

`mill_prototype.tscn` contains inherited child overrides from the original prototype assembly. They are intentionally preserved during the folder migration so machine placement, collision, and tuning do not change. Convert these to exported root properties or machine variants gradually when each production station is next edited.
