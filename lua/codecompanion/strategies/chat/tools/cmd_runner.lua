--[[
*Command Runner Tool*
This tool is used to run shell commands on your system. It can handle multiple
commands in the same XML block. All commands must be approved by you.
--]]

local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CmdRunner.ChatOpts
---@field cmd table|string The command that was executed
---@field output table|string The output of the command
---@field message? string An optional message

---Outputs a message to the chat buffer that initiated the tool
---@param msg string The message to output
---@param tool CodeCompanion.Tools The tools object
---@param opts CmdRunner.ChatOpts
local function to_chat(msg, tool, opts)
  if type(opts.cmd) == "table" then
    opts.cmd = table.concat(opts.cmd, " ")
  end
  if type(opts.output) == "table" then
    opts.output = table.concat(opts.output, "\n")
  end

  local content
  if opts.output == "" then
    content = string.format(
      [[%s the command `%s`.

]],
      msg,
      opts.cmd
    )
  else
    content = string.format(
      [[%s the command `%s`:

```txt
%s
```

]],
      msg,
      opts.cmd,
      opts.output
    )
  end

  return tool.chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = content,
  })
end

---@class CodeCompanion.Tool
return {
  name = "cmd_runner",
  cmds = {
    -- Dynamically populate this table via the setup function
  },
  schema = {
    {
      tool = {
        _attr = { name = "cmd_runner" },
        action = {
          command = "<![CDATA[gem install rspec]]>",
        },
      },
    },
    {
      tool = { name = "cmd_runner" },
      action = {
        {
          command = "<![CDATA[gem install rspec]]>",
        },
        {
          command = "<![CDATA[gem install rubocop]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "cmd_runner" },
        action = {
          flag = "testing",
          command = "<![CDATA[make test]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[## 命令执行工具（`cmd_runner`）——增强指南

### 目的：
- 在用户明确请求时，在其系统上执行安全且经过验证的 shell 命令。

### 使用场景：
- 仅在用户明确要求时调用命令执行工具。
- 此工具仅用于命令执行；文件操作必须使用指定的文件工具（Files Tool）处理。

### 执行格式：
- 始终以 XML Markdown 代码块的形式返回。
- 每次执行 shell 命令时需：
  - 使用 CDATA 区块包裹命令以保护特殊字符。
  - 严格遵循 XML 结构。
- 如果需要顺序执行多个命令，应在一个 XML 块中以单独的 `<action>` 条目组合命令。

### XML 结构：
- XML 必须有效。每次工具调用都应遵循以下结构：

```xml
%s
```

- 如果需要运行多个 shell 命令，可将它们组合在一个响应中，按顺序执行：

```xml
%s
```

- 如果用户要求运行测试或测试套件，请务必包含一个测试标志，以便 Neovim 编辑器能够识别：

```xml
%s
```

### 关键注意事项：
- **安全优先：** 确保每条命令均安全且经过验证。
- **用户环境信息：**
  - **Shell：** %s
  - **操作系统：** %s
  - **Neovim 版本：** %s
- **用户监督：** 用户保留完全控制权，并通过审批机制确认执行。
- **扩展性：** 如果环境细节不可用（例如语言版本信息），请先输出命令并请求更多信息。

### 提醒：
- 尽量减少解释，专注于返回精确的包含 CDATA 包裹命令的 XML 块。
- 每次都遵循此结构，以确保一致性和可靠性。]],
      xml2lua.toXml({ tools = { schema[1] } }), -- Regular
      xml2lua.toXml({ -- Multiple
        tools = {
          tool = {
            _attr = { name = "cmd_runner" },
            action = {
              schema[2].action[1],
              schema[2].action[2],
            },
          },
        },
      }),
      xml2lua.toXml({ tools = { schema[3] } }), -- Testing flag
      vim.o.shell,
      util.os(),
      vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
    )
  end,
  handlers = {
    ---@param self CodeCompanion.Tools The tool object
    setup = function(self)
      local tool = self.tool --[[@type CodeCompanion.Tool]]
      local action = tool.request.action
      local actions = vim.isarray(action) and action or { action }

      for _, act in ipairs(actions) do
        local entry = { cmd = vim.split(act.command, " ") }
        if act.flag then
          entry.flag = act.flag
        end
        table.insert(tool.cmds, entry)
      end
    end,

    ---Approve the command to be run
    ---@param self CodeCompanion.Tools The tool object
    ---@param cmd table
    ---@return boolean
    approved = function(self, cmd)
      if vim.g.codecompanion_auto_tool_mode then
        log:info("[Cmd Runner Tool] Auto-approved running the command")
        return true
      end

      local cmd_concat = table.concat(cmd.cmd or cmd, " ")

      local msg = "Run command: `" .. cmd_concat .. "`?"
      local ok, choice = pcall(vim.fn.confirm, msg, "No\nYes")
      if not ok or choice ~= 2 then
        log:info("[Cmd Runner Tool] Rejected running the command")
        return false
      end

      log:info("[Cmd Runner Tool] Approved running the command")
      return true
    end,
  },

  output = {
    ---Rejection message back to the LLM
    rejected = function(self, cmd)
      to_chat("I chose not to run", self, { cmd = cmd.cmd or cmd, output = "" })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stderr table|string
    error = function(self, cmd, stderr)
      to_chat("There was an error from", self, { cmd = cmd.cmd or cmd, output = stderr })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stdout table|string
    success = function(self, cmd, stdout)
      to_chat("The output from", self, { cmd = cmd.cmd or cmd, output = stdout })
    end,
  },
}
