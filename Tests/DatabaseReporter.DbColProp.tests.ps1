

. "$PSScriptRoot\Helpers.ps1"

Describe '[MagicDbProp()]' {

    It '<testname>' -test {
        param(
            [scriptblock] $Module,
            [scriptblock] $Commands,
            # Results should have ExpectedQuery and ExpectedParams keys, which
            # are used in the -ParameterFilter for the Assert-MockCalled command.
            [System.Collections.IDictionary[]] $ExpectedResults
        )

        <#
        I'm not happy with how this is working right now. Originally, I was going to use
        InModuleScope to execute the code and Mock InvokeReaderCommand. I wanted to simply
        use the PSModuleInfo for the dynamic modules instead of formally importing the
        modules, but it turns out Pester doesn't seem to support that. I peeked at the code
        that handles it, and it looks like it might be possible to make that work (I'd like
        to see InModuleScope, Mock, and Assert-MockCalled take PSModuleInfo's as an alternative
        to a module name).

        In theory, InModuleScope should still work with these in memory modules if they're
        imported w/ Import-Module, but I still had trouble. Using the -ModuleName on Mock and
        Assert-MockCalled, but that doesn't seem to like re-using the same module name (even
        if the old module is removed first).

        So, GUIDs are used to randomize the module names until a better solution is found.
        #>
        $TempModuleName = '__TempModule__{0}' -f [guid]::NewGuid().ToString('N')
        $TempModule = New-Module -Name $TempModuleName -ScriptBlock $Module
        $TempModule | Import-Module -Force

        # Big change to module structure (InvokeReaderCommand isn't at the top level of the
        # module anymore...it's tucked away into a helper module). This was already a crappy
        # way to do these tests, and it's getting even crappier. Gotta work on fixing this...
        $DBRModule = & $TempModule { $DBRModule }
        Import-Module $DBRModule

        Mock InvokeReaderCommand {
            # This helps with building the tests. If the module code had this
            # variable set to true, then dump the params passed to InvokeReaderCommand:
            if ($__ShowIrcParams) {
                Write-Host "InvokeReaderCommand called with:"  -ForegroundColor DarkYellow
                Write-Host "  Query: ${Query}"
                Write-Host "  QueryParameters:"
                foreach ($QueryParamEntry in $QueryParameters.GetEnumerator()) {
                        Write-Host ('    {0}: {1}' -f $QueryParamEntry.Name, $QueryParamEntry.Value)
                }
            }
        } -ModuleName $DBRModule.Name

        & $Commands

        foreach ($CurrResult in $ExpectedResults) {
            Assert-MockCalled InvokeReaderCommand -ModuleName $DBRModule.Name -ParameterFilter {
                ($Query | Test-QueryMatch $CurrResult.ExpectedQuery) -and
                ($QueryParameters | Test-DictionaryMatch $CurrResult.ExpectedParams)
            }
        }

        $TempModule | Remove-Module
    } -TestCases @(
        @{
            testname = 'PropertyName'
            Commands = { Get-Customer -FirstName a*, $null, b* -LastName a* } 
            ExpectedResults = @{
                ExpectedQuery = '
                SELECT Customers.CustomerId AS CustomerId, Customers.FirstName AS RenamedFirstName, Customers.LastName AS LastName 
                FROM Customers
                WHERE 
                ((Customers.FirstName LIKE @FirstName0 OR Customers.FirstName LIKE @FirstName1) OR (Customers.FirstName IS NULL)) AND
                ((Customers.LastName LIKE @LastName0))
                '
                ExpectedParams = @{
                    '@FirstName0' = 'a%'
                    '@FirstName1' = 'b%'
                    '@LastName0' = 'a%'
                }
            }
            Module = {

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
                        [MagicDbProp(ColumnName='Customers.FirstName', PropertyName='RenamedFirstName')]
                        [string] $FirstName,
                        [MagicDbProp(ColumnName='Customers.LastName')]
                        [string] $LastName
                    )
                }
            }
        },
        @{
            testname = 'ConditionalOperator'
            Commands = { Get-Customer -FirstName a*, e* -LastName a*, e* } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        Customers.FirstName AS FirstName,
                        Customers.LastName AS LastName
                    FROM
                        Customers
                    WHERE
                        ((Customers.FirstName LIKE @FirstName0 AND Customers.FirstName LIKE @FirstName1)) AND
                        ((Customers.LastName LIKE @LastName0 OR Customers.LastName LIKE @LastName1))
                '
                ExpectedParams = @{
                    '@FirstName0' = 'a%'
                    '@FirstName1' = 'e%'
                    '@LastName0' = 'a%'
                    '@LastName1' = 'e%'
                 }
            }
            Module = {
                . "$PSScriptRoot\..\DatabaseReporter.ps1"
                DbReaderCommand Get-Customer {
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
        },
        @{
            testname = 'AllowWildcards'
            Commands = { Get-Customer -FirstName fre?, g* -LastName fre?, g* } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        Customers.CustomerId AS CustomerId,
                        Customers.FirstName AS FirstName,
                        Customers.LastName AS LastName
                    FROM
                        Customers
                    WHERE
                        ((Customers.FirstName = @FirstName0 OR Customers.FirstName = @FirstName1)) AND
                        ((Customers.LastName LIKE @LastName0 OR Customers.LastName LIKE @LastName1))
                '
                ExpectedParams = @{ 
                    '@FirstName0' = 'fre?'
                    '@FirstName1' = 'g*'
                    '@LastName0' = 'fre_'
                    '@LastName1' = 'g%'
                }
            }
            Module = {
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
                        [MagicDbProp(ColumnName='Customers.FirstName', AllowWildcards=$false)]
                        [string] $FirstName,
                        [MagicDbProp(ColumnName='Customers.LastName')]
                        [string] $LastName
                    )
                }
            }
        },
        @{
            testname = 'TransformArgument'
            Commands = {
                Get-QuoteStringCustomer -FirstName FRED, GEORGE -LastName SMITH 
            } 
            ExpectedResults = @{
                ExpectedQuery = '
                SELECT
                    Customers.CustomerId AS CustomerId,
                    Customers.FirstName AS FirstName,
                    Customers.LastName AS LastName
                FROM
                    Customers
                WHERE
                    ((Customers.FirstName LIKE @FirstName0 OR Customers.FirstName LIKE @FirstName1)) AND
                    ((Customers.LastName LIKE @LastName0))
                '
                ExpectedParams = @{ 
                    '@FirstName0' = 'fred'
                    '@FirstName1' = 'george'
                    '@LastName0' = 'SMITH'
                }
            }
            Module = {
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
        },
        @{
            testname = 'ComparisonOperator'
            Commands = { Get-Customer -CustomerId 123, 456 -FirstName Fred, George -LastName A* -Title Blah } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        Customers.CustomerId AS CustomerId,
                        Customers.FirstName AS FirstName,
                        Customers.LastName AS LastName,
                        Customers.Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((Customers.CustomerId = @CustomerId0 OR Customers.CustomerId = @CustomerId1)) AND
                        ((Customers.FirstName LIKE @FirstName0 OR Customers.FirstName LIKE @FirstName1)) AND
                        ((Customers.LastName ILIKE @LastName0)) AND
                        ((Customers.Title FAKEOP @Title0))
                '
                ExpectedParams = @{
                    '@CustomerId0' = 123
                    '@CustomerId1' = 456
                    '@FirstName0' = 'Fred'
                    '@FirstName1' = 'George'
                    '@LastName0' = 'A%'
                    '@Title0' = 'Blah'
                }
            }
            Module = {
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
            }
        },
        @{
            testname = 'Entire attribute name can be changed'
            Commands = { Get-Customer -CustomerId 123, 456 -FirstName Fred, George -LastName A* -Title Blah } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        Customers.CustomerId AS CustomerId,
                        Customers.FirstName AS FirstName,
                        Customers.LastName AS LastName,
                        Customers.Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((Customers.CustomerId = @CustomerId0 OR Customers.CustomerId = @CustomerId1)) AND
                        ((Customers.FirstName LIKE @FirstName0 OR Customers.FirstName LIKE @FirstName1)) AND
                        ((Customers.LastName ILIKE @LastName0)) AND
                        ((Customers.Title FAKEOP @Title0))
                '
                ExpectedParams = @{
                    '@CustomerId0' = 123
                    '@CustomerId1' = 456
                    '@FirstName0' = 'Fred'
                    '@FirstName1' = 'George'
                    '@LastName0' = 'A%'
                    '@Title0' = 'Blah'
                }
            }
            Module = {

                . "$PSScriptRoot\..\DatabaseReporter.ps1"

                $__FakeAttributes.DbColumnProperty = 'RenamedProp'
                DbReaderCommand Get-Customer {
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
        },
        @{
            testname = 'NoParameter'
            Commands = {
                Get-Customer -FirstName a*                

                $Command1 = Get-Command Get-Customer
                $Command2 = Get-Command Get-CustomerAlt

                $Command1, $Command2 | ForEach-Object {
                    $_.Parameters.ContainsKey('CustomerId') | Should Be $false
                }
            } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        Customers.CustomerId AS CustomerId,
                        Customers.FirstName AS FirstName,
                        Customers.LastName AS LastName,
                        Customers.Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((Customers.FirstName LIKE @FirstName0))
                '
                ExpectedParams = @{
                    '@FirstName0' = 'a%'
                }
            }
            Module = {
                . "$PSScriptRoot\..\DatabaseReporter.ps1"

                DbReaderCommand Get-Customer {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
                        DbConnectionString = 'FakeConnectionString',
                        DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                    )]
                    param(
                        [MagicDbProp(ColumnName='Customers.CustomerId', NoParameter)]
                        [int] $CustomerId,
                        [MagicDbProp(ColumnName='Customers.FirstName', NoParameter=$false)]
                        [string] $FirstName,
                        [MagicDbProp(ColumnName='Customers.LastName', ComparisonOperator='ILIKE')]
                        [string] $LastName,
                        [MagicDbProp(ColumnName='Customers.Title', ComparisonOperator='FAKEOP')]
                        [string] $Title
                    )
                }

                DbReaderCommand Get-CustomerAlt {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
                        DbConnectionString = 'FakeConnectionString',
                        DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                    )]
                    param(
                        [MagicDbProp(ColumnName='Customers.CustomerId', NoParameter=$true)]
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
        },
        @{
            testname = 'DbColProp works with no properties'
            Commands = { Get-Customer -FirstName a* } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        CustomerId AS CustomerId,
                        FirstName AS FirstName,
                        LastName AS LastName,
                        Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((FirstName LIKE @FirstName0))
                '
                ExpectedParams = @{
                    '@FirstName0' = 'a%'
                }
            }
            Module = {
                . "$PSScriptRoot\..\DatabaseReporter.ps1"

                DbReaderCommand Get-Customer {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
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
                        [string] $Title
                    )
                }
            }
        }, 
        @{
            testname = 'ValueFromPipelineByPropertyName works'
            Commands = {
                [PSCustomObject] @{ CustomerId = 123 } | Get-Customer
            } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        CustomerId AS CustomerId,
                        FirstName AS FirstName,
                        LastName AS LastName,
                        Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((CustomerId = @CustomerId0))
                '
                ExpectedParams = @{
                    '@CustomerId0' = '123'
                }
            }
            Module = {
                . "$PSScriptRoot\..\DatabaseReporter.ps1"

                DbReaderCommand Get-Customer {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
                        DbConnectionString = 'FakeConnectionString',
                        DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                    )]
                    param(
                        [MagicDbProp()]
                        [Parameter(ValueFromPipelineByPropertyName)]
                        [int] $CustomerId,
                        [MagicDbProp()]
                        [string] $FirstName,
                        [MagicDbProp()]
                        [string] $LastName,
                        [MagicDbProp()]
                        [string] $Title
                    )
                }
            }
        },
        @{
            testname = 'ValueFromPipeline works'
            Commands = {
                123 | Get-Customer
            } 
            ExpectedResults = @{
                ExpectedQuery = '
                    SELECT
                        CustomerId AS CustomerId,
                        FirstName AS FirstName,
                        LastName AS LastName,
                        Title AS Title
                    FROM
                        Customers
                    WHERE
                        ((CustomerId = @CustomerId0))
                '
                ExpectedParams = @{
                    '@CustomerId0' = '123'
                }
            }
            Module = {
                . "$PSScriptRoot\..\DatabaseReporter.ps1"

                DbReaderCommand Get-Customer {
                    [MagicDbInfo(
                        FromClause = 'FROM Customers',
                        DbConnectionString = 'FakeConnectionString',
                        DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                    )]
                    param(
                        [MagicDbProp()]
                        [Parameter(ValueFromPipeline)]
                        [int] $CustomerId,
                        [MagicDbProp()]
                        [string] $FirstName,
                        [MagicDbProp()]
                        [string] $LastName,
                        [MagicDbProp()]
                        [string] $Title
                    )
                }
            }
        }

<#
        }
        @{
            testname = 'dummy'
            Commands = {} 
            ExpectedResults = @{
                ExpectedQuery = '
                '
                ExpectedParams = @{ }
            }
            Module = {
                $__ShowIrcParams = $true
            }
        }
#>
    )
<#

    It 'ComparisonOperator Property Works as Expected' {
        $Expected = "SELECT Customers.CustomerId as CustomerId, Customers.FirstName AS FirstName, Customers.LastName AS LastName, Customers.Title AS Title FROM Customers WHERE (Customers.CustomerId = 123 OR Customers.CustomerId = 456) AND (Customers.FirstName LIKE 'Fred' OR Customers.FirstName LIKE 'George') AND (Customers.LastName ILIKE 'A%') AND (Customers.Title FAKEOP 'Blah')" | NormalizeQuery
        | NormalizeQuery |  Should Be $Expected
    }

#>
    It 'TransformArgument attribute throws an error for non-scriptblock value' {
        {
            $CurrMod = New-Module -Name CondOpTest -ScriptBlock {

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
    It 'Formatting info changes properly when ProperyName attribute is used' {}
}