---@file lua/langs/yaml.lua
---@description YAML — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.yaml"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.json               JSON language support (conversion target)
---@see langs.toml               TOML language support (conversion target)
---@see langs.xml                XML language support (related data format)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/yaml.lua — YAML language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("yaml") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "yaml"):                     │    ║
--- ║  │  ├─ LSP          yamlls       (yaml-language-server + schemas)   │    ║
--- ║  │  ├─ Formatter    prettier     (opinionated code formatter)       │    ║
--- ║  │  ├─ Linter       yamllint     (YAML syntax & style checker)      │    ║
--- ║  │  ├─ Treesitter   yaml parser                                     │    ║
--- ║  │  └─ DAP          —            (N/A for YAML)                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ VALIDATE  r  Validate (yamllint)                             │    ║
--- ║  │  ├─ FORMAT    p  Pretty-print (yq)      s  Sort keys (yq)        │    ║
--- ║  │  ├─ CONVERT   j  Convert to JSON         t  Convert to TOML      │    ║
--- ║  │  ├─ QUERY     q  yq query                c  Copy key path        │    ║
--- ║  │  ├─ SCHEMA    x  Select schema (modeline)                        │    ║
--- ║  │  ├─ FOLD      f  Toggle fold level                               │    ║
--- ║  │  └─ DOCS      i  Document stats          h  YAML reference       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Schema integration flow:                                        │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. SchemaStore.nvim provides 600+ JSON schemas          │    │    ║
--- ║  │  │  2. yamlls.on_new_config merges SchemaStore schemas      │    │    ║
--- ║  │  │  3. <leader>lx inserts a schema modeline comment:        │    │    ║
--- ║  │  │     # yaml-language-server: $schema=<url>                │    │    ║
--- ║  │  │  4. yamlls picks up the modeline for validation          │    │    ║
--- ║  │  │  Available presets:                                      │    │    ║
--- ║  │  │  • GitHub Actions / Issue Template                       │    │    ║
--- ║  │  │  • Docker Compose / Kubernetes / Helm                    │    │    ║
--- ║  │  │  • GitLab CI / CircleCI / Ansible                        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  yq pipeline (used by format, convert, query, sort):             │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  buffer content → stdin → yq <expr> → stdout → buffer    │    │    ║
--- ║  │  │  Conversions use -o=json / -o=toml output flags          │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType yaml):                              ║
--- ║  • colorcolumn=120, textwidth=120  (wide for complex configs)            ║
--- ║  • tabstop=2, shiftwidth=2         (standard YAML indentation)           ║
--- ║  • expandtab=true                  (spaces, NEVER tabs — YAML requires)  ║
--- ║  • commentstring=# %s              (YAML comment format)                 ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .yml, .yaml → yaml                                                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if YAML support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("yaml") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string YAML Nerd Font icon (trailing whitespace stripped)
local yaml_icon = icons.lang.yaml:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for YAML buffers.
-- The group is buffer-local and only visible when filetype == "yaml".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("yaml", "YAML", yaml_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that `yq` (Go version by Mike Farah) is available.
---
--- Notifies the user with install instructions if the binary is not
--- found. Used as a guard in all keymaps that pipe through yq
--- (format, convert, query, sort).
---
--- ```lua
--- if not check_yq() then return end
--- vim.fn.system("yq '.' ", content)
--- ```
---
---@return boolean available `true` if `yq` is executable
---@private
local function check_yq()
	if vim.fn.executable("yq") == 1 then return true end
	vim.notify("Install: brew install yq", vim.log.levels.WARN, { title = "YAML" })
	return false
end

--- Get the entire buffer content as a single string.
---
--- Joins all buffer lines with newline separators. Used as stdin
--- input for yq pipeline commands.
---
--- ```lua
--- local content = get_buffer_content()
--- local result = vim.fn.system("yq '.' ", content)
--- ```
---
---@return string content Buffer content joined with newlines
---@private
local function get_buffer_content()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n")
end

--- Pipe buffer content through a yq expression and return the output.
---
--- Sends the current buffer content to yq via stdin. Returns the
--- result string and a boolean indicating success.
---
--- ```lua
--- local result, ok = yq_pipe(".", nil)           -- identity
--- local result, ok = yq_pipe(".", "-o=json")     -- convert to JSON
--- local result, ok = yq_pipe("sort_keys(..)")    -- sort all keys
--- ```
---
---@param expr string yq expression to evaluate (e.g. `"."`, `"sort_keys(..)"`)
---@param output_flag? string Output format flag (e.g. `"-o=json"`, `"-o=toml"`)
---@return string result Command output (stdout or stderr)
---@return boolean ok `true` if the command exited successfully
---@private
local function yq_pipe(expr, output_flag)
	local content = get_buffer_content()
	local cmd = "yq"
	if output_flag then cmd = cmd .. " " .. output_flag end
	cmd = cmd .. " " .. vim.fn.shellescape(expr)
	local result = vim.fn.system(cmd, content)
	return result, vim.v.shell_error == 0
end

--- Replace the current buffer contents with processed output.
---
--- Splits the output into lines, strips the trailing empty line
--- that yq appends, and replaces all buffer lines atomically.
---
--- ```lua
--- replace_buffer_with(formatted_yaml)
--- ```
---
---@param output string Processed text to replace buffer with
---@return nil
---@private
local function replace_buffer_with(output)
	local lines = vim.split(output, "\n")
	if lines[#lines] == "" then lines[#lines] = nil end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

--- Open text in a read-only scratch split with a given filetype.
---
--- Creates a new scratch buffer, sets the filetype for highlighting,
--- and opens it in a vertical split.
---
--- ```lua
--- open_scratch_vsplit(json_text, "json")
--- open_scratch_vsplit(toml_text, "toml")
--- ```
---
---@param content string Text content for the scratch buffer
---@param ft string Filetype to set on the buffer (for syntax highlighting)
---@return nil
---@private
local function open_scratch_vsplit(content, ft)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALIDATE
--
-- YAML syntax validation via yamllint with relaxed defaults.
-- Errors are displayed in a read-only scratch split.
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate YAML syntax with `yamllint -d relaxed`.
---
--- Saves the buffer before validation. On success, shows a
--- confirmation notification. On failure, opens the error output
--- in a read-only scratch split for inspection.
keys.lang_map("yaml", "n", "<leader>lr", function()
	if vim.fn.executable("yamllint") ~= 1 then
		vim.notify("Install: pip install yamllint", vim.log.levels.WARN, { title = "YAML" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("yamllint -d relaxed " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ Valid YAML", vim.log.levels.INFO, { title = "YAML" })
	else
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n"))
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.cmd.split()
		vim.api.nvim_win_set_buf(0, buf)
	end
end, { desc = icons.ui.Check .. " Validate (yamllint)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT
--
-- YAML pretty-printing and key sorting via yq.
-- Both operations pipe buffer content through yq and replace in-place.
-- ═══════════════════════════════════════════════════════════════════════════

--- Pretty-print (reformat) the current buffer with `yq '.'`.
---
--- Pipes the entire buffer through yq's identity expression, which
--- normalises indentation, quoting, and whitespace. Replaces the
--- buffer content in-place.
keys.lang_map("yaml", "n", "<leader>lp", function()
	if not check_yq() then return end
	local result, ok = yq_pipe(".", nil)
	if ok then
		replace_buffer_with(result)
		vim.notify("Formatted", vim.log.levels.INFO, { title = "YAML" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "YAML" })
	end
end, { desc = yaml_icon .. " Pretty-print" })

--- Sort all keys recursively with `yq 'sort_keys(..)'`.
---
--- Applies a deep recursive key sort to all mapping nodes in the
--- document. Replaces the buffer content in-place.
keys.lang_map("yaml", "n", "<leader>ls", function()
	if not check_yq() then return end
	local result, ok = yq_pipe("sort_keys(..)", nil)
	if ok then
		replace_buffer_with(result)
		vim.notify("Keys sorted", vim.log.levels.INFO, { title = "YAML" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "YAML" })
	end
end, { desc = yaml_icon .. " Sort keys" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONVERSION
--
-- Format conversion via yq's output flags.
-- Results are displayed in read-only vertical scratch splits with
-- appropriate filetype highlighting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert the current YAML to JSON.
---
--- Pipes the buffer through `yq -o=json '.'` and displays the JSON
--- output in a read-only vertical scratch split with `json` filetype
--- for syntax highlighting.
keys.lang_map("yaml", "n", "<leader>lj", function()
	if not check_yq() then return end
	local result, ok = yq_pipe(".", "-o=json")
	if not ok then
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "YAML" })
		return
	end
	open_scratch_vsplit(result, "json")
end, { desc = icons.file.Json .. " To JSON" })

--- Convert the current YAML to TOML.
---
--- Pipes the buffer through `yq -o=toml '.'` and displays the TOML
--- output in a read-only vertical scratch split with `toml` filetype
--- for syntax highlighting.
keys.lang_map("yaml", "n", "<leader>lt", function()
	if not check_yq() then return end
	local result, ok = yq_pipe(".", "-o=toml")
	if not ok then
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "YAML" })
		return
	end
	open_scratch_vsplit(result, "toml")
end, { desc = icons.file.Toml .. " To TOML" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — QUERY & PATH
--
-- Interactive yq expression evaluation and treesitter-based key path
-- extraction for navigating complex YAML documents.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run an interactive yq query on the current buffer.
---
--- Prompts for a yq expression (default `.`), pipes the buffer
--- through it, and displays the result in a read-only vertical
--- scratch split with YAML highlighting.
keys.lang_map("yaml", "n", "<leader>lq", function()
	if not check_yq() then return end
	vim.ui.input({ prompt = "yq expression: ", default = "." }, function(expr)
		if not expr or expr == "" then return end
		local result, ok = yq_pipe(expr, nil)
		if not ok then
			vim.notify("yq error:\n" .. result, vim.log.levels.ERROR, { title = "YAML" })
			return
		end
		open_scratch_vsplit(result, "yaml")
	end)
end, { desc = icons.ui.Search .. " yq query" })

--- Copy the YAML key path at cursor to the system clipboard.
---
--- Walks the treesitter AST upward from the cursor position,
--- collecting key names from `block_mapping_pair` nodes and array
--- indices from `block_sequence` nodes. The resulting dot-separated
--- path (e.g. `deploy.replicas[0].name`) is copied to register `+`.
---
--- Uses treesitter for accurate path extraction — handles nested
--- mappings, sequences, and quoted keys correctly.
keys.lang_map("yaml", "n", "<leader>lc", function()
	local node = vim.treesitter.get_node()
	if not node then
		vim.notify("No treesitter node", vim.log.levels.INFO, { title = "YAML" })
		return
	end

	---@type string[]
	local parts = {}
	---@type TSNode|nil
	local current = node

	while current do
		local parent = current:parent()
		if not parent then break end

		if parent:type() == "block_mapping_pair" then
			-- ── Extract key name from mapping pair ───────────────
			local key_node = parent:field("key")[1]
			if key_node then
				local key = vim.treesitter.get_node_text(key_node, 0):gsub('^"', ""):gsub('"$', "")
				table.insert(parts, 1, key)
			end
		elseif parent:type() == "block_sequence" then
			-- ── Compute array index within sequence ──────────────
			---@type integer
			local idx = 0
			for child in parent:iter_children() do
				if child:id() == current:id() then break end
				if child:named() then idx = idx + 1 end
			end
			table.insert(parts, 1, "[" .. idx .. "]")
		end

		current = parent
	end

	---@type string
	local path = table.concat(parts, ".")
	if path == "" then path = "." end

	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path, vim.log.levels.INFO, { title = "YAML" })
end, { desc = yaml_icon .. " Copy key path" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SCHEMA
--
-- Schema selection via modeline insertion. The yamlls language server
-- reads `# yaml-language-server: $schema=<url>` comments from the
-- first line and applies schema validation accordingly.
-- ═══════════════════════════════════════════════════════════════════════════

--- Select and insert a YAML schema modeline.
---
--- Presents a `vim.ui.select()` menu with common schema presets:
--- - CI/CD: GitHub Actions, GitLab CI, CircleCI
--- - Containers: Docker Compose, Kubernetes, Helm
--- - Automation: Ansible Playbook
--- - Templates: GitHub Issue Template
---
--- Inserts (or replaces) the schema modeline as the first line:
--- `# yaml-language-server: $schema=<url>`
---
--- The yamlls language server detects this comment and applies
--- the schema for validation, completion, and hover documentation.
keys.lang_map("yaml", "n", "<leader>lx", function()
	---@class YamlSchemaPreset
	---@field name string Display label for the schema
	---@field url string JSON Schema URL

	---@type YamlSchemaPreset[]
	local schemas = {
		{ name = "GitHub Actions", url = "https://json.schemastore.org/github-workflow.json" },
		{ name = "GitHub Issue Template", url = "https://json.schemastore.org/github-issue-config.json" },
		{
			name = "Docker Compose",
			url = "https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json",
		},
		{
			name = "Kubernetes",
			url = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.28.0/all.json",
		},
		{ name = "Helm Chart.yaml", url = "https://json.schemastore.org/chart.json" },
		{
			name = "CI: GitLab",
			url = "https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json",
		},
		{ name = "CI: CircleCI", url = "https://json.schemastore.org/circleciconfig.json" },
		{ name = "Ansible Playbook", url = "https://raw.githubusercontent.com/ansible/schemas/main/f/ansible.json" },
	}

	vim.ui.select(
		vim.tbl_map(function(s)
			return s.name
		end, schemas),
		{ prompt = yaml_icon .. " Schema:" },
		function(_, idx)
			if not idx then return end
			local modeline = "# yaml-language-server: $schema=" .. schemas[idx].url
			local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
			if first_line:match("^# yaml%-language%-server:") then
				-- Replace existing modeline
				vim.api.nvim_buf_set_lines(0, 0, 1, false, { modeline })
			else
				-- Insert new modeline at top
				vim.api.nvim_buf_set_lines(0, 0, 0, false, { modeline })
			end
			vim.notify("Schema set: " .. schemas[idx].name, vim.log.levels.INFO, { title = "YAML" })
		end
	)
end, { desc = yaml_icon .. " Select schema" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FOLD
--
-- Quick fold level toggling for navigating deeply nested YAML trees.
-- ═══════════════════════════════════════════════════════════════════════════

--- Cycle fold level: collapse all ↔ expand all.
---
--- If the current fold level is > 0 (some folds open) → collapse all
--- with `zM`. Otherwise → expand all with `zR`. Notifies the new
--- fold state.
keys.lang_map("yaml", "n", "<leader>lf", function()
	if vim.wo.foldlevel > 0 then
		vim.cmd("normal! zM")
		vim.notify("Folds: collapsed", vim.log.levels.INFO, { title = "YAML" })
	else
		vim.cmd("normal! zR")
		vim.notify("Folds: expanded", vim.log.levels.INFO, { title = "YAML" })
	end
end, { desc = yaml_icon .. " Toggle fold" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Document statistics and external reference documentation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show document statistics.
---
--- Analyses the buffer content and reports:
--- - Total line count
--- - Key count (lines matching `key:` pattern)
--- - List item count (lines starting with `-`)
--- - Comment count (lines starting with `#`)
--- - Document count (lines starting with `---`)
---
--- The analysis is regex-based for speed; it does not parse the
--- YAML AST and may over-count in edge cases (e.g. `#` in strings).
keys.lang_map("yaml", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local keys_count = 0
	---@type integer
	local comments = 0
	---@type integer
	local lists = 0
	---@type integer
	local docs = 0

	for _, line in ipairs(lines) do
		if line:match("^%s*#") then
			comments = comments + 1
		elseif line:match("^%s*[%w_%-]+%s*:") then
			keys_count = keys_count + 1
		end
		if line:match("^%s*%-") then lists = lists + 1 end
		if line:match("^%-%-%-") then docs = docs + 1 end
	end

	vim.notify(
		string.format(
			"%s YAML Stats:\n"
				.. "  Lines:      %d\n"
				.. "  Keys:       %d\n"
				.. "  List items: %d\n"
				.. "  Comments:   %d\n"
				.. "  Documents:  %d",
			yaml_icon,
			#lines,
			keys_count,
			lists,
			comments,
			docs
		),
		vim.log.levels.INFO,
		{ title = "YAML" }
	)
end, { desc = icons.diagnostics.Info .. " Stats" })

--- Open YAML / yq reference documentation in the browser.
---
--- Presents a `vim.ui.select()` menu with links to:
--- - YAML Spec 1.2
--- - YAML Cheatsheet (quickref.me)
--- - yq Manual (Mike Farah)
--- - JSON Schema Store
keys.lang_map("yaml", "n", "<leader>lh", function()
	---@class YamlDocRef
	---@field name string Display label for the documentation link
	---@field url string URL to open in the browser

	---@type YamlDocRef[]
	local refs = {
		{ name = "YAML Spec 1.2", url = "https://yaml.org/spec/1.2.2/" },
		{ name = "YAML Cheatsheet", url = "https://quickref.me/yaml.html" },
		{ name = "yq Manual", url = "https://mikefarah.gitbook.io/yq/" },
		{ name = "JSON Schema Store", url = "https://www.schemastore.org/json/" },
	}
	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = yaml_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " YAML reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers YAML-specific alignment presets for mini.align:
-- • yaml_pairs — align key-value pairs on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("yaml") then
		---@type string Alignment preset icon from icons.file
		local yaml_align_icon = icons.file.Yaml

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			yaml_pairs = {
				description = "Align YAML key-value pairs on ':'",
				icon = yaml_align_icon,
				split_pattern = ":",
				category = "data",
				lang = "yaml",
				filetypes = { "yaml" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("yaml", "yaml_pairs")
		align_registry.mark_language_loaded("yaml")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("yaml", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("yaml_pairs"), {
			desc = yaml_align_icon .. "  Align YAML pairs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the YAML-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for YAML                    │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (yamlls server added on require)  │
-- │ SchemaStore.nvim   │ dependency of lspconfig (loaded with yamlls) │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.yaml)           │
-- │ nvim-lint          │ opts merge (linters_by_ft.yaml)              │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for YAML
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- yamlls: yaml-language-server with SchemaStore integration
	-- Provides completions, diagnostics, hover, schema validation,
	-- and format capabilities. SchemaStore.nvim supplies 600+ schemas
	-- merged via `on_new_config` (the built-in schemaStore is disabled
	-- to avoid duplicates).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"b0o/SchemaStore.nvim",
		},
		opts = {
			servers = {
				yamlls = {
					on_new_config = function(new_config)
						new_config.settings = new_config.settings or {}
						new_config.settings.yaml = new_config.settings.yaml or {}
						new_config.settings.yaml.schemas = vim.tbl_deep_extend(
							"force",
							new_config.settings.yaml.schemas or {},
							require("schemastore").yaml.schemas()
						)
					end,
					settings = {
						yaml = {
							validate = true,
							hover = true,
							completion = true,
							format = { enable = true },
							schemaStore = { enable = false, url = "" },
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					yml = "yaml",
					yaml = "yaml",
				},
			})

			-- ── Buffer-local options for YAML files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "yaml" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "# %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures yaml-language-server, yamllint, and prettier are
	-- installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"yaml-language-server",
				"yamllint",
				"prettier",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Prettier: opinionated code formatter for YAML files.
	-- Respects project-local .prettierrc / prettier.config.js.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				yaml = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- yamllint: YAML syntax checker and style enforcer.
	-- Checks indentation, line length, truthy values, key duplicates,
	-- and more. Uses `-d relaxed` preset by default (via keymap).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				yaml = { "yamllint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- yaml: syntax highlighting, folding, text objects, key path
	--       extraction via AST walking
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"yaml",
			},
		},
	},
}
