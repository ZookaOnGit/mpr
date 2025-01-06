--- Command line package manager for Mudlet.
--

mpkg = mpkg or {}
mpkg.aliases = mpkg.aliases or {}
mpkg.debug = mpkg.debug or false
mpkg.maintainer = "https://github.com/mudlet/mudlet-package-repository/issues"
mpkg.repository = "https://mudlet.github.io/mudlet-package-repository/packages"
mpkg.website = "http://packages.mudlet.org"
mpkg.websiteUploads = f"{mpkg.website}/upload"
mpkg.filename = "mpkg.packages.json"
mpkg.help = [[

<b>mpkg</b> is a command line interface for managing packages
used in Mudlet. You can install, remove, search the package
repository and update installed packages using this interface.

Commands:
  mpkg help             -- show this help
  mpkg install          -- install a new package
  mpkg list             -- list all installed packages
  mpkg remove           -- remove an existing package
  mpkg search           -- search for a package via name and description
  mpkg show             -- show detailed information about a package
  mpkg show-repo        -- show package information from the repository only
  mpkg update           -- update your package listing
  mpkg upgrade          -- upgrade a specific package
  mpkg upgradeable      -- show packages that can be upgraded
  mpkg upload           -- opens the repository upload website
]]


--- Entry point of script.
function mpkg.initialise()

  -- clean up any old info
  mpkg.uninstallSelf()

  registerNamedEventHandler("mpkg", "download", "sysDownloadDone", "mpkg.eventHandler")
  registerNamedEventHandler("mpkg", "download-error", "sysDownloadError", "mpkg.eventHandler")
  registerNamedEventHandler("mpkg", "installed", "sysInstallPackage", "mpkg.eventHandler")
  registerNamedEventHandler("mpkg", "uninstalled", "sysUninstallPackage", "mpkg.eventHandler")

  mpkg.aliases = mpkg.aliases or {}

  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp)( help)?$", mpkg.displayHelp))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) debug$", mpkg.toggleDebug))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) install(?: (.+))?$", function() mpkg.install(matches[3]) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) list$", mpkg.listInstalledPackages))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) remove(?: (.+))?$", function() mpkg.remove(matches[3]) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) show(?: (.+))?$", function() mpkg.show(matches[3]) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) show-repo(?: (.+))?$", function() mpkg.show(matches[3], true) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) search(?: (.+))?$", function() mpkg.search(matches[3]) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) update$", function() mpkg.updatePackageList(false) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) upgrade(?: (.+))?$", function() mpkg.upgrade(matches[3]) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) upgradeable$", function() mpkg.checkForUpgrades(false) end))
  table.insert(mpkg.aliases, tempAlias("^(mpkg|mp) upload$", mpkg.openWebUploads))

  -- Setup a named timer for automatic repository listing updates every 12 hours (60s*60m*12h=43200s)
  registerNamedTimer("mpkg", "mpkg update package listing timer", 43200, function() mpkg.updatePackageList(true) end, true)

  mpkg.updatePackageList(true)
end


--- Pretty print any script echoes so users know where the information came from.
-- @param args the string to echo to the main console
function mpkg.echo(args)
  cecho(string.format("%s  - %s\n", "<khaki>[ MPKG ]<reset>", args))
end

--- Pretty print any text, followed by a clickable link.
-- Requires end of line terminator.
-- @param args a string to echo preceding the clickable link
-- @param ... a set of args as per cechoLink format
function mpkg.echoLink(args, ...)
  cecho(string.format("%s  - %s", "<khaki>[ MPKG ]<reset>", args))
  cechoLink(...)
end



--- Get which version of a package is installed on in Mudlet.
-- @param args the package name as found in getPackageInfo()
-- @return nil and error message if not found
-- @return string containing a version if found
function mpkg.getInstalledVersion(args)
    local installedVersion = getPackageInfo(args, "version")

    if installedVersion == "" then
      return nil, "No version found."
    else
      return installedVersion
    end

    return nil, "No package found."
end


