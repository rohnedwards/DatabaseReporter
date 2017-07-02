

# This would normally be in the same folder, but since it's a DatabaseReporter example, it references the file in the parent folder.
. "$PSScriptRoot\..\..\DatabaseReporter.ps1"

$__DbConnection = $null
$DefaultDbConnectionString = 'server=(LocalDB)\v11.0;Database=AdventureWorks2012'

function Get-SqlMetadataConnection {
<#
.SYNOPSIS
Provides a way to view the DB connection that the metadata commands will run
against.

.DESCRIPTION
Use this function to view the SqlConnection object that will be used to connect
to the database each run. 
#>
    $script:__DbConnection
}

function Set-SqlMetadataConnection {
<#
.SYNOPSIS
Allows configuring the DB connection
.DESCRIPTION
This command allows the database connection to be changed for the module's
metadata commands.

Right now it, only supports a connection string, but will eventually support
passing a full connection object.

When a new string (and optionally type) are passed, it first attempts to
use those to open a new connection. If that fails, the module's DB connection
object is not updated. If it succeeds, then the module's connection is updated.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName='ByConnectionString')]
        [string] $NewConnectionString,
        [Parameter(ParameterSetName='ByConnectionString')]
        [type] $NewConnectionType = 'System.Data.SqlClient.SqlConnection'
    )

    try {
        $SqlConnection = $NewConnectionType::new($NewConnectionString)
        $SqlConnection.Open()
        $script:__DbConnection = $SqlConnection
    }
    catch {
        Write-Warning "Error opening ${NewConnectionType} instance: ${_}"
    }
}

Set-SqlMetadataConnection -NewConnectionString $DefaultDbConnectionString

DbReaderCommand Get-SqlMetadataColumn {
<#
.SYNOPSIS
Get column information for the current database.

.DESCRIPTION
This function returns column information for the database connection that the
module is currently connected to. To view or change that connection, use the
Get/Set-SqlMetadataConnection functions.
#>
    [MagicDbInfo(
        FromClause = "INFORMATION_SCHEMA.COLUMNS",
        DbConnection = {$__DbConnection},
        PSTypeName = 'SqlMetadata.Column'
    )]
    param(
        [MagicDbProp(ColumnName='COLUMN_NAME')]
        [MagicDbFormatTableColumn()]
        [string] $ColumnName,
        [MagicDbProp(ColumnName='DATA_TYPE')]
        [MagicDbFormatTableColumn()]
        [string] $ColumnType,
        [MagicDbProp(ColumnName='TABLE_CATALOG')]
        [MagicDbFormatTableColumn()]
        [string] $TableCatalog,
        [MagicDbProp(ColumnName='TABLE_SCHEMA')]
        [MagicDbFormatTableColumn()]
        [string] $TableSchema,
        [MagicDbProp(ColumnName='TABLE_NAME')]
        [MagicDbFormatTableColumn()]
        [string] $TableName
    )
}

DbReaderCommand Get-SqlMetadataColumn2 {
<#
.SYNOPSIS
Get column information for the current database.

.DESCRIPTION
This function returns column information for the database connection that the
module is currently connected to. To view or change that connection, use the
Get/Set-SqlMetadataConnection functions.
#>
    [MagicDbInfo(
        FromClause = "
            INFORMATION_SCHEMA.COLUMNS
            JOIN INFORMATION_SCHEMA.TABLES ON TABLES.TABLE_NAME = COLUMNS.TABLE_NAME
        ",
        DbConnection = {$__DbConnection},
        PSTypeName = 'SqlMetadata.Column'
    )]
    param(
        [MagicDbProp(ColumnName='COLUMN_NAME')]
        [MagicDbFormatTableColumn()]
        [string] $ColumnName,
        [MagicDbProp(ColumnName='DATA_TYPE')]
        [MagicDbFormatTableColumn()]
        [string] $ColumnType,
        [MagicDbProp(ColumnName='TABLES.TABLE_CATALOG')]
        [MagicDbFormatTableColumn()]
        [string] $TableCatalog,
        [MagicDbProp(ColumnName='TABLES.TABLE_SCHEMA')]
        [MagicDbFormatTableColumn()]
        [string] $TableSchema,
        [MagicDbProp(ColumnName='TABLES.TABLE_NAME')]
        [MagicDbFormatTableColumn()]
        [string] $TableName,
        [MagicDbProp(ColumnName='TABLES.TABLE_TYPE')]
        [MagicDbFormatTableColumn()]
        [string] $TableType
    )
}

