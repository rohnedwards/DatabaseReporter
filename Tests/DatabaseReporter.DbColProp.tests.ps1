

. "$PSScriptRoot\Helpers.ps1"

Describe '[MagicDbProp()]' {

    $TestMod = New-Module -Name DBTest -ScriptBlock {
        $DebugMode = $true

        . "$PSScriptRoot\..\DatabaseReporter.ps1"

        DbReaderCommand Get-Customer {
            [MagicDbInfo(
                FromClause = 'FROM Customers',
                DbConnectionString = 'FakeConnectionString',
                DbConnectionType = 'System.Data.SqlClient.SqlConnection'
            )]
            param(
                [MagicDbProp(ColumnName='Customers.CustomerId')]
                [int] $CustomerId,
                [MagicDbProp(ColumnName='Customers.FirstName')]
                [string] $FirstName,
                [MagicDbProp(ColumnName='Customers.LastName', ComparisonOperator='ILIKE')]
                [string] $LastName,
                [MagicDbProp(ColumnName='Customers.Title', ComparisonOperator='FAKEOP')]
                [string] $Title
            )
        }

        DbReaderCommand Get-CustomerNoFrom {
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
                [MagicDbProp(ColumnName='Customers.LastName', ComparisonOperator='ILIKE')]
                [string] $LastName,
                [MagicDbProp(ColumnName='Customers.Title', ComparisonOperator='FAKEOP')]
                [string] $Title
            )
        }
    } 

    $TestModRenamed = New-Module -Name DBTest2 -ScriptBlock {
        $DebugMode = $true

        . "$PSScriptRoot\..\DatabaseReporter.ps1"

        $__FakeAttributes.DbColumnProperty = 'RenamedProp'
        DbReaderCommand Get-Customer2 {
            [MagicDbInfo(
                FromClause = 'FROM Customers',
                DbConnectionString = 'FakeConnectionString',
                DbConnectionType = 'System.Data.SqlClient.SqlConnection'
            )]
            param(
                [RenamedProp(ColumnName='Customers.CustomerId')]
                [int] $CustomerId,
                [RenamedProp(ColumnName='Customers.FirstName')]
                [string] $FirstName,
                [RenamedProp(ColumnName='Customers.LastName', ComparisonOperator='ILIKE')]
                [string] $LastName,
                [RenamedProp(ColumnName='Customers.Title', ComparisonOperator='FAKEOP')]
                [string] $Title
            )
        }
    } 

    It 'FromClause works without ''FROM'' keyword' {
        $Expected = "SELECT Customers.CustomerID as CustomerID* FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId WHERE (Customers.CustomerId = 123 OR Customers.CustomerId = 456)" | NormalizeQuery
        Get-CustomerNoFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }
    It 'Attribute Can Be Renamed' {
        Get-Customer -CustomerId 123, 456 -ReturnSqlQuery | Should Be (Get-Customer2 -CustomerId 123, 456 -ReturnSqlQuery)
    }
    It 'ColumnName Property Works as Expected' {
        $Expected = "SELECT Customers.CustomerID as CustomerID* FROM Customers WHERE (Customers.CustomerId = 123 OR Customers.CustomerId = 456)" | NormalizeQuery
        Get-Customer -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery |  Should BeLike $Expected
    }
    It 'ComparisonOperator Property Works as Expected' {
        $Expected = "SELECT Customers.CustomerId as CustomerId, Customers.FirstName AS FirstName, Customers.LastName AS LastName, Customers.Title AS Title FROM Customers WHERE (Customers.CustomerId = 123 OR Customers.CustomerId = 456) AND (Customers.FirstName LIKE 'Fred' OR Customers.FirstName LIKE 'George') AND (Customers.LastName ILIKE 'A%') AND (Customers.Title FAKEOP 'Blah')" | NormalizeQuery
        Get-Customer -CustomerId 123, 456 -FirstName Fred, George -LastName A* -Title Blah -ReturnSqlQuery | NormalizeQuery |  Should Be $Expected
    }

    It 'ConditionalOperator attribute works as expected' {
        $Expected = "
            SELECT
                Customers.FirstName AS FirstName,
                Customers.LastName AS LastName
            FROM
                Customers
            WHERE
                (Customers.FirstName LIKE 'a%' AND Customers.FirstName LIKE 'e%') AND
                (Customers.LastName LIKE 'a%' OR Customers.LastName LIKE 'e%')" | NormalizeQuery
        
        $CurrMod = New-Module -Name CondOpTest -ScriptBlock {

            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            DbReaderCommand Get-CondOpCustomer {
                [MagicDbInfo(
                    FromClause = 'FROM Customers',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.FirstName', ConditionalOperator='AND')]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName
                )
            }
        }

        Get-CondOpCustomer -FirstName a*, e* -LastName a*, e* -ReturnSqlQuery | NormalizeQuery |  Should Be $Expected
        $CurrMod | Remove-Module
    }

    It 'QuoteString attribute works as expected' {
        $Expected = "
            SELECT
                Customers.CustomerId AS CustomerId,
                Customers.FirstName AS FirstName,
                Customers.LastName AS LastName
            FROM
                Customers
            WHERE
                (Customers.CustomerId = ""123"" OR Customers.CustomerId = ""345"") AND
                (Customers.FirstName LIKE |Name|)" | NormalizeQuery
        
        $CurrMod = New-Module -Name CondOpTest -ScriptBlock {

            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            DbReaderCommand Get-QuoteStringCustomer {
                [MagicDbInfo(
                    FromClause = 'FROM Customers',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId', QuoteString='"')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName', QuoteString='|')]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName
                )
            }
        }

        Get-QuoteStringCustomer -CustomerId 123, 345 -FirstName Name -ReturnSqlQuery | NormalizeQuery |  Should Be $Expected
        $CurrMod | Remove-Module
    }
    It 'TransformArgument attribute works as expected' {
        $Expected = "
            SELECT
                Customers.CustomerId AS CustomerId,
                Customers.FirstName AS FirstName,
                Customers.LastName AS LastName
            FROM
                Customers
            WHERE
                (Customers.FirstName LIKE 'fred' OR Customers.FirstName LIKE 'george') AND
                (Customers.LastName LIKE 'SMITH')" | NormalizeQuery
        
        $CurrMod = New-Module -Name CondOpTest -ScriptBlock {

            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            DbReaderCommand Get-QuoteStringCustomer {
                [MagicDbInfo(
                    FromClause = 'FROM Customers',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName', TransformArgument={ "${_}".ToLower() })]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName
                )
            }
        }

        Get-QuoteStringCustomer -FirstName FRED, GEORGE -LastName SMITH -ReturnSqlQuery | NormalizeQuery |  Should BeExactly $Expected
        $CurrMod | Remove-Module
    }
    It 'TransformArgument attribute throws an error for non-scriptblock value' {
        {
            $CurrMod = New-Module -Name CondOpTest -ScriptBlock {

                $DebugMode = $true

                . "$PSScriptRoot\..\DatabaseReporter.ps1"
                DbReaderCommand Get-QuoteStringCustomer {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
                        DbConnectionString = 'FakeConnectionString',
                        DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                    )]
                    param(
                        [MagicDbProp(ColumnName='Customers.CustomerId')]
                        [int] $CustomerId,
                        [MagicDbProp(ColumnName='Customers.FirstName', TransformArgument='ThisIsBad')]
                        [string] $FirstName,
                        [MagicDbProp(ColumnName='Customers.LastName')]
                        [string] $LastName
                    )
                }
            }
        } | Should Throw

        if ($CurrMod) {
            $CurrMod | Remove-Module
        }
    }

    It 'AllowWildcards attribute works as expected' {

        $Expected = "
            SELECT
                Customers.CustomerId AS CustomerId,
                Customers.FirstName AS FirstName,
                Customers.LastName AS LastName
            FROM
                Customers
            WHERE
                (Customers.FirstName = 'fred?' OR Customers.FirstName = 'george*') AND
                (Customers.LastName LIKE 'fred_' OR Customers.LastName LIKE 'george%')" | NormalizeQuery

        $CurrMod = New-Module -Name AllowWildcardTest -ScriptBlock {

            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            DbReaderCommand Get-WildCardCustomer {
                [MagicDbInfo(
                    FromClause = 'FROM Customers',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName', AllowWildcards=$false)]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName
                )
            }
        }

        Get-WildCardCustomer -FirstName fred?, george* -LastName fred?, george* -ReturnSqlQuery | NormalizeQuery |  Should BeExactly $Expected
        $CurrMod | Remove-Module
    }

    It 'AllowWildcards attribute works as expected' {

        $Expected = "
            SELECT
                Customers.CustomerId AS CustomerId,
                Customers.FirstName AS RenamedFirstName,
                Customers.LastName AS LastName
            FROM
                Customers
            WHERE
                (Customers.FirstName LIKE 'First') AND
                (Customers.LastName LIKE 'Name')" | NormalizeQuery

        $CurrMod = New-Module -Name PropertyNameTest -ScriptBlock {

            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            DbReaderCommand Get-PropNameCustomer {
                [MagicDbInfo(
                    FromClause = 'FROM Customers',
                    DbConnectionString = 'FakeConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName', PropertyName='RenamedFirstName')]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName')]
                    [string] $LastName
                )
            }
        }

        Get-PropNameCustomer -FirstName First -LastName Name -ReturnSqlQuery | NormalizeQuery |  Should BeExactly $Expected
        $CurrMod | Remove-Module
    }

    It 'Formatting info changes properly when ProperyName attribute is used' {}

    $TestMod | Remove-Module
    $TestModRenamed | Remove-Module
}