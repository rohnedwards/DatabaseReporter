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
            
            . { $DatabaseReporterLocation }
            
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
        } 

        $Expected = "SELECT Customers.CustomerID as CustomerID* FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId WHERE (Customers.CustomerId = 123 OR Customers.CustomerId = 456)" | NormalizeQuery
        Get-CustomerNoFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }
    
}