--- Get which version of a package is available in the repository.
-- @param args the package name as listed in the repository
-- @return nil and error message if not found
-- @return string containing a version if found
function mpkg.getRepositoryVersion(args)
  local packages = mpkg.packages["packages"]

  for i = 1, #packages do
    if args == packages[i]["mpackage"] then
      return packages[i]["version"]
    end
  end

  return nil, "Package does not exist in repository."
end


--- Get a table of dependencies this package requires to be installed.
-- @param args the package name as listed in the repository
-- @return nil and error message if not found
-- @return an empty table (if no dependencies) or table containing package names if found
function mpkg.getDependencies(args)
  local packages = mpkg.packages["packages"]

  for i = 1, #packages do
    if args == packages[i]["mpackage"] then
      if packages[i]["dependencies"] then
        return string.split(packages[i]["dependencies"], ",")
      else
        return {}
      end
    end
  end

  return nil, "Package does not exist in repository."
end


--- Check if there are any packages that can be upgraded to a new version.
-- Checks if the installed version of a package is less than the repository
-- version using semantic versioning methods.
-- @param silent if true, do not display update messages
function mpkg.checkForUpgrades(silent)
  local packages = mpkg.packages["packages"]
  local requireUpgrade = {}

  for k,v in pairs(getPackages()) do
    local installedVersion, iError = mpkg.getInstalledVersion(v)
    local repoVersion, rError = mpkg.getRepositoryVersion(v)

    if mpkg.debug then
      if iError then
        mpkg.echo(f"Checking local package <green>'{v}': v '{iError}'<reset>")
      else
        mpkg.echo(f"Checking local package <green>'{v}': v '{installedVersion}'<reset>")
      end

      if repoVersion then
        mpkg.echo(f"Checking repo package <green>'{v}': v '{repoVersion}'<reset>")
      else
        mpkg.echo(f"Package not in repository <green>'{v}'<reset>")
      end
    end

    if repoVersion and installedVersion then
      if semver(installedVersion) < semver(repoVersion) then
        table.insert(requireUpgrade, v)
      end
    end
  end

  if not table.is_empty(requireUpgrade) then
    mpkg.echo("New package upgrades available.  The following packages can be upgraded:")
    mpkg.echo("")
    for k,v in pairs(requireUpgrade) do
      mpkg.echoLink(f"<b>{v}</b> v{mpkg.getInstalledVersion(v)} to v{mpkg.getRepositoryVersion(v)}", " (<b>click to upgrade</b>)\n", function() mpkg.upgrade(v) end, "Click to upgrade", true)
    end
  else
    if not silent then
      mpkg.echo("No package upgrades are available.")
    end
  end

end

function mpkg.performUpgradeAll(silent)
  local packages = mpkg.packages["packages"]
  local requireUpgrade = {}

  for k,v in pairs(getPackages()) do
    local installedVersion, iError = mpkg.getInstalledVersion(v)
    local repoVersion, rError = mpkg.getRepositoryVersion(v)

    if mpkg.debug then
      if iError then
        mpkg.echo(f"Checking local package <green>'{v}': v '{iError}'<reset>")
      else
        mpkg.echo(f"Checking local package <green>'{v}': v '{installedVersion}'<reset>")
      end

      if repoVersion then
        mpkg.echo(f"Checking repo package <green>'{v}': v '{repoVersion}'<reset>")
      else
        mpkg.echo(f"Package not in repository <green>'{v}'<reset>")
      end
    end

    if repoVersion and installedVersion then
      if semver(installedVersion) < semver(repoVersion) then
        table.insert(requireUpgrade, v)
      end
    end
  end

  if not table.is_empty(requireUpgrade) then
    mpkg.echo("New package upgrades available.  The following packages will be upgraded:")
    mpkg.echo("")
    for _,v in pairs(requireUpgrade) do
      mpkg.echo(f"<b>{v}</b> v{mpkg.getInstalledVersion(v)} to v{mpkg.getRepositoryVersion(v)}")
    end
    for _,v in pairs(requireUpgrade) do
      mpkg.upgrade(v)
    end
  else
    if not silent then
      mpkg.echo("No package upgrades are available.")
    end
  end