function DumbSqlParse {
<#
.SYNOPSIS
Parses SQL statement.

.DESCRIPTION
A simple SQL parser (seriously, it's easy to fool this thing right now). This
command is used during DbReaderCommand generation from a SELECT statement.

For now, it only cares about the SELECT and FROM clauses. Any WHERE, GROUP BY,
ORDER BY, HAVING, etc will be ignored.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] 
        [string] $SelectQuery
    )

    end {
        $SelectClauseRegex = "SELECT\s+(DISTINCT\s+)?(TOP\s+\d+(\s+PERCENT)?\s+)?(?<columns>.*)"

        # As written, a table provided with the schema and table name (which is probably
        # more common than catalog, schema, and table name), would match as a catalog and
        # table name. My regex-fu is weak, so if a regex can't be made that determines that
        # when only two components are specified it should be the schema and name, we'll need
        # logic to fix that after the regex has matched
        $TableRegex = '((?<TableCatalog>\w+)\.)?((?<TableSchema>\w+)\.)?(?<TableName>\w+)((\s+AS)?\s+(?<TableAlias>\w+))?\s*'
        $JoinRegex = '(?:(?:LEFT|RIGHT|FULL)\s+)?(?:(?:OUTER|INNER)\s+)?JOIN'
        $JoinCondition = '[\w\.]+\s+(\!?\=|\<\>|\>\=|\<\=)\s+[\w\.]+'
        $JoinOnRegex = "\s+ON\s+${JoinCondition}(\s+(AND|OR)\s+${JoinCondition})*"
        $FromClauseRegex = "(?<fromclause>FROM\s+${TableRegex}(\s*${JoinRegex}\s+${TableRegex}${JoinOnRegex})*)"

        # These sections can eventually get their own regexes. For now, just make sure they're in the right order
        $TheRest = '(\s+WHERE\s+.*)?(\s+GROUP\s+BY\s+.*)?(\s+HAVING\s+.*)?(\s+ORDER\s+BY\s+.*)?'
        
        #$Regex = "SELECT\s+(TOP\s+\d+(\s+PERCENT)?\s+)?(?<columns>.*)\s+FROM\s+(?<tables>.*)(\s+(WHERE|ORDER|GROUP|HAVING))?"
        $Regex = "^\s*${SelectClauseRegex}\s+${FromClauseRegex}\s*${TheRest}$"

        $SpacedSelectQuery = $SelectQuery -replace '\r?\n|\t', ' '
        if ($SpacedSelectQuery -notmatch $Regex) {
            Write-Warning "Unable to parse SQL statement: ${SelectQuery}"
            return
        }

        $Columns = $matches.columns
        $FromClause = $matches.fromclause -replace '^FROM\s+'
        $ReturnObject = [ordered] @{
            # This holds column information from the parsed SELECT clause
            Columns = New-Object System.Collections.ArrayList
            
            # This holds a subset of the information found in 'Columns'. If
            # a Column object has no wildcards, it will be stored in this
            # dictionary so that column aliases can be looked up later. 
            # Eventually this function will be refactored into something that
            # makes a little more sense (this was added after 'Columns' was
            # already in place)
            ColumnAliasDict = @{}

            # This holds parsed table information from the parsed FROM/JOIN
            # clause
            Tables = New-Object System.Collections.ArrayList

            FormattedFromClause = 'FROM ' + (($FromClause -replace '\s+', ' ') -replace "(\r?\n)*${JoinRegex}", "`n`$0")
        }

        $CurrObjProps = [ordered] @{}
        # SELECT clause
        foreach ($CurrentColumn in $Columns -split '\s*,\s*') {
            if ($CurrentColumn -notmatch '\s*((((?<TableSchema>\w+)\.)?(?<TableOrAlias>\w+)\.))?(?<ColumnName>[\w\*]+)(\s+(AS\s+)?(?<ColumnAlias>\w+)?)?') {
                Write-Warning "Error parsing SELECT clause: Unknown column format [${CurrentColumn}]" 
                continue
            }

            $CurrObjProps.Clear()
            $CurrObjProps.TableOrAlias = if ($matches.TableOrAlias) {
                $matches.TableOrAlias
            }
            else {
                '*' # This will be used when searching table schema   
            }

            $CurrObjProps.ColumnAlias = $CurrObjProps.ColumnName = $matches.ColumnName
            if ($matches.ContainsKey('ColumnAlias')) {
                $CurrObjProps.ColumnAlias = $matches.ColumnAlias

                # If we find an alias, we need to store that in the alias dict. First,
                # make sure there are no wildcards in the Table or Column names:
                if (-not (
                    [WildcardPattern]::ContainsWildcardCharacters($CurrObjProps.TableOrAlias) -or 
                    [WildcardPattern]::ContainsWildcardCharacters($CurrObjProps.ColumnName) -or 
                    [WildcardPattern]::ContainsWildcardCharacters($CurrObjProps.ColumnAlias) 
                )) {
                    $ReturnObject.ColumnAliasDict['{0}:{1}' -f $CurrObjProps.TableOrAlias, $CurrObjProps.ColumnName] = $CurrObjProps.ColumnAlias
                }
            } 
            $ReturnObject.Columns.Add([PSCustomObject] $CurrObjProps) | Out-Null
        }

        # FROM/JOIN clause
        foreach ($CurrentTable in $FromClause -split "\s*${JoinRegex}\s*") {
            $TrimmedCurrentTable = $CurrentTable -replace "${JoinOnRegex}$"
            if ($TrimmedCurrentTable -notmatch $TableRegex) {
                Write-Warning "Error parsing FROM/JOIN clause: Unknown table format [${CurrentTable}]" 
                continue
            }
            
            $CurrObjProps.Clear()
            $CurrObjProps.TableSchema = $CurrObjProps.TableCatalog = '*'

            if ($matches.TableCatalog -and $matches.TableSchema) {
                $CurrObjProps.TableSchema = $matches.TableSchema
                $CurrObjProps.TableCatalog = $matches.TableCatalog
            }
            elseif ($matches.TableCatalog) {
                $CurrObjProps.TableSchema = $matches.TableCatalog
            }

            $CurrObjProps.TableAlias = $CurrObjProps.TableName = $matches.TableName
            if ($matches.TableAlias) {
                $CurrObjProps.TableAlias = $matches.TableAlias
            }
            
            $ReturnObject.Tables.Add([PSCustomObject] $CurrObjProps) | Out-Null
        }

        [PSCustomObject] $ReturnObject
    }
}

