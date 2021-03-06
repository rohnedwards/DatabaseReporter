# [MagicDbInfo()] Attribute

A fake attribute named [MagicDBInfo()] must be added to each command defined via the DbReaderCommand function. It provides, at a minimum, the FROM clause information used when building dynamic SQL queries. The attribute belongs before the param keyword just inside the scriptblock that defines the command:
```
DbReaderCommand Get-TestData {
    [MagicDbInfo(FromClause='Test')]   <#--- This is the proper placement  #>
    param(
    )
}
```

 The attribute has several valid properties that alter the behavior of the command generated by the DbReaderCommand function:

* [FromClause](#fromclause)
* [DbConnectionType](#dbconnectiontype)
* [DbConnectionString](#dbconnectionstring)
* [PSTypeName](#pstypename)
* [WildcardReplacementScriptblock](#wildcardreplacementscriptblock)
* [WhereConditionBuilderScriptblock](#whereconditionbuilderscriptblock)
* [SqlMode](#sqlmode)

<a name="fromclause"></a>
## FromClause

This is the FROM clause that will be inserted directly into the query. It should include the primary table, along with any required JOINs. The word 'FROM' at the start of the clause is optional (when the SQL query is built, it will contain the word FROM). For example, these two definitions would do the same thing:
```
DbReaderCommand Get-TestData {
    [MagicDbInfo(FromClause='Test')]   <#--- No FROM keyword  #>
    param(
    )
}

DbReaderCommand Get-TestData2 {
    [MagicDbInfo(FromClause='FROM Test')]   <#--- With FROM keyword  #>
    param(
    )
}
```

Any required JOIN statements must also be included here:
```
DbReaderCommand Get-TestData {
    [MagicDbInfo(FromClause='
        Test
        JOIN AnotherTest at ON test.id = at.test_id
    ')]
    param(
    )
}
```

Note that extra linebreaks and spaces should not matter (at least one space must be used to separate each word in the clause, though).

If the FROM clause needs to change dynamically, a scriptblock may be used instead of a string. The scriptblock will be executed each time the user runs the defined command. For example, take this command:
```
DbReaderCommand Get-CustomerDynamicFrom {
    [MagicDbInfo(
        FromClause = {
            $TableName = if ($UseAltCustomers) {
                'AltCustomers'
            }
            else {
                'Customers'
            }

            "
                ${TableName} table1
                JOIN Orders ON table1.CustomerId = Orders.CustomerId
            "
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
```

That command's SQL query should change depending on whether or not the -UseAltCustomers switch is specified during runtime.

<a name="dbconnectiontype"></a>
## DbConnectionType

<a name="dbconnectionstring"></a>
## DbConnectionString

<a name="pstypename"></a>
## PSTypeName

This takes a string that is inserted into the resulting object's PSTypeNames collection.

If you don't specify a value, one will be calculated based on the name provided to DbReaderCommand.

Using the PSTypeName value has at least two uses:
* Formatting

  The formatting system requires a PSTypeName (or actual unique type for compiled .NET objects) to utilize default object formatting.

  When using a formatting attribute on a DbReaderCommand's parameter in the param() block, manually specifying a PSTypeName isn't necessary since one will be automatically generated.

* Type validation for input values to other functions. Take this example module:
 ```
  $DbLocation = "${PSScriptRoot}\test.sqlite"
  . $PSScriptRoot\DatabaseReporter.ps1
  
  Add-Type -Path "$PSScriptRoot\System.Data.SQLite.dll"
  Set-DbReaderConnection ([System.Data.SQLite.SQLiteConnection]::new("Data Source=${DbLocation};Version=3;"))

  DbReaderCommand Get-TestData {
      [MagicDbInfo(
          FromClause = "TestTable",
          PSTypeName='MyCustomType'
      )]
      param(
          [MagicDbProp()]
          [int] $ID,
          [MagicDbProp()]
          [MagicDbFormatTableColumn()]
          [string] $Name
      )
  }
  
  function Write-TestData {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory, ValueFromPipeline)]
          [PSTypeName('MyCustomType')] $InputObject
      )
  
      process {
          $InputObject
      }
  }
  Export-ModuleMember Write-TestData
  ```

  In this example, the ```Write-TestData``` function should only accept data output from ```Get-TestData``` since all returned objects are of type ```[MyCustomType]```, and there's a ```[PSTypeName('MyCustomType')]``` requirement for input to the ```Write-TestData``` function.


<a name="sqlmode"></a>
## SqlMode

Different RDBM systems have slightly different flavors of SQL. The DatabaseReporter framework hopes to be able to take some of the more common differences into account, and to be able to change default behavior behind the scenes depending on the DB connection properties.

This propery shouldn't have to be used, as the framework should auto detect the proper value to put here. Valid inputs probably won't be documented, but, as of this writing, the only valid input is 'SQLite'. Invalid inputs won't hurt anything, and will cause the behavior lookups revert to default settigns, which are geared towards SQL Server.

<a name="wildcardreplacementscriptblock"></a>
## WildcardReplacementScriptblock

NOTE: This should not normally be used.

This attribute allows you to override the logic used to replace wildcards to make them SQL compliant. For example, ```test*``` would normally be replaced with ```test%``` when a parameter is set for ```[MagicDbProp(AllowWildcards=$true)]```

Another example, ```test_test?_test%_test*``` would be replaced with the following strings, depending on the RDBM system being used:
```
SQL Server: test[_]test_test[%]test%
SQLite: test\_test_test\%test%         [NOTE THAT WHERE CONDITION MUST DEFINE \ AS ESCAPE CHARACTER IN THIS EXAMPLE]
```

If you find a case where literal SQL wildcards aren't being replaced properly by the framework, please submit a bug before attempting to work around the issue. If the framework is working properly, different rules for different DB systems should automatically be detected and configured.

If for some reason you wanted to have your users use a different wildcard, or if you find some sort of bug that you want to work around immediately without changing the source code, the attribute can be used like this:
```
DbReaderCommand Get-TestData {
    [MagicDbInfo(
        FromClause='Test',
        WildcardReplacementScriptblock={ ($_ -replace '(?<!\\)@', '%') -replace '\\@', '@'}
    )]
    param(
        [MagicDbProp()]
        [string] $Email
    )
}
```
That *should* use ```@``` as a wildcard to search for one or more instances, and it *should* allow you to escape the character with a backslash. So ```Get-TestData -WildcardParam test\@@.com``` should result in a query like this:
```
SELECT Email FROM Test WHERE Email LIKE @Email0

/* @Email0 = 'test@%.com' */
```

<a name="whereconditionbuilderscriptblock"></a>
## WhereConditionBuilderScriptblock

Don't use this. This was added to work around a specific problem, and it will probably be changed in the future. It's included here because it is possible to override it because of the workaround developed for the specific problem. For the sake of completeness, just know that the following `$args` are passed into any scriptblock defined here:
```
$args[0] = ColumnName
$args[1] = Comparison operator
$args[2] = Query parameter name
```