end


--- Print the help file.
function mpkg.displayHelp()

  mpkg.echo("<u>Mudlet Package Repository Client (mpkg)</u>")
  mpkg.echoLink("", f"[{mpkg.website}]\n", function() openUrl(mpkg.website) end, "open package website", true)

  local help = string.split(mpkg.help, "\n")

  for i = 1, #help do
    mpkg.echo(help[i])
  end

end


--- Install a new package from the repository.
-- @param args the package name as listed in the repository
-- @return false if there was an error
-- @return true if package was installed successfully
function mpkg.install(args)

  if not args then
    mpkg.echo("Missing package name.")
    mpkg.echo("Syntax: mpkg install <package_name>")
    return false
  end

  if table.contains(getPackages(), args) then
    mpkg.echo(f"<b>{args}</b> package is already installed, use <yellow>mpkg upgrade<reset> to install a newer version.")
    return false
  end

  local packages = mpkg.packages["packages"]

  for i = 1, #packages do
    if args == packages[i]["mpackage"] then
      -- check for dependencies
      local depends = mpkg.getDependencies(args)

      if depends then

        local unmet = {}

        for _,v in pairs(depends) do
          if not table.contains(getPackages(), v) then
            table.insert(unmet, v)
          end
        end

        -- TODO: automatic dependency resolution?
        if not table.is_empty(unmet) then
          mpkg.echo("This package has unmet dependencies.")
          mpkg.echo("Please install the following packages first.")
          mpkg.echo("")

          for _,v in pairs(unmet) do
            mpkg.echo(v)
          end

          return false
        end
      end

      mpkg.echo(f"Installing <b>{args}</b> (v{packages[i]['version']}).")
      installPackage(f"{mpkg.repository}/{args}.mpackage")
      return true

    end
  end

  mpkg.echo(f"Unable to locate <b>{args}</b> package in repository.")

  return false
end

--- Remove a locally installed package.
-- @param args the package name as listed in the repository
-- @return false if there was an error
-- @return true if packages was successfully uninstalled/removed
function mpkg.remove(args)

  if not args then
    mpkg.echo("Missing package name.")
    mpkg.echo("Syntax: mpkg remove <package_name>")
    return false
  end

  if not table.contains(getPackages(), args) then
    mpkg.echo(f"<b>{args}</b> package is not currently installed.")
    return false
  end

  local success = uninstallPackage(args)
  mpkg.echo(f"<b>{args}</b> package removed.")

  -- TODO: uninstallPackage doesn't currently provide a return value
  -- is it necessary to perform a post check on installed packages and compare?
  --[[
  if success then
    mpkg.echo(f"{args} uninstalled.")
  else
    mpkg.echo("Unable to uninstall.")
  end
  ]]--

  return true
end


--- Upgrade a locally installed package to a new repository version.
-- A convenience function which simply calls mpkg.remove and mpkg.install
-- @param args the package name as listed in the repository
-- @return false if there was an error
-- @return true if packages was successfully uninstalled/removed
function mpkg.upgrade(args)
  if not args then
    mpkg.echo("Missing package name.")
    mpkg.echo("Syntax: mpkg upgrade <package_name>")
    mpkg.echo("        mpkg upgrade all")
    return false
  end

  if args == "all" then
    mpkg.performUpgradeAll(false)
    return true
  end

  if not table.contains(getPackages(), args) then
    mpkg.echo(f"<b>{args}</b> package is not installed.")
    return false
  end

  if not semver(mpkg.getRepositoryVersion(args)) then
    mpkg("Aborting, unable to read repository information.  Retrying package listing update.")
    mpkg.updatePackageList()
    return
  end

  if semver(mpkg.getInstalledVersion(args)) < semver(mpkg.getRepositoryVersion(args)) then
    -- if no errors removing then install
    if mpkg.remove(args) then
      tempTimer(2, function() mpkg.install(args) end)
    end
  else
    mpkg.echo(f"<b>{args}</b> package is already on the latest version.")
  end
