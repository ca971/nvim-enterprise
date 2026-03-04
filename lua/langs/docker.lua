---@file lua/langs/docker.lua
---@description Docker & Compose — LSP, linter, treesitter & buffer-local keymaps
---@module "langs.docker"
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
---@see langs.lua                Lua language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/docker.lua — Docker & Compose language support                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("docker") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "dockerfile" /               │    ║
--- ║  │             "yaml.docker-compose"):                              │    ║
--- ║  │  ├─ LSP          dockerls (Dockerfile intelligence)              │    ║
--- ║  │  │               docker_compose_language_service (Compose)       │    ║
--- ║  │  ├─ Formatter    — (none, handled by LSP)                        │    ║
--- ║  │  ├─ Linter       hadolint (Dockerfile best-practice linter)      │    ║
--- ║  │  ├─ Treesitter   dockerfile parser                               │    ║
--- ║  │  ├─ DAP          — (not applicable)                              │    ║
--- ║  │  └─ Extras       — (none)                                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ BUILD     b  Build image           t  Tag image              │    ║
--- ║  │  ├─ RUN       r  Run container                                   │    ║
--- ║  │  ├─ PUSH      p  Push image                                      │    ║
--- ║  │  ├─ STATUS    s  docker ps             i  Images list            │    ║
--- ║  │  │            v  Volumes list          n  Networks list          │    ║
--- ║  │  ├─ EXEC      e  Exec into container   l  Logs (follow)          │    ║
--- ║  │  ├─ COMPOSE   u  Compose up            d  Compose down           │    ║
--- ║  │  │            c  Compose commands (picker)                       │    ║
--- ║  │  ├─ CLEANUP   x  Prune (picker)                                  │    ║
--- ║  │  └─ DOCS      h  Documentation (browser)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymap scope:                                                   │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Dockerfile-only:  b (build), r (run), p (push), t (tag) │    │    ║
--- ║  │  │  Shared (both ft): s, i, e, l, v, n, u, d, c, x, h      │     │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType dockerfile):                        ║
--- ║  • colorcolumn=120, textwidth=120 (Dockerfile line length)               ║
--- ║  • tabstop=4, shiftwidth=4        (standard indentation)                 ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="# %s"          (shell-style comments)                  ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • Dockerfile, Containerfile → dockerfile                                ║
--- ║  • Dockerfile.*, Containerfile.* → dockerfile (multi-stage)              ║
--- ║  • docker-compose.yml/yaml, compose.yml/yaml → yaml.docker-compose       ║
--- ║  • .dockerignore → gitignore                                             ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Docker support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("docker") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Docker Nerd Font icon (trailing whitespace stripped)
local docker_icon = icons.lang.docker:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for Docker and Compose buffers.
-- Both groups are buffer-local and only visible in their respective filetypes.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("dockerfile", "Docker", docker_icon)
keys.lang_group("yaml.docker-compose", "Docker Compose", docker_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
--
-- Shared constants used throughout the module.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string[] Filetypes that receive shared Docker keymaps
local docker_fts = { "dockerfile", "yaml.docker-compose" }

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the docker CLI is available in PATH.
---
--- Notifies the user with an error if docker is not found.
---
--- ```lua
--- if not check_docker() then return end
--- ```
---
---@return boolean available `true` if `docker` is executable, `false` otherwise
---@private
local function check_docker()
	if vim.fn.executable("docker") ~= 1 then
		vim.notify("docker not found in PATH", vim.log.levels.ERROR, { title = "Docker" })
		return false
	end
	return true
end

--- Detect the docker-compose file in the current working directory.
---
--- Scans for common compose file names in order of priority:
--- 1. `docker-compose.yml`
--- 2. `docker-compose.yaml`
--- 3. `compose.yml`
--- 4. `compose.yaml`
---
--- ```lua
--- local file = detect_compose_file()
--- if file then
---   vim.cmd.terminal("docker compose -f " .. file .. " up")
--- end
--- ```
---
---@return string|nil path Filename of the compose file, or `nil` if none found
---@private
local function detect_compose_file()
	local candidates = {
		"docker-compose.yml",
		"docker-compose.yaml",
		"compose.yml",
		"compose.yaml",
	}
	local cwd = vim.fn.getcwd()
	for _, f in ipairs(candidates) do
		if vim.fn.filereadable(cwd .. "/" .. f) == 1 then return f end
	end
	return nil
end

--- Build the `docker compose` command prefix with `-f` flag if needed.
---
--- Uses `detect_compose_file()` to find the compose file and appends
--- the `-f` flag. Falls back to bare `docker compose` if no file is found
--- (docker compose will use its own auto-detection).
---
--- ```lua
--- vim.cmd.terminal(compose_cmd() .. " up -d")
--- -- → "docker compose -f compose.yml up -d"
--- ```
---
---@return string cmd Complete `docker compose [-f <file>]` prefix
---@private
local function compose_cmd()
	local file = detect_compose_file()
	if file then return "docker compose -f " .. vim.fn.shellescape(file) end
	return "docker compose"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN / PUSH / TAG
--
-- Image lifecycle operations. These keymaps are only available in
-- Dockerfile buffers (not in docker-compose YAML files).
-- ═══════════════════════════════════════════════════════════════════════════

--- Build a Docker image from the current Dockerfile.
---
--- Prompts for an image tag (default: `myapp:latest`), then runs
--- `docker build` in a terminal split using the current file as the
--- Dockerfile and its parent directory as the build context.
keys.lang_map("dockerfile", "n", "<leader>lb", function()
	if not check_docker() then return end
	vim.cmd("silent! write")
	local dir = vim.fn.expand("%:p:h")
	local dockerfile = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Image tag: ", default = "myapp:latest" }, function(tag)
		if not tag or tag == "" then return end
		vim.cmd.split()
		vim.cmd.terminal(
			"docker build -t "
				.. vim.fn.shellescape(tag)
				.. " -f "
				.. vim.fn.shellescape(dockerfile)
				.. " "
				.. vim.fn.shellescape(dir)
		)
	end)
end, { desc = icons.dev.Container .. " Build image" })

