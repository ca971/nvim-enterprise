---@file lua/langs/terraform.lua
---@description Terraform / OpenTofu — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.terraform"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.ruby               Ruby language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/terraform.lua — Terraform / OpenTofu language support             ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("terraform") → {} if off    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "terraform" / "terraform-    │    ║
--- ║  │  vars" / "hcl"):                                                 │    ║
--- ║  │  ├─ LSP          terraformls (HashiCorp Terraform LS)            │    ║
--- ║  │  ├─ Formatter    terraform_fmt (via conform.nvim)                │    ║
--- ║  │  ├─ Linter       tflint (via nvim-lint)                          │    ║
--- ║  │  ├─ Treesitter   terraform · hcl parsers                         │    ║
--- ║  │  └─ Extras       state/workspace mgmt · graph rendering ·        │    ║
--- ║  │                  resource import · project info analytics        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ CORE      i  Init (4 modes)       r  Plan                    │    ║
--- ║  │  │            R  Apply (3 modes)       v  Validate (JSON diag)   │    ║
--- ║  │  │            d  Destroy (4 modes)                               │    ║
--- ║  │  ├─ STATE     s  State commands picker (7 actions)               │    ║
--- ║  │  ├─ WORKSPACE w  Workspace commands picker (5 actions)           │    ║
--- ║  │  ├─ TEST      t  Terraform test                                  │    ║
--- ║  │  ├─ FORMAT    f  Format (terraform fmt -recursive)               │    ║
--- ║  │  ├─ LINT      l  Lint (tflint --recursive)                       │    ║
--- ║  │  ├─ OUTPUT    o  Output (JSON)                                   │    ║
--- ║  │  ├─ PROVIDERS p  Providers lock picker (5 actions)               │    ║
--- ║  │  ├─ GRAPH     g  Dependency graph (DOT → SVG/PNG rendering)      │    ║
--- ║  │  ├─ CONSOLE   c  Interactive console (terraform console)         │    ║
--- ║  │  ├─ IMPORT    e  Import existing resource (address + ID)         │    ║
--- ║  │  ├─ INFO      I  Project info (version, providers, resource      │    ║
--- ║  │  │               counts, workspace, tools availability)          │    ║
--- ║  │  └─ DOCS      h  Documentation browser (contextual: detects      │    ║
--- ║  │                  resource type → registry link, 8+ static links) │    ║
--- ║  │                                                                  │    ║
--- ║  │  CLI auto-detection (Terraform / OpenTofu):                      │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. tofu executable      → tofu (OpenTofu, preferred)    │    │    ║
--- ║  │  │  2. terraform executable → terraform (HashiCorp)         │    │    ║
--- ║  │  │  3. nil                  → user notification             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Initialization guard:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Plan / Apply check for .terraform/ directory before     │    │    ║
--- ║  │  │  execution. If missing, prompts user to run init first.  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Graph rendering pipeline:                                       │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. terraform graph → DOT source (displayed in buffer)   │    │    ║
--- ║  │  │  2. If `dot` available → prompt: SVG or PNG rendering    │    │    ║
--- ║  │  │  3. Render via `dot -Tsvg/-Tpng` → open result           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Validate JSON diagnostics parsing:                              │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. terraform validate -json → parse response            │    │    ║
--- ║  │  │  2. valid=true → success notification                    │    │    ║
--- ║  │  │  3. diagnostics[] → formatted error messages             │    │    ║
--- ║  │  │  4. JSON parse failure → fallback to shell_error check   │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Project info analytics:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Scans all *.tf files in CWD and counts:                 │    │    ║
--- ║  │  │  • resource blocks   • data source blocks                │    │    ║
--- ║  │  │  • module blocks     • variable blocks                   │    │    ║
--- ║  │  │  • output blocks     • total .tf file count              │    │    ║
--- ║  │  │  Also checks 7 tools: terraform, tofu, tflint, tfsec,    │    │    ║
--- ║  │  │  checkov, infracost, terragrunt                          │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType terraform / terraform-vars / hcl):  ║
--- ║  • colorcolumn=120, textwidth=120  (HCL convention)                      ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="# %s"           (HCL uses # comments)                  ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .tf                → terraform                                        ║
--- ║  • .tfvars            → terraform-vars                                   ║
--- ║  • .hcl               → hcl                                              ║
--- ║  • .tfstate           → json                                             ║
--- ║  • .terraformrc       → hcl                                              ║
--- ║  • terraform.rc       → hcl                                              ║
--- ║  • .terraform.lock.hcl → hcl                                             ║
--- ║  • *.tfbackend        → hcl                                              ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  • Filetype detection and buffer options are registered at the TOP       ║
--- ║    LEVEL (outside lazy specs) to guarantee execution before any          ║
--- ║    FileType event fires, regardless of lazy.nvim init order.             ║
--- ║  • OpenTofu (`tofu`) is preferred over HashiCorp `terraform` when        ║
--- ║    both are available (open-source-first approach).                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Terraform support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("terraform") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Terraform Nerd Font icon (trailing whitespace stripped)
local tf_icon = icons.lang.terraform:gsub("%s+$", "")

---@type string[] Filetypes covered by this module
local tf_fts = { "terraform", "terraform-vars" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for Terraform-family filetypes.
-- Both filetypes share the same icon and keymap prefix.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("terraform", "Terraform", tf_icon)
keys.lang_group("terraform-vars", "Terraform Vars", tf_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Terraform / OpenTofu CLI binary.
---
--- Resolution order:
--- 1. `tofu` → OpenTofu (open-source fork, preferred)
--- 2. `terraform` → HashiCorp Terraform
--- 3. `nil` → not found
---
--- ```lua
--- local cmd = tf_cmd()
--- if cmd then
---   vim.cmd.terminal(cmd .. " plan")
--- end
--- ```
---
---@return string|nil cmd The CLI binary name, or `nil` if not found
---@private
local function tf_cmd()
	if vim.fn.executable("tofu") == 1 then return "tofu" end
	if vim.fn.executable("terraform") == 1 then return "terraform" end
	return nil
end

--- Detect the CLI and notify the user if not found.
---
--- Wraps `tf_cmd()` with a user-facing error notification.
--- All keymaps should call this instead of `tf_cmd()` directly
--- to ensure consistent error messaging.
---
---@return string|nil cmd The CLI binary name, or `nil` (with notification)
---@private
local function check_tf()
	local cmd = tf_cmd()
	if not cmd then vim.notify("terraform/tofu not found in PATH", vim.log.levels.ERROR, { title = "Terraform" }) end
	return cmd
end

--- Check whether the project has been initialized (`.terraform/` exists).
---
--- Plan and Apply require initialization. This guard prevents confusing
--- error messages from the CLI by checking upfront.
---
---@return boolean initialized `true` if `.terraform/` directory exists in CWD
---@private
local function is_initialized()
	return vim.fn.isdirectory(vim.fn.getcwd() .. "/.terraform") == 1
end

--- Guard that checks initialization and notifies if needed.
---
--- Combines `check_tf()` and `is_initialized()` for keymaps that
--- require both the CLI and an initialized project.
---
---@return string|nil cmd The CLI binary name, or `nil` (with notification)
---@private
local function check_tf_initialized()
	local cmd = check_tf()
	if not cmd then return nil end
	if not is_initialized() then
		vim.notify("Run init first (terraform init)", vim.log.levels.WARN, { title = "Terraform" })
		return nil
	end
	return cmd
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILETYPE DETECTION (TOP LEVEL)
--
-- Registered at module load time (outside lazy specs) to guarantee
-- execution before any FileType event fires, regardless of lazy.nvim
-- init order. This is a deliberate design decision — see header docs.
-- ═══════════════════════════════════════════════════════════════════════════

vim.filetype.add({
	extension = {
		tf = "terraform",
		tfvars = "terraform-vars",
		hcl = "hcl",
		tfstate = "json",
	},
	filename = {
		[".terraformrc"] = "hcl",
		["terraform.rc"] = "hcl",
		[".terraform.lock.hcl"] = "hcl",
	},
	pattern = {
		[".*%.tfbackend$"] = "hcl",
	},
})

-- ═══════════════════════════════════════════════════════════════════════════
-- BUFFER OPTIONS (TOP LEVEL)
--
-- Registered at module load time (outside lazy specs) for the same
-- reason as filetype detection above. Applies to terraform,
-- terraform-vars, and hcl filetypes.
-- ═══════════════════════════════════════════════════════════════════════════

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("TerraformBufferOptions", { clear = true }),
	pattern = { "terraform", "terraform-vars", "hcl" },
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

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CORE WORKFLOW (init → plan → apply → validate → destroy)
--
-- The fundamental Terraform workflow. Init offers 4 modes, Apply offers
-- 3 modes, and Destroy offers 4 modes — all via `vim.ui.select()`.
-- Plan and Apply check for initialization before execution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the Terraform working directory.
---
--- Presents 4 init modes:
--- - `init`                — standard initialization
--- - `init -upgrade`       — upgrade provider versions
--- - `init -reconfigure`   — reconfigure backend
--- - `init -migrate-state` — migrate state to new backend
keys.lang_map(tf_fts, "n", "<leader>li", function()
	local cmd = check_tf()
	if not cmd then return end

	vim.ui.select(
		{ "init", "init -upgrade", "init -reconfigure", "init -migrate-state" },
		{ prompt = tf_icon .. " Init mode:" },
		function(mode)
			if not mode then return end
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " " .. mode)
		end
	)
end, { desc = tf_icon .. " Init" })

--- Run `terraform plan` (execution plan preview).
---
--- Checks for initialization before execution. Saves the buffer
--- before planning to ensure the CLI operates on the latest source.
keys.lang_map(tf_fts, "n", "<leader>lr", function()
	local cmd = check_tf_initialized()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " plan")
end, { desc = icons.ui.Play .. " Plan" })

--- Apply infrastructure changes.
---
--- Checks for initialization, then presents 3 apply modes:
--- - **Interactive** — standard apply with confirmation prompt
--- - **Auto-approve** — skip confirmation (use with caution)
--- - **From plan file** — apply a previously saved plan file
keys.lang_map(tf_fts, "n", "<leader>lR", function()
	local cmd = check_tf_initialized()
	if not cmd then return end
	vim.cmd("silent! write")

	vim.ui.select({
		"Apply (interactive)",
		"Apply -auto-approve",
		"Apply from plan file…",
	}, { prompt = tf_icon .. " Apply:" }, function(_, idx)
		if not idx then return end

		if idx == 1 then
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " apply")
		elseif idx == 2 then
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " apply -auto-approve")
		elseif idx == 3 then
			vim.ui.input({ prompt = "Plan file: ", completion = "file" }, function(plan)
				if not plan or plan == "" then return end
				vim.cmd.split()
				vim.cmd.terminal(cmd .. " apply " .. vim.fn.shellescape(plan))
			end)
		end
	end)