function SqlTypeToDotNetType {
    <#
    Provides simple conversion from SQL types to .NET types. Basically looks
    for known types, and defaults to string otherwise.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $SqlType
    )

    process {
        switch -Regex ($SqlType) {
            '^(date|time){1,2}$' { [datetime] }
            '^bit$' { [bool] }
            '^n?(var)?char$' { [string] }
            '^int$' { [int] }
            '^tinyint$' { [byte] }
            '^smallint$' { [int16] }
            default {
                Write-Warning "Unknown SQL data type [${_}]: defaulting to [string]"
                [string] 
            }
        }
    }
}
function New-DbReaderCommandSkeleton {
<#
.SYNOPSIS
Generates a new DbReaderCommand skeleton after being provided a SQL SELECT
query or a list of tables and properties.

.DESCRIPTION
Even though a DbReaderCommand instance only requires a (customized) param 
block, the custom attributes can require a lot of tedious typing. This function
tries to remove a lot of that typing.

To use it, you provide a SQL SELECT query that contains the information you'd
like the DbReaderCommand to return. If there are more properties than you'd
like to type, you can provide wildcards, which means you can actually pass
invalid SQL queries to the command (see examples for more info).

For now, anything after the FROM/JOIN clauses are ignored, i.e., any WHERE,
GROUP BY, HAVING, or ORDER BY clauses will be completely ignored. Also, CTEs
before the SELECT statement are not supported yet.

The most important part of the SQL statement is the FROM/JOIN section. This
section must be valid, as it will be used in the DBReaderCommand instance.
Also, this section is parsed out to get the table names, and optional aliases.

Comma separated FROM clauses are not currently supported, e.g., the following
query would not work:

SELECT * FROM Table1, Table2 WHERE Table1.ID = Table2.ID

But this one would:

SELECT * FROM Table1 JOIN Table2 ON Table1.ID = Table2.ID

In order for this to work, the Get-SqlMetadataColumn command must be
functioning, which requires a valid DbConnection <MORE OR LESS DETAIL HERE?>

.EXAMPLE
PS> New-DbReaderCommandSkeleton "SELECT * FROM Person p"

.EXAMPLE
*PUT EXAMPLE OF JOINING THE SAME TABLE MORE THAN ONCE WITH TABLE ALIASES, AND
HAVING COMMAND PROPERTIES FOR EACH TABLE INSTANCE*

.NOTES
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SelectQuery,
        [switch] $NoVerify 
    )
    
    end {
        try {
            $ParsedQuery = DumbSqlParse $SelectQuery -WarningAction Stop -ErrorAction Stop
        }
        catch {
            Write-Warning "Error parsing SELECT statement: ${_}"
            return
        }

        # We've got to figure out the properties. To do that, we'll loop through
        # each table, then query the schema to get the column info. We only want
        # properties that pass the conditions set in the parsed column info, though.
        # 
        # It would be nice to generate the param() block definitions of each one at
        # this point, but there is a chance there will be some duplicate column names
        # (which become the actual param names in the param block). We can't have
        # dupes, so we've first got to generate the properties, fix any dupes found,
        # then generate the strings
        $PropertyInfos = foreach ($Table in $ParsedQuery.Tables) {
            Write-Verbose "Searching for columns in '$($Table.TableName)' table:"
            Get-SqlMetadataColumn -TableCatalog $Table.TableCatalog -TableSchema $Table.TableSchema -TableName $Table.TableName -Verbose:$false | Where-Object {
                $CurrentColumnInfo = $_

                # Look for the first matching property info from the parsed columns
                foreach ($ValidColumn in $ParsedQuery.Columns) {
                    if (
                        ($Table.TableAlias -like $ValidColumn.TableOrAlias) -and
                        ($CurrentColumnInfo.ColumnName -like $ValidColumn.ColumnName)
                    ) {
                        Write-Verbose "  Allowed column: $($CurrentColumnInfo.ColumnName)"
                        return $true
                    }
                }

                # If we make it here, there must not have been a matching column found
                Write-Verbose "  Ignored column: $($CurrentColumnInfo.ColumnName)"
                return $false
            } | ForEach-Object {
                [PSCustomObject] @{
                    Type = $_.ColumnType | SqlTypeToDotNetType
                    TableAlias = $Table.TableAlias
                    ColumnName = $_.ColumnName
                    PropertyName = if (($ColumnAlias = $ParsedQuery.ColumnAliasDict['{0}:{1}' -f $Table.TableAlias, $_.ColumnName])) {
                        $ColumnAlias
                    }
                    else {
                        $_.ColumnName
                    }
                }
            }
        }

        # To preserve the order as best as we can, we'll group the properties and
        # change them in place, then loop back over everything when we're done
Write-Warning "LOOK FOR DUPES HERE!"
        $PropertyStrings = $PropertyInfos | ForEach-Object {
@'
    [MagicDbProp(ColumnName='{0}.{1}')]
    [{2}] ${3}
'@ -f $_.TableAlias, $_.ColumnName, $_.Type, $_.PropertyName 
            }

@"
[MagicDbInfo(
    FromClause = "
        $($ParsedQuery.FormattedFromClause -replace '(\r?\n)+', "`n$(' ' * 8)")
    "    
    DbConnectionString = {`$null},
    DbConnectionType = '',
    PSTypeName = ''
)]
param(
$($PropertyStrings -join ",`n")
)
"@
    }
}

Export-ModuleMember *-*