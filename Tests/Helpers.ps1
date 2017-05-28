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
       $Query -replace $ReplaceRegex, ' ' | % Trim
    }
}

function Test-SqlStatement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Query1,
        [Parameter(Mandatory)]
        [string] $Query2
    )
   process {
        ($Query1 | NormalizeQuery) -eq ($Query2 | NormalizeQuery)
    }
}