end


--- Fetch the latest package information from the repository.
-- @param silent if true, do not display update messages
function mpkg.updatePackageList(silent)
  local saveto = getMudletHomeDir() .. "/" .. mpkg.filename
  downloadFile(saveto, mpkg.repository .. "/" .. mpkg.filename)
  if not silent then
    mpkg.echo("Updating package listing from repository.")
    mpkg.displayUpdateMessage = true
  end
end


--- Print a list of locally installed packages in Mudlet.
function mpkg.listInstalledPackages()

  mpkg.echo("Listing locally installed packages:")

  if mpkg.debug then
    mpkg.echo("DEBUG:")
    display(getPackages())
  end

  for _,v in pairs(getPackages()) do
    local version, error = mpkg.getInstalledVersion(v)
    if error then
      mpkg.echoLink("  ", f"<b>{v}</b> (unknown version)\n", function() mpkg.show(v) end, "show details", true)
    else
      mpkg.echoLink("  ", f"<b>{v}</b> (v{mpkg.getInstalledVersion(v)})\n", function() mpkg.show(v) end, "show details", true)
    end
  end

  local count = table.size(getPackages())
  mpkg.echo(count == 1 and f"{count} package installed." or f"{count} packages installed.")

end


--- Search for a package using keywords.
-- This will search both title and description fields as set in the package information
-- (config.lua) when the package was created.
-- @param args the keywords to search for
-- @return false if no matches were found
-- @return true if matches were found
function mpkg.search(args)

  if not args then
    mpkg.echo("Missing package name.")
    mpkg.echo("Syntax: mpkg search <package_name>")
    return
  end

  mpkg.echo(f"Searching for <b>{args}</b> in repository.")

  local count = 0

  args = string.lower(args)

  local packages = mpkg.packages["packages"]

  for i = 1, #packages do
    if string.find(string.lower(packages[i]["mpackage"]), args, 1, true) or string.find(string.lower(packages[i]["title"]), args, 1, true) then
      mpkg.echo("")
      mpkg.echoLink("  ", f"<b>{packages[i]['mpackage']}</b> (v{packages[i]['version']}) ", function() mpkg.show(packages[i]["mpackage"], true) end, "show details", true)
      echoLink("", "[install now]\n", function() mpkg.install(packages[i]["mpackage"]) end, "install now", true)
      mpkg.echo(f"  {packages[i]['title']}")
      count = count + 1
    end
  end

  if count == 0 then
    mpkg.echo("No matching packages found.")
    return false
  end

  return true

end


--- Print out detailed package information.
-- Display; title, version, author, installation status, description.
-- @param args the package name as listed in the repository
-- @param repoOnly skip local details, show only repository info
-- @return false if error or no matching package was found
-- @return true if information was displayed
function mpkg.show(args, repoOnly)

  if not args then
    mpkg.echo("Missing package name.")
    if repoOnly then
      mpkg.echo("Syntax: mpkg show-repo <package_name>")
    else
      mpkg.echo("Syntax: mpkg show <package_name>")
    end
    return false
  end

  local packages

  if not repoOnly then
    -- search locally first, then the repository if nothing was found
    packages = getPackages()

    if table.contains(packages, args) then
      local name = getPackageInfo(args, "mpackage")
      local title = getPackageInfo(args, "title")
      local version = getPackageInfo(args, "version")

      if name == "" then
        mpkg.echo("This package does not contain any further details.  It was likely installed from a XML import.")
      else
        mpkg.echo(f"Package: <b>{name}</b>")
        mpkg.echo(f"         {title}")
        mpkg.echo("")
        mpkg.echo(f"Status: <b>installed</b> (version: {version})")
        mpkg.echo("")
        mpkg.echo("Description:")

        local description = string.split(getPackageInfo(args, "description"), "\n")

        for i = 1, #description do
          mpkg.echo(description[i])
        end
      end

      return true
    end

    mpkg.echo(f"No package matching <b>{args}</b> found locally, search the repository.")

  end

  -- now search the repository
  packages = mpkg.packages["packages"]

  for i = 1, #packages do
    if args == packages[i]["mpackage"] then
      mpkg.echo(f"Package: <b>{packages[i]['mpackage']}</b> (version: {packages[i]['version']}) by {packages[i]['author']}")
      mpkg.echo(f"         {packages[i]['title']}")
      mpkg.echo("")

      local version = getPackageInfo(args, "version")

      if version == "" then
        mpkg.echoLink("Status: not installed  ", "[install now]\n", function() mpkg.install(args) end, "install now", true)
      else
        mpkg.echo(f"Status: <b>installed</b> (version: {version})")
      end
      mpkg.echo("")

      local description = string.split(packages[i]["description"], "\n")

      for i = 1, #description do
        mpkg.echo(description[i])
      end

      return true
    end
  end

  mpkg.echo(f"No package matching <b>{args}</b> found in the repository. Try <yellow>mpkg search<reset>.")
  return false

