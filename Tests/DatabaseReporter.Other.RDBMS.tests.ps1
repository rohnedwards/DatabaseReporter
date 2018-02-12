. "$PSScriptRoot\Helpers.ps1"

Describe 'LIKE supports ESCAPE clause (Tested for SQLite)' {

    It '_ and % are properly escaped' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-CustomerWildcardEscape {
                [MagicDbInfo(
                    FromClause = 'Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
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

        $Expected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*WHERE*Customers.LastName LIKE @LastName0 ESCAPE '\'" | NormalizeQuery
        $Result = Get-CustomerWildcardEscape -LastName t%est_* -ReturnSqlQueryNew
        $Result.Query | NormalizeQuery | Should BeLike $Expected
        $Result.Parameters['@LastName0'] | Should Be 't\%est\_%'
    }
}