-- nvim-cmp buffer words source.

-- ── Timer ─────────────────────────────────────────────────────────────────────
-- setInterval semantics: prevents callback stacking and respects stop() immediately.

local timer_mt = {}
timer_mt.__index = timer_mt

local function new_timer()
  local t = setmetatable({}, timer_mt)
  t.handle = vim.loop.new_timer()
  t._wrapper = nil
  return t
end

function timer_mt:start(timeout, repeat_ms, cb)
  local scheduled = false
  local function wrapper()
    if scheduled then return end
    scheduled = true
    vim.schedule(function()
      scheduled = false
      if self._wrapper ~= wrapper then return end
      cb()
    end)
  end
  self.handle:start(timeout, repeat_ms, wrapper)
  self._wrapper = wrapper
end

function timer_mt:stop()   self.handle:stop();  self._wrapper = nil end
function timer_mt:close()  self.handle:close() end
function timer_mt:is_active() return self.handle:is_active() end

-- ── Buffer ────────────────────────────────────────────────────────────────────

local CHUNK = 1000

local buf_mt = {}
buf_mt.__index = buf_mt

local function new_buffer(bufnr, opts)
  local self = setmetatable({}, buf_mt)
  self.bufnr   = bufnr
  self.timer   = new_timer()
  self.closed  = false
  self.on_close_cb = nil
  self.opts    = opts
  self.regex   = vim.regex(opts.keyword_pattern)

  self.lines_count         = 0
  self.timer_current_line  = -1
  self.lines_words         = {}

  self.unique_words_curr_line         = {}
  self.unique_words_other_lines       = {}
  self.unique_words_curr_line_dirty   = true
  self.unique_words_other_lines_dirty = true
  self.last_edit_first_line = 0
  self.last_edit_last_line  = 0

  self.words_distances              = {}
  self.words_distances_dirty        = true
  self.words_distances_last_cursor_row = 0
  return self
end

local function clear_table(t) for k in pairs(t) do t[k] = nil end end

function buf_mt:close()
  self.closed = true
  self:stop_indexing_timer()
  self.timer:close()
  self.timer = nil
  self.lines_words = {}
  self.unique_words_curr_line  = {}
  self.unique_words_other_lines = {}
  self.words_distances = {}
  if self.on_close_cb then self.on_close_cb() end
end

function buf_mt:stop_indexing_timer()
  self.timer:stop()
  self.timer_current_line = -1
end

function buf_mt:mark_all_lines_dirty()
  self.unique_words_curr_line_dirty   = true
  self.unique_words_other_lines_dirty = true
  self.last_edit_first_line = 0
  self.last_edit_last_line  = 0
  self.words_distances_dirty = true
end

function buf_mt:safe_buf_call(cb)
  if vim.api.nvim_get_current_buf() == self.bufnr then cb()
  else vim.api.nvim_buf_call(self.bufnr, cb) end
end

function buf_mt:index_line(linenr, line)
  local words = self.lines_words[linenr]
  if words then clear_table(words) else words = {}; self.lines_words[linenr] = words end
  local idx      = 1
  local remaining = #line > self.opts.max_indexed_line_length
    and vim.fn.strcharpart(line, 0, self.opts.max_indexed_line_length) or line
  while #remaining > 0 do
    local s, e = self.regex:match_str(remaining)
    if s and e then
      local w = remaining:sub(s + 1, e)
      if #w >= self.opts.keyword_length then words[idx] = w; idx = idx + 1 end
      remaining = remaining:sub(e + 1)
    else break end
  end
end

function buf_mt:index_range(range_start, range_end, skip)
  self:safe_buf_call(function()
    local cs = range_start
    while cs < range_end do
      local ce = math.min(cs + CHUNK, range_end)
      local lines = vim.api.nvim_buf_get_lines(self.bufnr, cs, ce, true)
      for i, ln in ipairs(lines) do
        if not skip or not self.lines_words[cs + i] then
          self:index_line(cs + i, ln)
        end
      end
      cs = ce
    end
  end)
end

function buf_mt:start_indexing_timer()
  self.lines_count = vim.api.nvim_buf_line_count(self.bufnr)
  self.timer_current_line = 0
  local interval = math.max(1, self.opts.indexing_interval)
  self.timer:start(0, interval, function()
    if self.closed then self:stop_indexing_timer(); return end
    while self.lines_words[self.timer_current_line + 1] do
      self.timer_current_line = self.timer_current_line + 1
    end
    local bs    = self.timer_current_line
    local bsize = self.opts.indexing_batch_size
    local be    = bsize >= 1 and math.min(bs + bsize, self.lines_count) or self.lines_count
    if be >= self.lines_count then self:stop_indexing_timer() end
    self.timer_current_line = be
    self:mark_all_lines_dirty()
    self:index_range(bs, be, true)
  end)
end

