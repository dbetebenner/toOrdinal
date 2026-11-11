-- @dataimago/css@0.1.0-alpha.50 dist/quarto/_extensions/dataimago/pkgsite/filters/figure-viewer.lua · sha256:ea35293c363ad0057e69f0df0bdbfac82675faddac6135b9b1e61350919f234d · generated from tokens; do not edit · restore: npx -p @dataimago/css@0.1.0-alpha.50 dataimago-sync
-- figure-viewer.lua: the dataimago figure viewer for Quarto. Pandoc 3 Lua filter for Quarto >= 1.11.
--
-- Marks the images inside a figure with `di-figure-box` (the trigger the house module binds by event
-- delegation) and ships the module, figure-viewer.js, as an HTML dependency. Skipped:
--   * a figure or image with the class `no-zoom` (the author's opt-out);
--   * an image inside a link (the link keeps its own meaning);
--   * a code cell (`.cell`) with the class `no-zoom` (`#| classes: no-zoom` lands there);
--   * revealjs: slides are not a Bootstrap page, so the viewer would open unstyled over the deck. The filter
--     does nothing there, except in the house slides format (`dataimago-slides: true` in its metadata), whose
--     stylesheet and plugin serve the viewer. Other Bootstrap HTML formats (html, dashboard) are served.
-- Marked: the images in a captioned figure, and the uncaptioned image a code cell leaves in
-- `.cell-output-display` (a knitr plot), so a vignette's plots open too.
-- Quarto's own lightbox would open a second viewer, so the filter sets `lightbox: false` in HTML output,
-- whatever the metadata says: the house viewer replaces the lightbox. (A manuscript project puts `lightbox: auto`
-- in the format defaults, so the filter cannot tell a project default from an author's choice; to use Quarto's
-- lightbox instead, do not add the filter.) Checked on Quarto 1.11.9: a Meta handler runs in time to turn the
-- lightbox off. The module still defuses an `a.lightbox` wrapper, for a page that loads it without the filter.

local function classes_of(el)
  if el.classes ~= nil then return el.classes end
  if el.attr ~= nil then return el.attr.classes end
  return nil
end

local function has_class(el, name)
  local c = classes_of(el)
  return c ~= nil and c:includes(name)
end

local marked = false

local function mark(img)
  if has_class(img, 'no-zoom') then return nil end
  -- An author who wrote .di-figure-box on an image still needs the module.
  marked = true
  if not has_class(img, 'di-figure-box') then
    img.classes:insert('di-figure-box')
    return img
  end
  return nil
end

-- Inside a walk, Quarto shows a nested float only as its scaffold Div: no classes, just the attributes
-- __quarto_custom=true and __quarto_custom_type=FloatRefTarget. The float's own classes (.no-zoom) are not
-- readable there, so mark_in never enters one; the top-down figure pass below reaches each inner float as a
-- FloatRefTarget node and decides for it.
local function is_nested_float(div)
  return div.attributes ~= nil and div.attributes['__quarto_custom_type'] == 'FloatRefTarget'
end

-- Mark the images inside a figure, top-down so a skipped node hides its whole subtree: an image inside a
-- link (the link keeps its meaning), and a nested float (handled by its own FloatRefTarget visit).
local function mark_in(blocks)
  return blocks:walk({
    traverse = 'topdown',
    Link = function(link) return nil, false end,
    Div = function(div) if is_nested_float(div) then return nil, false end return nil end,
    Image = mark,
  })
end

-- Set by the Meta handler, which runs before any other handler.
local slides = false

local function is_html()
  return quarto.doc.is_format('html') and (slides or not quarto.doc.is_format('revealjs'))
end

local added = false
local function add_dependency()
  if added or not marked or not is_html() then return end
  added = true
  quarto.doc.add_html_dependency({
    name = 'dataimago-figure-viewer',
    version = '1',
    scripts = { 'figure-viewer.js' },
  })
end

-- Quarto turns a captioned figure into a FloatRefTarget custom node before user filters run; a plain
-- Pandoc figure is covered too, and a code cell's output (below). The pass is top-down: a figure that opts out
-- (.no-zoom) is not entered, so neither are its sub-figures; a float that is marked is still entered, to reach
-- the floats nested in it (a panel's sub-figures), each of which decides for itself.
local function FloatRefTarget(float)
  if not is_html() then return nil end
  if has_class(float, 'no-zoom') then return nil, false end
  if float.type ~= nil and float.type ~= 'Figure' then return nil end
  float.content = mark_in(pandoc.Blocks(float.content))
  return float
end

local function Figure(fig)
  if not is_html() then return nil end
  if has_class(fig, 'no-zoom') then return nil, false end
  fig.content = mark_in(fig.content)
  return fig, false
end

-- An uncaptioned plot from a code cell reaches a user filter as Div.cell-output-display > Para > Image (the
-- Div.quarto-figure wrapper only exists after the filters). Mark an image that is the only inline of a
-- Para, top-down, skipping links, nested floats (their own visit decides) and anything marked no-zoom.
local function mark_cell_images(blocks)
  return blocks:walk({
    traverse = 'topdown',
    Link = function(link) return nil, false end,
    Div = function(div)
      if is_nested_float(div) or has_class(div, 'no-zoom') then return nil, false end
      return nil
    end,
    Para = function(para)
      if #para.content == 1 and para.content[1].t == 'Image' then
        local img = mark(para.content[1])
        if img ~= nil then para.content[1] = img return para end
      end
      return nil
    end,
  })
end

local function Div(div)
  if not is_html() then return nil end
  if has_class(div, 'no-zoom') then return nil, false end
  if has_class(div, 'cell-output-display') then
    div.content = mark_cell_images(div.content)
    return div
  end
  return nil
end

local function Meta(meta)
  slides = meta['dataimago-slides'] == true
  if is_html() then
    meta.lightbox = false
    return meta
  end
  return nil
end

local function Pandoc(doc)
  add_dependency()
  return nil
end

-- Meta first, so the setting is in place before the figures are walked; then the figures; then any trigger the
-- author wrote by hand anywhere (it still needs the module); the dependency last.
return {
  { Meta = Meta },
  { traverse = 'topdown', FloatRefTarget = FloatRefTarget, Figure = Figure, Div = Div },
  { Image = function(img) if has_class(img, 'di-figure-box') then marked = true end end }, -- authored triggers
  { Pandoc = Pandoc },
}
