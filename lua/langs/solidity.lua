---@file lua/langs/solidity.lua
---@description Solidity — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.solidity"
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
--- ║  langs/solidity.lua — Solidity language support                          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("solidity") → {} if off     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "solidity"):                 │    ║
--- ║  │  ├─ LSP          solidity_ls_nomicfoundation (conditional)       │    ║
--- ║  │  ├─ Formatter    forge fmt (Foundry) or prettier (Hardhat)       │    ║
--- ║  │  ├─ Linter       solhint (conditional, requires global install)  │    ║
--- ║  │  ├─ Treesitter   solidity parser (syntax + folding)              │    ║
--- ║  │  ├─ DAP          manual (no standard Mason adapter)              │    ║
--- ║  │  └─ Extras       gas reports · contract flattening · commands    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ BUILD     b  Compile contracts (framework-aware)             │    ║
--- ║  │  ├─ TEST      t  Run tests (forge test / hardhat test)           │    ║
--- ║  │  ├─ DEPLOY    r  Deploy to local network                         │    ║
--- ║  │  │            s  Forge script (Foundry only)                     │    ║
--- ║  │  ├─ ANALYSIS  g  Gas report         f  Flatten contract          │    ║
--- ║  │  │            l  Lint (solhint)                                  │    ║
--- ║  │  ├─ DEPS      p  Install dependency (forge install / npm)        │    ║
--- ║  │  ├─ COMMANDS  c  Commands picker (framework-specific)            │    ║
--- ║  │  ├─ DEBUG     d  Debug (manual DAP continue)                     │    ║
--- ║  │  ├─ INFO      i  Project info + tools availability               │    ║
--- ║  │  └─ DOCS      h  Documentation browser (Solidity, Foundry,       │    ║
--- ║  │                  Hardhat, OpenZeppelin, Solidity by Example)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Framework auto-detection:                                       │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. foundry.toml exists      → "foundry" (Forge/Anvil)   │    │    ║
--- ║  │  │  2. hardhat.config.ts/.js    → "hardhat"                 │    │    ║
--- ║  │  │  3. nil                      → user notification         │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Package runner auto-detection:                                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. pnpm-lock.yaml → pnpm                                │    │    ║
--- ║  │  │  2. yarn.lock      → yarn                                │    │    ║
--- ║  │  │  3. bun.lockb      → bun                                 │    │    ║
--- ║  │  │  4. fallback       → npx                                 │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Formatter resolution:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. forge executable → forge fmt (stdin, Foundry)        │    │    ║
--- ║  │  │  2. prettier         → prettier (with solidity plugin)   │    │    ║
--- ║  │  │  3. none             → no formatter configured           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Commands picker (framework-specific):                           │    ║
--- ║  │  ┌─────────────────────┬────────────────────────────────────┐    │    ║
--- ║  │  │  Foundry (8 cmds)   │  Hardhat (5 cmds)                  │    │    ║
--- ║  │  │  build · test · fmt │  compile · test · node             │    │    ║
--- ║  │  │  snapshot · coverage│  clean · flatten                   │    │    ║
--- ║  │  │  inspect · anvil    │                                    │    │    ║
--- ║  │  │  cast call          │                                    │    │    ║
--- ║  │  └─────────────────────┴────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType solidity):                          ║
--- ║  • colorcolumn=120, textwidth=120  (common Solidity convention)          ║
--- ║  • tabstop=4, shiftwidth=4         (4-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="// %s"           (Solidity uses // comments)           ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .sol → solidity                                                       ║
--- ║                                                                          ║
--- ║  Conditional loading:                                                    ║
--- ║  • LSP only configured when `nomicfoundation-solidity-ls` is in PATH     ║
--- ║  • Formatter: forge fmt OR prettier (whichever is available)             ║
--- ║  • Linter: solhint only when executable is in PATH                       ║
--- ║  • No Mason spec (nomicfoundation-solidity-ls not in Mason registry)     ║
--- ║  • DAP: no standard adapter — manual configuration required              ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Solidity support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("solidity") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Solidity Nerd Font icon (trailing whitespace stripped)
local sol_icon = icons.lang.solidity:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Solidity buffers.
-- The group is buffer-local and only visible when filetype == "solidity".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("solidity", "Solidity", sol_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Solidity development framework used by the current project.
---
--- Resolution order:
--- 1. `foundry.toml` in CWD → `"foundry"` (Forge / Anvil / Cast)
--- 2. `hardhat.config.ts` or `hardhat.config.js` → `"hardhat"`
--- 3. `nil` → no framework detected
---
--- ```lua
--- local fw = detect_framework()
--- if fw == "foundry" then
---   vim.cmd.terminal("forge build")
--- end
--- ```
---
---@return "foundry"|"hardhat"|nil framework The detected framework, or `nil`
---@private
local function detect_framework()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/foundry.toml") == 1 then
		return "foundry"
	elseif
		vim.fn.filereadable(cwd .. "/hardhat.config.ts") == 1 or vim.fn.filereadable(cwd .. "/hardhat.config.js") == 1
	then
		return "hardhat"
	end
	return nil
end

--- Detect the Node.js package runner for the current project.
---
--- Resolution order (based on lockfile presence):
--- 1. `pnpm-lock.yaml` → `"pnpm"`
--- 2. `yarn.lock`       → `"yarn"`
--- 3. `bun.lockb`       → `"bun"`
--- 4. Fallback           → `"npx"`
---
--- Used by Hardhat commands to ensure the correct package manager
--- context (e.g. `pnpm hardhat compile` vs `npx hardhat compile`).
---
---@return string runner The package runner command (`"pnpm"`, `"yarn"`, `"bun"`, or `"npx"`)
---@private
local function pkg_runner()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/pnpm-lock.yaml") == 1 then
		return "pnpm"
	elseif vim.fn.filereadable(cwd .. "/yarn.lock") == 1 then
		return "yarn"
	elseif vim.fn.filereadable(cwd .. "/bun.lockb") == 1 then
		return "bun"
	end
	return "npx"
end

--- Notify the user that no Solidity framework was detected.
---
--- Centralizes the warning notification to avoid repetition across
--- keymaps that require Foundry or Hardhat.
---
---@return nil
---@private
local function notify_no_framework()
	vim.notify("No foundry.toml or hardhat.config found", vim.log.levels.WARN, { title = "Solidity" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / TEST
--
-- Smart contract compilation and testing using the auto-detected
-- framework. Foundry uses `forge`, Hardhat uses the detected
-- package runner.
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile all contracts in the project.
---
--- Adapts the compile command to the detected framework:
--- - **Foundry** → `forge build`
--- - **Hardhat** → `<runner> hardhat compile`
--- - **None** → notification
keys.lang_map("solidity", "n", "<leader>lb", function()
	local fw = detect_framework()
	vim.cmd("silent! write")

	if fw == "foundry" then
		vim.cmd.split()
		vim.cmd.terminal("forge build")
	elseif fw == "hardhat" then
		vim.cmd.split()
		vim.cmd.terminal(pkg_runner() .. " hardhat compile")
	else
		notify_no_framework()
	end
end, { desc = icons.dev.Build .. " Compile" })

--- Run the test suite.
---
--- Adapts the test command to the detected framework:
--- - **Foundry** → `forge test -vvv` (triple verbosity for traces)
--- - **Hardhat** → `<runner> hardhat test`
--- - **None** → notification
keys.lang_map("solidity", "n", "<leader>lt", function()
	local fw = detect_framework()
	vim.cmd("silent! write")

	if fw == "foundry" then
		vim.cmd.split()
		vim.cmd.terminal("forge test -vvv")
	elseif fw == "hardhat" then
		vim.cmd.split()
		vim.cmd.terminal(pkg_runner() .. " hardhat test")
	else
		notify_no_framework()
	end
end, { desc = icons.dev.Test .. " Test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPLOY / SCRIPT
--
-- Contract deployment and Forge script execution.
-- Deploy targets the local network (localhost:8545 / Anvil).
-- Forge scripts are Foundry-specific (.s.sol files).
-- ═══════════════════════════════════════════════════════════════════════════

--- Deploy contracts to the local network.
---
--- Adapts the deploy command to the detected framework:
--- - **Foundry** → `forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast`
--- - **Hardhat** → `<runner> hardhat run scripts/deploy.ts --network localhost`
--- - **None** → notification
keys.lang_map("solidity", "n", "<leader>lr", function()
	local fw = detect_framework()
	vim.cmd("silent! write")

	if fw == "foundry" then
		vim.cmd.split()
		vim.cmd.terminal("forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast")
	elseif fw == "hardhat" then
		vim.cmd.split()
		vim.cmd.terminal(pkg_runner() .. " hardhat run scripts/deploy.ts --network localhost")
	else
		notify_no_framework()
	end
end, { desc = icons.ui.Play .. " Deploy (local)" })

--- Run the current file as a Forge script.
---
--- Executes `forge script <file> -vvvv` (maximum verbosity).
--- Only available in Foundry projects — notifies if Foundry
--- is not detected.
keys.lang_map("solidity", "n", "<leader>ls", function()
	if detect_framework() ~= "foundry" then
		vim.notify("Forge scripts require Foundry", vim.log.levels.WARN, { title = "Solidity" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("forge script " .. vim.fn.shellescape(file) .. " -vvvv")
end, { desc = sol_icon .. " Forge script" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ANALYSIS (GAS / FLATTEN / LINT)
--
-- Contract analysis tools: gas consumption reports, source flattening
-- for verification, and static analysis via solhint.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate a gas consumption report.
---
--- Adapts to the detected framework:
--- - **Foundry** → `forge test --gas-report`
--- - **Hardhat** → `<runner> hardhat test --gas-reporter`
--- - **None** → notification
keys.lang_map("solidity", "n", "<leader>lg", function()
	local fw = detect_framework()
	vim.cmd("silent! write")

	if fw == "foundry" then
		vim.cmd.split()
		vim.cmd.terminal("forge test --gas-report")
	elseif fw == "hardhat" then
		vim.cmd.split()
		vim.cmd.terminal(pkg_runner() .. " hardhat test --gas-reporter")
	else
		notify_no_framework()
	end
end, { desc = sol_icon .. " Gas report" })

--- Flatten the current contract (inline all imports).
---
--- Runs `forge flatten <file>` which resolves all import paths
--- and outputs a single Solidity file. Useful for Etherscan
--- source verification. Foundry only.
keys.lang_map("solidity", "n", "<leader>lf", function()
	local fw = detect_framework()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	if fw == "foundry" then
		vim.cmd.split()
		vim.cmd.terminal("forge flatten " .. vim.fn.shellescape(file))
	else
		vim.notify("Flatten requires Foundry", vim.log.levels.WARN, { title = "Solidity" })
	end
end, { desc = sol_icon .. " Flatten" })

--- Run solhint linter on the current file.
---
--- Requires `solhint` to be globally installed (`npm i -g solhint`).
--- Notifies the user with install instructions if not found.
keys.lang_map("solidity", "n", "<leader>ll", function()
	if vim.fn.executable("solhint") ~= 1 then
		vim.notify("Install: npm i -g solhint", vim.log.levels.WARN, { title = "Solidity" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("solhint " .. vim.fn.shellescape(file))
end, { desc = sol_icon .. " Lint (solhint)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPS / COMMANDS
--
-- Dependency installation and unified command palette.
-- Dependencies are installed via the framework's native package
-- manager (forge install for Foundry, npm/pnpm/yarn for Hardhat).
-- ═══════════════════════════════════════════════════════════════════════════

--- Install a project dependency.
---
--- Adapts to the detected framework:
--- - **Foundry** → `forge install <repo> --no-commit`
---   Prompts for a GitHub repo (e.g. `OpenZeppelin/openzeppelin-contracts`)
--- - **Hardhat** → `<runner> install <package>`
---   Prompts for an npm package name
--- - **None** → notification
keys.lang_map("solidity", "n", "<leader>lp", function()
	local fw = detect_framework()

	if fw == "foundry" then
		vim.ui.input({ prompt = "forge install (e.g. OpenZeppelin/openzeppelin-contracts): " }, function(dep)
			if not dep or dep == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("forge install " .. dep .. " --no-commit")
		end)
	elseif fw == "hardhat" then
		vim.ui.input({ prompt = "npm package: " }, function(dep)
			if not dep or dep == "" then return end
			vim.cmd.split()
			vim.cmd.terminal(pkg_runner() .. " install " .. vim.fn.shellescape(dep))
		end)
	else
		notify_no_framework()
	end
end, { desc = icons.ui.Package .. " Install dep" })

--- Open the framework-specific commands picker.
---
--- Presents a different set of commands depending on the detected
--- framework:
---
--- **Foundry** (8 commands):
--- - build, test, fmt, snapshot, coverage
--- - inspect (prompted), anvil (local node), cast call (prompted)
---
--- **Hardhat** (5 commands):
--- - compile, test, node (local), clean, flatten
---
--- Commands marked with `prompt = true` ask for additional input
--- (e.g. contract name for `forge inspect`).
keys.lang_map("solidity", "n", "<leader>lc", function()
	local fw = detect_framework()

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {}

	if fw == "foundry" then
		actions = {
			{ name = "forge build", cmd = "forge build" },
			{ name = "forge test", cmd = "forge test -vvv" },
			{ name = "forge fmt", cmd = "forge fmt" },
			{ name = "forge snapshot", cmd = "forge snapshot" },
			{ name = "forge coverage", cmd = "forge coverage" },
			{ name = "forge inspect…", cmd = "forge inspect", prompt = true },
			{ name = "anvil (local node)", cmd = "anvil" },
			{ name = "cast call…", cmd = "cast call", prompt = true },
		}
	elseif fw == "hardhat" then
		---@type string
		local runner = pkg_runner()
		actions = {
			{ name = "compile", cmd = runner .. " hardhat compile" },
			{ name = "test", cmd = runner .. " hardhat test" },
			{ name = "node (local)", cmd = runner .. " hardhat node" },
			{ name = "clean", cmd = runner .. " hardhat clean" },
			{ name = "flatten", cmd = runner .. " hardhat flatten" },
		}
	else
		notify_no_framework()
		return
	end

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = sol_icon .. " Solidity:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Args: " }, function(arg)
					if not arg or arg == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. arg)
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = sol_icon .. " Commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration for Solidity. Currently manual — no standard Mason
-- adapter exists for Solidity debugging. Uses `dap.continue()` which
-- requires manual adapter and configuration setup.
--
-- For Foundry: consider using `forge test --debug <TestContract>`
-- for interactive EVM debugging (not DAP-based).
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session (manual).
---
--- Calls `dap.continue()` which requires a manually configured
--- Solidity DAP adapter. Currently no standard adapter exists
--- in Mason or the nvim-dap ecosystem.
---
--- For Foundry users, consider `forge test --debug` for interactive
--- EVM-level debugging instead.
keys.lang_map("solidity", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Solidity" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (manual)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Project environment information and external documentation access.
-- Info displays the detected framework, CWD, and tool availability.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display Solidity project information.
---
--- Shows:
--- - Detected framework (Foundry / Hardhat / none)
--- - Current working directory
--- - Tool availability status for 5 Solidity tools
---   (forge, cast, anvil, solhint, solc)
keys.lang_map("solidity", "n", "<leader>li", function()
	local fw = detect_framework()

	---@type string[]
	local info = {
		sol_icon .. " Solidity Info:",
		"",
		"  Framework: " .. (fw or "none detected"),
		"  CWD:       " .. vim.fn.getcwd(),
	}

	---@type string[]
	local tools = { "forge", "cast", "anvil", "solhint", "solc" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Solidity" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Solidity documentation in the system browser.
---
--- Presents a selection menu with links to key Solidity and
--- smart contract development resources.
---
--- Available documentation links:
--- - Solidity Docs (official language documentation)
--- - Foundry Book (Forge / Anvil / Cast documentation)
--- - Hardhat Docs (Hardhat framework documentation)
--- - OpenZeppelin (smart contract library documentation)
--- - Solidity by Example (interactive tutorials)
keys.lang_map("solidity", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Solidity Docs", url = "https://docs.soliditylang.org/" },
		{ name = "Foundry Book", url = "https://book.getfoundry.sh/" },
		{ name = "Hardhat Docs", url = "https://hardhat.org/docs" },
		{ name = "OpenZeppelin", url = "https://docs.openzeppelin.com/contracts/" },
		{ name = "Solidity by Example", url = "https://solidity-by-example.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = sol_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Solidity-specific alignment presets for mini.align:
-- • solidity_vars — align variable declarations on whitespace
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("solidity") then
		---@type string Alignment preset icon from icons.lang
		local sol_align_icon = icons.lang.solidity

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			solidity_vars = {
				description = "Align Solidity variable declarations",
				icon = sol_align_icon,
				split_pattern = "%s+",
				category = "domain",
				lang = "solidity",
				filetypes = { "solidity" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("solidity", "solidity_vars")
		align_registry.mark_language_loaded("solidity")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("solidity", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("solidity_vars"), {
			desc = sol_align_icon .. "  Align Solidity vars",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Solidity-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Solidity               │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts fn (server added if LS executable)     │
-- │ conform.nvim       │ opts fn (forge_fmt or prettier, conditional)│
-- │ nvim-lint          │ opts fn (solhint, conditional)              │
-- │ nvim-treesitter    │ opts merge (solidity parser ensured)        │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Notable omissions:
-- • No Mason spec — nomicfoundation-solidity-ls is NOT in the Mason
--   registry. Install it manually: `npm i -g @nomicfoundation/solidity-language-server`
-- • No DAP spec — no standard Solidity DAP adapter exists. For EVM-level
--   debugging, use `forge test --debug <TestContract>` (Foundry).
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Solidity
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- solidity_ls_nomicfoundation: Nomic Foundation's Solidity Language
	-- Server (completions, diagnostics, hover, go-to-definition).
	-- Only configured when the LS executable is available in PATH.
	-- Install manually: npm i -g @nomicfoundation/solidity-language-server
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("nomicfoundation-solidity-ls") ~= 1 then return end
			opts.servers = opts.servers or {}
			opts.servers.solidity_ls_nomicfoundation = {}
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					sol = "solidity",
				},
			})

			-- ── Buffer-local options for Solidity files ──────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "solidity" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120

					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
					opt.expandtab = true

					opt.number = true
					opt.relativenumber = true

					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99

					opt.commentstring = "// %s"
				end,
			})
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Formatter resolution:
	-- 1. forge executable → forge fmt (stdin mode, Foundry native)
	-- 2. prettier executable → prettier (with solidity plugin)
	-- 3. Neither → no formatter configured
	--
	-- Custom formatter definition for forge fmt since it's not a
	-- standard conform formatter.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("forge") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.solidity = { "forge_fmt" }

				opts.formatters = opts.formatters or {}
				opts.formatters.forge_fmt = {
					command = "forge",
					args = { "fmt", "--raw", "-" },
					stdin = true,
				}
			elseif vim.fn.executable("prettier") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.solidity = { "prettier" }
			end
		end,
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- solhint: Solidity linter (security, best practices, style).
	-- Only configured when solhint is available in PATH.
	-- Install: npm i -g solhint
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("solhint") ~= 1 then return end
			opts.linters_by_ft = opts.linters_by_ft or {}
			opts.linters_by_ft.solidity = { "solhint" }
		end,
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- solidity: syntax highlighting, folding, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"solidity",
			},
		},
	},

	-- ── DAP (Solidity debugger) ────────────────────────────────────────────
	-- NOTE: No standard Mason DAP adapter exists for Solidity.
	-- For EVM-level debugging, use Foundry's built-in debugger:
	--   forge test --debug <TestContract>
	-- To enable DAP integration, configure dap.adapters.solidity and
	-- dap.configurations.solidity manually.
	-- ───────────────────────────────────────────────────────────────────────
}
