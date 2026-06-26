-- Workspace templates: create new projects from opinionated scaffolds.
local M = {}

local fn = vim.fn

local TASKS_GO = fn.json_encode({
  build = 'go build ./...',
  test  = 'go test ./...',
  run   = 'go run .',
  lint  = 'golangci-lint run',
})

local TASKS_TS = fn.json_encode({
  build = 'npm run build',
  test  = 'npm test',
  run   = 'npm run dev',
  lint  = 'npm run lint',
})

local TASKS_PY = fn.json_encode({
  test  = 'python -m pytest -v',
  run   = 'python main.py',
  lint  = 'ruff check .',
  fmt   = 'ruff format .',
})

local TASKS_RS = fn.json_encode({
  build = 'cargo build',
  test  = 'cargo test',
  run   = 'cargo run',
  lint  = 'cargo clippy',
})

local TASKS_LUA = fn.json_encode({
  test  = 'nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec" -c qa',
  lint  = 'luacheck lua/',
})

local TEMPLATES = {
  {
    name  = 'Go Service',
    key   = 'go',
    files = {
      ['go.mod']    = function(name) return 'module ' .. name .. '\n\ngo 1.22\n' end,
      ['main.go']   = [[package main

import "fmt"

func main() {
	fmt.Println("Hello, World!")
}
]],
      ['tasks.json'] = function() return TASKS_GO end,
    },
  },
  {
    name  = 'TypeScript / Node',
    key   = 'ts',
    files = {
      ['package.json'] = function(name)
        return fn.json_encode({
          name = name, version = '0.1.0', private = true,
          scripts = { build = 'tsc', test = 'jest', dev = 'ts-node src/index.ts', lint = 'eslint src' },
        })
      end,
      ['tsconfig.json'] = [[{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "strict": true,
    "outDir": "./dist",
    "rootDir": "./src"
  }
}
]],
      ['src/index.ts'] = 'console.log("Hello, World!");\n',
      ['tasks.json'] = function() return TASKS_TS end,
    },
  },
  {
    name  = 'Python',
    key   = 'py',
    files = {
      ['pyproject.toml'] = function(name)
        return '[project]\nname = "' .. name .. '"\nversion = "0.1.0"\n\n[tool.ruff]\nline-length = 100\n'
      end,
      ['main.py']    = 'def main() -> None:\n    print("Hello, World!")\n\n\nif __name__ == "__main__":\n    main()\n',
      ['tasks.json'] = function() return TASKS_PY end,
    },
  },
  {
    name  = 'Rust',
    key   = 'rs',
    files = {
      ['Cargo.toml'] = function(name)
        return '[package]\nname = "' .. name .. '"\nversion = "0.1.0"\nedition = "2021"\n'
      end,
      ['src/main.rs'] = 'fn main() {\n    println!("Hello, World!");\n}\n',
      ['tasks.json']  = function() return TASKS_RS end,
    },
  },
  {
    name  = 'Neovim Plugin (Lua)',
    key   = 'nvim',
    files = {
      ['lua/PLUGIN/init.lua'] = function(name)
        return 'local M = {}\n\nfunction M.setup(opts)\n  opts = opts or {}\nend\n\nreturn M\n'
      end,
      ['tests/minimal_init.lua'] = [[vim.opt.rtp:prepend(vim.fn.getcwd())
pcall(require, 'plenary')
]],
      ['tasks.json'] = function() return TASKS_LUA end,
    },
  },
}

local function write_file(path, content)
  local dir = fn.fnamemodify(path, ':h')
  if dir ~= '' and dir ~= '.' then fn.mkdir(dir, 'p') end
  local lines = vim.split(type(content) == 'function' and content() or content, '\n', { plain = true })
  fn.writefile(lines, path)
end

local function resolve_files(template, project_name, project_dir)
  local resolved = {}
  for rel_path, content in pairs(template.files) do
    rel_path = rel_path:gsub('PLUGIN', project_name)
    local abs_path = project_dir .. '/' .. rel_path
    local c = type(content) == 'function' and content(project_name) or content
    resolved[abs_path] = c
  end
  return resolved
end

function M.create(template_key, project_name, base_dir)
  local tmpl
  for _, t in ipairs(TEMPLATES) do
    if t.key == template_key then tmpl = t; break end
  end
  if not tmpl then
    vim.notify('Unknown template: ' .. template_key, vim.log.levels.ERROR)
    return
  end

  base_dir = base_dir or fn.getcwd()
  local project_dir = base_dir .. '/' .. project_name
  if fn.isdirectory(project_dir) == 1 then
    vim.notify('Directory already exists: ' .. project_dir, vim.log.levels.ERROR)
    return
  end

  fn.mkdir(project_dir, 'p')

  local files = resolve_files(tmpl, project_name, project_dir)
  for path, content in pairs(files) do
    write_file(path, content)
  end

  -- git init
  fn.system('git -C ' .. fn.shellescape(project_dir) .. ' init 2>/dev/null')

  -- Switch to new project and save as workspace
  vim.cmd('cd ' .. fn.fnameescape(project_dir))
  vim.schedule(function()
    require('claudespace.workspace').save(project_name)
    -- Open main file
    local main_files = { 'main.go', 'src/index.ts', 'main.py', 'src/main.rs',
                         'lua/' .. project_name .. '/init.lua' }
    for _, mf in ipairs(main_files) do
      if fn.filereadable(project_dir .. '/' .. mf) == 1 then
        pcall(vim.cmd, 'edit ' .. fn.fnameescape(project_dir .. '/' .. mf))
        break
      end
    end
    vim.notify('Created ' .. tmpl.name .. ' project: ' .. project_name, vim.log.levels.INFO)
  end)
end

function M.pick()
  vim.ui.select(TEMPLATES, {
    prompt = 'Select template',
    format_item = function(t) return t.name end,
  }, function(tmpl)
    if not tmpl then return end
    vim.ui.input({ prompt = 'Project name: ' }, function(name)
      if not name or name == '' then return end
      vim.ui.input({ prompt = 'Base directory: ',
                     default = fn.fnamemodify(fn.getcwd(), ':h') }, function(base)
        if not base or base == '' then return end
        M.create(tmpl.key, name, base)
      end)
    end)
  end)
end

function M.setup()
  vim.keymap.set('n', '<leader>wt', M.pick, { desc = 'Workspace: new from template' })
  vim.api.nvim_create_user_command('WorkspaceTemplate', function() M.pick() end,
    { desc = 'Create workspace from template' })
end

return M
