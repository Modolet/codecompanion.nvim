--[[
*Editor Tool*
This tool is used to directly modify the contents of a buffer. It can handle
multiple edits in the same XML block.
--]]

local config = require("codecompanion.config")

local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local diff_started = false

-- To keep track of the changes made to the buffer, we store them in this table
local deltas = {}
local function add_delta(bufnr, line, delta)
  table.insert(deltas, { bufnr = bufnr, line = line, delta = delta })
end

---Calculate if there is any intersection between the lines
---@param bufnr number
---@param line number
local function intersect(bufnr, line)
  local delta = 0
  for _, v in ipairs(deltas) do
    if bufnr == v.bufnr and line > v.line then
      delta = delta + v.delta
    end
  end
  return delta
end

---Delete lines from the buffer
---@param bufnr number
---@param action table
local function delete(bufnr, action)
  log:debug("[Editor Tool] Deleting code from the buffer")

  local start_line
  local end_line
  if action.all then
    start_line = 1
    end_line = api.nvim_buf_line_count(bufnr)
  else
    start_line = tonumber(action.start_line)
    assert(start_line, "No start line number provided by the LLM")
    if start_line == 0 then
      start_line = 1
    end

    end_line = tonumber(action.end_line)
    assert(end_line, "No end line number provided by the LLM")
    if end_line == 0 then
      end_line = 1
    end
  end

  local delta = intersect(bufnr, start_line)

  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, end_line + delta, false, {})
  add_delta(bufnr, start_line, (start_line - end_line - 1))
end

---Add lines to the buffer
---@param bufnr number
---@param action table
local function add(bufnr, action)
  log:debug("[Editor Tool] Adding code to buffer")

  if not action.line and not action.replace then
    assert(false, "No line number or replace request provided by the LLM")
  end

  local start_line
  if action.replace then
    -- Clear the entire buffer
    log:debug("[Editor Tool] Replacing the entire buffer")
    delete(bufnr, { start_line = 1, end_line = api.nvim_buf_line_count(bufnr) })
    start_line = 1
  else
    start_line = tonumber(action.line)
    assert(start_line, "No line number provided by the LLM")
    if start_line == 0 then
      start_line = 1
    end
  end

  local delta = intersect(bufnr, start_line)

  local lines = vim.split(action.code, "\n", { plain = true, trimempty = false })
  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, start_line + delta - 1, false, lines)

  add_delta(bufnr, start_line, tonumber(#lines))
end

---@class CodeCompanion.Tool
return {
  name = "editor",
  cmds = {
    ---Ensure the final function returns the status and the output
    ---@param self CodeCompanion.Tools The Tools object
    ---@param actions table The action object
    ---@param input any The output from the previous function call
    ---@return { status: string, msg: string }
    function(self, actions, input)
      ---Run the action
      ---@param action table
      local function run(action)
        local type = action._attr.type

        if not action.buffer then
          return { status = "error", msg = "No buffer number provided by the LLM" }
        end
        local bufnr = tonumber(action.buffer)
        assert(bufnr, "Buffer number conversion failed")
        local is_valid, _ = pcall(api.nvim_buf_is_valid, bufnr)
        assert(is_valid, "Invalid buffer number")

        local winnr = ui.buf_get_win(bufnr)
        log:trace("[Editor Tool] request: %s", action)

        -- Diff the buffer
        if
          not vim.g.codecompanion_auto_tool_mode
          and (not diff_started and config.display.diff.enabled and bufnr and vim.bo[bufnr].buftype ~= "terminal")
        then
          local provider = config.display.diff.provider
          local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)

          if ok and winnr then
            ---@type CodeCompanion.DiffArgs
            local diff_args = {
              bufnr = bufnr,
              contents = api.nvim_buf_get_lines(bufnr, 0, -1, true),
              filetype = api.nvim_buf_get_option(bufnr, "filetype"),
              winnr = winnr,
            }
            ---@type CodeCompanion.Diff
            diff = diff.new(diff_args)
            keymaps
              .new({
                bufnr = bufnr,
                callbacks = require("codecompanion.strategies.inline.keymaps"),
                data = { diff = diff },
                keymaps = config.strategies.inline.keymaps,
              })
              :set()

            diff_started = true
          end
        end

        if type == "add" then
          add(bufnr, action)
        elseif type == "delete" then
          delete(bufnr, action)
        elseif type == "update" then
          delete(bufnr, action)

          action.line = action.start_line
          add(bufnr, action)
        end

        --TODO: Scroll to buffer and the new lines

        -- Automatically save the buffer
        if vim.g.codecompanion_auto_tool_mode then
          log:info("[Editor Tool] Auto-saving buffer")
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent write")
          end)
        end

        return { status = "success", msg = nil }
      end

      local output = {}
      if vim.isarray(actions) then
        for _, v in ipairs(actions) do
          output = run(v)
          if output.status == "error" then
            break
          end
        end
      else
        output = run(actions)
      end

      return output
    end,
  },
  schema = {
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "add" },
          buffer = 1,
          line = 203,
          code = "<![CDATA[    print('Hello World')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "add" },
          buffer = 1,
          replace = true,
          code = "<![CDATA[    print('Hello World')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "update" },
          buffer = 10,
          start_line = 50,
          end_line = 99,
          code = "<![CDATA[   function M.capitalize()]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "delete" },
          buffer = 14,
          start_line = 10,
          end_line = 15,
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "delete" },
          buffer = 14,
          all = true,
        },
      },
    },
    {
      tool = { name = "editor" },
      action = {
        {
          _attr = { type = "delete" },
          buffer = 5,
          start_line = 13,
          end_line = 13,
        },
        {
          _attr = { type = "add" },
          buffer = 5,
          line = 20,
          code = "<![CDATA[function M.hello_world()]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[## 编辑器工具（`editor`）——增强指南

### 目的：
- 在用户明确请求时，通过添加、更新或删除代码来修改 Neovim 缓冲区的内容。

### 使用场景：
- 仅在用户明确要求时调用编辑器工具（例如，“你能更新代码吗？”或“更新缓冲区……”）。
- 此工具仅用于缓冲区编辑操作，其他文件相关任务应使用指定的工具处理。

### 执行格式：
- 始终以 XML Markdown 代码块的形式返回。
- 必须包含用户提供的缓冲区编号，并放在 `<buffer></buffer>` 标签中。如果用户未提供缓冲区编号，请提示用户提供。
- 每个代码操作必须：
  - 使用 CDATA 区块包裹代码以保护特殊字符（CDATA 区块确保像 `<` 和 `&` 这样的字符不会被解释为 XML 标记）。
  - 严格遵循 XML 结构。
- 如果需要顺序执行多个操作（添加、更新、删除），应在一个 XML 块中组合这些操作，放在 `<tool></tool>` 标签内，并使用单独的 `<action></action>` 条目。

### XML 结构：
每次工具调用都应遵循以下结构：

a) **添加操作（Add Action）：**
```xml
%s
```

如果需要替换整个缓冲区的内容，请在操作中传递 `<replace>true</replace>`：
```xml
%s
```

b) **更新操作（Update Action）：**
```xml
%s
```
- 确保包含需要更新范围的起始行和结束行。

c) **删除操作（Delete Action）：**
```xml
%s
```

