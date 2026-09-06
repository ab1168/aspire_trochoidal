# Trochoidal Toolpath Gadget for Vectric Aspire

**Version:** 1.0.0  
**Compatible with:** Vectric Aspire 12.014  
**License:** GNU Lesser General Public License v3.0
By ab1168@gmail.com (Ashkan.B)

---

## Overview

This gadget extends Vectric Aspire by generating **trochoidal toolpaths** for CNC machining. Trochoidal milling (also known as dynamic or peel milling) uses circular arcs combined with linear motion to maintain a constant chip load, reduce tool deflection, and improve tool life—especially effective when machining hard materials (e.g., hardened steels, titanium, or composites).

The gadget works on selected vectors (open or closed contours) and produces a continuous trochoidal toolpath that can be saved as a standard Vectric toolpath or exported for use with your CNC controller.

---

## Features

- **Easy selection** – Choose any vector(s) in your Aspire project.
- **Parameter control** – Adjust trochoid stepover, radius, and feed rates to suit your material and tool.
- **Preview** – Visualize the generated path before committing.
- **Optimized motion** – Reduces sudden direction changes, minimizing stress on the machine.
- **Vectric native integration** – Runs as a gadget inside Aspire, using its API.

---

## Installation

1. **Download** the gadget files from this repository.
2. **Copy** the `TrochoidalGadget.lua` (or the provided gadget folder) into your Vectric Aspire gadgets directory. Typically:
   - Windows: `C:\Users\<YourUserName>\AppData\Roaming\Vectric\Aspire\Gadgets\`
   - macOS: `~/Library/Application Support/Vectric/Aspire/Gadgets/`
3. **Restart** Aspire. The gadget will appear under the **Gadgets** menu.

> **Note:** If you have a different Vectric version, check your installation path. The gadget is written for Aspire 12.014 but may work on other versions with minor adjustments.

---

## Usage

1. Open your project in Aspire and select the vector(s) you want to machine.
2. Go to **Gadgets** → **Trochoidal Toolpath**.
3. In the dialog, set:
   - **Tool diameter** – matches your physical end mill.
   - **Trochoid radius** – the radius of each circular loop (typically 10–30% of tool diameter).
   - **Stepover** – the forward movement per loop (as a percentage of tool diameter).
   - **Feed rate** – cutting feed (mm/min or in/min).
   - **Plunge rate** – vertical feed (if applicable).
   - **Stepdown** – depth per pass (if multiple passes are needed).
4. Click **Generate** – the gadget will compute the path and display a preview.
5. If satisfied, click **Save Toolpath** – it will be added to your project’s toolpath list, ready for post‑processing.

---

## Requirements

- **Vectric Aspire 12.014** (or later, with Lua gadget support).
- Windows or macOS (as supported by Aspire).
- No additional libraries – everything is self‑contained.

---

## Building from Source

If you wish to modify or extend the gadget:

1. Clone this repository.
2. The main logic is in `TrochoidalGadget.lua`. It uses the Vectric Lua API (see Vectric’s developer documentation).
3. Edit and test directly inside Aspire – no compilation needed.

---

## Contributing

Contributions are welcome! Please:

- Fork the repository.
- Create a feature branch.
- Submit a pull request with a clear description of changes.

All contributions must be licensed under LGPL v3.0 to match the project.

---

## License

This project is licensed under the **GNU Lesser General Public License v3.0**. See the [LICENSE](LICENSE) file for full details.

**In short:**
- You may use, modify, and distribute this software.
- If you distribute a modified version, you must make your source code available under the same license.
- You may link this library with proprietary applications, as long as you follow the terms of the LGPL (e.g., allow users to replace the library).

---

## Disclaimer

This gadget is provided “as is”, without warranty of any kind. Use at your own risk. The author is not responsible for any damage to your machine, tooling, or workpiece resulting from the use of this software. Always test with a simulation or air cut first.

---

## Author

**Your Name**  
[ab1168@gmail.com]  
[Your Website/GitHub]

---

## Support

For issues, feature requests, or questions, please open an issue on this GitHub repository.  
I will do my best to respond promptly.

---

**Happy machining!**
