Describe 'Argument Completion' {

    # For now, one monolithic module will be used for all the testing
    $Module = New-Module {
        . "$pwd\DatabaseReporter.ps1"

        DbReaderCommand Get-Customer {
            [MagicDbInfo(FromClause = 'FROM DoesntMatter',
                DbConnectionString = 'FakeConnectionString',
                DbConnectionType = 'System.Data.SqlClient.SqlConnection'
            )]
            param(
                [MagicDbProp()]
                [int] $CustomerId,
                [MagicDbProp()]
                [string] $FirstName,
                [MagicDbProp()]
                [string] $LastName,
                [MagicDbProp()]
                [MagicDbComparisonSuffix()]
                [int] $SomeNumber,
                [MagicDbProp()]
                [string] $Title
            )
        }
    }

    # At some point the framework stuff will be hidden behind a submodule, and
    # this code to get at the completer will need to be tweaked
    $ArgCompleter = & $Module { $StandardArgumentCompleter }

    $AllParametersDict = & $Module { Get-Command Get-Customer | Select-Object -ExpandProperty Parameters }
    $NonCommonParameterNames = $AllParametersDict.Keys | Where-Object {
        $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters -and
        $_ -notin [System.Management.Automation.Cmdlet]::OptionalCommonParameters -and
        $_ -notin 'Negate', 'GroupBy', 'OrderBy', 'ReturnSqlQuery'
    }
    $ColumnParameters = & $Module { $__CommandDeclarations.'Get-Customer'.PropertyParameters }
    $ColumnNames = $ColumnParameters.Values | ForEach-Object PropertyName | Sort-Object -Unique

    It 'GroupBy Offers All Parameters (Empty)' {
        $CompletedWords = & $ArgCompleter Get-Customer GroupBy '' $null @{} | Select-Object -ExpandProperty CompletionText
        Compare-Object $CompletedWords $ColumnNames | Should BeNullOrEmpty
    }

    It 'OrderBy Offers All Parameters (Also tests that Count isn''t suggested when GroupBy isn''t specified)' {
        $CompletedWords = & $ArgCompleter Get-Customer OrderBy '' $null @{} | Select-Object -ExpandProperty CompletionText
        Compare-Object $CompletedWords $ColumnNames | Should BeNullOrEmpty
    }

    It 'Negate Offers No Parameters When No Params Specified' {
        & $ArgCompleter Get-Customer Negate '' $null @{} | Select-Object -ExpandProperty CompletionText | Should BeNullOrEmpty
    }

    It 'Negate Offers Parameters That Have Been Specified' {
        $CompletedWords = & $ArgCompleter Get-Customer Negate '' $null @{LastName='Name'; FirstName='Name'} | Select-Object -ExpandProperty CompletionText 
        Compare-Object $CompletedWords 'FirstName', 'LastName' | Should BeNullOrEmpty
    }

    It 'Negate Offers ComparisonSuffix Parameters That Have Been Specified' {
        $CompletedWords = & $ArgCompleter Get-Customer Negate '' $null @{LastName='Name'; FirstName='Name'; SomeNumberGreaterThan=3} | Select-Object -ExpandProperty CompletionText 
        Compare-Object $CompletedWords 'FirstName', 'LastName', 'SomeNumberGreaterThan' | Should BeNullOrEmpty
    }

    It 'OrderBy isn''t fooled by fake GroupBy parameters (also tests that Count is suggested word)' {
        $CompletedWords = & $ArgCompleter Get-Customer OrderBy '' $null @{GroupBy = 'fakeparam'} | Select-Object -ExpandProperty CompletionText
        $CompletedWords | Where-Object { $_ -ne 'Count' } | Should BeNullOrEmpty
    }

    It 'Count is suggested word for -OrderBy when -GroupBy is specified' {
        $CompletedWords = & $ArgCompleter Get-Customer OrderBy '' $null @{GroupBy = 'fakeparam'} | Select-Object -ExpandProperty CompletionText
        $CompletedWords | Should Be Count
    }

    # param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
}