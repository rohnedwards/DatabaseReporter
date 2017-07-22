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

        $Expected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        Get-CustomerNoFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
        Get-CustomerWithFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }

    It 'FromClause works with and without ''FROM'' keyword with extra linebreaks' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand Get-CustomerNoFrom {
                [MagicDbInfo(
                    FromClause = '
                        Customers 
                        JOIN Orders 
                            on Customers.CustomerId = Orders.CustomerId
                    ',
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
                    FromClause = '
                        FROM Customers 
                        JOIN Orders 
                            on Customers.CustomerId = Orders.CustomerId
                    ',
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

        $Expected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        Get-CustomerNoFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
        Get-CustomerWithFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
    }
    
    It 'Dynamic FROM works with ScriptBlock' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            $FakeConnection = New-Object System.Data.SqlClient.SqlConnection ''
            Set-DbReaderConnection $FakeConnection

            DbReaderCommand Get-CustomerDynamicFrom {
                [MagicDbInfo(
                    FromClause = {
                        if ($UseAltCustomers) { 
                            'AltCustomers
                            JOIN Orders
                                on AltCustomers.CustomerId = Orders.CustomerId'
                        }
                        else {
                            'Customers 
                            JOIN Orders 
                                on Customers.CustomerId = Orders.CustomerId'
                        }
                    }
                )]
                param(
                    [MagicDbProp(ColumnName='Customers.CustomerId')]
                    [int] $CustomerId,
                    [MagicDbProp(ColumnName='Customers.FirstName')]
                    [string] $FirstName,
                    [MagicDbProp(ColumnName='Customers.LastName', ComparisonOperator='ILIKE')]
                    [string] $LastName,
                    [MagicDbProp(ColumnName='Customers.Title', ComparisonOperator='FAKEOP')]
                    [string] $Title,
                    [switch] $UseAltCustomers
                )
            }
        } 

        $Expected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        $AltExpected = "SELECT Customers.CustomerID as CustomerID*Customers.Title AS Title FROM AltCustomers JOIN Orders on AltCustomers.CustomerId = Orders.CustomerId*" | NormalizeQuery
        Get-CustomerDynamicFrom -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $Expected
        Get-CustomerDynamicFrom -UseAltCustomers -CustomerId 123, 456 -ReturnSqlQuery | NormalizeQuery | Should BeLike $AltExpected
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

    It 'SELECT * When No [MagicDbColumn()] attributes specified' {

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
                    [int] $CustomerId,
                    [string] $FirstName,
                    [string] $LastName,
                    [string] $Title
                )
            }
        } 

        $Expected = "SELECT * FROM Customers JOIN Orders on Customers.CustomerId = Orders.CustomerId"
        # Gotta fix the parameter list in -ReturnSql. Maybe use Write-Host?
        Get-Customer -ReturnSqlQuery | NormalizeQuery | Test-QueryMatch $Expected | Should Be $true 
    }

    It 'InvokeReaderCommand handles duplicate properties' {
        # InvokeReaderCommand needs to be modified so that the executing of the reader command is separate
        # so that part can be mocked. Might have to create a dummy C# class to mimic a reader object, too :(
    }

    It 'DbReaderCommand parameters don''t conflict with ReferenceCommand parameters' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true
            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            Set-DbReaderConnection (New-Object System.Data.SqlClient.SqlConnection '')

            DbReaderCommand Get-Demographics {
                [MagicDbInfo(
                    FromClause = 'Sales.vPersonDemographics demo
                    FULL JOIN Person.Person person ON demo.BusinessEntityID = person.BusinessEntityID'
                )]
                param(
                    [string] $Param # $Param is a variable used in the reference script block (at the time of the test)
                )
            }
        }
        
        { Get-Demographics -ReturnSqlQuery -ErrorAction Stop } | Should Not Throw
    }

    It '[datetime] columns can search for $null' {

        $TestMod = New-Module -Name DBTest -ScriptBlock {
            $DebugMode = $true
            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            Set-DbReaderConnection (New-Object System.Data.SqlClient.SqlConnection '')

            DbReaderCommand Get-Demographics {
                [MagicDbInfo(
                    FromClause = 'Sales.vPersonDemographics demo
                    FULL JOIN Person.Person person ON demo.BusinessEntityID = person.BusinessEntityID'
                )]
                param(
                    [MagicDbProp(ColumnName='StartTime')]
                    [datetime] $DateTimeColumn
                )
            }
        }
        
        Get-Demographics -ReturnSqlQuery -DateTimeColumn $null | NormalizeQuery | Should BeLike '*((StartTime IS NULL))*'
    }
}