--- Run a container from an image.
---
--- Prompts for:
--- 1. Image tag or ID (default: `myapp:latest`)
--- 2. Extra flags (default: `-it --rm`)
---
--- Executes `docker run` in a terminal split.
keys.lang_map("dockerfile", "n", "<leader>lr", function()
	if not check_docker() then return end
	vim.ui.input({ prompt = "Image (tag or ID): ", default = "myapp:latest" }, function(image)
		if not image or image == "" then return end
		vim.ui.input({ prompt = "Extra flags (e.g. -p 8080:80 -d): ", default = "-it --rm" }, function(flags)
			if flags == nil then return end
			vim.cmd.split()
			vim.cmd.terminal("docker run " .. flags .. " " .. vim.fn.shellescape(image))
		end)
	end)
end, { desc = icons.ui.Play .. " Run container" })

--- Push an image to a registry.
---
--- Prompts for the image tag, then runs `docker push` in a terminal split.
keys.lang_map("dockerfile", "n", "<leader>lp", function()
	if not check_docker() then return end
	vim.ui.input({ prompt = "Image tag to push: " }, function(tag)
		if not tag or tag == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("docker push " .. vim.fn.shellescape(tag))
	end)
end, { desc = docker_icon .. " Push image" })

--- Tag an image with a new name.
---
--- Prompts for:
--- 1. Source image (existing tag or ID)
--- 2. New tag
---
--- Runs `docker tag` synchronously and notifies on success or failure.
keys.lang_map("dockerfile", "n", "<leader>lt", function()
	if not check_docker() then return end
	vim.ui.input({ prompt = "Source image: " }, function(src)
		if not src or src == "" then return end
		vim.ui.input({ prompt = "New tag: " }, function(tag)
			if not tag or tag == "" then return end
			local result = vim.fn.system("docker tag " .. vim.fn.shellescape(src) .. " " .. vim.fn.shellescape(tag))
			if vim.v.shell_error == 0 then
				vim.notify("Tagged: " .. src .. " → " .. tag, vim.log.levels.INFO, { title = "Docker" })
			else
				vim.notify("Error: " .. result, vim.log.levels.ERROR, { title = "Docker" })
			end
		end)
	end)
end, { desc = docker_icon .. " Tag image" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATUS / INSPECT
--
-- Container, image, volume and network inspection commands.
-- Available in both Dockerfile and docker-compose buffers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show running containers with formatted output.
---
--- Displays ID, Image, Status, Names and Ports columns via
--- `docker ps --format`.
keys.lang_map(docker_fts, "n", "<leader>ls", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal("docker ps --format 'table {{.ID}}\\t{{.Image}}\\t{{.Status}}\\t{{.Names}}\\t{{.Ports}}'")
end, { desc = icons.dev.Container .. " Status (docker ps)" })

--- List Docker images with formatted output.
---
--- Displays Repository, Tag, Size and CreatedSince columns.
keys.lang_map(docker_fts, "n", "<leader>li", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal("docker images --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}\\t{{.CreatedSince}}'")
end, { desc = docker_icon .. " Images" })

--- Execute a command inside a running container.
---
--- Lists running containers via `docker ps`, presents them in a
--- `vim.ui.select()` picker, then prompts for the shell to use
--- (default: `/bin/sh`). Opens an interactive session in a terminal split.
keys.lang_map(docker_fts, "n", "<leader>le", function()
	if not check_docker() then return end

	local result = vim.fn.system("docker ps --format '{{.Names}}' 2>/dev/null")
	---@type string[]
	local containers = {}
	for name in result:gmatch("[^\r\n]+") do
		if name ~= "" then containers[#containers + 1] = name end
	end

	if #containers == 0 then
		vim.notify("No running containers", vim.log.levels.INFO, { title = "Docker" })
		return
	end

	vim.ui.select(containers, { prompt = docker_icon .. " Exec into:" }, function(container)
		if not container then return end
		vim.ui.input({ prompt = "Shell: ", default = "/bin/sh" }, function(shell)
			if not shell or shell == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("docker exec -it " .. vim.fn.shellescape(container) .. " " .. shell)
		end)
	end)
end, { desc = icons.ui.Terminal .. " Exec into container" })

--- Follow logs for a running container.
---
--- Lists running containers via `docker ps`, presents them in a picker,
--- then tails the last 100 lines with `docker logs -f --tail 100`.
keys.lang_map(docker_fts, "n", "<leader>ll", function()
	if not check_docker() then return end

	local result = vim.fn.system("docker ps --format '{{.Names}}' 2>/dev/null")
	---@type string[]
	local containers = {}
	for name in result:gmatch("[^\r\n]+") do
		if name ~= "" then containers[#containers + 1] = name end
	end

	if #containers == 0 then
		vim.notify("No running containers", vim.log.levels.INFO, { title = "Docker" })
		return
	end

	vim.ui.select(containers, { prompt = docker_icon .. " Logs for:" }, function(container)
		if not container then return end
		vim.cmd.split()
		vim.cmd.terminal("docker logs -f --tail 100 " .. vim.fn.shellescape(container))
	end)
end, { desc = docker_icon .. " Logs (follow)" })

--- List Docker volumes.
keys.lang_map(docker_fts, "n", "<leader>lv", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal("docker volume ls")
end, { desc = docker_icon .. " Volumes" })

--- List Docker networks.
keys.lang_map(docker_fts, "n", "<leader>ln", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal("docker network ls")
end, { desc = docker_icon .. " Networks" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMPOSE
--
-- Docker Compose lifecycle operations.
-- Available in both Dockerfile and docker-compose buffers.
-- Uses `compose_cmd()` to auto-detect the compose file.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start all services in detached mode with build.
---
--- Runs `docker compose up -d --build` using the auto-detected
--- compose file.
keys.lang_map(docker_fts, "n", "<leader>lu", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal(compose_cmd() .. " up -d --build")
end, { desc = docker_icon .. " Compose up" })

--- Stop and remove all compose services.
---
--- Runs `docker compose down` using the auto-detected compose file.
keys.lang_map(docker_fts, "n", "<leader>ld", function()
	if not check_docker() then return end
	vim.cmd.split()
	vim.cmd.terminal(compose_cmd() .. " down")
end, { desc = docker_icon .. " Compose down" })

--- Open a picker with common Docker Compose commands.
---
--- Available actions:
--- • `up -d --build`           — start services (detached, rebuild)
--- • `down`                    — stop and remove
--- • `down -v`                 — stop, remove and delete volumes
--- • `restart`                 — restart all services
--- • `ps`                      — list running services
--- • `logs -f`                 — follow logs (last 50 lines)
--- • `pull`                    — pull latest images
--- • `build`                   — build images
--- • `config`                  — validate compose file
--- • `top`                     — display running processes
keys.lang_map(docker_fts, "n", "<leader>lc", function()
	if not check_docker() then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "up -d --build", cmd = compose_cmd() .. " up -d --build" },
		{ name = "down", cmd = compose_cmd() .. " down" },
		{ name = "down -v (with volumes)", cmd = compose_cmd() .. " down -v" },
		{ name = "restart", cmd = compose_cmd() .. " restart" },
		{ name = "ps", cmd = compose_cmd() .. " ps" },
		{ name = "logs -f", cmd = compose_cmd() .. " logs -f --tail 50" },
		{ name = "pull", cmd = compose_cmd() .. " pull" },
		{ name = "build", cmd = compose_cmd() .. " build" },
		{ name = "config (validate)", cmd = compose_cmd() .. " config" },
		{ name = "top", cmd = compose_cmd() .. " top" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = docker_icon .. " Compose:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = docker_icon .. " Compose commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CLEANUP
--
-- Docker resource pruning with a safety picker to prevent accidental
-- deletion of important resources.
-- ═══════════════════════════════════════════════════════════════════════════

--- Prune unused Docker resources.
---
--- Presents a picker with granular prune options:
--- • Containers           — remove stopped containers
--- • Images (dangling)    — remove untagged images
--- • Images (all unused)  — remove all images without containers
--- • Volumes              — remove unused volumes
--- • Networks             — remove unused networks
--- • System prune (all)   — nuclear option: everything + volumes
keys.lang_map(docker_fts, "n", "<leader>lx", function()
	if not check_docker() then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Prune containers", cmd = "docker container prune -f" },
		{ name = "Prune images (dangling)", cmd = "docker image prune -f" },
		{ name = "Prune images (all unused)", cmd = "docker image prune -a -f" },
		{ name = "Prune volumes", cmd = "docker volume prune -f" },
		{ name = "Prune networks", cmd = "docker network prune -f" },
		{ name = "System prune (all)", cmd = "docker system prune -af --volumes" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = docker_icon .. " Prune:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = docker_icon .. " Prune" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Docker reference documentation via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Docker documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Dockerfile reference        — instruction syntax and semantics
--- • Compose file reference      — services, networks, volumes spec
--- • Docker CLI reference        — command-line usage
--- • Docker Hub                  — public image registry
--- • Best practices              — image authoring guidelines
keys.lang_map(docker_fts, "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Dockerfile reference", url = "https://docs.docker.com/engine/reference/builder/" },
		{ name = "Compose file reference", url = "https://docs.docker.com/compose/compose-file/" },
		{ name = "Docker CLI reference", url = "https://docs.docker.com/engine/reference/commandline/cli/" },
		{ name = "Docker Hub", url = "https://hub.docker.com/" },
		{ name = "Best practices", url = "https://docs.docker.com/develop/develop-images/dockerfile_best-practices/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = docker_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Docker-specific alignment presets for mini.align:
-- • docker_env — align Dockerfile ENV / ARG directives on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("docker") then
		---@type string Alignment preset icon from icons.dev
		local align_icon = icons.dev.Container

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			docker_env = {
				description = "Align Dockerfile ENV / ARG on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "devops",
				lang = "docker",
				filetypes = { "dockerfile" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("dockerfile", "docker_env")
		align_registry.mark_language_loaded("docker")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map({ "dockerfile" }, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("docker_env"), {
			desc = align_icon .. "  Align Docker ENV",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Docker-specific
-- parts (servers, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Docker                 │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (servers added on require)        │
-- │ mason.nvim                             │ opts merge (tools added to ensure_installed) │
-- │ nvim-lint                              │ opts merge (linters_by_ft.dockerfile)        │
-- │ nvim-treesitter                        │ opts merge (parsers added to ensure_installed│
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Docker
return {
	-- ── LSP SERVERS ────────────────────────────────────────────────────────
	-- dockerls:                          Dockerfile intelligence (completions,
	--                                    hover, diagnostics)
	-- docker_compose_language_service:   Compose YAML intelligence (service
	--                                    names, volumes, networks)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				dockerls = {},
				docker_compose_language_service = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				filename = {
					["Dockerfile"] = "dockerfile",
					["Containerfile"] = "dockerfile",
					["docker-compose.yml"] = "yaml.docker-compose",
					["docker-compose.yaml"] = "yaml.docker-compose",
					["compose.yml"] = "yaml.docker-compose",
					["compose.yaml"] = "yaml.docker-compose",
					[".dockerignore"] = "gitignore",
				},
				pattern = {
					["Dockerfile%..*"] = "dockerfile",
					["Containerfile%..*"] = "dockerfile",
					["docker%-compose%..*%.ya?ml"] = "yaml.docker-compose",
				},
			})

			-- ── Buffer-local options for Dockerfile ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "dockerfile" },
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
					opt.commentstring = "# %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures dockerls, docker_compose_language_service and hadolint are
	-- installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"dockerfile-language-server",
				"docker-compose-language-service",
				"hadolint",
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- hadolint: Dockerfile best-practice linter (Haskell-based, very strict).
	-- Checks for common anti-patterns like `apt-get` without `--no-install-recommends`,
	-- missing `WORKDIR`, pinning versions, etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				dockerfile = { "hadolint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- dockerfile: syntax highlighting, folding, text objects for
	--             Dockerfile instructions (FROM, RUN, COPY, etc.)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"dockerfile",
			},
		},
	},
}
