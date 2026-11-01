-- @dataimago/css@0.1.0-alpha.24 dist/quarto/_extensions/dataimago/pkgsite/filters/provenance.lua · sha256:68e33df59cd4c88e1d4bd51bdd3ec45bfa62f64a1b27c8ed305cb59d4e49853b · generated from tokens; do not edit · restore: npx -p @dataimago/css@0.1.0-alpha.24 dataimago-sync
-- provenance.lua: the AI-composed label. Pandoc 3 Lua filter for Quarto >= 1.8.
--
-- A page whose front matter carries `knowledge:` gets a div.di-provenance before its first block; a page
-- without the key is returned unchanged. The label is how a reader knows the page was drafted by a model and
-- whether the maintainer has approved it, so the strings are fixed:
--   draft:    AI-composed draft: not yet approved by the maintainer
--   approved: AI-composed · drafted by {composer} from source {sha7} · {edited and }approved by {who}, {date} · How this page was made
--   stale:    appends " · written against {sha7}; the code has changed since" to whichever label is shown
--
-- Rules:
--  * Every interpolated value is a Pandoc Str, so the HTML writer escapes it.
--  * source_sha must match ^[0-9a-f]{7,40}$ (shown as its first 7 characters) or the render fails: a malformed
--    sha is never printed. source_url is linked only if it matches ^https?://; otherwise the sha is unlinked.
--  * `about` is site-root relative; the href is prefixed with "../" once per directory the page sits below the
--    project root, and a .qmd extension becomes .html. Absolute paths and URL schemes are not linked.
--  * status: approved without composer, approved_by or approved_on fails the render: Phase D writes this block, so
--    a gap is a generator bug, and a silent downgrade to "draft" would hide it. approved_on must be a real
--    YYYY-MM-DD date; edited_by_author and stale must be YAML booleans (not "true", "yes" or 1).
--  * Every failure names the page.

local stringify = pandoc.utils.stringify

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

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function page_name()
  local input = quarto and quarto.doc and quarto.doc.input_file
  if not input then
    local inputs = PANDOC_STATE and PANDOC_STATE.input_files
    input = inputs and inputs[1]
  end
  if not input then return '(unknown page)' end
  local root = quarto and quarto.project and quarto.project.directory
  if root then
    root = root:gsub('/+$', '')
    if input:sub(1, #root + 1) == root .. '/' then return input:sub(#root + 2) end
  end
  return input
end

local function warn(msg)
  io.stderr:write('provenance.lua: WARNING: ' .. page_name() .. ': ' .. msg .. '\n')
end

-- Quarto's Lua environment logs error() and carries on, which would publish a page with no label (or the
-- wrong one). Exiting non-zero is what actually refuses the render.
local function fail(msg)
  io.stderr:write('ERROR: provenance.lua: ' .. page_name() .. ': ' .. msg .. '\n')
  os.exit(1)
end

-- plain text -> Str/Space inlines (Pandoc escapes them on output); leading and trailing spaces are kept
local function words(s)
  local out = pandoc.Inlines({})
  for space, w in s:gmatch('(%s*)(%S+)') do
    if space ~= '' then out:insert(pandoc.Space()) end
    out:insert(pandoc.Str(w))
  end
  if s:match('%s$') then out:insert(pandoc.Space()) end
  return out
end

local function append(dst, src)
  for _, el in ipairs(src) do dst:insert(el) end
end

local function dirname(p) return (p:match('^(.*)/[^/]*$')) or '' end

