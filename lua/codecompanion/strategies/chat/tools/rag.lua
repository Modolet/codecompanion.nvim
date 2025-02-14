--[[
*RAG Tool*
This tool can be used to search the internet or navigate directly to a specific URL.
--]]

local config = require("codecompanion.config")

local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  name = "rag",
  env = function(tool)
    local url
    local key
    local value

    local action = tool.action._attr.type
    if action == "search" then
      url = "https://s.jina.ai"
      key = "q"
      value = tool.action.query
    elseif action == "navigate" then
      url = "https://r.jina.ai"
      key = "url"
      value = tool.action.url
    end

    return {
      url = url,
      key = key,
      value = value,
    }
  end,
  cmds = {
    {
      "curl",
      "-X",
      "POST",
      "${url}/",
      "-H",
      "Content-Type: application/json",
      "-H",
      "X-Return-Format: text",
      "-d",
      '{"${key}": "${value}"}',
    },
  },
  schema = {
    {
      tool = {
        _attr = { name = "rag" },
        action = {
          _attr = { type = "search" },
          query = "<![CDATA[What's the newest version of Neovim?]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "rag" },
        action = {
          _attr = { type = "navigate" },
          url = "<![CDATA[https://github.com/neovim/neovim/releases]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### 检索增强生成（RAG）工具（`rag`）

1. **目的**：让你能够访问互联网以查找你可能不知道的信息。

2. **使用方法**：返回一个 XML Markdown 代码块，用于搜索互联网或导航到指定的 URL。

3. **关键点**：
   - **根据需要自行决定使用**，当你觉得无法获取最新信息以回答用户问题时，可以使用此工具。
   - 此工具成本较高，因此在使用前你可以询问用户的意见。
   - 确保 XML **有效且符合结构要求**。
   - **不要转义**特殊字符。
   - **将查询内容和 URL 包裹在 CDATA 区块中**，因为文本可能包含 XML 的保留字符。
   - 确保工具的 XML 块被 **```xml** 包裹。

4. **操作**：

a) **搜索互联网**：

```xml
%s
```

b) **导航到 URL**：

```xml
%s
```

**注意**：
- 除非用户要求，否则尽量减少解释，专注于生成正确的 XML。]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({ tools = { schema[2] } })
    )
  end,
  output = {
    error = function(self, cmd, stderr)
      if type(stderr) == "table" then
        stderr = table.concat(stderr, "\n")
      end

      self.chat:add_message({
        role = config.constants.USER_ROLE,
        content = string.format(
          [[RAG 工具执行完成后发生错误：

<error>  
%s  
</error>  
]],
          stderr
        ),
      }, { visible = false })

      self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = "我已将 RAG 工具的错误信息分享给你。\n",
      })
    end,

    success = function(self, cmd, stdout)
      if type(stdout) == "table" then
        stdout = table.concat(stdout, "\n")
      end

      self.chat:add_message({
        role = config.constants.USER_ROLE,
        content = string.format(
          [[以下是 RAG 工具检索到的内容：

<content>  
%s  
</content>  
]],
          stdout
        ),
      }, { visible = false })

      self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = "我已将 RAG 工具的内容分享给你。\n",
      })
    end,
  },
}
