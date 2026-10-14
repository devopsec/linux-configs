local trace_target = os.getenv("NVIM_TRACEOPT")

if trace_target then
    local autocmd = vim.api.nvim_create_autocmd
    local augroup = vim.api.nvim_create_augroup

    local function log(msg)
        io.stdout:write(msg .. "\n")
        io.stdout:flush()
    end

    local function fmt_val(val)
        if type(val) == "string" then
            return string.format("%q", val)
        end
        return tostring(val)
    end

    local function get_trace_info()
        local val = vim.api.nvim_get_option_value(trace_target, {})
        local info = vim.api.nvim_get_option_info2(trace_target, {})
        local source = "NeoVim Default (vim.opt)"
        if info.last_set_sid == -8 then
            -- SID_LUA: set via Lua API (vim.opt / vim.o / nvim_set_option_value)
            source = "Lua API (vim.opt)"
        elseif info.last_set_sid > 0 then
            -- Try to get the script name from SID
            local script_info = vim.fn.getscriptinfo({ id = info.last_set_sid })
            if script_info and #script_info > 0 then
                source = script_info[1].name
                if info.last_set_linenr > 0 then
                    source = string.format("%s:%d", source, info.last_set_linenr)
                end
            else
                source = string.format("SID %d", info.last_set_sid)
            end
        elseif info.last_set_chan > 0 then
            source = string.format("Channel %d", info.last_set_chan)
        end
        return val, source
    end

    local last_val, last_source = get_trace_info()
    log(string.format("[START] %s is: %s", trace_target, fmt_val(last_val)))

    local debug_group = augroup("DebugSettings", { clear = true })

    -- Watch for changes via OptionSet (works for :set and vim.opt)
    autocmd("OptionSet", {
        group = debug_group,
        pattern = trace_target,
        callback = function()
            -- Capture source at the moment of the event, before anything else runs
            local _, source = get_trace_info()
            local val = vim.v.option_new
            if val ~= last_val then
                log(string.format("[CHANGE] %s -> %s (OptionSet)", trace_target, fmt_val(val)))
                log(string.format("[SOURCE] %s", source))
                last_val = val
                last_source = source
            end
        end,
    })

    -- Wrap require to detect changes in Lua modules that bypass OptionSet
    local old_require = require
    _G.require = function(modname)
        local before = vim.api.nvim_get_option_value(trace_target, {})
        local res = old_require(modname)
        local after = vim.api.nvim_get_option_value(trace_target, {})
        if after ~= before and after ~= last_val then
            -- Resolve module name to actual file path for accurate source reporting
            local modfile = modname:gsub("%.", "/") .. ".lua"
            local found = vim.api.nvim_get_runtime_file("lua/" .. modfile, false)
            local modpath = (found and found[1]) or modname
            log(string.format("[CHANGE] %s -> %s (require: %s)", trace_target, fmt_val(after), modname))
            log(string.format("[SOURCE] %s", modpath))
            last_val = after
            last_source = modpath
        end
        return res
    end

    -- Final check on exit
    autocmd("VimLeave", {
        group = debug_group,
        callback = function(ev)
            local end_val, source = get_trace_info()
            if end_val ~= last_val then
                log(string.format("[CHANGE] %s -> %s (VimLeave)", trace_target, fmt_val(end_val)))
                log(string.format("[SOURCE] %s", source))
                last_source = source
            end
            log(string.format("[EXIT] %s is: %s", trace_target, fmt_val(end_val)))
        end,
    })
end
