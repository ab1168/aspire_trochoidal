-- VECTRIC LUA SCRIPT | By ab1168@gmail.com
-- Trochoidal Path Generator for Aspire 12
-- Version 3.2
--
-- Generates trochoidal TOOL-CENTER vectors from selected Vectric contours.
-- Supported source geometry: line, arc, Bezier, polyline, mixed contours,
-- open vectors, closed vectors, and multiple selected vectors.
--
-- Optional: creates a standard Aspire Profile Toolpath on the generated
-- vectors using PROFILE_ON. The generated vectors remain in the job so the
-- toolpath can be recalculated later.
--
-- IMPORTANT: Always preview/simulate before machining.

local VERSION = "3.2"
local REG_SECTION = "OpenAI_Trochoidal_Path_Generator_v3_2"
local PI = math.pi
local TWO_PI = 2.0 * PI
local EPS = 1.0e-9

local function message(title, text)
  DisplayMessageBox(title .. "\n\n" .. text)
end

local function fmt(v)
  return string.format("%.4f", v)
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function smoothstep01(t)
  t = clamp(t, 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)
end

local function hypot(x, y)
  return math.sqrt(x*x + y*y)
end

local function normalize(x, y)
  local l = hypot(x, y)
  if l <= EPS then return 0.0, 0.0 end
  return x/l, y/l
end

