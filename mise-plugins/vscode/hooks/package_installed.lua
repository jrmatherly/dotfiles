local cmd = require("cmd")

function PLUGIN:PackageInstalled(ctx)
    local installed = {}
    local output = cmd.exec("code --list-extensions --show-versions")
    for line in output:gmatch("[^\r\n]+") do
        local name, version = line:match("^(.+)@([^@]+)$")
        if name then
            installed[name:lower()] = version
        end
    end
    local results = {}
    for _, pkg in ipairs(ctx.packages) do
        local version = installed[pkg.name:lower()]
        table.insert(results, {
            name = pkg.name,
            state = version and "installed" or "missing",
            version = version,
        })
    end
    return { packages = results }
end
