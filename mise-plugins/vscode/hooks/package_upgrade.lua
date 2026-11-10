-- Without this hook mise falls back to PackageInstall and reinstalls every extension
function PLUGIN:PackageUpgrade(ctx)
    print("VS Code updates its own extensions")
end
