. "$PSScriptRoot\Helpers.ps1"

Describe 'LIKE supports ESCAPE clause (Tested for SQLite)' {

    It '_ and % are properly escaped in SqlLite mode (SqlMode used)' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-CustomerWildcardEscape {
                [MagicDbInfo(
                    FromClause = 'Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection',
                    SqlMode='SQLite'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName')]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName,
                    [MagicDbProp(ColumnName='Customers.Title')]
                    [string] $Title
                )
            }
        } 

        $Expected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*WHERE*Customers.LastName LIKE @LastName0 ESCAPE '\'*" | NormalizeQuery
        $Result = Get-CustomerWildcardEscape -LastName t%est_* -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $Expected
        $Result.Parameters['@LastName0'] | Should Be 't\%est\_%'
    }

    It '_ and % are properly escaped in SQLite mode (Auto detect)' {
        # No test yet since the framework won't allow an unknown type to be used.
        # Easy enough to test, but easiest way requires adding Sqlite library with
        # call to Add-Type...
    }

    It 'WildcardReplacementScriptblock allows custom logic' {
        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-TestData {
                [MagicDbInfo(
                    FromClause='Test',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection',
                    WildcardReplacementScriptblock={ ($_ -replace '(?<!\\)@', '%') -replace '\\@', '@'}
                )]
                param(
                    [MagicDbProp()]
                    [string] $Email
                )
            }
        }

        $Expected = "SELECT Email AS Email FROM Test*WHERE*Email LIKE @Email0*" | NormalizeQuery
        $Result = Get-TestData -Email test\@@.com -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $Expected
        $Result.Parameters['@Email0'] | Should Be 'test@%.com'
    }

    It 'WhereConditionBuilder allows custom logic' {
        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-TestData {
                [MagicDbInfo(
                    FromClause='Test',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection',
                    WhereConditionBuilderScriptblock={ 
                        if ($args[1] -eq 'LIKE') {
                            '{0} {1} {2} /* This is a {1} test */' -f $args 
                        }
                        else {
                            '{0} {1} {2}' -f $args
                        }
                    }
                )]
                param(
                    [MagicDbProp()]
                    [string] $Email
                )
            }
        }

        $ExpectedWithLike = "SELECT Email AS Email FROM Test*WHERE*Email LIKE @Email0*This is a LIKE test*" | NormalizeQuery
        $ExpectedWithEq = "SELECT Email AS Email FROM Test*WHERE*Email = @Email0*" | NormalizeQuery
        $Result = Get-TestData -Email test -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $ExpectedWithLike

        $Result = Get-TestData -Email @{V='test'; ComparisonOperator='='} -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $ExpectedWithEq
        $Result.Query | NormalizeQuery | Should Not BeLike '*This is a * test'
    }

    It 'Invalid SqlMode doesn''t cause warnings or errors' {
        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-TestData {
                [MagicDbInfo(
                    FromClause='Test',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection',
                    SqlMode='ThisShouldNeverBeValid'
                )]
                param(
                    [MagicDbProp()]
                    [string] $Email
                )
            }
        } -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable TestWarnings -ErrorVariable TestErrors

        $TestWarnings.Count | Should Be 0
        $TestErrors.Count | Should Be 0

        $Expected = "SELECT Email AS Email FROM Test*WHERE*Email LIKE @Email0*" | NormalizeQuery
        $Result = Get-TestData -Email test -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $Expected
        $Result.Parameters['@Email0'] | Should Be 'test'
    }
}