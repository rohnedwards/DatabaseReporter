$Module = Import-Module $PSScriptRoot\..\SqlMetaData.psm1 -PassThru -Force

InModuleScope -ModuleName $Module.Name {
    function NewParsedColumn {
        [CmdletBinding()]
        param(
            [Parameter(Position=0)]
            [string] $ColumnName,
            [Parameter(Position=1)]
            [string] $ColumnAlias,
            [Parameter(Position=2)]
            [string] $TableOrAlias = '*'
        )

        process {
            if (-not $ColumnAlias) {
                $ColumnAlias = $ColumnName
            }

            [PSCustomObject] @{
                TableOrAlias = $TableOrAlias
                ColumnName = $ColumnName
                ColumnAlias = $ColumnAlias
            }
        }
    }

    function NewParsedTable {
        [CmdletBinding()]
        param(
            [Parameter(Position=0)]
            [string] $TableName,
            [Parameter(Position=1)]
            [string] $TableAlias,
            [Parameter(Position=2)]
            [string] $TableSchema = '*',
            [Parameter(Position=3)]
            [string] $TableCatalog = '*'
        )

        process {
            if (-not $TableAlias) {
                $TableAlias = $TableName
            }

            [PSCustomObject] @{
                TableCatalog = $TableCatalog
                TableSchema = $TableSchema
                TableName = $TableName
                TableAlias = $TableAlias
            }
        }
    }
    Describe "Parse SELECT Statements" {

        It "Works with extra tabs/spaces/line breaks" {
            $SimpleResult = DumbSqlParse "
            `tSELECT 
                prop1
         `t       , prop2 
        FROM 
                        table
                        
                        

                        "
            
            $SimpleResult | Should Not BeNullOrEmpty
            $ExpectedColumns = (NewParsedColumn prop1), (NewParsedColumn prop2)
            Compare-Object $SimpleResult.Columns $ExpectedColumns -Property $ExpectedColumns[0].psobject.Properties.Name | Should BeNullOrEmpty

            $ExpectedTables = (NewParsedTable table)
            Compare-Object $SimpleResult.Tables $ExpectedTables -Property $ExpectedTables[0].psobject.Properties.Name | Should BeNullOrEmpty
        }

        It "Works with compound JOIN conditions" {
            $Results = DumbSqlParse "
            SELECT prop1, prop2
            FROM table
            JOIN table2 ON condition1 = condition1 AND condition2 = condition2 
            " 

            $ExpectedTables = (NewParsedTable table), (NewParsedTable table2)
            Compare-Object $Results.Tables $ExpectedTables -Property $ExpectedTables[0].psobject.Properties.Name | Should BeNullOrEmpty
        }
        
        $Params = @{
            TestCases = Write-Output '', Right, Left, Full, Inner, 'Right Outer' | ForEach-Object {
                @{ JoinModifier = $_ }
            }
            Test = {
                param(
                    [string] $JoinModifier
                )

                $Results = DumbSqlParse "
                    SELECT
                        demo.BusinessEntityID BEID,
                        person.FirstName AS FName,
                        person.LastName AS LastName,
                        Education
                    FROM Sales.vPersonDemographics demo
                    ${JoinModifier} JOIN AdventureWorks2012.Person.Person ON demo.BusinessEntityID = person.BusinessEntityID
                " -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

                $Results | Should Not BeNullOrEmpty
                $ExpectedColumns = (NewParsedColumn BusinessEntityId BEID demo), (NewParsedColumn FirstName FName person), (NewParsedColumn LastName LastName person), (NewParsedColumn Education)
                Compare-Object $Results.Columns $ExpectedColumns -Property $ExpectedColumns[0].psobject.Properties.Name | Should BeNullOrEmpty

                $ExpectedTables = (NewParsedTable vPersonDemographics demo Sales), (NewParsedTable Person -TableSchema Person -TableCatalog AdventureWorks2012)
                Compare-Object $Results.Tables $ExpectedTables -Property $ExpectedTables[0].psobject.Properties.Name | Should BeNullOrEmpty
            }
        }
        It 'Works with <JoinModifier> JOINS' @Params

        $Params = @{
            TestCases = Write-Output '', 'DISTINCT', 'TOP 10', 'TOP 50 PERCENT', 'DISTINCT TOP 10' | ForEach-Object {
                @{ SelectModifier = $_ }
            }
            Test = {
                param(
                    [string] $SelectModifier
                )

                $Results = DumbSqlParse "
                    SELECT ${SelectModifier}
                        demo.BusinessEntityID BEID,
                        person.FirstName AS FName,
                        person.LastName AS LastName,
                        Education
                    FROM Sales.vPersonDemographics demo
                    JOIN AdventureWorks2012.Person.Person ON demo.BusinessEntityID = person.BusinessEntityID
                " -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

                $Results | Should Not BeNullOrEmpty
                $ExpectedColumns = (NewParsedColumn BusinessEntityId BEID demo), (NewParsedColumn FirstName FName person), (NewParsedColumn LastName LastName person), (NewParsedColumn Education)
                Compare-Object $Results.Columns $ExpectedColumns -Property $ExpectedColumns[0].psobject.Properties.Name | Should BeNullOrEmpty

                $ExpectedTables = (NewParsedTable vPersonDemographics demo Sales), (NewParsedTable Person -TableSchema Person -TableCatalog AdventureWorks2012)
                Compare-Object $Results.Tables $ExpectedTables -Property $ExpectedTables[0].psobject.Properties.Name | Should BeNullOrEmpty
            }
        }
        It 'Works with <SelectModifier> SELECTS' @Params


        $Params = @{
            TestCases = Write-Output '=', '!=', '<>', '<=', '>=' | ForEach-Object {
                @{ Operator = $_ }
            }
            Test = {
                param(
                    [string] $Operator
                )

                $Results = DumbSqlParse "
                    SELECT
                        demo.BusinessEntityID BEID,
                        person.FirstName AS FName,
                        person.LastName AS LastName,
                        Education
                    FROM Sales.vPersonDemographics demo
                    JOIN AdventureWorks2012.Person.Person ON demo.BusinessEntityID ${Operator} person.BusinessEntityID
                " -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

                $Results | Should Not BeNullOrEmpty
                $ExpectedColumns = (NewParsedColumn BusinessEntityId BEID demo), (NewParsedColumn FirstName FName person), (NewParsedColumn LastName LastName person), (NewParsedColumn Education)
                Compare-Object $Results.Columns $ExpectedColumns -Property $ExpectedColumns[0].psobject.Properties.Name | Should BeNullOrEmpty

                $ExpectedTables = (NewParsedTable vPersonDemographics demo Sales), (NewParsedTable Person -TableSchema Person -TableCatalog AdventureWorks2012)
                Compare-Object $Results.Tables $ExpectedTables -Property $ExpectedTables[0].psobject.Properties.Name | Should BeNullOrEmpty
            }
        }
        It 'Works with <Operator> JOIN operator' @Params

        It 'Parses columns with Schema.Table.Column' {
            $Results = DumbSqlParse "
                SELECT
                    Schema.Table.Column,
                    Schema.Table.Column2 AS C2,
                    Schema.Table.Column3 C3
                FROM Schema.Table
            "

            $Results.Columns[0].ColumnAlias | Should Be Column
            $Results.Columns[0].ColumnName | Should Be Column
            $Results.Columns[1].ColumnAlias | Should Be C2
            $Results.Columns[1].ColumnName | Should Be Column2
            $Results.Columns[2].ColumnAlias | Should Be C3

            # All should have the same values for these properties:
            $Results.Columns.TableOrAlias | Should Be Table
            #$Results.Columns.TableSchema | Should Be Schema

            $Results.ColumnAliasDict['Table:Column2'] | Should Be C2
        }

        It 'Parses subtables' {
            $Results = DumbSqlParse "
                SELECT
                    Test.Column
                FROM (
                    SELECT Column
                    FROM Table2
                ) AS Test
            "

            $Results.Columns[0].TableOrAlias | Should Be Test
        }
        
    }
}