# DatabaseReporter Framework

Welcome to the DatabaseReporter framework's documentation page.

#### Overview

The DatabaseReporter framework provides a way to generate advanced PowerShell functions that read from a database without having to do any scripting. Instead, you define the command's parameters and add some framework specific attributes.

#### Attributes
* [[MagicDbInfo](MagicDbInfoAttribute.md)()]
* [[MagicDbProp](MagicDbPropAttribute.md)()]
* [[MagicDbFormatTableColumn](MagicDbFormatTableColumnAttribute.md)()]
* [[MagicDbComparisonSuffix](MagicDbComparisonSuffixAttribute.md)()]
* [[MagicPsHelp](MagicPsHelpAttribute.md)()]

#### Usage and example
To use the framework, you need to get the latest version of ```DatabaseReporter.ps1``` from the [project's GitHub repository](https://github.com/rohnedwards/DatabaseReporter).

Once you've downloaded the file, simply copy it into a module's folder structure and dot source it at the beginning of the root module file. Here's an example of the expected folder structure for a module named 'DbReporterTestModule':
```
c:\DbReporterTestModule\
|
|-- DatabaseReporter.ps1
|
|-- DbReporterTestModule.psm1
|
\-- DbReporterTestModule.psd1
```        

Contents of DbReporterTestModule.psm1 {
```

# This should only be enabled when creating your module. It adds a
# common parameter, -ReturnSqlQuery, to all DbReaderCommand instances.
$DebugMode = $true

. "$PSScriptRoot\..\DatabaseReporter.ps1"

# A real connection string would need to go below:
$Connection = New-Object System.Data.SqlClient.SqlConnection ('')
Set-DbReaderConnection $Connection

DbReaderCommand Get-TestUser {
    [MagicDbInfo(FromClause = 'Users')]
    param(
        [MagicDbProp(ColumnName='Users.UserId')]
        [int] $UserId,
        [MagicDbProp(ColumnName='Users.UserName')]
        [string] $UserName
    )
}
```

A module with that structure, and those contents in the root module file, would have a command named 'Get-TestUser' that would have the following syntax:
```
Get-TestUser [[-UserId] <int[]>] [[-UserName] <string[]>] 
                [[-Negate] <string[]>] [[-GroupBy] <string[]>] [[-OrderBy] <string[]>] 
                [<CommonParameters>]
```

The -UserId and -UserName parameters come from the DbReaderCommand definition param() block, and the -Negate, -GroupBy, and -OrderBy common parameters are added to all DbReaderCommand instances.

Running the command generates a SQL select statement (NOTE: The following examples are using the -ReturnSqlQuery switch, which was added to the commands because $DebugMode = $true was present in the module. This switch prevents the command from being run against a database, and simply echos the statement):

```
PS> Get-TestUser -ReturnSqlQuery

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
```

If parameters are used, the WHERE clause is automatically populated with the proper conditions:
```
PS> Get-TestUser -ReturnSqlQuery -UserName a*

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
WHERE
    ((Users.UserName LIKE @UserName0))
```

You can use it to find NULL values, too:
```
PS> Get-TestUser -ReturnSqlQuery -UserName a*, $null

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
WHERE
    ((Users.UserName LIKE @UserName0) OR (Users.UserName IS NULL))
```

WHERE clause conditions can be negated in a few ways:
```
# Negate the entire condition by using the -Negate parameter:
PS> Get-TestUser -ReturnSqlQuery -UserName a*, $null -Negate UserName

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
WHERE
    NOT ((Users.UserName LIKE @UserName0) OR (Users.UserName IS NULL))

# Negate parts of the condition (or the entire thing) by passing a hash
# table for the parameter value with special options)                                <-- ADD REFERENCE TO HELP TOPIC ON THIS
PS> Get-TestUser -ReturnSqlQuery -UserName @{Value='a*'; Negate=$true}, $null

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
WHERE
    ((Users.UserName IS NULL) OR NOT (Users.UserName LIKE @UserName0))

# Change the operator completely (similar to previous example):
PS> Get-TestUser -ReturnSqlQuery -UserName @{Value='a*'; ComparisonOperator='NOT LIKE'}, $nu

SELECT
    Users.UserId AS UserId,
    Users.UserName AS UserName
FROM
    Users
WHERE
    ((Users.UserName IS NULL) OR (Users.UserName NOT LIKE @UserName0))
```

That was simple example with no table joins. Handling table joins is simple: just put a working FROM clause with all of the required JOIN statements inside the 'FromClause' property on the [MagicDbInfo()] attribute. The spacing doesn't matter, so you can format the string however you like (as long as it is a valid FROM/JOIN clause). The value of the 'FromClause' property is used as-is, so its syntax is very important. Subtables should work here, too. Any table aliases that are used for the 'ColumnName' property on the command parameter's [MagicDbProp()] attributes need to be defined here as well.