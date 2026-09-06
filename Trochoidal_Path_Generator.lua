-- VECTRIC LUA SCRIPT
-- Trochoidal Path Generator for Aspire 12
-- Version 1.0
--
-- Select one or more STRAIGHT OPEN VECTORS, then run:
-- Gadgets -> Trochoidal Path Generator
--
-- The gadget creates a new OPEN VECTOR for each selected line.
-- The generated vector is the TOOL-CENTER PATH. Use:
--   2D Profile Toolpath -> Machine Vectors = ON
--
-- Geometry:
--   x(theta) = pitch*theta/(2*pi) + R*sin(theta)
--   y(theta) = R*cos(theta)
--
-- R is calculated from:
--   R = (slot_width - tool_diameter) / 2
--
-- IMPORTANT:
-- This is a geometry generator, not a complete CAM cutting-strategy validator.
-- Always preview/simulate and verify the resulting G-code before machining.

local VERSION = "1.0"

local function fmt(v)
  return string.format("%.3f", v)
end

local function show_error(msg)
  DisplayMessageBox("Trochoidal Path Generator\n\n" .. msg)
end

local function build_trochoid(p1, p2, radius, pitch, points_per_rev, side)
  local dx = p2.X - p1.X
  local dy = p2.Y - p1.Y
  local length = math.sqrt(dx*dx + dy*dy)

  if length <= 0.000001 then
    return nil, "Zero-length vector."
  end

  local tx = dx / length
  local ty = dy / length

  -- Left-hand normal of the selected vector.
  local nx = -ty
  local ny = tx

  -- side = +1 for left, -1 for right.
  nx = nx * side
  ny = ny * side

  -- Only generate complete revolutions. This guarantees that each
  -- complete revolution advances exactly one pitch and finishes at
  -- the same transverse offset as it started.
  local revolutions = math.floor(length / pitch + 1.0e-9)

  if revolutions < 1 then
    return nil, "The selected line is shorter than one pitch."
  end

  local usable_length = revolutions * pitch
  local total_steps = revolutions * points_per_rev

  local ctr = Contour(0.0)

  -- Start at the centerline and then enter the first loop smoothly.
  -- We use a half-amplitude phase offset so the first point is on the
  -- centerline. The first half-cycle is therefore an intentional lead-in.
  --
  -- For a pure repeating trochoid, use the standard parametric form
  -- beginning at theta=0. That starts at +R normal to the centerline.
  local theta0 = 0.0
  local x0 = 0.0 + radius * math.sin(theta0)
  local y0 = radius * math.cos(theta0)

  local sx = p1.X + tx*x0 + nx*y0
  local sy = p1.Y + ty*x0 + ny*y0

  ctr:AppendPoint(sx, sy)

  for i = 1, total_steps do
    local theta = 2.0 * math.pi * (i / points_per_rev)
    local axial = pitch * theta / (2.0 * math.pi)

    local lx = axial + radius * math.sin(theta)
    local ly = radius * math.cos(theta)

    local x = p1.X + tx*lx + nx*ly
    local y = p1.Y + ty*lx + ny*ly

    ctr:LineTo(x, y)
  end

  return ctr, revolutions, usable_length
end