end


--- Toggles debugging information for program diagnostics.
-- Prints out further information when debug is true (default: false) when calling;
-- checkForUpgrades(), listInstalledPackages(), whenever the eventHandler is fired.
function mpkg.toggleDebug()

  if mpkg.debug then
    mpkg.debug = false
    mpkg.echo("mpackage debugging disabled.")
  else
    mpkg.debug = true
    mpkg.echo("mpackage debugging <b>ENABLED</b>.")
  end

end


--- Reacts to downloading of repository files and self install/uninstall events.
-- @param event the event which called this handler; sysDownloadError, sysDownloadDone
-- @param arg all event args, including the filename associated with the download
function mpkg.eventHandler(event, ...)

  if mpkg.debug then
    display(event)
    display(arg)
  end

  if event == "sysDownloadError" and string.ends(arg[2], mpkg.filename) then
    if not mpkg.silentFailures then
      mpkg.echo("Failed to download package listing.")
      mpkg.silentFailures = true
    end
    return
  end

  if event == "sysDownloadDone" and arg[1] == getMudletHomeDir() .. "/" .. mpkg.filename then

    if mpkg.displayUpdateMessage then
      mpkg.echo("Package listing downloaded.")
      mpkg.displayUpdateMessage = nil
    end

    local file, error, content = io.open(arg[1])

    if error then
      mpkg.echo(f"Error reading package listing file.  Please file a bug report at {mpkg.maintainer}")
    else
      content = file:read("*a")
      mpkg.packages = json_to_value(content)
      io.close(file)
      mpkg.checkForUpgrades(true)
    end

    if semver(mpkg.getInstalledVersion("mpkg")) < semver(mpkg.getRepositoryVersion("mpkg")) then
      mpkg.echo(f"New version of mpkg found.  Automatically upgrading to {mpkg.getRepositoryVersion('mpkg')}")
      mpkg.remove("mpkg")
      tempTimer(2, function() mpkg.install("mpkg") end)
    end
  end

  if event == "sysUninstallPackage" and arg[1] == "mpkg" then
    mpkg.uninstallSelf()
    return
  end

  if event == "sysInstallPackage" and arg[1] == "mpkg" then
    mpkg.displayHelp()
    return
  end

end


function mpkg.openWebUploads()

  mpkg.echo("Redirecting to the package repository website.")
  openUrl(mpkg.websiteUploads)

end

-- clean up after uninstallation of mpkg
function mpkg.uninstallSelf()

  deleteNamedTimer("mpkg", "mpkg update package listing timer")

  deleteNamedEventHandler("mpkg", "download")
  deleteNamedEventHandler("mpkg", "download-error")
  deleteNamedEventHandler("mpkg", "installed")
  deleteNamedEventHandler("mpkg", "uninstalled")


  if mpkg and mpkg.aliases then
    for _,v in pairs(mpkg.aliases) do
      killAlias(v)
    end
  end

  mpkg.aliases = nil

end

-- call the script entry point function
mpkg.initialise()
