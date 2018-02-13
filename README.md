DatbaseReporter
===============

NOTE: Please see the documenation page here: https://rohnedwards.github.io/DatabaseReporter/

About
-----
The *DatabaseReporter.ps1* file is an addon to a module to make creating PowerShell commands that read from a database simple to generate. While the project contains several files, *DatabaseReporter.ps1* is the only one that is required for operation.

It is not meant to be used by itself. Instead, it is placed inside a module's folder, and it is dot sourced early in its parent module's root module file.

It is designed to work with any RDBMS that supports the *DbConnection* .NET interface, or that supports ODBC (since .NET has an *OdbcConnection* class that implements *DbConnection*).

The project is currently in a pre-release mode, and lots of options and features are expected to change in the future.

Documentation and Pester tests are still being added.

Example
-------
In the following examples, we're going to use the *New-Module* command instead of creating a root module file. This is just to simplify writing the examples. Each of these can be copied into a *.psm1* file (omitting the New-Module command and scriptblock braces) and imported like a traditional module (you'd also want to use *$PSScriptRoot* when dot-sourcing the *DatabaseReporter.ps1* file)

The first step is determining how to connect to your database. I'm going to use the AdventureWorks database, which is installed on my local machine. To connect, I'll use a *SqlConnection* instance with a connection string of ```server=(LocalDB)\v11.0;Database=AdventureWorks2012;```

```
$DbModule = New-Module {
    # Load the DatabaseReporter engine:
    . $pwd\DatabaseReporter.ps1

    $DebugMode = $true  # This makes it so that -ReturnSqlQuery parameter is available on all commands

    Set-DbReaderConnection ([System.Data.SqlClient.SqlConnection]::new('server=(LocalDB)\v11.0;Database=AdventureWorks2012'))

    DbReaderCommand Get-AwEmployee {
        [MagicDbInfo(
            FromClause = '
                HumanResources.Employee
                JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID    
            '
        )]
        param(
        )
    }
}
```

Notice that that looks very similar to a normal function's param() block. The only addition is the [MagicDbInfo()] attribute. If you import that module (in this case, just run the code), you have a functioning commmand (even if you don't have AdventureWorks set up, you can run the first command below):
```
PS> Get-AwEmployee -ReturnSqlQuery  
 
SELECT
  *
FROM
  HumanResources.Employee JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID
```

If you run the command without -ReturnSqlQuery, you'll get A LOT of information. Too much information. Let's add some parameters (once you add parameters with the special attribute below, the SELECT statement no longer selects all properties):

```

$DbModule = New-Module {
    # Load the DatabaseReporter engine:
    . $pwd\DatabaseReporter.ps1

    $DebugMode = $true  # This makes it so that -ReturnSqlQuery parameter is available on all commands

    Set-DbReaderConnection ([System.Data.SqlClient.SqlConnection]::new('server=(LocalDB)\v11.0;Database=AdventureWorks2012'))
    DbReaderCommand Get-AwEmployee {
        [MagicDbInfo(
            FromClause = '
                HumanResources.Employee
                JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID    
            '
        )]
        param(
            [MagicDbProp(ColumnName='Employee.BusinessEntityID')]
            [System.Int32] $BusinessEntityID,
            [MagicDbProp(ColumnName='Employee.NationalIDNumber')]
            [System.String] $NationalIDNumber,
            [MagicDbProp(ColumnName='Person.PersonType')]
            [char] $PersonType,
            [MagicDbProp(ColumnName='Person.Title')]
            [string] $Title,
            [MagicDbProp(ColumnName='Person.FirstName')]
            [string] $FirstName,
            [MagicDbProp(ColumnName='Person.LastName')]
            [string] $LastName,
            [MagicDbProp(ColumnName='Person.Suffix')]
            [string] $Suffix,
            [MagicDbProp(ColumnName='Employee.LoginID')]
            [System.String] $LoginID,
            [MagicDbProp(ColumnName='Employee.OrganizationLevel')]
            [System.Int16] $OrganizationLevel,
            [MagicDbProp(ColumnName='Employee.JobTitle')]
            [System.String] $JobTitle,
            [MagicDbProp(ColumnName='Employee.BirthDate')]
            [System.DateTime] $BirthDate,
            [MagicDbProp(ColumnName='Employee.MaritalStatus')]
            [System.String] $MaritalStatus,
            [MagicDbProp(ColumnName='Employee.Gender')]
            [System.String] $Gender,
            [MagicDbProp(ColumnName='Employee.HireDate')]
            [System.DateTime] $HireDate,
            [MagicDbProp(ColumnName='Employee.SalariedFlag')]
            [switch] $IsSalaried,
            [MagicDbProp(ColumnName='Employee.VacationHours')]
            [System.Int16] $VacationHours,
            [MagicDbProp(ColumnName='Employee.SickLeaveHours')]
            [System.Int16] $SickLeaveHours,
            [MagicDbProp(ColumnName='Employee.CurrentFlag')]
            [switch] $IsCurrent
        )
    }
}
```

