local settings = require("core.settings")
if not settings:is_plugin_enabled("nvim_lint") then
  return {}
end

return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufNewFile", "BufWritePre" },
  opts_extend = { "linters_by_ft" },
  opts = {
    -- Default linters: none.
    -- Language files (langs/*.lua) add their linters dynamically.
    linters_by_ft = {},
    -- Autocommand events that trigger linting
    events = { "BufWritePost", "BufReadPost", "InsertLeave" },
  },
  config = function(_, opts)
    local lint = require("lint")
    lint.linters_by_ft = opts.linters_by_ft or {}

    -- Create autocommand for linting
    vim.api.nvim_create_autocmd(opts.events or { "BufWritePost" }, {
      group = vim.api.nvim_create_augroup("NvimEnterprise_lint", { clear = true }),
      callback = function()
        -- Only lint if the buffer has a filetype with configured linters
        local ft = vim.bo.filetype
        if lint.linters_by_ft[ft] then
          lint.try_lint()
        end
      end,
    })

    -- Command to manually trigger linting
    vim.api.nvim_create_user_command("Lint", function()
      lint.try_lint()
    end, { desc = "Trigger linting for current file" })
  end,
}
