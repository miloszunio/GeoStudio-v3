# Photo-to-3D Studio (GeoStudio) v3

*Wersja polska: [README.pl.md](README.pl.md)*

**Turn photos and public geodata into ready-to-use 3D objects.**

Pick a building on the Polish [Geoportal](https://www.geoportal.gov.pl) map, get its footprint from the land-and-building register (EGiB) and the orthophoto,
build a 3D model and texture it from photos of the real building. ChatGPT cleans the photos and arranges them on one canvas (the program writes the prompt); the program cuts the canvas,
maps it onto walls and roof, lets you fix every surface, draw the roof on the gable photo and place chimneys. It exports **GLB/glTF with metadata**
and **T3D for the MaSzyna train simulator**. The whole project is saved in one **`.mgdot`** file.

> **Purpose.** GeoStudio is a tool made for creating models for the **MaSzyna** train simulator, and in particular for **MaSzyna Reloaded** (the Godot-based edition).
> It is meant for building scenery objects (houses, outbuildings, chimneys) quickly from real places. GLB/glTF export is a by-product for other uses; the T3D export is the main target.

![Textured model](docs/img/model-3d.png)

## What it does

- **Geodata → solid**: footprints and orthophoto from Geoportal.gov.pl (EPSG:2180), multi-part buildings, your own GeoJSON, place search, cache.
- **Walls and a separate roof solid**; a **roof generator** drawn on the real gable photo (gable, mansard, hips).
- **Photos → texture**: a prompt for ChatGPT (8 sectors, one px/m scale, no JSON), automatic sector cutting, codes S1–S8, real-scale layout, panel editor.
- **Chimneys** from a generator with three views; a **UV editor** for every surface (like Unwrap UVW), photo rectification.
- **Edge and vertex display** like "Edged Faces" in 3ds Max (thickness in px, colour, hidden edges paler).
- **Export**: GLB, glTF (`.gltf` + `.bin` + textures), **T3D for MaSzyna** (LOD0/LOD1, TGA + MAT, `.inc`, nodebank, chimney smoke).
- **`.mgdot` project**: the whole scene saved and opened as one file, recent-files list.

![Roof generator](docs/img/roof-gen.png)

## Quick start

1. Download `GeoStudio-windows.zip` or `GeoStudio-linux.zip`, unpack and run (no installer; the exe is unsigned).
   Or from source: Godot **4.6** (standard) → Import → `project.godot` → **F5**.
2. Pick a project folder (or open a `.mgdot` file), find a place, click a building, **Zbuduj model 3D** (build the 3D model).
3. Tabs: *Miejsce → Budynek → Tekstury → Dach → Widok* (place, building, textures, roof, view). In *Tekstury* copy the prompt to ChatGPT, attach your photos, save the result and point to it as "Płótno od GPT" (GPT canvas).

The internet is needed only in the "Miejsce" step (Geoportal, Nominatim). The program interface is in **Polish**.

## Building the program

`export_presets.cfg` has ready presets (Windows x64, Linux x86_64, a single file with data). Install the Godot 4.6.3 export templates, then:

```
godot --headless --path . --export-release "Windows" build/windows/GeoStudio.exe
godot --headless --path . --export-release "Linux"   build/linux/GeoStudio.x86_64
```

## Documentation

- [docs/MANUAL.en.md](docs/MANUAL.en.md) – user and tester manual (EN); [docs/PODRECZNIK.pl.md](docs/PODRECZNIK.pl.md) – the same in Polish.
- [docs/FORMATS.md](docs/FORMATS.md) – the `.mgdot`, glTF and **T3D** formats (PL + EN).
- [docs/MODEL_META.md](docs/MODEL_META.md) – target metadata contract: a generator profile on top of the MaSzyna Reloaded model format (PL + EN). [docs/MODEL_META_V1.md](docs/MODEL_META_V1.md) – what the exporter writes today.
- [docs/ROADMAP.md](docs/ROADMAP.md) – roadmap (PL + EN).
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – code layout (PL + EN). [docs/CHANGELOG.md](docs/CHANGELOG.md) – change history.

## Work in progress – next steps

- **The whole metadata section** (`docs/MODEL_META.md`, the `model_meta` block, per-part data, how the simulator side reads it) still has to be worked through and finished.
- **Cut-outs on the panel** (the sector canvas) for elements that imitate lighting – lit windows, lamps, `light_on` surfaces – need work: how they are cut, marked and exported to T3D (currently a neutral `light_on00` without a mask).

## Status – what works and what was not verified

A working prototype (3.0.4). **Not verified**: the T3D export in the MaSzyna simulator itself (the format was rebuilt from the sample pack and automatic checks), importing GLB/glTF into Blender and other engines,
running on Windows (paths), the live Geoportal and Nominatim services (developed against a mock server). The roof is a simplified model, not LoD2; windows and doors are not separate geometry;
ChatGPT does not guarantee the number of windows or the image size. Full list: [manual, section 13](docs/MANUAL.en.md).

## Tests

```
godot --headless --path . --import
godot --headless --path . --script res://tools/selftest.gd      # 342 checks, exit code 0 = OK
```

## Data and licence

Geodata © GUGiK / Geoportal.gov.pl – check the service terms before publishing results. The sample textures in `textures/` are demo material;
make sure you may redistribute them before publishing the repository.

The code is licensed under the **MIT** licence – see [LICENSE](LICENSE). © 2026 Miłosz "pol102" Mindak. Supported by Claude AI.

„Porzućcie wszelką nadzieję, wy, którzy tu wchodzicie”