function buf_mt:watch()
  self.lines_count = vim.api.nvim_buf_line_count(self.bufnr)
  vim.api.nvim_buf_attach(self.bufnr, false, {
    on_lines = function(_, _, _, fl, oll, nll)
      if self.closed then return true end
      if oll == nll and fl == nll then return end
      local delta   = nll - oll
      local old_cnt = self.lines_count
      local new_cnt = old_cnt + delta
      if new_cnt == 0 then
        new_cnt = 1
        for i = old_cnt, 2, -1 do self.lines_words[i] = nil end
        self.lines_words[1] = {}
      elseif delta > 0 then
        for i = old_cnt + 1, new_cnt do self.lines_words[i] = false end
        for i = old_cnt, oll + 1, -1 do self.lines_words[i + delta] = self.lines_words[i] end
        for i = oll + 1, nll do self.lines_words[i] = {} end
      elseif delta < 0 then
        for i = oll + 1, old_cnt do self.lines_words[i + delta] = self.lines_words[i] end
        for i = old_cnt, new_cnt + 1, -1 do self.lines_words[i] = nil end
      end
      self.lines_count = new_cnt
      if self.timer:is_active() then
        if fl <= self.timer_current_line and self.timer_current_line < oll then
          self.timer_current_line = nll
        elseif self.timer_current_line >= oll then
          self.timer_current_line = self.timer_current_line + delta
        end
      end
      if fl == self.last_edit_first_line and oll == self.last_edit_last_line and nll == self.last_edit_last_line then
        self.unique_words_curr_line_dirty = true
      else
        self.unique_words_curr_line_dirty   = true
        self.unique_words_other_lines_dirty = true
      end
      self.last_edit_first_line = fl
      self.last_edit_last_line  = nll
      self.words_distances_dirty = true
      self:index_range(fl, nll)
    end,
    on_reload = function()
      if self.closed then return true end
      clear_table(self.lines_words)
      self:stop_indexing_timer()
      self:start_indexing_timer()
    end,
    on_detach = function()
      if self.closed then return true end
      self:close()
    end,
  })
end

function buf_mt:rebuild_unique_words(tbl, rs, re)
  for i = rs + 1, re do
    for _, w in ipairs(self.lines_words[i] or {}) do tbl[w] = true end
  end
end

function buf_mt:get_words()
  if self.unique_words_other_lines_dirty then
    clear_table(self.unique_words_other_lines)
    self:rebuild_unique_words(self.unique_words_other_lines, 0, self.last_edit_first_line)
    self:rebuild_unique_words(self.unique_words_other_lines, self.last_edit_last_line, self.lines_count)
    self.unique_words_other_lines_dirty = false
  end
  if self.unique_words_curr_line_dirty then
    clear_table(self.unique_words_curr_line)
    self:rebuild_unique_words(self.unique_words_curr_line, self.last_edit_first_line, self.last_edit_last_line)
    self.unique_words_curr_line_dirty = false
  end
  return { self.unique_words_other_lines, self.unique_words_curr_line }
end

function buf_mt:get_words_distances(cursor_row)
  if self.words_distances_dirty or cursor_row ~= self.words_distances_last_cursor_row then
    local d = self.words_distances; clear_table(d)
    for i = 1, self.lines_count do
      for _, w in ipairs(self.lines_words[i] or {}) do
        local dist = math.abs(cursor_row - i)
        d[w] = d[w] and math.min(d[w], dist) or dist
      end
    end
    self.words_distances_last_cursor_row = cursor_row
    self.words_distances_dirty = false
  end
  return self.words_distances
end

-- ── Source ────────────────────────────────────────────────────────────────────

local defaults = {
  keyword_length         = 3,
  keyword_pattern        = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\%(\w\|á\|Á\|é\|É\|í\|Í\|ó\|Ó\|ú\|Ú\)*\%(-\%(\w\|á\|Á\|é\|É\|í\|Í\|ó\|Ó\|ú\|Ú\)*\)*\)]],
  get_bufnrs             = function() return { vim.api.nvim_get_current_buf() } end,
  indexing_batch_size    = 1000,
  indexing_interval      = 100,
  max_indexed_line_length = 1024 * 40,
}

local source = {}
source.__index = source

function source.new()
  return setmetatable({ buffers = {} }, source)
end

function source:_opts(params)
  local opts = vim.tbl_deep_extend('keep', params.option, defaults)
  return opts
end

function source:get_keyword_pattern(params)
  return self:_opts(params).keyword_pattern
end

function source:complete(params, callback)
  local opts = self:_opts(params)
  local bufs = self:_get_buffers(opts)
  local processing = vim.iter(bufs):any(function(b) return b.timer:is_active() end)
  vim.defer_fn(function()
    local input = string.sub(params.context.cursor_before_line, params.offset)
    local items, words = {}, {}
    for _, buf in ipairs(bufs) do
      for _, wl in ipairs(buf:get_words()) do
        for w in pairs(wl) do
          if not words[w] and input ~= w then
            words[w] = true
            table.insert(items, { label = w, dup = 0 })
          end
        end
      end
    end
    callback({ items = items, isIncomplete = processing })
  end, processing and 100 or 0)
end

function source:_get_buffers(opts)
  local result = {}
  for _, bufnr in ipairs(opts.get_bufnrs()) do
    if not self.buffers[bufnr] then
      local b = new_buffer(bufnr, opts)
      b.on_close_cb = function() self.buffers[bufnr] = nil end
      b:start_indexing_timer()
      b:watch()
      self.buffers[bufnr] = b
    end
    table.insert(result, self.buffers[bufnr])
  end
  return result
end

function source:_get_distance_from_entry(entry)
  local buf = self.buffers[entry.context.bufnr]
  if buf then
    local d = buf:get_words_distances(entry.context.cursor.line + 1)
    return d[entry.completion_item.filterText] or d[entry.completion_item.label]
  end
end

function source:compare_locality(e1, e2)
  if e1.context ~= e2.context then return end
  local d1 = self:_get_distance_from_entry(e1) or math.huge
  local d2 = self:_get_distance_from_entry(e2) or math.huge
  if d1 ~= d2 then return d1 < d2 end
end

return source
