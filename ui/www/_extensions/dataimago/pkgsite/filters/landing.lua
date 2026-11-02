-- @dataimago/css@0.1.0-alpha.25 dist/quarto/_extensions/dataimago/pkgsite/filters/landing.lua · sha256:62acb5db754e39609ca32197be3c81ec4899ea8637c9ff27621077006b72fb23 · generated from tokens; do not edit · restore: npx -p @dataimago/css@0.1.0-alpha.25 dataimago-sync
-- landing.lua: replaces the author's `.di-landing` div with the package-site landing stage.
-- Pandoc 3 Lua filter for Quarto >= 1.8. Metadata comes from `pkgsite` (index.qmd's `metadata-files`
-- merges the generator's _landing.yml into it). A page with no `.di-landing` div is returned unchanged.
--
-- DOM order: pause control, then div.di-landing holding div.di-landing-intro, div.di-landing-overview (the
-- author's content, still Pandoc blocks), div.di-landing-hero[aria-hidden], nav.di-landing-cards.
-- The stage, the intro and the overview are real Pandoc Div nodes, never raw open/close tags around Pandoc
-- content: Quarto's section-divs wraps every heading in <section>, and a section swallows a raw closing tag
-- that follows it (a README's `##` headings put the hero and the cards inside the overview).
-- A page that holds a `.di-landing` stage gets `toc: false`: the stage is the page, a TOC beside it is noise.
-- Layout is pkgsite.scss's job; this file only produces markup.
--
-- Only the FIRST `.di-landing` div on a page is the stage; any later one is unwrapped (its content stays in
-- place, without the class). The name falls back to `pagetitle`, then `title`; with none of them the intro
-- (and its h1) is omitted. With no cards, nav.di-landing-cards is omitted. The visible pause label lives at the
-- end of the intro (reachable and in reading order); the checkbox it toggles comes first in the stage.

local stringify = pandoc.utils.stringify

local function esc(s)
  s = tostring(s or '')
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  s = s:gsub('"', '&quot;')
  return s
end

-- Metadata strings arrive as Inlines, parsed as markdown: `<it>` becomes a RawInline and would vanish
-- under stringify. Rebuild the author's literal text from the inlines instead.
local function text(v)
  if v == nil then return '' end
  local t = pandoc.utils.type(v)
  if t == 'string' then return v end
  if t == 'boolean' or t == 'number' then return tostring(v) end
  if t == 'Inlines' then
    local out = {}
    for _, el in ipairs(v) do
      if el.t == 'Str' then out[#out + 1] = el.text
      elseif el.t == 'Space' or el.t == 'SoftBreak' then out[#out + 1] = ' '
      elseif el.t == 'RawInline' or el.t == 'Code' then out[#out + 1] = el.text
      else out[#out + 1] = stringify(el) end
    end
    return table.concat(out)
  end
  return stringify(v)
end

local function list(v)
  if v == nil then return {} end
  if pandoc.utils.type(v) == 'List' or pandoc.utils.type(v) == 'table' then return v end
  return { v }
end

local function dirname(p)
  return (p:match('^(.*)/[^/]*$')) or '.'
end

local function read_file(p)
  local f = io.open(p, 'r')
  if not f then return nil end
  local s = f:read('a')
  f:close()
  return s
end

-- An inlined SVG must start at `<svg`: drop a provenance comment and an xml declaration.
local function clean_svg(s)
  s = s:gsub('^%s*<%?xml.-%?>%s*', '')
  while s:match('^%s*<!%-%-') do s = s:gsub('^%s*<!%-%-.-%-%->%s*', '', 1) end
  return (s:gsub('%s+$', ''))
end

local function project_dir()
  if quarto and quarto.project and quarto.project.directory then return quarto.project.directory end
  if quarto and quarto.doc and quarto.doc.input_file then return dirname(quarto.doc.input_file) end
  local inputs = PANDOC_STATE and PANDOC_STATE.input_files
  if inputs and inputs[1] then return dirname(inputs[1]) end
  return '.'
end

local function extension_dir()
  local script = PANDOC_SCRIPT_FILE or ''
  return dirname(dirname(script)) -- <ext>/filters/landing.lua -> <ext>
end


local function fail(msg)
  io.stderr:write('ERROR: landing.lua: ' .. msg .. '\n')
  os.exit(1)
end

-- hero.src / hero.poster are project-relative: refuse an absolute path or any `..` segment.
local function check_rel(key, v)
  if v == '' then return end
  if v:sub(1, 1) == '/' or v:sub(1, 1) == '\\' or v:match('^%a[%w+.-]*:') or v:find('\\', 1, true) then
    fail('hero.' .. key .. ' must be a relative path inside the project, got: ' .. v)
  end
  for seg in (v .. '/'):gmatch('([^/]*)/') do
    if seg == '..' then fail('hero.' .. key .. ' must not contain a ".." segment, got: ' .. v) end
  end
end

-- Re-validate an SVG before it is inlined into the page: the leaf does not trust the generator's check.
-- Returns nil when clean, else the reason. Comments are stripped first.
-- Parity: these two rules mirror the dataimago R package's .check_svg_markup exactly, and tools/formats/fixtures/hero-svg-parity.json pins them.
-- An href / xlink:href is a same-document #fragment or a raster data URI (png, jpeg, jpg, gif, webp; never svg+xml); any @import is refused.
local RASTER = { 'png', 'jpeg', 'jpg', 'gif', 'webp' }
local function raster_data_uri(v)
  local lv = v:lower()
  for _, t in ipairs(RASTER) do
    local pre = 'data:image/' .. t
    if lv:sub(1, #pre) == pre and lv:sub(#pre + 1, #pre + 1):match('[;,]') then return true end
  end
  return false
end

local function svg_problem(raw)
  -- R greps the raw text, comments included, so `@import` is checked before they are stripped
  if raw:lower():find('@import', 1, true) then return 'contains "@import"' end
  local s = raw:gsub('<!%-%-.-%-%->', '')
  local l = s:lower()
  for _, t in ipairs({ 'script', 'foreignobject', 'iframe', 'object', 'embed' }) do
    if l:find('<' .. t .. '[%s/>]') or l:find('<%w+:' .. t .. '[%s/>]') then return 'contains <' .. t .. '>' end
  end
  if l:find('<animate') or l:find('<%w+:animate') then return 'contains a SMIL animate element' end
  if l:find('<set[%s/>]') or l:find('<%w+:set[%s/>]') then return 'contains a SMIL set element' end
  if l:find('javascript:', 1, true) then return 'contains "javascript:"' end
  if l:find('[%s"\'/]on%a+%s*=') then return 'contains an on* event-handler attribute' end
  -- Every <style opening must have its own </style> (the R generator counts them the same way).
  local opens, closed = 0, 0
  for _ in (l .. ' '):gmatch('<style[^%w_%-]') do opens = opens + 1 end
  for body in l:gmatch('<style[^>]*>(.-)</style>') do
    closed = closed + 1
    if body:find('<', 1, true) then return 'has "<" inside a <style> element' end
  end
  if opens ~= closed then return 'has an unterminated <style> element' end
  for q, c in l:gmatch('url%s*%(%s*(["\']?)%s*(.?)') do
    if c ~= '#' then return 'has a url() that does not point at a #fragment' end
  end
  for pos in l:gmatch('()href%s*=') do
    local rest = s:sub(pos):match('^href%s*=%s*(.*)$') or ''
    local q = rest:sub(1, 1)
    local v
    if q == '"' or q == "'" then v = rest:match('^' .. q .. '(.-)' .. q) or ''
    else v = rest:match('^([^%s>]*)') end
    if v:gsub('^%s+', ''):sub(1, 1) ~= '#' and not raster_data_uri((v:gsub('^%s+', ''))) then return 'has an href that is not a #fragment: ' .. v:sub(1, 60) end
  end
  return nil
end

local function hero_html(hero)
  local kind = text(hero and hero.kind)
  if kind == '' then kind = 'fallback' end
  if hero then
    check_rel('src', text(hero.src))
    check_rel('poster', text(hero.poster))
  end
  local open = '<div class="di-landing-hero" aria-hidden="true">'
  if kind == 'svg' then
    local src = text(hero.src)
    local body = read_file(project_dir() .. '/' .. src)
    if body then
      local why = svg_problem(body)
      if why then fail('hero.src ' .. src .. ' is not safe to inline: ' .. why) end
      return open .. clean_svg(body) .. '</div>'
    end
    io.stderr:write('landing.lua: hero.src not found: ' .. src .. '; using the brand fallback\n')
  elseif kind == 'js' then
    local src, poster, alt = text(hero.src), text(hero.poster), text(hero.alt)
    local img = poster ~= '' and ('<img src="' .. esc(poster) .. '" alt="' .. esc(alt) .. '">') or ''
    return open .. '<div class="di-hero-mount" data-hero-src="' .. esc(src) .. '" data-hero-poster="'
      .. esc(poster) .. '">' .. img .. '</div><script type="module" src="pkgsite-hero.js"></script></div>'
  end
  local body = read_file(extension_dir() .. '/hero-fallback.svg')
  return open .. (body and clean_svg(body) or '') .. '</div>'
end

local function build(div, meta)
  local p = meta.pkgsite or {}
  local out = pandoc.List()
  local stage = pandoc.List()
  local function raw(s) stage:insert(pandoc.RawBlock('html', s)) end

  local label = '<label class="di-hero-pause-label" for="di-hero-pause">'
    .. '<span class="di-pause-on">Pause animation</span><span class="di-pause-off">Play animation</span></label>'
  out:insert(pandoc.RawBlock('html', '<input type="checkbox" id="di-hero-pause" class="di-hero-pause-input">'))

  local name = text(p.name)
  if name == '' then name = text(meta.pagetitle) end
  if name == '' then name = text(meta.title) end
  if name ~= '' then
    local intro = pandoc.List()
    local function iraw(s) intro:insert(pandoc.RawBlock('html', s)) end
    iraw('<h1 class="di-landing-name">' .. esc(name) .. '</h1>')
    if text(p.title) ~= '' then iraw('<p class="di-landing-title">' .. esc(text(p.title)) .. '</p>') end
    if text(p.version) ~= '' then iraw('<p class="di-landing-version">Version ' .. esc(text(p.version)) .. '</p>') end
    local links = list(p.links)
    if #links > 0 then
      iraw('<ul class="pill-links">')
      for _, l in ipairs(links) do
        local a = pandoc.Link({ pandoc.Str(text(l.text)) }, text(l.href))
        intro:insert(pandoc.Plain({ pandoc.RawInline('html', '<li>'), a, pandoc.RawInline('html', '</li>') }))
      end
      iraw('</ul>')
    end
    iraw('<p class="di-hero-pause">' .. label .. '</p>')
    stage:insert(pandoc.Div(intro, pandoc.Attr('', { 'di-landing-intro' })))
  else
    raw('<div class="di-landing-controls"><p class="di-hero-pause">' .. label .. '</p></div>')
  end

  local content = nil
  for _, b in ipairs(div.content) do
    if b.t == 'Div' and b.classes:includes('di-landing-overview') then content = b.content end
  end
  stage:insert(pandoc.Div(content or div.content, pandoc.Attr('', { 'di-landing-overview' })))

  raw(hero_html(p.hero))

  local cards = list(p.cards)
  if #cards > 0 then raw('<nav class="di-landing-cards" aria-label="Sections">') end
  for _, c in ipairs(cards) do
    local inl = {
      pandoc.Span({ pandoc.Str(text(c.title)) }, pandoc.Attr('', { 'di-card-title' })),
      pandoc.Span({ pandoc.Str(text(c.desc)) }, pandoc.Attr('', { 'di-card-desc' })),
    }
    local a = pandoc.Link(inl, text(c.href), '', pandoc.Attr('', { 'di-card' }, { { 'data-card', text(c.key) } }))
    stage:insert(pandoc.Plain({ a }))
  end
  if #cards > 0 then raw('</nav>') end
  out:insert(pandoc.Div(stage, pandoc.Attr('', { 'di-landing' })))
  return out
end

function Pandoc(doc)
  local found = false
  local result = doc:walk({
    Div = function(div)
      if div.classes:includes('di-landing') then
        if found then return div.content end -- a later one: unwrapped, content stays in place
        found = true
        return build(div, doc.meta)
      end
    end,
  })
  if not found then return nil end
  result.meta.toc = false
  return result
end
