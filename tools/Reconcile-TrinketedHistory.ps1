<#
.SYNOPSIS
    Reconciles an existing TrinketedHistory.lua SavedVariables file with the
    schema TrinketedHistory currently writes, so history filters stop dropping
    older games.

.DESCRIPTION
    TrinketedHistory's save format drifted across roughly 17 schema variants.
    Games written by older builds are missing fields the filter UI requires, or
    carry fields nothing reads any more. The visible symptom is games that no
    filter combination will show.

    This script rewrites the file so every game matches what SaveMatch() writes
    today. It does five things:

      1. bracket    Games with no bracket, or a bracket written as a number
                    (an early-build bug), get the canonical "2v2"/"3v3"/"5v5"
                    derived from team size -- the same rule SaveMatch uses.
                    The bracket dropdown is a hardcoded 2v2/3v3/5v5 list, so
                    anything else is invisible under every bracket filter.
      2. class      Player entries with no class get one inferred from their
                    spec, where that spec belongs to exactly one TBC class.
      3. spec       Player entries with no spec get one backfilled from other
                    games featuring the same player, but ONLY when that player
                    was ever seen as exactly one spec. Anyone observed playing
                    two specs is left alone and reported.
      4. enemyComp  Rebuilt from enemyTeam whenever step 2 changed a class, so
                    the comp dropdown stops showing "?/Druid" style entries.
      5. cleanup    Drops dead fields no current code reads: game-level _v and
                    playerRealm, player-level isSelf and rating.

    Nothing else is touched. eventLog blobs are passed through byte for byte,
    and the file is streamed a line at a time, so a 200MB save file is fine.

    Runs as a report only unless you pass -Apply.

.PARAMETER Path
    The TrinketedHistory.lua to reconcile. If omitted, the script searches the
    usual WoW install locations and uses the one it finds.

.PARAMETER Apply
    Actually rewrite the file. Without this the script only reports.

.PARAMETER NoBackup
    Skip the timestamped backup copy. Not recommended.

.PARAMETER DropIncomplete
    Also delete games where either team has fewer than 2 players. These are
    aborted or corrupt recordings that no bracket filter can ever match.

.EXAMPLE
    .\Reconcile-TrinketedHistory.ps1
    Report what would change, touching nothing.

.EXAMPLE
    .\Reconcile-TrinketedHistory.ps1 -Apply
    Back up the file and rewrite it.

.NOTES
    Close World of Warcraft first. WoW holds the whole SavedVariables table in
    memory and rewrites it on logout, which would overwrite anything this
    script changed.

    Requires only Windows PowerShell 5.1, which ships with Windows. No modules,
    no Node, no Python. If Windows blocks the script, run it as:
        powershell -ExecutionPolicy Bypass -File .\Reconcile-TrinketedHistory.ps1
#>