-- how many directories below the project root this page is
local function depth()
  local input = quarto and quarto.doc and quarto.doc.input_file
  if not input then
    local inputs = PANDOC_STATE and PANDOC_STATE.input_files
    input = inputs and inputs[1]
  end
  local root = quarto and quarto.project and quarto.project.directory
  if not input or not root then return 0 end
  root = root:gsub('/+$', '')
  local rel
  if input:sub(1, #root + 1) == root .. '/' then rel = input:sub(#root + 2) else return 0 end
  local dir = dirname(rel)
  if dir == '' then return 0 end
  local n = 0
  for _ in dir:gmatch('[^/]+') do n = n + 1 end
  return n
end

local function about_href(about)
  about = trim(about)
  if about == '' then return nil end
  if about:sub(1, 1) == '/' or about:match('^%a[%w+.%-]*:') then
    warn('knowledge.about must be a site-relative path; "' .. about .. '" is not linked')
    return nil
  end
  for seg in about:gmatch('[^/]+') do
    if seg == '..' then
      warn('knowledge.about must not contain a ".." segment; "' .. about .. '" is not linked')
      return nil
    end
  end
  -- Quarto does not rewrite links inside a filter-built block, so point at the rendered page
  about = about:gsub('%.qmd$', '.html')
  about = about:gsub('%.qmd([#?])', '.html%1', 1)
  return string.rep('../', depth()) .. about
end

local function sha7(sha)
  sha = trim(sha)
  if not (sha:match('^[0-9a-f]+$') and #sha >= 7 and #sha <= 40) then
    fail('knowledge.source_sha must be 7 to 40 lowercase hex characters; refusing to print it')
  end
  return sha:sub(1, 7)
end

-- absent -> false; a YAML boolean -> itself; anything else (including the strings "true", "yes", "1") fails
local function bool(k, key)
  local v = k[key]
  if v == nil then return false end
  if type(v) == 'boolean' then return v end
  fail('knowledge.' .. key .. ' must be a boolean (true or false), not "' .. text(v) .. '"')
end

local function valid_date(s)
  local y, m, d = s:match('^(%d%d%d%d)-(%d%d)-(%d%d)$')
  if not y then return false end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 then return false end
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then days[2] = 29 end
  return d <= days[m]
end

function Pandoc(doc)
  local k = doc.meta.knowledge
  if k == nil then return nil end
  if pandoc.utils.type(k) ~= 'table' and pandoc.utils.type(k) ~= 'Map' then
    fail('knowledge: must be a mapping')
  end
  local function get(key) return trim(text(k[key])) end

  local status = get('status')
  if status ~= 'draft' and status ~= 'approved' then
    fail('knowledge.status must be "draft" or "approved"')
  end
  local stale = bool(k, 'stale')
  local sha_raw = get('source_sha')
  local short
  if sha_raw ~= '' then short = sha7(sha_raw) end
  if (status == 'approved' or stale) and not short then
    fail('knowledge.source_sha is required for an approved or stale page')
  end

  local approved = status == 'approved'
  local edited = bool(k, 'edited_by_author')
  if approved then
    for _, key in ipairs({ 'composer', 'approved_by', 'approved_on' }) do
      if get(key) == '' then fail('knowledge.status is approved but knowledge.' .. key .. ' is missing') end
    end
    if not valid_date(get('approved_on')) then
      fail('knowledge.approved_on must be a real date written YYYY-MM-DD, not "' .. get('approved_on') .. '"')
    end
  end

  local inl = pandoc.Inlines({})
  if not approved then
    append(inl, words('AI-composed draft: not yet approved by the maintainer'))
  else
    append(inl, words('AI-composed · drafted by ' .. get('composer') .. ' from source'))
    inl:insert(pandoc.Space())
    local url = get('source_url')
    if url:match('^https?://') then
      inl:insert(pandoc.Link({ pandoc.Str(short) }, url))
    else
      inl:insert(pandoc.Str(short))
    end
    local who = edited and 'edited and approved by ' or 'approved by '
    append(inl, words(' · ' .. who .. get('approved_by') .. ', ' .. get('approved_on')))
    local href = about_href(get('about'))
    if href then
      append(inl, words(' ·'))
      inl:insert(pandoc.Space())
      inl:insert(pandoc.Link(words('How this page was made'), href))
    end
  end
  if stale then
    append(inl, words(' · written against ' .. short .. '; the code has changed since'))
  end

  local classes = { 'di-provenance', approved and 'di-provenance-approved' or 'di-provenance-draft' }
  if stale then classes[#classes + 1] = 'di-provenance-stale' end
  local div = pandoc.Div({ pandoc.Para(inl) }, pandoc.Attr('', classes, { { 'role', 'note' } }))
  doc.blocks:insert(1, div)
  return doc
end