Again, just a param() block with a fake attribute (in this case, [MagicDbProp()]). You could add some normal comment based help in that fake function definition, too, if you wanted to. Now try to pass your command some parameters and see the resutling query (again -ReturnSqlQuery works even if you don't have the DB setup if you just use a blank connection string):

```
PS> Get-AwEmployee -FirstName a*, b* -Suffix $null -Negate Suffix -ReturnSqlQuery

SELECT
  Employee.BusinessEntityID AS BusinessEntityID,
  Employee.NationalIDNumber AS NationalIDNumber,
  Person.PersonType AS PersonType,
  Person.Title AS Title,
  Person.FirstName AS FirstName,
  Person.LastName AS LastName,
  Person.Suffix AS Suffix,
  Employee.LoginID AS LoginID,
  Employee.OrganizationLevel AS OrganizationLevel,
  Employee.JobTitle AS JobTitle,
  Employee.BirthDate AS BirthDate,
  Employee.MaritalStatus AS MaritalStatus,
  Employee.Gender AS Gender,
  Employee.HireDate AS HireDate,
  Employee.SalariedFlag AS IsSalaried,
  Employee.VacationHours AS VacationHours,
  Employee.SickLeaveHours AS SickLeaveHours,
  Employee.CurrentFlag AS IsCurrent
FROM
  HumanResources.Employee
  JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID
WHERE
  ((Person.FirstName LIKE @FirstName0 OR Person.FirstName LIKE @FirstName1)) AND
  NOT ((Person.Suffix IS NULL))

/*
Parameters:
  @FirstName0: a%
  @FirstName1: b%
*/

```

Parameterized queries! That's just the beginning. If you remove -ReturnSqlQuery, it returns live results. There are also some common parameters: -Negate, -GroupBy, and -OrderBy:
```
PS> Get-AwEmployee -FirstName a*, b* -GroupBy JobTitle, Gender -ReturnSqlQuery

SELECT
  Employee.JobTitle AS JobTitle,
  Employee.Gender AS Gender,
  COUNT(*) AS Count
FROM
  HumanResources.Employee
  JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID
WHERE
  ((Person.FirstName LIKE @FirstName0 OR Person.FirstName LIKE @FirstName1))
GROUP BY
  Employee.JobTitle,
  Employee.Gender


/*
Parameters:
  @FirstName0: a%
  @FirstName1: b%
*/
```

Here's the really cool part. Let's add a second command that's related to the first one. It looks like AdventureWorks has an employee department history table, so we'll make a command for that. To cut down on repeating the same code, this version of the module is going to do two new things:
1. Add formatting information to both commands by adding a *PSTypeName* and the *[MagicDbFormatTableColumn()]* attribute to the parameter/columns we want to show up in the table
1. Show that we can still use the *[Parameter()]* attribute and make the second command take pipeline input 
   
   **NOTE:** Doing this requires a change to the connection string so we can run multiple commands with the same connection. If you're using something other than SQL server that doesn't support that same feature, there are ways to set the module up to build a new connection each time a query is executed, so this would still work.

```
$Module = New-Module -Name SimpleTest {

    # Load the DatabaseReporter engine:
    . $pwd\DatabaseReporter.ps1

    $DebugMode = $true  # This makes it so that -ReturnSqlQuery parameter is available on all commands

    Set-DbReaderConnection ([System.Data.SqlClient.SqlConnection]::new('server=(LocalDB)\v11.0;Database=AdventureWorks2012; MultipleActiveResultSets=True;'))

    DbReaderCommand Get-AwEmployee {
        [MagicDbInfo(
            FromClause = '
                HumanResources.Employee
                JOIN Person.Person ON Person.BusinessEntityID = Employee.BusinessEntityID    
            ',
            PSTypeName = 'AwEmployee'
        )]
        param(
            [MagicDbProp(ColumnName='Employee.BusinessEntityID')]
            [System.Int32] $BusinessEntityID,
            [MagicDbProp(ColumnName='Employee.NationalIDNumber')]
            [System.String] $NationalIDNumber,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='Person.PersonType')]
            [char] $PersonType,
            [MagicDbProp(ColumnName='Person.Title')]
            [string] $Title,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='Person.FirstName')]
            [string] $FirstName,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='Person.LastName')]
            [string] $LastName,
            [MagicDbProp(ColumnName='Person.Suffix')]
            [string] $Suffix,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='Employee.LoginID')]
            [System.String] $LoginID,
            [MagicDbProp(ColumnName='Employee.OrganizationLevel')]
            [System.Int16] $OrganizationLevel,
            [MagicDbProp(ColumnName='Employee.JobTitle')]
            [MagicDbFormatTableColumn()]
            [System.String] $JobTitle,
            [MagicDbProp(ColumnName='Employee.BirthDate')]
            [System.DateTime] $BirthDate,
            [MagicDbProp(ColumnName='Employee.MaritalStatus')]
            [System.String] $MaritalStatus,
            [MagicDbProp(ColumnName='Employee.Gender')]
            [System.String] $Gender,
            [MagicDbProp(ColumnName='Employee.HireDate')]
            [System.DateTime] $HireDate,
            [MagicDbProp(ColumnName='Employee.SalariedFlag')]
            [switch] $IsSalaried,
            [MagicDbProp(ColumnName='Employee.VacationHours')]
            [System.Int16] $VacationHours,
            [MagicDbProp(ColumnName='Employee.SickLeaveHours')]
            [System.Int16] $SickLeaveHours,
            [MagicDbProp(ColumnName='Employee.CurrentFlag')]
            [switch] $IsCurrent
        )
    }

    DbReaderCommand Get-AwEmployeeDepartmentHistory {
        [MagicDbInfo(
            FromClause = '
                HumanResources.EmployeeDepartmentHistory edh
                JOIN HumanResources.Employee e ON e.BusinessEntityID = edh.BusinessEntityID
                JOIN Person.Person p ON p.BusinessEntityID = edh.BusinessEntityID
                LEFT JOIN HumanResources.Shift s ON s.ShiftID = edh.ShiftID
                LEFT JOIN HumanResources.Department d ON d.DepartmentID = edh.DepartmentID
                ',
            PSTypeName = 'AwEmployeeDepartmentHistory'
        )]
        param(
            [MagicDbProp(ColumnName='edh.BusinessEntityID')]
            [Parameter(ValueFromPipelineByPropertyName)]
            [System.Int32] $BusinessEntityID,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='p.FirstName')]
            [string] $FirstName,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='p.LastName')]
            [string] $LastName,
            [MagicDbProp(ColumnName='e.LoginID')]
            [System.String] $LoginID,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='edh.DepartmentID')]
            [System.Int16] $DepartmentID,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='d.Name')]
            [string] $DepartmentName,
            [MagicDbProp(ColumnName='edh.ShiftID')]
            [System.Byte] $ShiftID,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='s.Name')]
            [string] $ShiftName,
            [MagicDbProp(ColumnName='s.StartTime', TransformArgument={$_.ToString('HH:mm:ss')})]
            [datetime] $ShiftStart,
            [MagicDbProp(ColumnName='s.EndTime')]
            [datetime] $ShiftEnd,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='edh.StartDate')]
            [System.DateTime] $StartDate,
            [MagicDbFormatTableColumn()]
            [MagicDbProp(ColumnName='edh.EndDate')]
            [System.DateTime] $EndDate
        )
    }
}
```

And to show it off (this time let's include actual results instead of the query):
```
PS> Get-AwEmployee -FirstName a* | Get-AwEmployeeDepartmentHistory

FirstName LastName  DepartmentID DepartmentName       ShiftName StartDate             EndDate
--------- --------  ------------ --------------       --------- ---------             -------
Annik     Stahl     7            Production           Day       1/18/2003 12:00:00 AM $null  
Andrew    Hill      7            Production           Day       3/26/2003 12:00:00 AM $null  
Alice     Ciccu     7            Production           Day       1/8/2003 12:00:00 AM  $null  
Angela    Barbariol 7            Production           Day       2/21/2003 12:00:00 AM $null  
Anibal    Sousa     7            Production           Day       3/27/2003 12:00:00 AM $null  
Andy      Ruth      7            Production           Evening   3/4/2003 12:00:00 AM  $null  
Alex      Nayberg   7            Production           Day       3/12/2003 12:00:00 AM $null  
Andrew    Cencini   7            Production           Day       4/7/2003 12:00:00 AM  $null  
Alejandro McGuel    7            Production           Day       1/7/2003 12:00:00 AM  $null  
Andreas   Berglund  13           Quality Assurance    Evening   3/6/2003 12:00:00 AM  $null  
A. Scott  Wright    8            Production Control   Day       1/13/2003 12:00:00 AM $null  
Alan      Brewer    8            Production Control   Evening   3/17/2003 12:00:00 AM $null  
Arvind    Rao       5            Purchasing           Day       4/1/2003 12:00:00 AM  $null  
Annette   Hill      5            Purchasing           Day       1/6/2005 12:00:00 AM  $null  
Ashvini   Sharma    11           Information Services Evening   1/5/2003 12:00:00 AM  $null  
Amy       Alberts   3            Sales                Day       5/18/2006 12:00:00 AM $null  

# We did some magic to ShiftStart, too, so this is possible (even though it's a [time] column)
# NOTE: The hashtable syntax isn't special...all filtering parameters can do that and take
#       overrides to their default behavior, but that's for another example
PS> Get-AwEmployeeDepartmentHistory -ShiftStart @{Value='8:00:00'; ComparisonOperator='<'}
```

While that is a lot of text, notice that there's no actual code. It's just boilerplate attributes (and stay tuned for the helper functions that take a valid SELECT statement and output most of that code for you).