local function process_selection(tool_dia, slot_width, pitch, points_per_rev, side)
  local job = VectricJob()
  if not job.Exists then
    show_error("No Aspire job is open.")
    return false
  end

  local selection = job.Selection
  if selection.IsEmpty then
    show_error("Select one or more straight open vectors first.")
    return false
  end

  if tool_dia <= 0 then
    show_error("Tool diameter must be greater than zero.")
    return false
  end

  if slot_width <= tool_dia then
    show_error("Slot width must be greater than tool diameter.")
    return false
  end

  if pitch <= 0 then
    show_error("Pitch must be greater than zero.")
    return false
  end

  if points_per_rev < 8 or points_per_rev > 200 then
    show_error("Points / revolution must be between 8 and 200.")
    return false
  end

  local radius = (slot_width - tool_dia) / 2.0
  local layer = job.LayerManager:GetActiveLayer()

  local pos = selection:GetHeadPosition()
  local created = 0
  local skipped = {}

  while pos ~= nil do
    local obj
    obj, pos = selection:GetNext(pos)

    local cad = CastCadObjectToCadContour(obj)
    if cad == nil then
      table.insert(skipped, "Selected object is not a vector.")
    else
      local src = cad:GetContour()

      if src.IsClosed then
        table.insert(skipped, "Closed vector skipped.")
      elseif src.Count ~= 1 then
        table.insert(skipped, "Only single-span straight lines are supported in v1.0.")
      else
        local span_pos = src:GetHeadPosition()
        local span = nil
        if span_pos ~= nil then
          span = src:GetAt(span_pos)
        end

        if span == nil or not span.IsLineType then
          table.insert(skipped, "Non-line vector skipped.")
        else
          local p1 = src.StartPoint2D
          local p2 = src.EndPoint2D

          local ctr, revolutions, usable_length =
            build_trochoid(p1, p2, radius, pitch, points_per_rev, side)

          if ctr == nil then
            table.insert(skipped, "Line skipped: shorter than one pitch.")
          else
            local cc = CreateCadContour(ctr)
            layer:AddObject(cc, true)
            created = created + 1
          end
        end
      end
    end
  end

  job:Refresh2DView()

  local msg = "Created " .. tostring(created) .. " trochoidal vector(s).\n\n"
  msg = msg .. "Tool diameter: " .. fmt(tool_dia) .. "\n"
  msg = msg .. "Slot width:    " .. fmt(slot_width) .. "\n"
  msg = msg .. "Trochoid R:    " .. fmt(radius) .. "\n"
  msg = msg .. "Pitch:         " .. fmt(pitch) .. "\n"
  msg = msg .. "Points/rev:    " .. tostring(points_per_rev) .. "\n\n"
  msg = msg .. "The generated vectors are TOOL-CENTER paths.\n"
  msg = msg .. "Use Profile Toolpath with Machine Vectors = ON."

  if #skipped > 0 then
    msg = msg .. "\n\nSkipped " .. tostring(#skipped) .. " selection(s):"
    local limit = math.min(#skipped, 8)
    for i = 1, limit do
      msg = msg .. "\n- " .. skipped[i]
    end
    if #skipped > limit then
      msg = msg .. "\n- ... and more"
    end
  end

  MessageBox(msg)
  return true
end

local HTML = [[
<html>
<head>
<style>
body {
  font-family: Arial, sans-serif;
  font-size: 13px;
  margin: 12px;
}
h2 { margin: 0 0 8px 0; }
table { width: 100%; }
td { padding: 4px 2px; }
.label { width: 58%; }
input[type=text] { width: 90px; }
.note {
  margin-top: 10px;
  padding: 8px;
  border: 1px solid #aaa;
  background: #f3f3f3;
}
.LuaButton {
  padding: 7px 14px;
  margin-top: 10px;
}
</style>
</head>
<body>
<h2>Trochoidal Path Generator</h2>

<p>Select one or more <b>straight open vectors</b> before running this gadget.</p>

<table>
<tr>
<td class="label">Tool diameter:</td>
<td><input id="ToolDia" type="text"></td>
</tr>
<tr>
<td class="label">Desired slot width:</td>
<td><input id="SlotWidth" type="text"></td>
</tr>
<tr>
<td class="label">Pitch / advance per revolution:</td>
<td><input id="Pitch" type="text"></td>
</tr>
<tr>
<td class="label">Points per revolution:</td>
<td><input id="PointsPerRev" type="text"></td>
</tr>
<tr>
<td class="label">Trochoid side:</td>
<td>
<select id="Side">
<option value="1">Left of vector</option>
<option value="-1">Right of vector</option>
</select>
</td>
</tr>
</table>

<div class="note">
<b>Formula:</b><br>
Trochoid radius = (Slot Width - Tool Diameter) / 2<br><br>
The gadget creates a <b>tool-center vector</b>. In Aspire use
<b>Profile Toolpath → Machine Vectors = ON</b>.
</div>

<button class="LuaButton" id="CreateButton" type="button">Create Trochoidal Vector</button>
</body>
</html>
]]

function OnLuaButton_CreateButton(dialog)
  local tool_dia = dialog:GetDoubleField("ToolDia")
  local slot_width = dialog:GetDoubleField("SlotWidth")
  local pitch = dialog:GetDoubleField("Pitch")
  local points = dialog:GetIntegerField("PointsPerRev")
  local side = tonumber(dialog:GetDropDownListValue("Side"))

  process_selection(tool_dia, slot_width, pitch, points, side)
  return true
end

function main(script_path)
  local job = VectricJob()

  if not job.Exists then
    show_error("Open or create an Aspire job first.")
    return false
  end

  local dialog = HTML_Dialog(true, HTML, 500, 430, "Trochoidal Path Generator")

  dialog:AddDoubleField("ToolDia", 6.0)
  dialog:AddDoubleField("SlotWidth", 10.0)
  dialog:AddDoubleField("Pitch", 1.0)
  dialog:AddIntegerField("PointsPerRev", 24)
  dialog:AddDropDownList("Side", "1")
  dialog:AddDropDownListValue("Side", "-1")
  dialog:ShowDialog()

  return true
end
