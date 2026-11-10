local cmd = require("cmd")

function PLUGIN:PackageInstall(ctx)
    local failed = {}
    for _, pkg in ipairs(ctx.packages) do
        if ctx.dry_run then
            print("would install " .. pkg.name)
        -- one delisted extension must not block every one after it on each run
        elseif not pcall(cmd.exec, 'code --install-extension "$EXTENSION"', { env = { EXTENSION = pkg.name } }) then
            table.insert(failed, pkg.name)
        end
    end
    if #failed > 0 then
        error("failed to install: " .. table.concat(failed, ", "))
    end
end