end, { desc = icons.ui.Play .. " Apply" })

--- Validate the Terraform configuration.
---
--- Runs `terraform validate -json` and parses the JSON response:
--- 1. `valid = true` → success notification
--- 2. `diagnostics[]` → formatted error messages with severity
--- 3. JSON parse failure → fallback to `shell_error` check
keys.lang_map(tf_fts, "n", "<leader>lv", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd("silent! write")

	local result = vim.fn.system(cmd .. " validate -json 2>&1")
	local ok_parse, parsed = pcall(vim.fn.json_decode, result)

	if ok_parse and parsed and parsed.valid then
		vim.notify("✓ Configuration valid", vim.log.levels.INFO, { title = "Terraform" })
	elseif ok_parse and parsed and parsed.diagnostics then
		---@type string[]
		local msgs = {}
		for _, diag in ipairs(parsed.diagnostics) do
			msgs[#msgs + 1] = string.format("[%s] %s: %s", diag.severity, diag.summary, diag.detail or "")
		end
		vim.notify("✗ Validation errors:\n" .. table.concat(msgs, "\n"), vim.log.levels.ERROR, { title = "Terraform" })
	else
		-- Fallback: JSON parsing failed, use shell exit code
		if vim.v.shell_error == 0 then
			vim.notify("✓ Configuration valid", vim.log.levels.INFO, { title = "Terraform" })
		else
			vim.notify("✗ Errors:\n" .. result, vim.log.levels.ERROR, { title = "Terraform" })
		end
	end
end, { desc = icons.ui.Check .. " Validate" })

--- Destroy infrastructure resources.
---
--- Presents 4 destroy modes:
--- - **Plan destroy** — dry run showing what would be destroyed
--- - **Interactive** — standard destroy with confirmation
--- - **Auto-approve** — skip confirmation (use with extreme caution)
--- - **Specific target** — destroy a single resource by address
keys.lang_map(tf_fts, "n", "<leader>ld", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd("silent! write")

	vim.ui.select({
		"Plan destroy (dry run)",
		"Destroy (interactive)",
		"Destroy -auto-approve",
		"Destroy specific target…",
	}, { prompt = tf_icon .. " Destroy:" }, function(_, idx)
		if not idx then return end

		if idx == 1 then
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " plan -destroy")
		elseif idx == 2 then
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " destroy")
		elseif idx == 3 then
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " destroy -auto-approve")
		elseif idx == 4 then
			vim.ui.input({ prompt = "Target resource: " }, function(target)
				if not target or target == "" then return end
				vim.cmd.split()
				vim.cmd.terminal(cmd .. " destroy -target=" .. vim.fn.shellescape(target))
			end)
		end
	end)
