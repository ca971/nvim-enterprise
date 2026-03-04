-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  User settings: jane — Data science / Python focus                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

---@type NvimEnterpriseSettings
return {
  ui = {
    colorscheme       = "kanagawa",
    colorscheme_style = "wave",
  },

  editor = {
    tab_size = 4,
    wrap     = true,
  },

  languages = {
    enabled = {
      "lua", "python", "r", "julia", "sql",
      "json", "yaml", "markdown", "csv",
    },
  },

  ai = {
    enabled  = true,
    provider = "claude",
    continue_completion = false,
    avante = {
      enabled  = true,
      provider = "claude",
    },
  },

  plugins = {
    flash     = { enabled = false }, -- Jane doesn't use flash
    startuptime = { enabled = true },
  },

  lazyvim_extras = {
    enabled = false,
  },
}