[CmdletBinding()]
param(
    [string] $Path,
    [switch] $Apply,
    [switch] $NoBackup,
    [switch] $DropIncomplete
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------------------

# Specs that belong to exactly one TBC class. Holy (Paladin/Priest),
# Protection (Warrior/Paladin) and Restoration (Shaman/Druid) are shared, so
# they are deliberately absent -- a spec alone cannot identify the class.
$SPEC_TO_CLASS = @{
    'Arms' = 'Warrior'; 'Fury' = 'Warrior'
    'Retribution' = 'Paladin'
    'Assassination' = 'Rogue'; 'Combat' = 'Rogue'; 'Subtlety' = 'Rogue'
    'Discipline' = 'Priest'; 'Shadow' = 'Priest'
    'Frost' = 'Mage'; 'Fire' = 'Mage'; 'Arcane' = 'Mage'
    'Affliction' = 'Warlock'; 'Demonology' = 'Warlock'; 'Destruction' = 'Warlock'
    'Elemental' = 'Shaman'; 'Enhancement' = 'Shaman'
    'Beast Mastery' = 'Hunter'; 'Marksmanship' = 'Hunter'; 'Survival' = 'Hunter'
    'Balance' = 'Druid'; 'Feral' = 'Druid'
}

# Every spec -> the classes that can hold it. Used to reject a backfill that
# would contradict a class already on the record.
$SPEC_VALID_CLASSES = @{
    'Arms' = @('Warrior'); 'Fury' = @('Warrior')
    'Protection' = @('Warrior', 'Paladin')
    'Holy' = @('Paladin', 'Priest'); 'Retribution' = @('Paladin')
    'Assassination' = @('Rogue'); 'Combat' = @('Rogue'); 'Subtlety' = @('Rogue')
    'Discipline' = @('Priest'); 'Shadow' = @('Priest')
    'Frost' = @('Mage'); 'Fire' = @('Mage'); 'Arcane' = @('Mage')
    'Affliction' = @('Warlock'); 'Demonology' = @('Warlock'); 'Destruction' = @('Warlock')
    'Elemental' = @('Shaman'); 'Enhancement' = @('Shaman')
    'Restoration' = @('Shaman', 'Druid')
    'Beast Mastery' = @('Hunter'); 'Marksmanship' = @('Hunter'); 'Survival' = @('Hunter')
    'Balance' = @('Druid'); 'Feral' = @('Druid')
}

# teamSize -> bracket, mirroring bracketNames in SaveMatch().
$BRACKET_NAMES = @{ 2 = '2v2'; 3 = '3v3'; 5 = '5v5' }

# Names that stand in for an unidentified player rather than naming one. Never
# used as a backfill key -- every "Unknown" is a different person.
$PLACEHOLDER_NAMES = @('Unknown', '')

# Fields no current code path reads. Removed so the file matches SaveMatch().
$DEAD_GAME_FIELDS = @('_v', 'playerRealm')
$DEAD_PLAYER_FIELDS = @('isSelf', 'rating')

# Lines longer than this are eventLog blobs. Never parsed, only copied.
$BLOB_THRESHOLD = 4096

# ---------------------------------------------------------------------------
# Lua line helpers
# ---------------------------------------------------------------------------
# WoW writes SavedVariables one field per line with no indentation, so plain
# line matching is enough -- no Lua parser required.

$script:reKV = [regex] '^\["([^"]*)"\]\s*=\s*(.*?),?$'
$script:reArrayString = [regex] '^"([^"]*)"\s*,?$'

function Get-LuaKey {
    param([string] $Line)
    $m = $script:reKV.Match($Line)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-LuaValue {
    param([string] $Line)
    $m = $script:reKV.Match($Line)
    if (-not $m.Success) { return $null }
    $v = $m.Groups[2].Value
    if ($v.Length -ge 2 -and $v[0] -eq '"' -and $v[$v.Length - 1] -eq '"') {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

function Test-LuaValueQuoted {
    param([string] $Line)
    $m = $script:reKV.Match($Line)
    if (-not $m.Success) { return $false }
    $v = $m.Groups[2].Value
    return ($v.Length -ge 2 -and $v[0] -eq '"' -and $v[$v.Length - 1] -eq '"')
}

function Write-Head {
    param([string] $Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkGray
}

function Format-GameDate {
    param($StartTime)
    # Newer builds write fractional epoch seconds, so parse as a double.
    $n = 0.0
    $ok = [double]::TryParse(
        [string] $StartTime,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref] $n)
    if ($ok -and $n -gt 1000000000) {
        return ([datetimeoffset]::FromUnixTimeSeconds([int64] $n)).ToString('yyyy-MM-dd')
    }
    return 'unknown date'
}

# ---------------------------------------------------------------------------
# Rewrites one buffered game record according to its planned actions.
# Returns the lines to emit. Blob lines are returned untouched.
# ---------------------------------------------------------------------------
function Convert-GameBuffer {
    param(
        [System.Collections.ArrayList] $Buffer,
        $Actions
    )

    $out = New-Object System.Collections.ArrayList
    $depth = 0
    $teamName = $null
    $playerIdx = -1
    $bracketWritten = $false

    for ($i = 0; $i -lt $Buffer.Count; $i++) {
        $raw = $Buffer[$i]
        $isBlob = $raw.Length -gt $BLOB_THRESHOLD
        $line = if ($isBlob) { '' } else { $raw.Trim() }

        # --- table opens -------------------------------------------------
        if (-not $isBlob -and $line.EndsWith('{')) {
            $key = Get-LuaKey $line
            $depth++

            if ($depth -eq 2) {
                if ($key -eq 'friendlyTeam' -or $key -eq 'enemyTeam') {
                    $teamName = $key
                    $playerIdx = -1
                }
                else {
                    $teamName = $null
                }

                # enemyComp holds only strings, so the block can be replaced
                # wholesale by scanning to its closing brace.
                if ($key -eq 'enemyComp' -and $Actions -and $Actions.NewEnemyComp) {
                    [void] $out.Add('["enemyComp"] = {')
                    foreach ($c in $Actions.NewEnemyComp) { [void] $out.Add('"' + $c + '",') }
                    [void] $out.Add('},')
                    while ($i + 1 -lt $Buffer.Count) {
                        $i++
                        $t = $Buffer[$i].Trim()
                        if ($t -eq '}' -or $t -eq '},') { break }
                    }
                    $depth--
                    continue
                }
            }
            elseif ($depth -eq 3 -and $teamName) {
                $playerIdx++
            }

            [void] $out.Add($raw)

            # New player fields go straight after the entry's opening brace.
            if ($depth -eq 3 -and $teamName -and $Actions) {
                $slot = $teamName + ':' + $playerIdx
                if ($Actions.PlayerEdits.ContainsKey($slot)) {
                    $edit = $Actions.PlayerEdits[$slot]
                    if ($edit.Class) { [void] $out.Add('["class"] = "' + $edit.Class + '",') }
                    if ($edit.Spec) { [void] $out.Add('["spec"] = "' + $edit.Spec + '",') }
                }
            }
            continue
        }

        # --- table closes ------------------------------------------------
        if (-not $isBlob -and ($line -eq '}' -or $line -eq '},')) {
            # A bracket the record never had gets added before the game closes.
            if ($depth -eq 1 -and $Actions -and $Actions.SetBracket -and -not $bracketWritten) {
                [void] $out.Add('["bracket"] = "' + $Actions.SetBracket + '",')
                $bracketWritten = $true
            }
            if ($depth -eq 2) { $teamName = $null }
            [void] $out.Add($raw)
            $depth--
            continue
        }

        # --- key = value -------------------------------------------------
        if (-not $isBlob -and $Actions) {
            $key = Get-LuaKey $line
            if ($key) {
                if ($depth -eq 1) {
                    if ($Actions.RemoveGame -contains $key) { continue }
                    if ($key -eq 'bracket' -and $Actions.SetBracket) {
                        [void] $out.Add('["bracket"] = "' + $Actions.SetBracket + '",')
                        $bracketWritten = $true
                        continue
                    }
                }
                elseif ($depth -eq 3 -and $teamName) {
                    $slot = $teamName + ':' + $playerIdx
                    if ($Actions.PlayerEdits.ContainsKey($slot)) {
                        if ($Actions.PlayerEdits[$slot].Remove -contains $key) { continue }
                    }
                }
            }
        }

        [void] $out.Add($raw)
    }

    return $out
}

function Resolve-SavedVariablesPath {
    $roots = @(
        "${env:ProgramFiles(x86)}\World of Warcraft",
        "$env:ProgramFiles\World of Warcraft",
        'C:\World of Warcraft',
        'D:\World of Warcraft',
        'C:\Games\World of Warcraft'
    )
    $hits = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hits += Get-ChildItem -LiteralPath $root -Recurse -Filter 'TrinketedHistory.lua' -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*\SavedVariables' }
    }
    return $hits
}

# ---------------------------------------------------------------------------
# Locate the file
# ---------------------------------------------------------------------------

if (-not $Path) {
    Write-Host 'Searching for TrinketedHistory.lua...' -ForegroundColor DarkGray
    $found = @(Resolve-SavedVariablesPath)
    if ($found.Count -eq 0) {
        throw "Could not find TrinketedHistory.lua. Pass -Path with the full path, e.g. -Path 'C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\<ID>\SavedVariables\TrinketedHistory.lua'"
    }
    if ($found.Count -gt 1) {
        Write-Host 'Found more than one TrinketedHistory.lua:' -ForegroundColor Yellow
        $found | ForEach-Object { Write-Host "  $($_.FullName)" }
        throw 'Pass -Path to choose which one to reconcile.'
    }
    $Path = $found[0].FullName
}

if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
$fileInfo = Get-Item -LiteralPath $Path

Write-Host ''
Write-Host 'Trinketed history reconciler' -ForegroundColor White
Write-Host "  file : $Path"
Write-Host ("  size : {0:N1} MB" -f ($fileInfo.Length / 1MB))
if ($Apply) {
    Write-Host '  mode : APPLY -- the file will be rewritten' -ForegroundColor Yellow
}
else {
    Write-Host '  mode : report only (pass -Apply to write)' -ForegroundColor DarkGray
}

# Only a file WoW is actually reading is at risk of being overwritten on
# logout. Reconciling a copy while the game runs is harmless, so the guard is
# scoped to real SavedVariables paths.
$isLiveSavedVariables = $Path -match '\\WTF\\.*\\SavedVariables\\[^\\]+$'
if ($Apply -and $isLiveSavedVariables) {
    $wow = @(Get-Process -Name 'Wow', 'WowClassic', 'WowT', 'WowB' -ErrorAction SilentlyContinue)
    if ($wow.Count -gt 0) {
        $which = ($wow | ForEach-Object { $_.ProcessName }) -join ', '
        throw "World of Warcraft is running ($which). Log out and close it fully first -- WoW holds SavedVariables in memory and rewrites the file on logout, which would undo these changes."
    }
}

# ---------------------------------------------------------------------------
# Pass 1 -- read the structure, learn each player's spec
# ---------------------------------------------------------------------------

Write-Head 'Pass 1: scanning'

$games = New-Object System.Collections.ArrayList
$playerSpecs = @{}
$linesRead = 0

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$reader = New-Object System.IO.StreamReader($Path, $utf8NoBom, $true)
try {
    $depth = 0
    $inGames = $false
    $game = $null
    $team = $null
    $container = $null
    $player = $null

    while ($null -ne ($raw = $reader.ReadLine())) {
        $linesRead++
        if ($raw.Length -gt $BLOB_THRESHOLD) { continue }
        $line = $raw.Trim()
        if ($line.Length -eq 0) { continue }

        if (-not $inGames) {
            if ($line.StartsWith('["games"]')) { $inGames = $true; $depth = 0 }
            continue
        }

        if ($line.EndsWith('{')) {
            $depth++
            $key = Get-LuaKey $line
            if ($depth -eq 1) {
                $game = [pscustomobject] @{
                    Index        = $games.Count
                    StartTime    = $null
                    Bracket      = $null
                    BracketIsNum = $false
                    HasBracket   = $false
                    EnemyComp    = (New-Object System.Collections.ArrayList)
                    Friendly     = (New-Object System.Collections.ArrayList)
                    Enemy        = (New-Object System.Collections.ArrayList)
                    DeadFields   = (New-Object System.Collections.ArrayList)
                }
                $team = $null
                $container = $null
            }
            elseif ($depth -eq 2) {
                $container = $key
                $team = if ($key -eq 'friendlyTeam' -or $key -eq 'enemyTeam') { $key } else { $null }
            }
            elseif ($depth -eq 3 -and $team -and $game) {
                $player = [pscustomobject] @{
                    Name       = $null
                    Class      = $null
                    Spec       = $null
                    DeadFields = (New-Object System.Collections.ArrayList)
                }
                if ($team -eq 'friendlyTeam') { [void] $game.Friendly.Add($player) }
                else { [void] $game.Enemy.Add($player) }
            }
            continue
        }

        if ($line -eq '}' -or $line -eq '},') {
            if ($depth -eq 3) { $player = $null }
            if ($depth -eq 2) { $team = $null; $container = $null }
            if ($depth -eq 1 -and $game) { [void] $games.Add($game); $game = $null }
            # depth 0 here is the games array closing. TrinketedHistoryDB has
            # sibling tables after it (minimap, settings) whose nested tables
            # would otherwise be mistaken for game records.
            if ($depth -eq 0) { $inGames = $false }
            $depth--
            continue
        }

        if ($depth -eq 3 -and $player) {
            $key = Get-LuaKey $line
            if (-not $key) { continue }
            if ($key -eq 'name') { $player.Name = Get-LuaValue $line }
            elseif ($key -eq 'class') { $player.Class = Get-LuaValue $line }
            elseif ($key -eq 'spec') { $player.Spec = Get-LuaValue $line }
            elseif ($DEAD_PLAYER_FIELDS -contains $key) { [void] $player.DeadFields.Add($key) }
            continue
        }

        # Bare strings at depth 2 belong to enemyComp or playerGuids. Only
        # enemyComp matters here -- playerGuids must not be mistaken for it.
        if ($depth -eq 2 -and $game -and $container -eq 'enemyComp') {
            $m = $script:reArrayString.Match($line)
            if ($m.Success) { [void] $game.EnemyComp.Add($m.Groups[1].Value) }
            continue
        }

        if ($depth -eq 1 -and $game) {
            $key = Get-LuaKey $line
            if (-not $key) { continue }
            if ($key -eq 'startTime') { $game.StartTime = Get-LuaValue $line }
            elseif ($key -eq 'bracket') {
                $game.HasBracket = $true
                $game.Bracket = Get-LuaValue $line
                $game.BracketIsNum = -not (Test-LuaValueQuoted $line)
            }
            elseif ($DEAD_GAME_FIELDS -contains $key) { [void] $game.DeadFields.Add($key) }
            continue
        }
    }
}
finally { $reader.Dispose() }

# The walk emits one trailing record for the file's closing braces. A real game
# always has a startTime, so anything without one is that artifact.
for ($i = $games.Count - 1; $i -ge 0; $i--) {
    if (-not $games[$i].StartTime) { $games.RemoveAt($i) }
}
for ($i = 0; $i -lt $games.Count; $i++) { $games[$i].Index = $i }

Write-Host "  read $linesRead lines, found $($games.Count) games"

foreach ($g in $games) {
    foreach ($p in (@($g.Friendly) + @($g.Enemy))) {
        if (-not $p.Spec) { continue }
        if (-not $p.Name -or ($PLACEHOLDER_NAMES -contains $p.Name)) { continue }
        if (-not $playerSpecs.ContainsKey($p.Name)) { $playerSpecs[$p.Name] = @{} }
        $bucket = $playerSpecs[$p.Name]
        if ($bucket.ContainsKey($p.Spec)) { $bucket[$p.Spec]++ } else { $bucket[$p.Spec] = 1 }
    }
}

# A name is backfillable only if every game that identified its spec agreed.
$specByName = @{}
$ambiguousNames = New-Object System.Collections.ArrayList
foreach ($name in $playerSpecs.Keys) {
    $observed = @($playerSpecs[$name].Keys)
    if ($observed.Count -eq 1) { $specByName[$name] = $observed[0] }
    else { [void] $ambiguousNames.Add($name) }
}

# ---------------------------------------------------------------------------
# Plan -- decide every change before writing anything
# ---------------------------------------------------------------------------

Write-Head 'Pass 2: planning'

$plan = @{}
$stats = [ordered] @{
    'games'                       = $games.Count
    'bracket added (was missing)' = 0
    'bracket fixed (was numeric)' = 0
    'bracket underivable'         = 0
    'class inferred from spec'    = 0
    'class still unknown'         = 0
    'spec backfilled by name'     = 0
    'spec still unknown'          = 0
    'enemyComp rebuilt'           = 0
    'dead fields removed'         = 0
    'games dropped (incomplete)'  = 0
}
$notes = New-Object System.Collections.ArrayList

foreach ($g in $games) {
    $actions = [pscustomobject] @{
        Drop         = $false
        SetBracket   = $null
        RemoveGame   = @($g.DeadFields)
        PlayerEdits  = @{}
        NewEnemyComp = $null
    }

    $friendlyCount = $g.Friendly.Count
    $enemyCount = $g.Enemy.Count

    if ($DropIncomplete -and ($friendlyCount -lt 2 -or $enemyCount -lt 2)) {
        $actions.Drop = $true
        $stats['games dropped (incomplete)']++
        $plan[$g.Index] = $actions
        continue
    }

    # --- bracket ---------------------------------------------------------
    $canonical = $null
    $teamSize = [Math]::Max($friendlyCount, $enemyCount)
    if ($BRACKET_NAMES.ContainsKey($teamSize)) { $canonical = $BRACKET_NAMES[$teamSize] }

    $bracketOk = $g.HasBracket -and (-not $g.BracketIsNum) -and ($g.Bracket -match '^\dv\d$')
    if (-not $bracketOk) {
        if ($canonical) {
            $actions.SetBracket = $canonical
            if ($g.BracketIsNum) { $stats['bracket fixed (was numeric)']++ }
            else { $stats['bracket added (was missing)']++ }
        }
        else {
            $stats['bracket underivable']++
            [void] $notes.Add("game #$($g.Index) $(Format-GameDate $g.StartTime): $friendlyCount v $enemyCount players, no bracket can be derived -- left as-is")
        }
    }

    # --- players ---------------------------------------------------------
    foreach ($teamName in @('friendlyTeam', 'enemyTeam')) {
        # @() is load-bearing: a bare `if` returning a one-element collection
        # unrolls it to a scalar, whose .Count is null, silently skipping the
        # whole roster on 1v1 and 2v1 records.
        $roster = @()
        if ($teamName -eq 'friendlyTeam') { $roster = @($g.Friendly) } else { $roster = @($g.Enemy) }
        for ($pi = 0; $pi -lt $roster.Count; $pi++) {
            $p = $roster[$pi]
            $newClass = $null
            $newSpec = $null

            if (-not $p.Class) {
                if ($p.Spec -and $SPEC_TO_CLASS.ContainsKey($p.Spec)) {
                    $newClass = $SPEC_TO_CLASS[$p.Spec]
                    $p.Class = $newClass   # so the enemyComp rebuild below sees it
                    $stats['class inferred from spec']++
                }
                else {
                    $stats['class still unknown']++
                }
            }

            if (-not $p.Spec) {
                $candidate = $null
                if ($p.Name -and -not ($PLACEHOLDER_NAMES -contains $p.Name) -and $specByName.ContainsKey($p.Name)) {
                    $candidate = $specByName[$p.Name]
                }
                # Never write a spec that contradicts the class on the record.
                if ($candidate -and $p.Class -and $SPEC_VALID_CLASSES.ContainsKey($candidate)) {
                    if (-not ($SPEC_VALID_CLASSES[$candidate] -contains $p.Class)) { $candidate = $null }
                }
                if ($candidate) {
                    $newSpec = $candidate
                    $stats['spec backfilled by name']++
                }
                else {
                    $stats['spec still unknown']++
                }
            }

            $remove = @($p.DeadFields)
            if ($newClass -or $newSpec -or $remove.Count -gt 0) {
                $actions.PlayerEdits[$teamName + ':' + $pi] = @{
                    Class  = $newClass
                    Spec   = $newSpec
                    Remove = $remove
                }
            }
        }
    }

    # --- enemyComp -------------------------------------------------------
    # SaveMatch derives enemyComp from the enemy roster's distinct classes, so
    # rebuild it whenever a class changed above or it never agreed.
    $enemyClasses = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($p in $g.Enemy) {
        if ($p.Class -and -not $seen.ContainsKey($p.Class)) {
            [void] $enemyClasses.Add($p.Class)
            $seen[$p.Class] = $true
        }
    }
    $currentComp = ((@($g.EnemyComp) | Sort-Object) -join '/')
    $rebuiltComp = ((@($enemyClasses) | Sort-Object) -join '/')
    if ($enemyClasses.Count -gt 0 -and $currentComp -ne $rebuiltComp) {
        $actions.NewEnemyComp = @($enemyClasses)
        $stats['enemyComp rebuilt']++
    }

    $stats['dead fields removed'] += $actions.RemoveGame.Count
    foreach ($e in $actions.PlayerEdits.Values) { $stats['dead fields removed'] += $e.Remove.Count }

    $plan[$g.Index] = $actions
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

Write-Head 'What this will change'
foreach ($k in $stats.Keys) {
    $v = $stats[$k]
    $colour = if ($v -eq 0) { 'DarkGray' } else { 'White' }
    Write-Host ("  {0,-30} {1,7}" -f $k, $v) -ForegroundColor $colour
}

if ($ambiguousNames.Count -gt 0) {
    Write-Head 'Players left alone (seen as more than one spec)'
    foreach ($n in ($ambiguousNames | Sort-Object)) {
        $detail = (($playerSpecs[$n].GetEnumerator() | Sort-Object -Property Value -Descending |
                    ForEach-Object { "$($_.Key) x$($_.Value)" }) -join ', ')
        Write-Host ("  {0,-18} {1}" -f $n, $detail)
    }
}

if ($notes.Count -gt 0) {
    Write-Head 'Games needing a look'
    foreach ($n in $notes) { Write-Host "  $n" -ForegroundColor Yellow }
    if (-not $DropIncomplete) {
        Write-Host '  (re-run with -DropIncomplete to delete these instead)' -ForegroundColor DarkGray
    }
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Report only -- nothing was written. Re-run with -Apply to make these changes.' -ForegroundColor Cyan
    Write-Host ''
    return
}

# ---------------------------------------------------------------------------
# Pass 3 -- rewrite
# ---------------------------------------------------------------------------
# Buffers one game at a time so edits stay local. eventLog blobs ride along in
# the buffer untouched.

Write-Head 'Pass 3: writing'

$tempPath = "$Path.reconcile-tmp"
$reader = New-Object System.IO.StreamReader($Path, $utf8NoBom, $true)
$writer = New-Object System.IO.StreamWriter($tempPath, $false, $utf8NoBom)
$writer.NewLine = "`r`n"

$gamesWritten = 0
try {
    $depth = 0
    $inGames = $false
    $gameIdx = -1
    $buffer = $null

    while ($null -ne ($raw = $reader.ReadLine())) {
        $isBlob = $raw.Length -gt $BLOB_THRESHOLD
        $line = if ($isBlob) { '' } else { $raw.Trim() }

        if (-not $inGames) {
            $writer.WriteLine($raw)
            if ($line.StartsWith('["games"]')) { $inGames = $true; $depth = 0 }
            continue
        }

        if (-not $isBlob -and $line.EndsWith('{')) {
            $depth++
            if ($depth -eq 1) {
                $gameIdx++
                $buffer = New-Object System.Collections.ArrayList
            }
        }

        if ($null -ne $buffer) { [void] $buffer.Add($raw) } else { $writer.WriteLine($raw) }

        if (-not $isBlob -and ($line -eq '}' -or $line -eq '},')) {
            if ($depth -eq 1 -and $null -ne $buffer) {
                $actions = if ($plan.ContainsKey($gameIdx)) { $plan[$gameIdx] } else { $null }
                if ($null -eq $actions -or -not $actions.Drop) {
                    foreach ($outLine in (Convert-GameBuffer -Buffer $buffer -Actions $actions)) {
                        $writer.WriteLine($outLine)
                    }
                    $gamesWritten++
                }
                $buffer = $null
            }
            # See pass 1: depth 0 is the games array closing, and the sibling
            # tables after it are not games.
            if ($depth -eq 0) { $inGames = $false }
            $depth--
        }
    }
}
finally {
    $reader.Dispose()
    $writer.Dispose()
}

Write-Host "  wrote $gamesWritten games"

# ---------------------------------------------------------------------------
# Verify before replacing anything
# ---------------------------------------------------------------------------

Write-Head 'Verifying output'

$expected = $games.Count - $stats['games dropped (incomplete)']
$problems = New-Object System.Collections.ArrayList

if ($gamesWritten -ne $expected) {
    [void] $problems.Add("expected $expected games, wrote $gamesWritten")
}

$vGames = 0
$vBraces = 0
$vDead = 0
$vBadBracket = 0
$vBracketed = 0
$reader = New-Object System.IO.StreamReader($tempPath, $utf8NoBom, $true)
try {
    $depth = 0
    $inGames = $false
    $sawBracket = $false
    while ($null -ne ($raw = $reader.ReadLine())) {
        if ($raw.Length -gt $BLOB_THRESHOLD) { continue }
        $line = $raw.Trim()
        if ($line.Length -eq 0) { continue }

        if ($line.EndsWith('{')) { $vBraces++ }
        elseif ($line -eq '}' -or $line -eq '},') { $vBraces-- }

        if (-not $inGames) {
            if ($line.StartsWith('["games"]')) { $inGames = $true; $depth = 0 }
            continue
        }
        if ($line.EndsWith('{')) {
            $depth++
            if ($depth -eq 1) { $vGames++; $sawBracket = $false }
            continue
        }
        if ($line -eq '}' -or $line -eq '},') {
            if ($depth -eq 1 -and -not $sawBracket) { $vBadBracket++ }
            if ($depth -eq 0) { $inGames = $false }
            $depth--
            continue
        }
        $key = Get-LuaKey $line
        if (-not $key) { continue }
        if ($DEAD_GAME_FIELDS -contains $key -or $DEAD_PLAYER_FIELDS -contains $key) { $vDead++ }
        if ($depth -eq 1 -and $key -eq 'bracket') {
            $sawBracket = $true
            $vBracketed++
            if (-not (Test-LuaValueQuoted $line) -or ((Get-LuaValue $line) -notmatch '^\dv\d$')) {
                [void] $problems.Add("non-canonical bracket survived: $line")
            }
        }
    }
}
finally { $reader.Dispose() }

if ($vBraces -ne 0) { [void] $problems.Add("unbalanced braces in output (net $vBraces)") }
if ($vGames -ne $gamesWritten) { [void] $problems.Add("re-scan counted $vGames games, wrote $gamesWritten") }
if ($vDead -ne 0) { [void] $problems.Add("$vDead dead fields survived") }

$allowedBracketless = $stats['bracket underivable']
if ($vBadBracket -gt $allowedBracketless) {
    [void] $problems.Add("$vBadBracket games have no bracket, expected at most $allowedBracketless")
}

Write-Host "  games        $vGames"
Write-Host "  with bracket $vBracketed"
Write-Host "  brace balance $vBraces"

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "  PROBLEM: $p" -ForegroundColor Red }
    Remove-Item -LiteralPath $tempPath -Force
    throw 'Verification failed. The original file was NOT modified and the temp file was discarded.'
}

Write-Host '  ok' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Swap in the reconciled file
# ---------------------------------------------------------------------------

if (-not $NoBackup) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupPath = "$Path.reconcile-backup-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Host ''
    Write-Host "Backup: $backupPath" -ForegroundColor DarkGray
}

Move-Item -LiteralPath $tempPath -Destination $Path -Force

Write-Host ''
Write-Host 'Done. Launch WoW and check the history filters.' -ForegroundColor Green
Write-Host ''
