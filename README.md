# Trochoidal Path Generator for Vectric Aspire

A Lua-based **trochoidal tool-center path generator** for **Vectric Aspire 12**.

The gadget converts selected Aspire vectors into trochoidal cutter-center geometry. It is designed for CNC applications where a conventional profile path would create excessive radial engagement, especially in slotting and narrow-channel operations.

> **Current documented repository version: 3.2**


**By:** ab1168@gmail.com (Ashkan.B)

[Download Latest Version](https://github.com/ab1168/aspire_trochoidal/releases/tag/3.2)
---

---

## Features

Trochoidal Path Generator 3.2 supports:

- Straight lines
- Arcs
- Bezier curves
- Polylines
- Mixed contours containing different span types
- Open vectors
- Closed vectors
- Multiple selected vectors in one operation
- Left/right trochoidal side selection
- Configurable trochoid radius through slot width and tool diameter
- Configurable pitch / advance per revolution
- Configurable points per revolution
- Trochoid phase control
- Smooth lead-in and lead-out amplitude ramping
- Closed-vector seam locking
- Optional closed-output handling
- Curve polygonization with configurable tolerance
- Configurable curve sampling step
- Curvature warnings
- Output to a dedicated Aspire layer
- Optional automatic Aspire Profile Toolpath generation
- Persistent settings using the Aspire Registry

The generated geometry is a **tool-center path**, not an inside/outside profile vector.

---

## How Trochoidal Geometry Is Calculated

For the standard slot-width mode:

```text
Trochoid Radius = (Slot Width - Tool Diameter) / 2
```

For example:

```text
Tool Diameter = 6 mm
Slot Width    = 10 mm

Trochoid Radius = (10 - 6) / 2
                = 2 mm
```

The cutter center therefore oscillates around the selected source vector while advancing along it.

Conceptually:

```text
                 ○
             ○       ○
          ○             ○
────────○─────────────────○────────
          ○             ○
             ○       ○
                 ○

        → direction of travel
```

The resulting vector represents the **center of the cutting tool**.

---

## Requirements

- **Vectric Aspire 12**
- Windows
- A valid Aspire job
- One or more selectable vector contours

The gadget is written in Lua using the Vectric Gadget/SDK API available to Aspire.

---

# Installation

## Option 1 — Install the `.vgadget` package

If the repository contains a packaged `.vgadget` release:

1. Download the `.vgadget` file from the repository's **Releases** section.
2. Open **Vectric Aspire 12**.
3. Go to the Aspire Gadget manager / gadget installation command.
4. Select the downloaded `.vgadget` file.
5. Complete the installation.
6. Restart Aspire if the gadget does not immediately appear.
7. The gadget should be available from Aspire's **Gadgets** menu.

> The `.vgadget` file is a ZIP-based Vectric gadget package. Do not extract it before installing unless you are intentionally developing/debugging the gadget.

---

## Option 2 — Install the Lua source during development

For development or testing, the `.lua` source can be placed in the appropriate Aspire gadget directory used by the local Aspire installation.

The exact gadget directory can vary by Vectric version and Windows installation. For normal users, the packaged `.vgadget` release is recommended.

---

# Basic Usage

## 1. Create or open an Aspire job

Open an existing Aspire project or create a new one.

Make sure the job uses the intended units (mm or inches).

---

## 2. Draw or import the source vector

Create the vector representing the **desired centerline of the machining operation**.

For example:

```text
────────────────────────────────────────
                 SOURCE
                  VECTOR
────────────────────────────────────────
```

The source vector can be:

- a line
- an arc
- a Bezier curve
- a polyline
- a mixed contour

---

## 3. Select the vector

Select one or more vectors in Aspire.

The gadget processes the current Aspire selection.

---

## 4. Launch the gadget

Open:

```text
Gadgets
    → Trochoidal Path Generator 3.2
```

---

## 5. Configure the tool and slot

Example:

```text
Tool diameter:       6.0 mm
Desired slot width: 10.0 mm
Pitch:                1.0 mm
Points/revolution:   32
Trochoid side:       Left (+1)
```

With these values:

```text
Radius = (10 - 6) / 2
       = 2 mm
```

---

## 6. Select the trochoid side

The gadget provides:

```text
Left (+1)
Right (-1)
```

The side is relative to the direction of the source vector.

If the generated path appears on the opposite side from the intended machining region, change the side.

For compatibility and reliability, the default side is explicitly initialized to:

```text
Left (+1)
```

rather than relying on a null/uninitialized dropdown value.

---

## 7. Set the pitch

**Pitch** is the forward distance traveled by the trochoid during one complete revolution.

For example:

```text
Pitch = 1.0 mm
```

means approximately one millimeter of forward progress per trochoidal revolution.

Smaller pitch:

```text
○○○○○○○○○○○○
```

produces a denser path.

Larger pitch:

```text
○    ○    ○    ○    ○
```

produces fewer revolutions.

The correct value depends on cutter diameter, material, machine rigidity, feed rate, spindle speed, axial depth, and the desired radial engagement.

---

# Recommended Starting Values

These are **starting points for experimentation only**, not universal machining parameters.

For a 6 mm cutter:

```text
Tool diameter:       6 mm
Slot width:         10 mm
Trochoid radius:     2 mm
Pitch:               1 mm
Points/revolution:  32
Trochoid side:       Left (+1)
Phase:               0°
```

Always verify the result using Aspire's toolpath preview and your cutter/tool manufacturer's recommendations before machining.

---

# Working With Closed Vectors

Closed vectors such as circles and rectangles are supported.

Example:

```text
┌───────────────────┐
│                   │
│                   │
│                   │
└───────────────────┘
```

Enable the closed-vector options when appropriate.

The gadget can preserve the relationship between the beginning and end of the generated trochoidal path using closed-seam handling.

For closed geometry, inspect the seam carefully in Aspire Preview before machining.

---

# Lead-In / Lead-Out

The gadget can smoothly ramp the trochoid amplitude at the beginning and end of an open contour.

For example:

```text
Source:

────────────────────────────────────────

Generated:

       ○
         ○
           ○○
             ○○○○○○○○○○○○
           ○○
         ○
       ○
```

This can provide a more gradual entry/exit into the trochoidal motion than abruptly starting with the full amplitude.

---

# Curve Handling

The gadget does not assume that Bezier or other curve parameters correspond directly to physical distance.

Instead, source contours are polygonized and their actual chord lengths are accumulated.

This is important because:

```text
Bezier parameter ≠ physical arc length
```

The gadget therefore samples the actual contour geometry before constructing the trochoidal path.

Curve polygonization is controlled by:

- **Sampling step**
- **Tolerance**

Smaller tolerance generally produces a closer geometric approximation but can increase the number of generated points.

---

# Points Per Revolution

This parameter controls how finely each trochoidal revolution is approximated.

For example:

```text
16 points/revolution
```

is relatively coarse.

```text
32 points/revolution
```

is a reasonable starting point.

```text
64 points/revolution
```

produces smoother geometry but increases vector complexity and file size.

For CNC work, do not automatically assume that more points are always better. Excessive point counts can make Aspire and the CNC controller process unnecessarily large toolpaths.

---

# Phase

The **Phase** parameter controls the starting angular position of the trochoidal oscillation.

It is useful when controlling how the path begins relative to the source vector.

Example:

```text
Phase = 0°
Phase = 90°
Phase = 180°
```

can produce different starting positions around the source centerline without changing the basic trochoidal radius.

---

# Output Layer

Generated vectors are placed on a dedicated Aspire layer.

Default:

```text
Trochoidal Paths
```

This makes it possible to keep the original design vectors separate from the generated CNC geometry.

A typical project can therefore contain:

```text
Original Geometry
        │
        ├── Source Vectors
        │
        └── Trochoidal Paths
              │
              └── CNC Toolpath
```

---

# IMPORTANT: The Generated Vector Is Already a Tool-Center Path

This is one of the most important points when using the gadget.

The generated vector is already offset to represent the **center of the cutter**.

Therefore, when manually creating an Aspire Profile Toolpath from the generated vector, use:

```text
Profile Toolpath
    → Machine Vectors = ON
```

Do **not** use:

```text
Inside
```

or:

```text
Outside
```

because Aspire would apply another cutter-radius offset.

Conceptually:

```text
SOURCE VECTOR
      ↓
Trochoidal Generator
      ↓
TOOL-CENTER VECTOR
      ↓
Profile Toolpath
      ↓
Machine Vectors = ON
```

---

# Optional Automatic Profile Toolpath

Version 3.2 can optionally create an Aspire Profile Toolpath automatically.

The toolpath configuration includes:

- Tool diameter
- Stepdown
- Feed rate
- Plunge rate
- Spindle speed
- Tool number
- Start depth
- Cut depth
- Safe Z gap
- Toolpath name

The generated profile uses the trochoidal vectors as the actual machining vectors.

---

# CNC Workflow

A typical workflow is:

```text
1. Create/import source vector
             ↓
2. Select vector
             ↓
3. Run Trochoidal Path Generator
             ↓
4. Configure cutter / slot / pitch
             ↓
5. Generate trochoidal geometry
             ↓
6. Inspect generated vectors
             ↓
7. Create Profile Toolpath
             ↓
8. Machine Vectors = ON
             ↓
9. Preview in Aspire
             ↓
10. Verify feeds, speeds, depth and clearance
             ↓
11. Post-process G-code
             ↓
12. Machine
```

---

# Understanding the Parameters

| Parameter | Meaning |
|---|---|
| Tool Diameter | Diameter of the cutting tool |
| Slot Width | Desired overall machined slot width |
| Pitch | Forward travel per trochoidal revolution |
| Points/Revolution | Number of linear segments used to approximate each revolution |
| Trochoid Side | Side of the source vector where the oscillation is generated |
| Phase | Initial angular phase of the oscillation |
| Lead-In | Distance used to ramp the oscillation into the path |
| Lead-Out | Distance used to ramp the oscillation out of the path |
| Sampling Step | Approximate maximum source-curve sampling distance |
| Tolerance | Polygonization tolerance for curved source geometry |
| Allow Closed | Allow processing of closed source vectors |
| Lock Closed Seam | Preserve the closed-vector seam relationship |
| Close Output | Close generated geometry for closed sources |
| Curvature Warning | Warn when source geometry may create problematic curvature |
| Output Layer | Aspire layer receiving generated vectors |

---

# Troubleshooting

## "Created vectors: 0"

Check:

1. A vector is actually selected.
2. The selected object is a CAD/vector contour.
3. The vector is not a single point.
4. Closed-vector processing is enabled if the source is closed.
5. Tool diameter is smaller than the requested slot width.
6. Pitch is greater than zero.
7. Points per revolution is within a valid range.

The result dialog reports skipped selections and, where possible, the reason they were skipped.

---

## The trochoid is generated on the wrong side

Change:

```text
Trochoid side
```

from:

```text
Left (+1)
```

to:

```text
Right (-1)
```

The correct side depends on the direction of the source vector.

---

## The generated path is too dense

Try:

```text
Points/revolution: 16–32
```

instead of a very high value.

Also review:

```text
Sampling step
Tolerance
```

Excessively small tolerances can generate unnecessarily complex geometry.

---

## The generated path looks polygonal

Increase:

```text
Points/revolution
```

For example:

```text
24 → 32 → 48 → 64
```

and/or reduce the polygonization tolerance.

Always balance geometric quality against vector complexity.

---

# Safety and Machining Disclaimer

This project generates CNC geometry. It does **not** determine safe machining parameters for your particular machine, material, cutter, spindle, workholding, or controller.

Before cutting:

- Verify tool diameter.
- Verify tool stick-out.
- Verify spindle speed.
- Verify feed rate.
- Verify plunge rate.
- Verify axial depth of cut.
- Verify radial engagement.
- Verify workholding.
- Verify machine travel limits.
- Run Aspire Preview.
- Inspect the generated tool-center path.
- Perform a suitable dry run/simulation when appropriate.

**Never rely solely on the generated geometry for safe machining.**

The operator is responsible for validating the final G-code and machining parameters.

---

# Development

The project is written in Lua and targets the Vectric Aspire Gadget/SDK environment.

The source intentionally avoids Aspire APIs that have demonstrated version/build-dependent overload behavior. Curved geometry is first polygonized and then processed using the resulting line spans.

This makes the geometry-generation stage more predictable across Aspire 12 environments.

---

# Repository Structure

A suggested repository layout is:

```text
Trochoidal-Path-Generator/
│
├── README.md
├── LICENSE
│
├── src/
│   └── Trochoidal_Path_Generator_v3_2.lua
│
├── release/
│   └── Trochoidal_Path_Generator_v3_2.vgadget
│
└── docs/
    └── images/
```

---

# Version History

## v3.2

Major stable geometry-generation release.

- Added support for arbitrary Aspire contour geometry.
- Added line, arc, Bezier and polyline/mixed contour processing.
- Added open and closed vector support.
- Added multiple-selection processing.
- Added robust curve polygonization.
- Added configurable tolerance and sampling.
- Added closed-vector seam handling.
- Added lead-in / lead-out amplitude ramping.
- Added curvature warnings.
- Added persistent Aspire settings.
- Added optional automatic Profile Toolpath creation.
- Improved error reporting and skipped-selection diagnostics.
- Explicitly initialized the trochoid side to `Left (+1)` to avoid null dropdown behavior.

---

# Roadmap

Potential future improvements include:

- Automatic inside/outside side detection for closed contours
- Direct trochoid-radius input
- Automatic points-per-revolution calculation from chord tolerance
- Point-count budgeting
- Adaptive corner amplitude control
- Climb / conventional direction control
- Path-length and machining-time estimation
- Stock/boundary-aware engagement analysis
- More advanced constant-engagement trochoidal optimization
- Improved CNC entry/exit strategies

---

# Contributing

Issues, bug reports, test cases and improvements are welcome.

When reporting a problem, please include:

1. Aspire version
2. Windows version
3. Job units (mm/inch)
4. Source-vector type
5. Gadget parameters
6. Screenshot of the source vector
7. Screenshot of the generated result
8. The exact error message, if any

A minimal reproducible Aspire test file is especially useful for API-related problems.

---

# Author / Contact

**Ashkan**

Email:

**ab1168@gmail.com**

---

## License

See the repository's `LICENSE` file for licensing terms.

---

## Disclaimer

This software is provided for CNC geometry generation and experimentation. Use it at your own risk.

Always simulate and verify toolpaths before operating a CNC machine.
