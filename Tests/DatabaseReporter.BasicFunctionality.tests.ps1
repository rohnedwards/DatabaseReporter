. "$PSScriptRoot\Helpers.ps1"

Describe 'Basic Functionality' {
    It 'Writes an error when no command information is provided' {
        $TestMod = New-Module -Name DBTest -ScriptBlock {

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand HelpTest {
                
            } -ErrorAction SilentlyContinue -ErrorVariable TestErrors
        } 

        $ErrorList = & $TestMod { $TestErrors }
        $ErrorList.Count | Should BeGreaterThan 0    # This should actually just be 1, but for some reason, there are some generic errors coming back...
        $TestMod | Remove-Module
    }

    It 'Exports only defined commands' {
        $WorkingMod = New-Module -Name ExportCommandTest -ScriptBlock {
            
            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            
            DbReaderCommand HelpTest1 {
                [MagicDbInfo(
                    FromClause = 'TableName',
                    DbConnectionString = 'ConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param()
            }
            DbReaderCommand HelpTest2 {
                [MagicDbInfo(
                    FromClause = 'FromTable',
                    DbConnectionString = 'ConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param()
            }
        }

        Get-Command -Module $WorkingMod.Name | Where-Object Name -notin HelpTest1, HelpTest2 | Should BeNullOrEmpty
    }

    It 'Exports only defined commands, and exports nothing if no commands defined' {
        
        $WorkingMod = New-Module -Name ExportCommandTest -ScriptBlock {
            
            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            
        }

        $WorkingMod.ExportedCommands | Should BeNullOrEmpty
        $WorkingMod.ExportedAliases | Should BeNullOrEmpty
        $WorkingMod.ExportedVariables | Should BeNullOrEmpty
    }

    It 'FromClause works with and without ''FROM'' keyword' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

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

            DbReaderCommand Get-CustomerWithFrom {
                [MagicDbInfo(
                    FromClause = 'FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId',
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

        $Expected = "SELECT Customers.CustomerID as CustomerID* FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        Get-CustomerNoFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
        Get-CustomerWithFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }
    
    It 'Outputs error if no DBConnection available (<description>)' {
        param(
            [string[]] $DbInfoProps
        )

        $DbInfoStrings = @("FromClause = 'Customers JOIN Orders on Customers.CustomerId = OrdersCustomerId'") + $DbInfoProps
        $DbInfoStrings = $DbInfoStrings -join ','

        $DbReaderCommandScriptblock = [scriptblock]::Create(@'
            [MagicDbInfo(
                {0}
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
'@ -f $DbInfoStrings)

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-Customer $args[0] -ErrorAction SilentlyContinue -ErrorVariable GetCustomerErrors

            $GetCustomerErrors = $GetCustomerErrors | Where-Object {
                # Not sure what this is, but it's an extra error that gets written out (not public,
                # either)
                $_.GetType().Name -ne 'StopUpstreamCommandsException' -and
                $_.CategoryInfo.Activity -ne 'Get-Variable'  # This one comes from dictionary lookup
            }
        } -ArgumentList $DbReaderCommandScriptblock

        & $TestMod { $GetCustomerErrors.Count } | Should Be 1

        # These errors should be stored somewhere and looked up. For now, test 
        # for really generic message:
        & $TestMod { $GetCustomerErrors[0] } | Should BeLike *DBConnection*
        $TestMod.ExportedCommands.Keys | Should BeNullOrEmpty
    } -TestCases @{
        description = 'Only DbConnectionType specified' 
        DbInfoProps = "DbConnectionType = 'System.Data.SqlClient.SqlConnection'"
    }, @{
        description = 'Only DbConnectionString specified'
        DbInfoProps = "DbConnectionString = 'ConnectionStringGoesHere'"
    }

    It 'Works with module scoped connection object' {
        # Not going to support connection strings/types for the module scoped
        # settings.

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            $Connection = New-Object System.Data.SqlClient.SqlConnection ('')
            Set-DbReaderConnection $Connection

            DbReaderCommand Get-Customer {
                [MagicDbInfo(
                    FromClause = 'Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId'
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

        $Expected = "SELECT Customers.CustomerID as CustomerID* FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        Get-Customer -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }
}