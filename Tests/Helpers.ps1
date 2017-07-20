$DatabaseReporterLocation = "$PSScriptRoot\..\DatabaseReporter.ps1"

function NormalizeQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Query
    )
    begin {
        $ReplaceRegex = '(\s|\n|\r)+' 
    }
    process {
        if ($Query -match '(?s)^\s*\/\*.*\*\/\s*$') {
            # Exit w/o doing anything since this seems to be the parameter value string
            return
        } 
        $Query -replace $ReplaceRegex, ' ' | ForEach-Object Trim
    }
}

function Test-QueryMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Query1,
        [Parameter(Mandatory, Position=0)]
        [string] $Query2
    )
   process {
        ($Query1 | NormalizeQuery) -ceq ($Query2 | NormalizeQuery)
    }
}

function Test-DictionaryMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Collections.IDictionary] $Dictionary1,
        [Parameter(Mandatory, Position=0)]
        [System.Collections.IDictionary] $Dictionary2
    )

    begin {
        $ToKeyValueStrings = {
            '{0}:{1}' -f $_.Name, $_.Value
        }
    }

    process {
        $RefObject = $Dictionary1.GetEnumerator() | ForEach-Object $ToKeyValueStrings
        $DiffObject = $Dictionary2.GetEnumerator() | ForEach-Object $ToKeyValueStrings

        if ($null -eq $RefObject) { $RefObject = '' }
        if ($null -eq $DiffObject) { $DiffObject = '' }
        $Differences = Compare-Object $RefObject $DiffObject -CaseSensitive

        # If the dicts matched, there shouldn't be any differences
        -not $Differences
    }
}