end, { desc = icons.diagnostics.Warn .. " Destroy" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATE
--
-- Terraform state management via a command picker.
-- Supports 7 state operations including list, show, pull, rm, mv,
-- replace-provider, and refresh.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the state commands picker.
---
--- Presents 7 state operations:
--- - `list`             — list all resources in state
--- - `show`             — show a specific resource (prompted)
--- - `pull`             — show raw state JSON
--- - `rm`               — remove a resource from state (prompted)
--- - `mv`               — move/rename a resource in state (prompted)
--- - `replace-provider` — replace a provider in state (prompted)
--- - `refresh`          — refresh state against real infrastructure
keys.lang_map(tf_fts, "n", "<leader>ls", function()
	local cmd = check_tf()
	if not cmd then return end

	---@type { name: string, cmd: string, prompt?: string }[]
	local actions = {
		{ name = "list", cmd = cmd .. " state list" },
		{ name = "show…", cmd = cmd .. " state show", prompt = "Resource address: " },
		{ name = "pull (show raw)", cmd = cmd .. " state pull" },
		{ name = "rm…", cmd = cmd .. " state rm", prompt = "Resource address: " },
		{
			name = "mv…",
			cmd = cmd .. " state mv",
			prompt = "Source → Dest (space-separated): ",
		},
		{ name = "replace-provider…", cmd = cmd .. " state replace-provider", prompt = "Old → New: " },
		{ name = "refresh", cmd = cmd .. " apply -refresh-only" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = tf_icon .. " State:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = action.prompt }, function(input)
					if not input or input == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. input)
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = tf_icon .. " State" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — WORKSPACE
--
-- Terraform workspace management via a command picker.
-- Supports listing, showing current, creating new, selecting, and
-- deleting workspaces. The select action shows all available workspaces
-- and the delete action filters out the current workspace.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the workspace commands picker.
---
--- Presents 5 workspace operations:
--- - `list`   — show all workspaces
--- - `show`   — display current workspace name
--- - `new`    — create a new workspace (prompted)
--- - `select` — switch to an existing workspace (picker)
--- - `delete` — delete a workspace (picker, excludes current)
keys.lang_map(tf_fts, "n", "<leader>lw", function()
	local cmd = check_tf()
	if not cmd then return end

	---@type string
	local current_ws = vim.fn.system(cmd .. " workspace show 2>/dev/null"):gsub("%s+$", "")

	-- Parse workspace list
	local ws_result = vim.fn.system(cmd .. " workspace list 2>/dev/null")
	---@type string[]
	local workspaces = {}
	for line in ws_result:gmatch("[^\r\n]+") do
		local clean = line:gsub("^[%s%*]+", ""):gsub("%s+$", "")
		if clean ~= "" then workspaces[#workspaces + 1] = clean end
	end

	---@type { name: string, action: string, cmd?: string }[]
	local actions = {
		{ name = "list", action = "cmd", cmd = cmd .. " workspace list" },
		{ name = "show (current: " .. current_ws .. ")", action = "cmd", cmd = cmd .. " workspace show" },
		{ name = "new…", action = "new" },
		{ name = "select…", action = "select" },
		{ name = "delete…", action = "delete" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = tf_icon .. " Workspace:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]

			if action.action == "cmd" then
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			elseif action.action == "new" then
				vim.ui.input({ prompt = "New workspace name: " }, function(name)
					if not name or name == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(cmd .. " workspace new " .. vim.fn.shellescape(name))
				end)
			elseif action.action == "select" then
				vim.ui.select(workspaces, { prompt = tf_icon .. " Select:" }, function(ws)
					if not ws then return end
					vim.fn.system(cmd .. " workspace select " .. vim.fn.shellescape(ws))
					vim.notify("Switched to: " .. ws, vim.log.levels.INFO, { title = "Terraform" })
				end)
			elseif action.action == "delete" then
				local deletable = vim.tbl_filter(function(ws)
					return ws ~= current_ws
				end, workspaces)
				vim.ui.select(deletable, { prompt = tf_icon .. " Delete:" }, function(ws)
					if not ws then return end
					vim.cmd.split()
					vim.cmd.terminal(cmd .. " workspace delete " .. vim.fn.shellescape(ws))
				end)
			end
		end
	)
end, { desc = tf_icon .. " Workspace" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST / FORMAT / LINT
--
-- Testing, formatting, and static analysis.
-- Test uses Terraform's built-in test framework (HCL test files).
-- Format runs recursively on the project. Lint uses tflint.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run Terraform tests.
---
--- Executes `terraform test` which discovers and runs `.tftest.hcl`
--- files in the project. Requires Terraform 1.6+.
keys.lang_map(tf_fts, "n", "<leader>lt", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " test")
end, { desc = icons.dev.Test .. " Test" })

--- Format all Terraform files recursively.
---
--- Runs `terraform fmt -recursive` which formats all `.tf` and
--- `.tfvars` files in the directory tree. Reloads the current
--- buffer to reflect changes.
keys.lang_map(tf_fts, "n", "<leader>lf", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd("silent! write")
	local result = vim.fn.system(cmd .. " fmt -recursive 2>&1")
	vim.cmd.edit()
	if vim.v.shell_error == 0 then
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Terraform" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "Terraform" })
	end
end, { desc = tf_icon .. " Format" })

--- Run tflint recursively on the project.
---
--- Executes `tflint --recursive` which checks all Terraform modules
--- in the directory tree. Requires `tflint` to be installed
--- (notifies with install instructions if not found).
keys.lang_map(tf_fts, "n", "<leader>ll", function()
	if vim.fn.executable("tflint") ~= 1 then
		vim.notify("Install: brew install tflint", vim.log.levels.WARN, { title = "Terraform" })
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("tflint --recursive")
end, { desc = tf_icon .. " Lint (tflint)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — OUTPUT / PROVIDERS / GRAPH / CONSOLE / IMPORT
--
-- Advanced Terraform operations: output inspection, provider management,
-- dependency graph visualization, interactive console, and resource import.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Terraform outputs in JSON format.
---
--- Runs `terraform output -json` which displays all output values
--- from the current state in JSON format.
keys.lang_map(tf_fts, "n", "<leader>lo", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " output -json")
end, { desc = tf_icon .. " Output" })

--- Open the provider lock commands picker.
---
--- Presents 5 provider operations:
--- - **All platforms** — lock for linux_amd64 + darwin_amd64 + darwin_arm64
--- - **linux_amd64** — lock for Linux x86_64 only
--- - **darwin_amd64** — lock for macOS Intel only
--- - **darwin_arm64** — lock for macOS Apple Silicon only
--- - **mirror** — mirror providers to a local directory (prompted)
keys.lang_map(tf_fts, "n", "<leader>lp", function()
	local cmd = check_tf()
	if not cmd then return end

	vim.ui.select({
		"providers lock (all platforms)",
		"providers lock -platform=linux_amd64",
		"providers lock -platform=darwin_amd64",
		"providers lock -platform=darwin_arm64",
		"providers mirror…",
	}, { prompt = tf_icon .. " Providers:" }, function(_, idx)
		if not idx then return end

		if idx == 1 then
			vim.cmd.split()
			vim.cmd.terminal(
				cmd .. " providers lock" .. " -platform=linux_amd64" .. " -platform=darwin_amd64" .. " -platform=darwin_arm64"
			)
		elseif idx >= 2 and idx <= 4 then
			---@type string[]
			local platforms = { "linux_amd64", "darwin_amd64", "darwin_arm64" }
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " providers lock -platform=" .. platforms[idx - 1])
		else
			vim.ui.input({ prompt = "Mirror directory: ", completion = "dir" }, function(dir)
				if not dir or dir == "" then return end
				vim.cmd.split()
				vim.cmd.terminal(cmd .. " providers mirror " .. vim.fn.shellescape(dir))
			end)
		end
	end)
end, { desc = icons.ui.Lock .. " Providers" })

--- Generate and display the Terraform dependency graph.
---
--- Pipeline:
--- 1. Runs `terraform graph` → DOT source output
--- 2. Opens DOT source in a vertical split (filetype = "dot")
--- 3. If `dot` (Graphviz) is available → prompts for rendering:
---    - View DOT source (default)
---    - Render to SVG → open in browser/viewer
---    - Render to PNG → open in browser/viewer
keys.lang_map(tf_fts, "n", "<leader>lg", function()
	local cmd = check_tf()
	if not cmd then return end

	local result = vim.fn.system(cmd .. " graph 2>&1")
	if vim.v.shell_error ~= 0 then
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "Terraform" })
		return
	end

	-- ── Display DOT source in a scratch buffer ───────────────────
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n"))
	vim.api.nvim_set_option_value("filetype", "dot", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)

	-- ── Optional: render to SVG/PNG if Graphviz is available ─────
	if vim.fn.executable("dot") == 1 then
		vim.schedule(function()
			vim.ui.select(
				{ "View DOT source", "Render to SVG", "Render to PNG" },
				{ prompt = tf_icon .. " Graph output:" },
				function(_, idx2)
					if not idx2 or idx2 == 1 then return end

					---@type string
					local ext = idx2 == 2 and "svg" or "png"
					local output = vim.fn.getcwd() .. "/terraform-graph." .. ext
					vim.fn.system(
						"echo " .. vim.fn.shellescape(result) .. " | dot -T" .. ext .. " -o " .. vim.fn.shellescape(output)
					)
					vim.notify("Rendered: " .. output, vim.log.levels.INFO, { title = "Terraform" })
					vim.ui.open(output)
				end
			)
		end)
	end
end, { desc = tf_icon .. " Graph" })

--- Open the Terraform interactive console.
---
--- Runs `terraform console` which provides an interactive REPL
--- for evaluating Terraform expressions against the current state
--- and configuration.
keys.lang_map(tf_fts, "n", "<leader>lc", function()
	local cmd = check_tf()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " console")
end, { desc = icons.ui.Terminal .. " Console" })

--- Import an existing resource into Terraform state.
---
--- Prompts for two inputs:
--- 1. **Resource address** — the Terraform address (e.g. `aws_instance.web`)
--- 2. **Resource ID** — the cloud provider's resource identifier
---
--- Runs `terraform import <address> <id>` to associate the existing
--- resource with the Terraform configuration.
keys.lang_map(tf_fts, "n", "<leader>le", function()
	local cmd = check_tf()
	if not cmd then return end

	vim.ui.input({ prompt = "Resource address (e.g. aws_instance.web): " }, function(addr)
		if not addr or addr == "" then return end
		vim.ui.input({ prompt = "Resource ID: " }, function(id)
			if not id or id == "" then return end
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " import " .. vim.fn.shellescape(addr) .. " " .. vim.fn.shellescape(id))
		end)
	end)
end, { desc = tf_icon .. " Import resource" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PROJECT INFO
--
-- Comprehensive project analytics: CLI version, provider versions,
-- resource/data/module/variable/output counts, workspace, and
-- tool availability (7 tools).
-- ═══════════════════════════════════════════════════════════════════════════

--- Display comprehensive Terraform project information.
---
--- Collects and displays:
--- - CLI binary name and version
--- - Current working directory
--- - Initialization status
--- - Provider versions (from `terraform version -json`)
--- - Current workspace (if initialized)
--- - Resource analytics: counts of resource, data, module, variable,
---   and output blocks across all `.tf` files
--- - Tool availability: terraform, tofu, tflint, tfsec, checkov,
---   infracost, terragrunt
keys.lang_map(tf_fts, "n", "<leader>lI", function()
	local cmd = tf_cmd() or "terraform"

	---@type string[]
	local info = { tf_icon .. " Terraform Info:", "" }
	info[#info + 1] = "  CLI:         " .. cmd
	info[#info + 1] = "  CWD:         " .. vim.fn.getcwd()
	info[#info + 1] = "  Initialized: " .. (is_initialized() and "✓" or "✗")

	-- ── Version and providers ────────────────────────────────────
	local version_json = vim.fn.system(cmd .. " version -json 2>/dev/null")
	if version_json ~= "" and vim.v.shell_error == 0 then
		local ok, parsed = pcall(vim.fn.json_decode, version_json)
		if ok and parsed then
			info[#info + 1] = "  Version:     " .. (parsed.terraform_version or "?")
			if parsed.provider_selections then
				info[#info + 1] = ""
				info[#info + 1] = "  Providers:"
				for provider, ver in pairs(parsed.provider_selections) do
					info[#info + 1] = "    " .. provider .. " = " .. ver
				end
			end
		end
	end

	-- ── Current workspace ────────────────────────────────────────
	if is_initialized() then
		---@type string
		local ws = vim.fn.system(cmd .. " workspace show 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Workspace:   " .. ws
	end

	-- ── Resource analytics ───────────────────────────────────────
	---@type string[]
	local tf_files = vim.fn.glob("*.tf", false, true)

	---@type integer
	local resources = 0
	---@type integer
	local data_sources = 0
	---@type integer
	local modules = 0
	---@type integer
	local variables = 0
	---@type integer
	local outputs = 0

	for _, f in ipairs(tf_files) do
		local lines = vim.fn.readfile(f)
		for _, line in ipairs(lines) do
			if line:match('^resource%s+"') then
				resources = resources + 1
			elseif line:match('^data%s+"') then
				data_sources = data_sources + 1
			elseif line:match('^module%s+"') then
				modules = modules + 1
			elseif line:match("^variable%s+") then
				variables = variables + 1
			elseif line:match("^output%s+") then
				outputs = outputs + 1
			end
		end
	end

	info[#info + 1] = ""
	info[#info + 1] = "  Resources:   " .. resources
	info[#info + 1] = "  Data:        " .. data_sources
	info[#info + 1] = "  Modules:     " .. modules
	info[#info + 1] = "  Variables:   " .. variables
	info[#info + 1] = "  Outputs:     " .. outputs
	info[#info + 1] = "  TF files:    " .. #tf_files

	-- ── Tool availability ────────────────────────────────────────
	---@type string[]
	local tools = { "terraform", "tofu", "tflint", "tfsec", "checkov", "infracost", "terragrunt" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Terraform" })
end, { desc = icons.diagnostics.Info .. " Project info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Terraform documentation access with contextual resource type detection.
-- If the cursor is on a `resource` or `data` block, prepends a direct
-- link to the Terraform Registry page for that resource type.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Terraform documentation in the system browser.
---
--- Contextual detection: if the cursor is on a line containing
--- `resource "aws_instance"` or `data "aws_ami"`, extracts the
--- resource type and prepends a direct Registry link.
---
--- Available documentation links (8 static + 1 contextual):
--- - Registry: <resource_type> (contextual, only on resource lines)
--- - Terraform Docs (main documentation)
--- - Terraform Registry (provider/module search)
--- - HCL Syntax (language reference)
--- - Provider: AWS / Azure / GCP / Kubernetes
--- - Functions Reference
keys.lang_map(tf_fts, "n", "<leader>lh", function()
	local line = vim.api.nvim_get_current_line()

	-- ── Contextual resource type detection ───────────────────────
	---@type string|nil
	local resource_type = line:match('^resource%s+"([%w_]+)"') or line:match('^data%s+"([%w_]+)"')

	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Terraform Docs", url = "https://developer.hashicorp.com/terraform/docs" },
		{ name = "Terraform Registry", url = "https://registry.terraform.io/" },
		{ name = "HCL Syntax", url = "https://developer.hashicorp.com/terraform/language/syntax" },
		{ name = "Provider: AWS", url = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs" },
		{ name = "Provider: Azure", url = "https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs" },
		{ name = "Provider: GCP", url = "https://registry.terraform.io/providers/hashicorp/google/latest/docs" },
		{ name = "Provider: Kubernetes", url = "https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs" },
		{ name = "Functions Reference", url = "https://developer.hashicorp.com/terraform/language/functions" },
	}

	-- Prepend contextual registry link if a resource type was detected
	if resource_type then
		---@type string|nil
		local provider = resource_type:match("^(%w+)_")
		if provider then
			table.insert(refs, 1, {
				name = "Registry: " .. resource_type,
				url = "https://registry.terraform.io/providers/hashicorp/"
					.. provider
					.. "/latest/docs/resources/"
					.. resource_type:gsub("^" .. provider .. "_", ""),
			})
		end
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = tf_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Terraform-specific alignment presets for mini.align:
-- • terraform_attrs — align resource attribute assignments on "="
--
-- Applied to both terraform and hcl filetypes.
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("terraform") then
		---@type string Alignment preset icon from icons.dev
		local tf_align_icon = icons.dev.Terraform

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			terraform_attrs = {
				description = "Align Terraform resource attributes on '='",
				icon = tf_align_icon,
				split_pattern = "=",
				category = "devops",
				lang = "terraform",
				filetypes = { "terraform", "hcl" },
			},
		})

		-- ── Set default filetype mappings ─────────────────────────────
		align_registry.set_ft_mapping("terraform", "terraform_attrs")
		align_registry.set_ft_mapping("hcl", "terraform_attrs")
		align_registry.mark_language_loaded("terraform")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map({ "terraform", "hcl" }, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("terraform_attrs"), {
			desc = tf_align_icon .. "  Align Terraform attrs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Terraform-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Terraform              │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (terraformls server, NO init)    │
-- │ mason.nvim         │ opts merge (terraform-ls + tflint ensured)  │
-- │ conform.nvim       │ opts merge (terraform_fmt for 3 filetypes)  │
-- │ nvim-lint          │ opts merge (tflint for terraform)           │
-- │ nvim-treesitter    │ opts merge (terraform + hcl parsers)        │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Design note:
-- • Filetype detection and buffer options are NOT in the lspconfig
--   init() — they are registered at the top level of this module to
--   guarantee execution before any FileType event fires, regardless
--   of lazy.nvim's plugin initialization order.
-- • The lspconfig spec uses opts-only (no init function) because
--   all init-time work is done at the top level.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Terraform
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- terraformls: HashiCorp Terraform Language Server (completions,
	-- diagnostics, hover, go-to-definition, formatting).
	-- NOTE: opts only — no init() (filetype detection is top-level).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				terraformls = {},
			},
		},
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures terraform-ls and tflint are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"terraform-ls",
				"tflint",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- terraform_fmt: built-in HCL formatter for all Terraform filetypes.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				terraform = { "terraform_fmt" },
				["terraform-vars"] = { "terraform_fmt" },
				hcl = { "terraform_fmt" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- tflint: Terraform linter (provider-specific rules, best practices).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				terraform = { "tflint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- terraform: HCL syntax highlighting, folding, indentation
	-- hcl:       generic HCL files (.hcl, .terraformrc, etc.)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"terraform",
				"hcl",
			},
		},
	},
}
