--[[
*Files Tool*
This tool can be used make edits to files on disk. It can handle multiple actions
in the same XML block. All actions must be approved by you.
--]]

local Path = require("plenary.path")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local fmt = string.format
local file = nil

---Create a file and it's surrounding folders
---@param action table The action object
---@return nil
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
end

---Read the contents of af ile
---@param action table The action object
---@return table<string, string>
local function read(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  file = {
    content = p:read(),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Read the contents of a file between specific lines
---@param action table The action object
---@return nil
local function read_lines(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- Read requested lines
  local extracted = {}
  local current_line = 0

  local lines = p:iter()

  -- Parse line numbers
  local start_line = tonumber(action.start_line) or 1
  local end_line = tonumber(action.end_line) or #lines

  for line in lines do
    current_line = current_line + 1
    if current_line >= start_line and current_line <= end_line then
      table.insert(extracted, current_line .. ":  " .. line)
    end
    if current_line > end_line then
      break
    end
  end

  file = {
    content = table.concat(extracted, "\n"),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Edit the contents of a file
---@param action table The action object
---@return nil
local function edit(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local content = p:read()
  if not content then
    return util.notify(fmt("No data found in %s", action.path))
  end

  if not content:find(vim.pesc(action.search)) then
    return util.notify(fmt("Could not find the search string in %s", action.path))
  end

  p:write(content:gsub(vim.pesc(action.search), vim.pesc(action.replace)))
end

---Delete a file
---@param action table The action object
---@return nil
local function delete(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:rm()
end

---Rename a file
---@param action table The action object
---@return nil
local function rename(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:rename({ new_name = new_p.filename })
end

---Copy a file
---@param action table The action object
---@return nil
local function copy(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
end

---Move a file
---@param action table The action object
---@return nil
local function move(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
  p:rm()
end

local actions = {
  create = create,
  read = read,
  read_lines = read_lines,
  edit = edit,
  delete = delete,
  rename = rename,
  copy = copy,
  move = move,
}

---@class CodeCompanion.Tool
return {
  name = "files",
  actions = actions,
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tools The Tools object
    ---@param action table The action object
    ---@param input any The output from the previous function call
    ---@return { status: string, msg: string }
    function(self, action, input)
      local ok, data = pcall(actions[action._attr.type], action)
      if not ok then
        return { status = "error", msg = data }
      end
      return { status = "success", msg = nil }
    end,
  },
  schema = {
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "create" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello World')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "read" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "read_lines" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          start_line = "1",
          end_line = "10",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "edit" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          search = "<![CDATA[    print('Hello World')]]>",
          replace = "<![CDATA[    print('Hello CodeCompanion')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "delete" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "rename" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/new_app/new_hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "copy" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/old_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "move" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/new_app/new_folder/hello_world.py",
        },
      },
    },
    {
      tool = { name = "files" },
      action = {
        {
          _attr = { type = "create" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello World')]]>",
        },
        {
          _attr = { type = "edit" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello CodeCompanion')]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return fmt(
      [[### 文件工具（`files`）

1. **目的**：在文件系统中创建、编辑、删除、重命名、复制文件。

2. **使用方法**：对于创建、编辑或删除操作，返回一个 XML Markdown 代码块。

3. **关键点**：
   - **仅在你认为必要时使用**，用户通过审批机制对这些操作拥有最终控制权。
   - 确保 XML **有效且符合结构要求**。
   - **在文件内容中包含正确的缩进**。
   - **不要转义**特殊字符。
   - **将文件内容包裹在 CDATA 区块中**，因为内容可能包含 XML 保留字符。
   - **不要在响应中重复代码**，尽量直接将代码写入 XML 的 `<contents>` 标签中。
   - 用户当前在 Neovim 中的工作目录是 `%s`，用户可能会在消息中提到这一点。
   - 确保工具的 XML 块被 **```xml** 包裹。
   - 不要凭空想象文件内容。如果无法读取文件内容，请如实说明。

4. **操作**：

a) 创建文件（Create）：

```xml
%s
```
- 确保在指定路径创建文件并写入给定内容。
- 如果路径中存在不存在的文件夹，会自动创建这些文件夹。

b) 读取文件内容（Read）：

```xml
%s
```
- 读取指定路径文件的内容。

c) 读取文件指定行（Read Lines，含起止行）：

```xml
%s
```
- 读取文件中指定路径范围内的行号（包括起始和结束行）。
- 如果用户提供了文件的大致结构，但需要查看更多内容时，这会很有用。

d) 编辑文件（Edit）：

```xml
%s
```
- 确保编辑指定路径的文件。
- 对于需要搜索和替换的文本，尽量简洁明确。
- 明确指出需要查找的文本和替换的内容。
- 如果未找到指定文本，文件不会被编辑。

e) 删除文件（Delete）：

```xml
%s
```
- 确保删除指定路径的文件。

f) 重命名文件（Rename）：

```xml
%s
```
- 确保 `new_path` 包含文件名。

g) 复制文件（Copy）：

```xml
%s
```
- 确保 `new_path` 包含文件名。
- 如果路径中存在不存在的文件夹，会自动创建这些文件夹。

h) 移动文件（Move）：

```xml
%s
```
- 确保 `new_path` 包含文件名。
- 如果路径中存在不存在的文件夹，会自动创建这些文件夹。

5. **多个操作**：如果需要，可以在一个响应中组合多个操作：

```xml
%s
```

**注意**：
- 除非用户要求，否则尽量减少解释，专注于生成正确的 XML。
- 如果用户在路径中使用 `~`，不要替换或展开它。
- 等待用户分享操作结果后再进行下一步响应。]],
      vim.fn.getcwd(),
      xml2lua.toXml({ tools = { schema[1] } }), -- Create
      xml2lua.toXml({ tools = { schema[2] } }), -- Read
      xml2lua.toXml({ tools = { schema[3] } }), -- Extract
      xml2lua.toXml({ tools = { schema[4] } }),
      xml2lua.toXml({ tools = { schema[5] } }),
      xml2lua.toXml({ tools = { schema[6] } }),
      xml2lua.toXml({ tools = { schema[7] } }),
      xml2lua.toXml({ tools = { schema[8] } }),
      xml2lua.toXml({
        tools = {
          tool = {
            _attr = { name = "files" },
            action = {
              schema[#schema].action[1],
              schema[#schema].action[2],
            },
          },
        },
      })
    )
  end,
  handlers = {
    ---Approve the command to be run
    ---@param self CodeCompanion.Tools The tool object
    ---@param action table
    ---@return boolean
    approved = function(self, action)
      if vim.g.codecompanion_auto_tool_mode then
        log:info("[Files Tool] Auto-approved running the command")
        return true
      end

      log:info("[Files Tool] Prompting for: %s", string.upper(action._attr.type))

      local prompts = {
        base = function(a)
          return fmt("%s the file at `%s`?", string.upper(a._attr.type), vim.fn.fnamemodify(a.path, ":."))
        end,
        move = function(a)
          return fmt(
            "%s file from `%s` to `%s`?",
            string.upper(a._attr.type),
            vim.fn.fnamemodify(a.path, ":."),
            vim.fn.fnamemodify(a.new_path, ":.")
          )
        end,
      }

      local prompt = prompts.base(action)
      if action.new_path then
        prompt = prompts.move(action)
      end

      local ok, choice = pcall(vim.fn.confirm, prompt, "No\nYes")
      if not ok or choice ~= 2 then
        log:info("[Files Tool] Rejected the %s action", string.upper(action._attr.type))
        return false
      end

      log:info("[Files Tool] Approved the %s action", string.upper(action._attr.type))
      return true
    end,
    on_exit = function(self)
      log:debug("[Files Tool] on_exit handler executed")
      file = nil
    end,
  },
  output = {
    success = function(self, action, output)
      local type = action._attr.type
      local path = action.path
      log:debug("[Files Tool] success callback executed")
      util.notify(fmt("The files tool executed successfully for the `%s` file", vim.fn.fnamemodify(path, ":t")))

      if file then
        self.chat:add_message({
          role = config.constants.USER_ROLE,
          content = fmt(
            [[来自 `%s` 操作的文件 `%s` 输出为：

```%s
%s
```]],
            string.upper(type),
            path,
            file.filetype,
            file.content
          ),
        }, { visible = false })
      end
    end,

    error = function(self, action, err)
      log:debug("[Files Tool] error callback executed")
      return self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = fmt(
          [[运行 `%s` 操作时发生错误：

```txt
%s
```]],
          string.upper(action._attr.type),
          err
        ),
      })
    end,

    rejected = function(self, action)
      return self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = fmt("我已拒绝 `%s` 操作。\n\n", string.upper(action._attr.type)),
      })
    end,
  },
}