如果需要删除整个缓冲区的内容，请在操作中传递 `<all>true</all>`：
```xml
%s
```

d) **多个操作（Multiple Actions）：**（如果需要顺序执行多个操作，如添加、更新、删除）
```xml
%s
```

### 关键注意事项：
- **安全性和准确性：** 仔细验证所有代码更新。
- **CDATA 使用：** 代码必须用 CDATA 区块包裹，以保护特殊字符并防止其被 XML 误解。
- **标签顺序：** 对于更新和删除操作，始终按顺序先列出 `<start_line>`，再列出 `<end_line>`。
- **行号：** 行号从 1 开始计数，因此第一行是第 1 行，而不是第 0 行。
- **更新规则：** 更新操作会先删除 `<start_line>` 到 `<end_line>` 范围内的内容（包含起止行），然后从 `<start_line>` 开始添加新代码。
- **上下文假设：** 如果未提供上下文，假设需要用你上一条响应中的代码更新缓冲区。

### 提醒：
- 尽量减少额外解释，专注于返回正确的 XML 块，并正确包裹 CDATA 区块。
- 始终使用上述结构以确保一致性。]],
      xml2lua.toXml({ tools = { schema[1] } }), -- Add
      xml2lua.toXml({ tools = { schema[2] } }), -- Add with replace
      xml2lua.toXml({ tools = { schema[3] } }), -- Update
      xml2lua.toXml({ tools = { schema[4] } }), -- Delete
      xml2lua.toXml({ tools = { schema[5] } }), -- Delete all
      xml2lua.toXml({ -- Multiple
        tools = {
          tool = {
            _attr = { name = "editor" },
            action = {
              schema[6].action[1],
              schema[6].action[2],
            },
          },
        },
      })
    )
  end,
  handlers = {
    on_exit = function(self)
      deltas = {}
      diff_started = false
    end,
  },
}