local function distance_xy(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  return hypot(dx, dy)
end

local function copy_original_selection(selection)
  local out = {}
  local pos = selection:GetHeadPosition()
  while pos ~= nil do
    local obj
    obj, pos = selection:GetNext(pos)
    out[#out + 1] = obj
  end
  return out
end

local function restore_selection(selection, objects)
  selection:Clear()
  for i = 1, #objects do
    selection:Add(objects[i], true, true)
  end
  if #objects > 0 then selection:GroupSelectionFinished() end
end

-- Sample every span by parameter, then accumulate actual chord lengths.
-- This deliberately avoids assuming that Bezier parameter u is proportional
-- to arc length.
local function sample_contour(src, sample_step, tolerance)
  -- Aspire 12 builds can expose Span:PointAtParameter() with different
  -- overloads. Avoid that API entirely: polygonize the source contour and
  -- read StartPoint2D/EndPoint2D from the resulting line spans.
  local max_line_len = math.max(sample_step, tolerance * 10.0)
  local poly = src:CreatePolygonizedCopy(tolerance, max_line_len)
  if poly == nil or poly.IsEmpty then
    return nil, nil, 0.0, "Contour could not be polygonized."
  end

  local pts = {}
  local cum = {}
  local total = 0.0

  local function append_unique(p)
    if p == nil then return end
    local x, y = p.X, p.Y

    if #pts == 0 then
      pts[1] = {x = x, y = y}
      cum[1] = 0.0
      return
    end

    local last = pts[#pts]
    local dx = x - last.x
    local dy = y - last.y
    local d = math.sqrt(dx * dx + dy * dy)

    if d <= math.max(tolerance * 0.05, 1.0e-10) then
      return
    end

    total = total + d
    pts[#pts + 1] = {x = x, y = y}
    cum[#cum + 1] = total
  end

  local pos = poly:GetHeadPosition()
  while pos ~= nil do
    local span
    span, pos = poly:GetNext(pos)

    -- Polygonized spans are line spans. No PointAtParameter overload is used.
    append_unique(span.StartPoint2D)
    append_unique(span.EndPoint2D)
  end

  if #pts < 2 or total <= EPS then
    return nil, nil, 0.0, "Contour could not be converted to a usable polyline."
  end

  -- append_unique() deliberately removes the duplicate end point of a
  -- closed contour. Re-add the closing segment explicitly so 'total' is the
  -- true perimeter and point_at_length() has a final interval [last -> first].
  if src.IsClosed then
    local first = pts[1]
    local last = pts[#pts]
    local dx = first.x - last.x
    local dy = first.y - last.y
    local close_len = math.sqrt(dx * dx + dy * dy)

    if close_len > math.max(tolerance * 0.05, 1.0e-10) then
      total = total + close_len
      pts[#pts + 1] = {x = first.x, y = first.y}
      cum[#cum + 1] = total
    else
      -- Degenerate closure: still make the cumulative endpoint available.
      pts[#pts + 1] = {x = first.x, y = first.y}
      cum[#cum + 1] = total
    end
  end

  return pts, cum, total, nil
end

local function point_at_length(pts, cum, total, s, closed)
  if total <= EPS then return pts[1].x, pts[1].y end

  if closed then
    s = s % total
    if s < 0 then s = s + total end
  else
    if s <= 0.0 then return pts[1].x, pts[1].y end
    if s >= total then return pts[#pts].x, pts[#pts].y end
  end

  local lo = 2
  local hi = #cum
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if cum[mid] < s then
      lo = mid + 1
    else
      hi = mid
    end
  end

  local i = lo
  local s0 = cum[i - 1]
  local s1 = cum[i]
  local t = 0.0
  if s1 > s0 + EPS then t = (s - s0) / (s1 - s0) end

  local a = pts[i - 1]
  local b = pts[i]
  return a.x + (b.x - a.x) * t,
         a.y + (b.y - a.y) * t
end

local function tangent_at_length(pts, cum, total, s, closed, ds)
  if total <= EPS then return 1.0, 0.0 end
  ds = math.max(ds, math.min(total * 0.0005, 1.0e-5))

  local a = s - ds
  local b = s + ds
  if not closed then
    a = clamp(a, 0.0, total)
    b = clamp(b, 0.0, total)
    if b - a <= EPS then
      if s <= total * 0.5 then
        a, b = 0.0, math.min(total, ds * 2.0)
      else
        a, b = math.max(0.0, total - ds * 2.0), total
      end
    end
  end

  local ax, ay = point_at_length(pts, cum, total, a, closed)
  local bx, by = point_at_length(pts, cum, total, b, closed)
  local tx, ty = normalize(bx - ax, by - ay)
  if tx == 0.0 and ty == 0.0 then return 1.0, 0.0 end
  return tx, ty
end

local function amplitude_factor(s, total, lead_in, lead_out, closed)
  if closed then return 1.0 end
  local f = 1.0
  if lead_in > EPS then
    f = math.min(f, smoothstep01(s / lead_in))
  end
  if lead_out > EPS then
    f = math.min(f, smoothstep01((total - s) / lead_out))
  end
  return f
end

-- Estimate local centerline radius of curvature numerically. This is only a
-- warning metric; it is intentionally not used to alter the source geometry.
local function estimate_min_curvature_radius(pts, cum, total, closed, probe_step)
  if total <= EPS then return math.huge end
  local ds = math.max(probe_step, total / 500.0)
  local start_s = closed and 0.0 or ds
  local end_s = closed and (total - ds) or (total - ds)
  if end_s <= start_s then return math.huge end

  local min_r = math.huge
  local s = start_s
  while s <= end_s + EPS do
    local t1x, t1y = tangent_at_length(pts, cum, total, s - ds, closed, ds * 0.5)
    local t2x, t2y = tangent_at_length(pts, cum, total, s + ds, closed, ds * 0.5)
    local dot = clamp(t1x*t2x + t1y*t2y, -1.0, 1.0)
    local ang = math.acos(dot)
    if ang > 1.0e-5 then
      local r = (2.0 * ds) / ang
      if r < min_r then min_r = r end
    end
    s = s + ds
  end
  return min_r
end

local function build_trochoid(src, opts)
  local pts, cum, total, err = sample_contour(src, opts.sample_step, opts.tolerance)
  if pts == nil then return nil, nil, err end
  if total <= EPS then return nil, nil, "Zero-length contour." end

  local closed = src.IsClosed
  local pitch_used = opts.pitch
  local revolutions

  if closed and opts.lock_closed_seam then
    revolutions = math.max(1, math.floor(total / opts.pitch + 0.5))
    pitch_used = total / revolutions
  else
    revolutions = total / opts.pitch
  end

  -- Step by angle rather than just by centerline sampling distance. This keeps
  -- the number of segments per revolution predictable on every source curve.
  local steps = math.max(1, math.ceil(revolutions * opts.points_per_rev))
  local theta_total = TWO_PI * (total / pitch_used)
  local phase = opts.phase_deg * PI / 180.0
  local tangent_ds = math.max(opts.sample_step * 0.75,
                              pitch_used / math.max(opts.points_per_rev, 8))

  local ctr = Contour(0.0)
  local out_pts = {}

  for i = 0, steps do
    local f = i / steps
    local s = total * f
    if closed and i == steps then s = total end

    local cx, cy = point_at_length(pts, cum, total, s, closed and i < steps)
    local tx, ty = tangent_at_length(pts, cum, total,
                                     (closed and i == steps) and 0.0 or s,
                                     closed, tangent_ds)
    local nx = -ty * opts.side
    local ny =  tx * opts.side

    local theta = phase + theta_total * f
    local amp = opts.radius * amplitude_factor(s, total,
                                               opts.lead_in,
                                               opts.lead_out,
                                               closed)

    local tangent_offset = amp * math.sin(theta)
    local normal_offset  = amp * math.cos(theta)
    local x = cx + tx * tangent_offset + nx * normal_offset
    local y = cy + ty * tangent_offset + ny * normal_offset

    if i == 0 then
      ctr:AppendPoint(x, y)
    else
      ctr:LineTo(x, y)
    end
    out_pts[#out_pts + 1] = {x=x, y=y}
  end

  -- For closed source vectors, make the final XY point coincide with the
  -- start when requested. Vectric recognises a contour as closed from its
  -- coincident endpoints; there is no dependency here on an undocumented
  -- Contour:Close() helper.
  if closed and opts.close_output_for_closed_source then
    local a = out_pts[1]
    local b = out_pts[#out_pts]
    if distance_xy(a, b) > math.max(opts.tolerance * 2.0, 1.0e-8) then
      ctr:LineTo(a.x, a.y)
      out_pts[#out_pts + 1] = {x=a.x, y=a.y}
    end
  end

  local min_curve_r = estimate_min_curvature_radius(
    pts, cum, total, closed,
    math.max(opts.sample_step * 2.0, pitch_used / 4.0)
  )

  local info = {
    source_length = total,
    pitch_used = pitch_used,
    revolutions = total / pitch_used,
    min_curve_radius = min_curve_r,
    closed_source = closed,
    generated_points = #out_pts
  }

  return ctr, info, nil
end

local function validate_options(opts)
  if opts.tool_dia <= 0 then return false, "Tool diameter must be greater than zero." end
  if opts.slot_width <= opts.tool_dia then return false, "Slot width must be greater than tool diameter." end
  if opts.pitch <= 0 then return false, "Pitch must be greater than zero." end
  if opts.points_per_rev < 8 or opts.points_per_rev > 720 then
    return false, "Points per revolution must be between 8 and 720."
  end
  if opts.sample_step <= 0 then return false, "Curve sampling step must be greater than zero." end
  if opts.tolerance <= 0 then return false, "Curve tolerance must be greater than zero." end
  if opts.lead_in < 0 or opts.lead_out < 0 then return false, "Lead-in/out lengths cannot be negative." end
  if opts.create_toolpath then
    if opts.cut_depth <= 0 then return false, "Cut depth must be greater than zero." end
    if opts.stepdown <= 0 then return false, "Tool stepdown must be greater than zero." end
    if opts.feed_rate <= 0 then return false, "Feed rate must be greater than zero." end
    if opts.plunge_rate <= 0 then return false, "Plunge rate must be greater than zero." end
    if opts.safe_z_gap <= 0 then return false, "Safe Z gap must be greater than zero." end
  end
  return true, nil
end

local function unique_toolpath_name(base)
  local mgr = ToolpathManager()
  if not mgr:ToolpathWithNameExists(base) then return base end
  local i = 2
  while mgr:ToolpathWithNameExists(base .. " " .. tostring(i)) do
    i = i + 1
  end
  return base .. " " .. tostring(i)
end

local function create_profile_toolpath(job, generated_objects, opts)
  if #generated_objects == 0 then
    return false, "No generated vectors are available for toolpath creation."
  end

  local selection = job.Selection
  selection:Clear()
  for i = 1, #generated_objects do
    selection:Add(generated_objects[i], true, true)
  end
  selection:GroupSelectionFinished()

  local tool = Tool("Trochoidal End Mill", Tool.END_MILL)
  tool.InMM = job.InMM
  tool.ToolDia = opts.tool_dia
  tool.Stepdown = opts.stepdown
  tool.Stepover = opts.tool_dia * 0.25
  tool.RateUnits = job.InMM and Tool.MM_MIN or Tool.INCHES_MIN
  tool.FeedRate = opts.feed_rate
  tool.PlungeRate = opts.plunge_rate
  tool.SpindleSpeed = opts.spindle_speed
  tool.ToolNumber = opts.tool_number

  local profile = ProfileParameterData()
  profile.StartDepth = opts.start_depth
  profile.CutDepth = opts.cut_depth
  profile.CutDirection = ProfileParameterData.CLIMB_DIRECTION
  profile.ProfileSide = ProfileParameterData.PROFILE_ON
  profile.Allowance = 0.0
  profile.KeepStartPoints = true
  profile.CreateSquareCorners = false
  profile.CornerSharpen = false
  profile.UseTabs = false

  local ramp = RampingData()
  local lead = LeadInOutData()

  local pos_data = ToolpathPosData()
  pos_data.SafeZGap = opts.safe_z_gap
  pos_data.StartZGap = math.min(opts.safe_z_gap, math.max(0.1, opts.safe_z_gap * 0.2))
  pos_data:EnsureHomeZIsSafe()

  local selector = GeometrySelector() -- inactive => currently selected vectors
  local name = unique_toolpath_name(opts.toolpath_name)
  local mgr = ToolpathManager()

  local ok, result = pcall(function()
    return mgr:CreateProfilingToolpath(
      name,
      tool,
      profile,
      ramp,
      lead,
      pos_data,
      selector,
      true,
      true
    )
  end)

  if not ok then return false, tostring(result) end
  if result == nil or result == false then
    return false, "Aspire did not return a valid toolpath id."
  end
  return true, name
end

local function save_settings(opts)
  local r = Registry(REG_SECTION)
  r:SetDouble("ToolDia", opts.tool_dia)
  r:SetDouble("SlotWidth", opts.slot_width)
  r:SetDouble("Pitch", opts.pitch)
  r:SetInt("PointsPerRev", opts.points_per_rev)
  r:SetInt("Side", opts.side)
  r:SetDouble("Phase", opts.phase_deg)
  r:SetDouble("SampleStep", opts.sample_step)
  r:SetDouble("Tolerance", opts.tolerance)
  r:SetDouble("LeadIn", opts.lead_in)
  r:SetDouble("LeadOut", opts.lead_out)
  r:SetBool("AllowClosed", opts.allow_closed)
  r:SetBool("LockClosedSeam", opts.lock_closed_seam)
  r:SetBool("CloseOutput", opts.close_output_for_closed_source)
  r:SetString("LayerName", opts.layer_name)
  r:SetBool("CreateToolpath", opts.create_toolpath)
  r:SetString("ToolpathName", opts.toolpath_name)
  r:SetDouble("StartDepth", opts.start_depth)
  r:SetDouble("CutDepth", opts.cut_depth)
  r:SetDouble("Stepdown", opts.stepdown)
  r:SetDouble("FeedRate", opts.feed_rate)
  r:SetDouble("PlungeRate", opts.plunge_rate)
  r:SetInt("SpindleSpeed", opts.spindle_speed)
  r:SetInt("ToolNumber", opts.tool_number)
  r:SetDouble("SafeZGap", opts.safe_z_gap)
  r:SetBool("CurvatureWarning", opts.curvature_warning)
end

local function load_defaults(job)
  local r = Registry(REG_SECTION)
  local metric = job.InMM
  return {
    tool_dia = r:GetDouble("ToolDia", metric and 6.0 or 0.25),
    slot_width = r:GetDouble("SlotWidth", metric and 10.0 or 0.4),
    pitch = r:GetDouble("Pitch", metric and 1.0 or 0.04),
    points_per_rev = r:GetInt("PointsPerRev", 32),
    side = r:GetInt("Side", 1),
    phase_deg = r:GetDouble("Phase", 0.0),
    sample_step = r:GetDouble("SampleStep", metric and 0.25 or 0.01),
    tolerance = r:GetDouble("Tolerance", metric and 0.001 or 0.00005),
    lead_in = r:GetDouble("LeadIn", metric and 3.0 or 0.12),
    lead_out = r:GetDouble("LeadOut", metric and 3.0 or 0.12),
    allow_closed = r:GetBool("AllowClosed", true),
    lock_closed_seam = r:GetBool("LockClosedSeam", true),
    close_output_for_closed_source = r:GetBool("CloseOutput", true),
    layer_name = r:GetString("LayerName", "Trochoidal Paths"),
    create_toolpath = r:GetBool("CreateToolpath", false),
    toolpath_name = r:GetString("ToolpathName", "Trochoidal Profile"),
    start_depth = r:GetDouble("StartDepth", 0.0),
    cut_depth = r:GetDouble("CutDepth", metric and 1.0 or 0.04),
    stepdown = r:GetDouble("Stepdown", metric and 1.0 or 0.04),
    feed_rate = r:GetDouble("FeedRate", metric and 800.0 or 30.0),
    plunge_rate = r:GetDouble("PlungeRate", metric and 250.0 or 10.0),
    spindle_speed = r:GetInt("SpindleSpeed", 18000),
    tool_number = r:GetInt("ToolNumber", 1),
    safe_z_gap = r:GetDouble("SafeZGap", metric and 5.0 or 0.2),
    curvature_warning = r:GetBool("CurvatureWarning", true)
  }
end

local function process_selection(opts)
  local job = VectricJob()
  if not job.Exists then
    message("Trochoidal Path Generator", "No Aspire job is open.")
    return false
  end

  local ok, err = validate_options(opts)
  if not ok then
    message("Invalid input", err)
    return false
  end

  local selection = job.Selection
  if selection.IsEmpty then
    message("Trochoidal Path Generator", "Select one or more vectors first.")
    return false
  end

  local originals = copy_original_selection(selection)
  local layer = job.LayerManager:GetLayerWithName(opts.layer_name)
  local generated = {}
  local skipped = {}
  local warnings = {}
  local total_points = 0
  local total_revs = 0.0

  for i = 1, #originals do
    local obj = originals[i]
    local cad = CastCadObjectToCadContour(obj)
    if cad == nil then
      skipped[#skipped + 1] = "Selection " .. tostring(i) .. ": not a CadContour."
    else
      local src = cad:GetContour()
      if src == nil or src.IsSinglePoint then
        skipped[#skipped + 1] = "Selection " .. tostring(i) .. ": invalid/single-point contour."
      elseif src.IsClosed and not opts.allow_closed then
        skipped[#skipped + 1] = "Selection " .. tostring(i) .. ": closed vectors disabled."
      else
        local success, ctr, info, build_err = pcall(function()
          local c, inf, e = build_trochoid(src, opts)
          return c, inf, e
        end)

        if not success then
          skipped[#skipped + 1] = "Selection " .. tostring(i) .. ": " .. tostring(ctr)
        elseif ctr == nil then
          skipped[#skipped + 1] = "Selection " .. tostring(i) .. ": " .. tostring(build_err or "generation failed")
        else
          local cad_out = CreateCadContour(ctr)
          layer:AddObject(cad_out, true)
          generated[#generated + 1] = cad_out
          total_points = total_points + (info.generated_points or 0)
          total_revs = total_revs + (info.revolutions or 0.0)

          if info.closed_source and math.abs(info.pitch_used - opts.pitch) > opts.tolerance then
            warnings[#warnings + 1] = "Closed vector " .. tostring(i) ..
              ": pitch adjusted from " .. fmt(opts.pitch) .. " to " .. fmt(info.pitch_used) ..
              " to close the seam."
          end

          if opts.curvature_warning and info.min_curve_radius < math.huge then
            local required = opts.radius + opts.tool_dia * 0.5
            if info.min_curve_radius < required then
              warnings[#warnings + 1] = "Vector " .. tostring(i) ..
                ": tight curvature detected (estimated R=" .. fmt(info.min_curve_radius) ..
                ", cutter-center envelope R=" .. fmt(required) .. "). Preview carefully."
            end
          end
        end
      end
    end
  end

  job:Refresh2DView()

  local toolpath_created = false
  local toolpath_text = ""
  if opts.create_toolpath and #generated > 0 then
    local tp_ok, tp_result = create_profile_toolpath(job, generated, opts)
    if tp_ok then
      toolpath_created = true
      toolpath_text = "\nProfile toolpath: " .. tostring(tp_result) .. " (PROFILE_ON)"
    else
      toolpath_text = "\nToolpath creation failed: " .. tostring(tp_result)
    end
  end

  if not opts.create_toolpath then
    restore_selection(selection, originals)
  end

  save_settings(opts)

  local text = "Created vectors: " .. tostring(#generated) .. "\n" ..
               "Skipped: " .. tostring(#skipped) .. "\n" ..
               "Generated points: " .. tostring(total_points) .. "\n" ..
               "Approx. revolutions: " .. fmt(total_revs) .. "\n\n" ..
               "Tool diameter: " .. fmt(opts.tool_dia) .. "\n" ..
               "Slot width: " .. fmt(opts.slot_width) .. "\n" ..
               "Trochoid radius: " .. fmt(opts.radius) .. "\n" ..
               "Pitch: " .. fmt(opts.pitch) .. "\n" ..
               "Side: " .. ((opts.side == 1) and "Left (+1)" or "Right (-1)") .. "\n" ..
               "Output layer: " .. opts.layer_name .. toolpath_text

  if #warnings > 0 then
    text = text .. "\n\nWarnings:"
    for i = 1, math.min(#warnings, 8) do
      text = text .. "\n- " .. warnings[i]
    end
    if #warnings > 8 then text = text .. "\n- ... and more" end
  end

  if #skipped > 0 then
    text = text .. "\n\nSkipped details:"
    for i = 1, math.min(#skipped, 8) do
      text = text .. "\n- " .. skipped[i]
    end
    if #skipped > 8 then text = text .. "\n- ... and more" end
  end

  text = text .. "\n\nGenerated geometry is the TOOL-CENTER path."
  if not toolpath_created then
    text = text .. "\nFor manual CAM use Profile Toolpath -> Machine Vectors = ON."
  end

  message("Trochoidal Path Generator " .. VERSION, text)
  return #generated > 0
end

local HTML = [[
<html>
<head>
<style>
body{font-family:Arial,sans-serif;font-size:13px;margin:12px;background:#fafafa;}
h2{margin:0 0 4px 0;} h3{margin:12px 0 5px 0;border-bottom:1px solid #ccc;padding-bottom:2px;}
table{width:100%;border-collapse:collapse;} td{padding:3px 2px;vertical-align:middle;}
.label{width:62%;} input[type=text]{width:105px;} select{width:145px;}
.note{margin:8px 0;padding:8px;border:1px solid #aaa;background:#f3f3f3;}
.warn{margin:8px 0;padding:8px;border:1px solid #c88;background:#fff2f2;}
.LuaButton{padding:8px 16px;margin-top:12px;font-weight:bold;}
.small{font-size:11px;color:#555;}
</style>
</head>
<body>
<h2>Trochoidal Path Generator 3.2</h2>
<div class="note">Select one or more vectors before running. Supports lines, arcs, Beziers, polylines, mixed contours, open and closed vectors.</div>

<h3>Trochoid geometry</h3>
<table>
<tr><td class="label">Tool diameter:</td><td><input id="ToolDia" type="text"></td></tr>
<tr><td class="label">Desired slot width:</td><td><input id="SlotWidth" type="text"></td></tr>
<tr><td class="label">Pitch / advance per revolution:</td><td><input id="Pitch" type="text"></td></tr>
<tr><td class="label">Points per revolution:</td><td><input id="PointsPerRev" type="text"></td></tr>
<tr><td class="label">Trochoid side:</td><td><select id="Side"></select></td></tr>
<tr><td class="label">Phase (degrees):</td><td><input id="Phase" type="text"></td></tr>
<tr><td class="label">Smooth lead-in length:</td><td><input id="LeadIn" type="text"></td></tr>
<tr><td class="label">Smooth lead-out length:</td><td><input id="LeadOut" type="text"></td></tr>
</table>

<h3>Curve handling</h3>
<table>
<tr><td class="label">Curve sampling step:</td><td><input id="SampleStep" type="text"></td></tr>
<tr><td class="label">Bezier/length tolerance:</td><td><input id="Tolerance" type="text"></td></tr>
<tr><td class="label">Allow closed source vectors:</td><td><input id="AllowClosed" type="checkbox"></td></tr>
<tr><td class="label">Lock closed-vector seam (adjust pitch slightly):</td><td><input id="LockClosedSeam" type="checkbox"></td></tr>
<tr><td class="label">Close generated output for closed source:</td><td><input id="CloseOutput" type="checkbox"></td></tr>
<tr><td class="label">Warn on very tight curvature:</td><td><input id="CurvatureWarning" type="checkbox"></td></tr>
</table>

<h3>Output geometry</h3>
<table>
<tr><td class="label">Output layer:</td><td><input id="LayerName" type="text"></td></tr>
</table>

<h3>Optional Aspire Profile Toolpath</h3>
<table>
<tr><td class="label">Create Profile Toolpath automatically:</td><td><input id="CreateToolpath" type="checkbox"></td></tr>
<tr><td class="label">Toolpath name:</td><td><input id="ToolpathName" type="text"></td></tr>
<tr><td class="label">Start depth:</td><td><input id="StartDepth" type="text"></td></tr>
<tr><td class="label">Cut depth:</td><td><input id="CutDepth" type="text"></td></tr>
<tr><td class="label">Tool stepdown:</td><td><input id="Stepdown" type="text"></td></tr>
<tr><td class="label">Feed rate:</td><td><input id="FeedRate" type="text"></td></tr>
<tr><td class="label">Plunge rate:</td><td><input id="PlungeRate" type="text"></td></tr>
<tr><td class="label">Spindle RPM:</td><td><input id="SpindleSpeed" type="text"></td></tr>
<tr><td class="label">Tool number:</td><td><input id="ToolNumber" type="text"></td></tr>
<tr><td class="label">Safe Z gap:</td><td><input id="SafeZGap" type="text"></td></tr>
</table>

<div class="warn"><b>Safety:</b> The generated vector is already the cutter-center path. If you create a toolpath manually, use <b>Profile -> Machine Vectors = ON</b>, never Inside/Outside. Always run Aspire Preview before cutting.</div>
<button class="LuaButton" id="CreateButton" type="button">Create Trochoidal Paths</button>
</body>
</html>
]]

function OnLuaButton_CreateButton(dialog)
  local side_text = dialog:GetDropDownListValue("Side")
  local side = 1
  if side_text == "Right (-1)" then side = -1 end

  local opts = {
    tool_dia = dialog:GetDoubleField("ToolDia"),
    slot_width = dialog:GetDoubleField("SlotWidth"),
    pitch = dialog:GetDoubleField("Pitch"),
    points_per_rev = dialog:GetIntegerField("PointsPerRev"),
    side = side,
    phase_deg = dialog:GetDoubleField("Phase"),
    lead_in = dialog:GetDoubleField("LeadIn"),
    lead_out = dialog:GetDoubleField("LeadOut"),
    sample_step = dialog:GetDoubleField("SampleStep"),
    tolerance = dialog:GetDoubleField("Tolerance"),
    allow_closed = dialog:GetCheckBox("AllowClosed"),
    lock_closed_seam = dialog:GetCheckBox("LockClosedSeam"),
    close_output_for_closed_source = dialog:GetCheckBox("CloseOutput"),
    curvature_warning = dialog:GetCheckBox("CurvatureWarning"),
    layer_name = dialog:GetTextField("LayerName"),
    create_toolpath = dialog:GetCheckBox("CreateToolpath"),
    toolpath_name = dialog:GetTextField("ToolpathName"),
    start_depth = dialog:GetDoubleField("StartDepth"),
    cut_depth = dialog:GetDoubleField("CutDepth"),
    stepdown = dialog:GetDoubleField("Stepdown"),
    feed_rate = dialog:GetDoubleField("FeedRate"),
    plunge_rate = dialog:GetDoubleField("PlungeRate"),
    spindle_speed = dialog:GetIntegerField("SpindleSpeed"),
    tool_number = dialog:GetIntegerField("ToolNumber"),
    safe_z_gap = dialog:GetDoubleField("SafeZGap")
  }

  if opts.layer_name == nil or opts.layer_name == "" then opts.layer_name = "Trochoidal Paths" end
  if opts.toolpath_name == nil or opts.toolpath_name == "" then opts.toolpath_name = "Trochoidal Profile" end
  opts.radius = (opts.slot_width - opts.tool_dia) * 0.5

  local ok, result = xpcall(function()
    return process_selection(opts)
  end, debug.traceback)
  if not ok then
    DisplayMessageBox("Trochoidal Path Generator 3.2 - unexpected error\n\n" .. tostring(result))
  end
  return true
end

function main(script_path)
  local job = VectricJob()
  if not job.Exists then
    message("Trochoidal Path Generator", "Open or create an Aspire job first.")
    return false
  end

  local d = load_defaults(job)
  if d.side ~= 1 and d.side ~= -1 then d.side = 1 end

  local dialog = HTML_Dialog(true, HTML, 620, 900, "Trochoidal Path Generator 3.2")
  dialog:AddDoubleField("ToolDia", d.tool_dia)
  dialog:AddDoubleField("SlotWidth", d.slot_width)
  dialog:AddDoubleField("Pitch", d.pitch)
  dialog:AddIntegerField("PointsPerRev", d.points_per_rev)

  -- IMPORTANT: default value MUST be one of the added values.
  local default_side = (d.side == -1) and "Right (-1)" or "Left (+1)"
  dialog:AddDropDownList("Side", default_side)
  dialog:AddDropDownListValue("Side", "Left (+1)")
  dialog:AddDropDownListValue("Side", "Right (-1)")

  dialog:AddDoubleField("Phase", d.phase_deg)
  dialog:AddDoubleField("LeadIn", d.lead_in)
  dialog:AddDoubleField("LeadOut", d.lead_out)
  dialog:AddDoubleField("SampleStep", d.sample_step)
  dialog:AddDoubleField("Tolerance", d.tolerance)
  dialog:AddCheckBox("AllowClosed", d.allow_closed)
  dialog:AddCheckBox("LockClosedSeam", d.lock_closed_seam)
  dialog:AddCheckBox("CloseOutput", d.close_output_for_closed_source)
  dialog:AddCheckBox("CurvatureWarning", d.curvature_warning)
  dialog:AddTextField("LayerName", d.layer_name)

  dialog:AddCheckBox("CreateToolpath", d.create_toolpath)
  dialog:AddTextField("ToolpathName", d.toolpath_name)
  dialog:AddDoubleField("StartDepth", d.start_depth)
  dialog:AddDoubleField("CutDepth", d.cut_depth)
  dialog:AddDoubleField("Stepdown", d.stepdown)
  dialog:AddDoubleField("FeedRate", d.feed_rate)
  dialog:AddDoubleField("PlungeRate", d.plunge_rate)
  dialog:AddIntegerField("SpindleSpeed", d.spindle_speed)
  dialog:AddIntegerField("ToolNumber", d.tool_number)
  dialog:AddDoubleField("SafeZGap", d.safe_z_gap)

  dialog:ShowDialog()
  return true
end
