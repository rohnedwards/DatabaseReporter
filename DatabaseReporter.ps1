﻿

if (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue) {
    $TabExpansionAvailable = $true
}
else {
    $TabExpansionAvailable = $false
}

#region Constants/script-scope variables
$__FakeAttributes = @{
    DbCommandInfoAttributeName = 'MagicDbInfo'
    DbComparisonSuffixAttributeName = 'MagicDbComparisonSuffix'
    HelpAttributeName = 'MagicPsHelp'
    DbColumnProperty = 'MagicDbProp'
    DbFormatTableInfo = 'MagicDbFormatTableColumn'
}
$__OutputNullReplacementString = '$null'  # When return field is null from an InvokeReaderCommand invocation, the value is replaced with this string
$__DbReaderInfoTableName = 'PsBoundDbInfos'

$__CommandDeclarations = @{}
#endregion

#region Reference Scriptblock and Standard Argument completer
$ReferenceCommandScriptBlock = [scriptblock]::Create({
<#
.SYNOPSIS
Synopsis goes here (FROM REFERENCE COMMAND)

.DESCRIPTION
Description goes here (FROM REFERENCE COMMAND)

.EXAMPLE
An example from the reference command
#>

    [CmdletBinding()]
    param(
        # Negates specified properties that have been provided to the command. 
        # Any filtering parameter that is specified in the same call can be 
        # provided as input.
        [string[]] $Negate,
        # Changes the returned object to have properties specified in this
        # parameter, along with a count property that shows the number of 
        # records grouped together by those properties. More than one parameter
        # name can be specified.
        [string[]] $GroupBy,
        # Changes the order the objects are returned in, depending on what 
        # parameter names are provided. This behaves the way that Sort-Object
        # would, except it causes the database to do the sorting.
        #
        # Adding a '!' or ' DESC' to the end of a parameter name causes the
        # sorting to be descening, instead of the default ascending order.
        [string[]] $OrderBy
    )

    begin {
        
        # If prefix was used at import time, we're going to have problems looking the
        # command up. Let's figure out the real command name:
        $MyCommandMetaData = $PsCmdlet.MyInvocation.MyCommand

<#
        $MyCommandName = if (($ModulePrefix = $MyCommandMetaData.Module.Prefix) -and $MyCommandMetaData.Verb -and $MyCommandMetaData.Noun) {
            '{0}-{1}' -f $MyCommandMetaData.Verb, ($MyCommandMetaData.Noun -replace "^$([regex]::Escape($ModulePrefix))")
        }
        else {
            $MyCommandMetaData.Name
        }
#>
$MyCommandName = $MyCommandMetaData.Name
        # $MyCommandInfo will hold the command declaration info
        $MyCommandInfo = $__CommandDeclarations[$MyCommandName]

        if (-not $MyCommandInfo) {
            throw "Unable to get command information for '$MyCommandName'"
        }

        # This is the dictionary that gets set up during parameter binding that has all the information for handling
        # the WHERE clause. If no parameters are specified (at least DB column parameters), then it won't have been
        # defined, and that will be bad later. So, if it's not defined, create an empty one:
        $PSBoundDbInfos = Get-Variable -ErrorAction SilentlyContinue -Scope 0 -Name $__DbReaderInfoTableName -ValueOnly
        if ($null -eq $PSBoundDbInfos) { $PSBoundDbInfos = @{} }

        # Default parameter values need to work. The way this is set up right now, PSBoundParameters is all that's going
        # to be checked. So, let's take any default values (they'll stand out b/c they'll be variables with a value that
        # exist in this scope), and add them to the PSBoundParameters dictionary (only if they weren't already bound).
        # 
        # That's great for parameters that weren't passed via pipeline. What if about pipeline bound parameters (they won't
        # show up in PSBoundParameters in the begin{} block). Well, they'll be updated in the process{} block, and since
        # all the work will happen there, it should be fine
        #
        
        foreach ($__ParameterName in $PsCmdlet.MyInvocation.MyCommand.Parameters.Keys) {

            Write-Verbose "Checking to see if $__ParameterName wasn't specified and has a default value..."
            if (-not ($PSBoundParameters.ContainsKey($__ParameterName)) -and ($__ParamDefaultValue = Get-Variable -Name $__ParameterName -Scope 0 -ValueOnly -ErrorAction SilentlyContinue)) {
                Write-Verbose "  ...one of those conditions was met! Setting PSBoundParameter to show value of $__ParamDefaultValue"

                # If this is a DB property, we need to make sure the DbReaderInfo is attached
                if ($MyCommandInfo.PropertyParameters.Contains($__ParameterName)) {
                    Write-Verbose "     (Attaching DBReaderInfo property first)"
                    $__ParamDefaultValue = AddDbReaderInfo -InputObject $__ParamDefaultValue -OutputType $PSCmdlet.MyInvocation.MyCommand.Parameters[$__ParameterName].ParameterType -CommandName $PsCmdlet.MyInvocation.MyCommand.Name -ParameterName $__ParameterName
                }
                $PSBoundParameters[$__ParameterName] = $__ParamDefaultValue
            }
            else {
                Write-Verbose "  ...either already specified, or no default value"
            }
        }

        Write-Verbose "begin PSBoundParameters {"
        foreach ($Param in $PSBoundParameters.GetEnumerator()) {
            Write-Verbose ("    {0} = {1}{2}" -f $Param.Key, ($Param.Value -join ', '), $(if ($PSBoundDbInfos.ContainsKey($Param.Key)) {' (DBReaderInfo bound)'})) 
        }
        Write-Verbose "}"

    }

    process {
        

        Write-Verbose "process PSBoundParameters {"
        foreach ($Param in $PSBoundParameters.GetEnumerator()) {
            Write-Verbose ("    {0} = {1}{2}" -f $Param.Key, ($Param.Value -join ', '), $(if ($PSBoundDbInfos.ContainsKey($Param.Key)) {' (DBReaderInfo bound)'}))
        }

        Write-Verbose "}"

        # For now, process block will execute multiple times when pipeline input comes in (that's nothing new). Should the process block attempt to
        # collect all the pipeline data, though, and do one query in the end block instead? Just something to think about...

        $JoinSpacingString = "`n  "
        $SqlQuerySb = New-Object System.Text.StringBuilder

        # Get SELECT clause info (get GROUP BY info too, just in case it's needed):
        $StringList = New-Object System.Collections.Generic.List[string]
        $GroupByList = New-Object System.Collections.Generic.List[string]

        foreach ($Property in $MyCommandInfo.PropertyParameters.GetEnumerator()) {

            if (-not $PSBoundParameters.ContainsKey('GroupBy') -or (ContainsMatch -Collection $GroupBy -ValueToMatch $Property.Value.PropertyName) -or (ContainsMatch -Collection $GroupBy -ValueToMatch $Property.Name)) {
                $CurrentSelect = '{0} AS {1}' -f $Property.Value.ColumnName, $Property.Value.PropertyName
                if (-not $StringList.Contains($CurrentSelect)) {
                    $StringList.Add($CurrentSelect)
                }

                if (-not $GroupByList.Contains($Property.Value.ColumnName)) {
                    $GroupByList.Add($Property.Value.ColumnName)
                }
            }
        }
        
        if ($PSBoundParameters.ContainsKey('GroupBy')) {
            if ($StringList.Count -eq 0) {
                Write-Warning 'No -GroupBy parameters matched valid DB parameters, so Count will be the only property returned'
                # Should this error the command out??
            }
            $StringList.Add('COUNT(*) AS Count')
        }

        $null = $SqlQuerySb.AppendFormat('SELECT{0}', $JoinSpacingString)
        $null = $SqlQuerySb.AppendLine(($StringList -join ",$JoinSpacingString"))

        $ValidOrderByParameterNames = $StringList | select-string "(?<=\sas\s)(.*)$" | ForEach-Object Matches | ForEach-Object Value
        $StringList.Clear()

        # Add the FROM clause
        $null = $SqlQuerySb.AppendFormat('FROM{0}', $JoinSpacingString)
        $null = $SqlQuerySb.AppendLine(($MyCommandInfo.FromClause.FormattedStrings -join $JoinSpacingString))

        # Get WHERE clause info:

        # Notice that the actual values of the PSBoundParameters are ignored. Instead, we look for the DbReaderInfo from the $PSBoundDbInfos
        # table for the actual value(s)
        foreach ($Param in $PSBoundParameters.GetEnumerator()) {
Write-Debug "Current param: $($Param.Key)"
            if ($MyCommandInfo.PropertyParameters.Contains($Param.Key)) {
                $DbReaderInfos = $PSBoundDbInfos[$Param.Key]
                
                if ($DbReaderInfos -eq $null) {
                    Write-Error "Unable to find DbReaderInfo object for '$($Param.Key)' parameter; exiting..."
                    return
                }

                $StringList.Add($DbReaderInfos.ToWhereString())

                if (ContainsMatch -Collection $Negate -ValueToMatch $Param.Key) {
                    $StringList[-1] = 'NOT {0}' -f $StringList[-1]
                }
            }
        }

        if ($StringList.Count -gt 0) {
            $null = $SqlQuerySb.AppendFormat('WHERE{0}', $JoinSpacingString)
            $null = $SqlQuerySb.AppendLine(($StringList -join " AND$JoinSpacingString"))   # Right now, AND is hard coded. Need to figure out good way to make this configurable
        }

        $StringList.Clear()

        # GROUP BY
        if ($PSBoundParameters.ContainsKey('GroupBy') -and $GroupByList.Count -gt 0) {
            $null = $SqlQuerySb.AppendFormat('GROUP BY{0}', $JoinSpacingString)
            $null = $SqlQuerySb.AppendLine(($GroupByList -join ",$JoinSpacingString"))
        }

        # ORDER BY
        $OrderByStrings = if ($PSBoundParameters.ContainsKey('OrderBy')) {
            $PSBoundParameters['OrderBy'] | NewOrderByString -ValidNames $ValidOrderByParameterNames
        }

        if ($OrderByStrings.Count -gt 0) {
            $null = $SqlQuerySb.AppendFormat('ORDER BY{0}', $JoinSpacingString)
            $null = $SqlQuerySb.AppendLine(($OrderByStrings -join ",$JoinSpacingString"))
        }

        $SqlQuery = $SqlQuerySb.ToString()

        if ($PSBoundParameters['ReturnSqlQuery']) {
            # This parameter is only available in debug mode, and it changes the
            # behavior of the command to just return this string instead of executing
            # the command
            $SqlQuery
        }
        else {
            # Make a copy since we might add a pstype name
            $ConnectionParams = @{} + $MyCommandInfo.DbConnectionParams

            if ($MyCommandInfo.Contains('PSTypeName') -and -not $PSBoundParameters.ContainsKey('GroupBy')) {
                # Only add a typename if one's defined, and if command is not in GroupBy mode (that will change
                # the look of the object)
                $ConnectionParams['PSTypeName'] = $MyCommandInfo['PSTypeName']
            }

            Write-Debug "About to execute:`n$SqlQuery"

            InvokeReaderCommand -Query $SqlQuery @ConnectionParams
        }
    }

    end {
        Write-Verbose "end PSBoundParameters {"
        foreach ($Param in $PSBoundParameters.GetEnumerator()) {
            Write-Verbose ("    {0} = {1}{2}" -f $Param.Key, ($Param.Value -join ', '), $(if ($PSBoundDbInfos.ContainsKey($Param.Key)) {' (DBReaderInfo bound)'})) 
       }
        Write-Verbose "}"
    }
})

# OrderBy, GroupBy, and Negate all use the same completer. It has logic to change behavior based
# on what parameter is being used
$StandardArgumentCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)

#"$commandName`:$parameterName`:" | Out-File $DebugFile -Append
#"    $wordToComplete" | Out-File $DebugFile -Append
#"" | Out-File $DebugFile -Append
<#
    # TabExpansion++ screws up the bound scriptblock right now, so we don't have
    # direct module access. This is workaround:
    $CommandDeclarations = & (Get-Module DatabaseReporter) { $CommandDeclarations }
#>

    $ValidParameters = $__CommandDeclarations[$commandName].PropertyParameters.Values.PropertyName | Select-Object -Unique

    # Keep track of the words to return as completions. This changes based on the name of the current
    # parameter, and even based on previously bound parameters
    $PotentialWordsToComplete = New-Object System.Collections.ArrayList

    if ($parameterName -eq 'OrderBy' -and $fakeBoundParameter.ContainsKey('GroupBy')) {
        # When working on -OrderBy and -GroupBy has been specified, you can only use
        # parameters from -GroupBy and the 'Count' alias (which needs to be configurable,
        # but that's for a different day)
        foreach ($GroupByParam in $fakeBoundParameter['GroupBy']) {
            $null = $PotentialWordsToComplete.Add($GroupByParam)
        }
        $null = $PotentialWordsToComplete.Add("Count")
    }
    else {

        # Parameters that have already been specified will show up first:
        $fakeBoundParameter.Keys | Where-Object { $_ -and $_ -in $ValidParameters } | ForEach-Object {
            $null = $PotentialWordsToComplete.Add($_)
        }
    
        # Negate should only complete on parameters that have been specified, so
        # don't add any more potentials if that's the current parameterName
        if ($parameterName -ne "Negate") {
            $ValidParameters | Where-Object { $_ -notin $fakeBoundParameter.Keys } | ForEach-Object {
                $null = $PotentialWordsToComplete.Add($_)
            }
        }
        else {
            # There's a problem with -Negate and param names that don't match the DB column names, e.g.,
            # DateTime columns will get two parameters (a <Column>Before and <Column>After).
            # Problem is that $ValidParameters contains the column names, which you want for -GroupBy and 
            # -OrderBy.
            # This would get the valid -Negate parameters: $__CommandDeclarations[$commandName].PropertyParameters.Keys
            #
            # This is a fairly easy problem to solve, but the completer's code needs to be refactored.
        }
    }

    $PotentialWordsToComplete | Where-Object { $_ -like "*${wordToComplete}*" } | ForEach-Object {
        New-Object System.Management.Automation.CompletionResult (
            $_,
            $_,
            'ParameterValue',
            $_
        )
    }
}
$BoundStandardCompleter = {}.Module.NewBoundScriptBlock($StandardArgumentCompleter)

$BoundDateTimeCompleter = {}.Module.NewBoundScriptBlock({
    DateTimeConverter -wordToComplete $args[2]
})

#endregion

#region DSL commands

function DbReaderCommand {
    param(
        [Parameter(Mandatory, Position=0)]
        [string] $CommandName,
        [Parameter(Mandatory, Position=1)]
        [scriptblock] $Definition
    )

    if ($Definition.Ast -isnot [System.Management.Automation.Language.ScriptBlockAst]) {
        throw "-Definition must be provided as a scriptblock!"
    }

    $NewCommandStringBuilder = New-Object System.Text.StringBuilder
    $DateParametersThatNeedCompleter = New-Object System.Collections.Generic.List[string]

    #region Generate comment based help
    # For some reason, GetHelpContent requires a new scriptblock to be generated for GetHelpContent() to work properly. Test this in v5...
    $Definition = [scriptblock]::Create($Definition)

    # Let's sort out the help mess. Start by getting the reference command's help info
    if (-not ($HelpInfo = $ReferenceCommandScriptBlock.Ast.GetHelpContent())) {
        # This can't be null, so create an empty one
        $HelpInfo = New-Object System.Management.Automation.Language.CommentHelpInfo
    }

    # Next, get the help content from the definition that was passed in
    if (-not ($DefinitionHelpInfo = $Definition.Ast.GetHelpContent())) {
        # This can't be null, so create an empty one
        $DefinitionHelpInfo = New-Object System.Management.Automation.Language.CommentHelpInfo
    }

    # At this point, we know the comment based help for the reference command and the definition that
    # was passed in. The param() block can still have a help attribute decoration (see $__FakeAttributes.HelpAttributeName
    # for the name to use). We'll look at that, but we need to start keeping track of parameters defined in 
    # the reference param block, and in the $Definition param block at the same time (we need to strip 
    # non-PowerShell fake attributes from the param definitions)
    $ReferenceCommandParsedParamBlock = ParseParamBlock $ReferenceCommandScriptBlock.Ast.ParamBlock -CommandName $CommandName
    $DefinitionParsedParamBlock = ParseParamBlock $Definition.Ast.ParamBlock -CommandName $CommandName

    # Help merging order is 
    #  1. comment block help from reference command
    #  2. fake help attribute help from reference command
    #  3. comment block help from definition
    #  4. fake help attribute from reference command
    foreach ($HelpAttribute in $ReferenceCommandParsedParamBlock.HelpAttributes) {
        MergeHelpInfo -HelpInfo $HelpInfo -HelpAttribute $HelpAttribute
    }
    
    # Next, overwrite any help fields that were defined in $Definition
    MergeHelpInfo -HelpInfo $HelpInfo -UpdatedHelpInfo $DefinitionHelpInfo

    foreach ($HelpAttribute in $DefinitionParsedParamBlock.HelpAttributes) {
        MergeHelpInfo -HelpInfo $HelpInfo -HelpAttribute $HelpAttribute
    }

    # At this point, we have the comment block for the help. The only other help we need to worry about is
    # comments on parameters, but that will still go inside the param block. Go ahead and write the comment
    # block to the stringbuilder:
    $null = $NewCommandStringBuilder.AppendLine($HelpInfo.GetCommentBlock())
    $null = $NewCommandStringBuilder.AppendLine()

    #endregion

    # Need DB Info (this doesn't even check reference command...should it?)
    $CommandDbInformation = $DefinitionParsedParamBlock.DbInfo

    # Command MUST have a connection object, either specified by 'DbConnection' ScriptBlock (already opened), or by
    # DbConnectionString and DbConnectionType strings
    $DbConnectionParams = @{}
    if ($CommandDbInformation.Contains('DbConnection')) {
        $DbConnection = $CommandDbInformation['DbConnection']

        switch ($DbConnection.GetType().Name) {
            string {
                # See if this is a variable
                Write-Error 'String type not supported for DbConnection yet! Try a scriptblock that returns an object...'
                return
            }

            ScriptBlock {
                $DbConnectionObject = (& $DbConnection) -as [System.Data.Common.DbConnection]
            }
        }

        if ($DbConnectionObject -eq $null) {
            Write-Error "Unable to get DbConnection from '$DbConnection'"
            return
        }

        $CommandDbInformation.Remove('DbConnection')
        $DbConnectionParams.Connection = $DbConnectionObject
    }
    elseif ($CommandDbInformation.Contains('DbConnectionString') -and $CommandDbInformation.Contains('DbConnectionType')) {
        $ConnectionString = $CommandDbInformation['DbConnectionString'] | EvaluateAttributeArgumentValue -OutputAs string -LimitAstToType VariableExpressionAst -LimitNumberOfElements 1
        $ConnectionType = $CommandDbInformation['DbConnectionType'] | EvaluateAttributeArgumentValue -OutputAs string -LimitAstToType VariableExpressionAst -LimitNumberOfElements 1

        if ($ConnectionString -eq $null) {
            Write-Error "Unable to get a connection string from value: $($CommandDbInformation['DbConnectionString'])"
            return
        }

        $PotentialType = $ConnectionType -as [type]
        if (-not $PotentialType) {
            # Maybe shortname was used. Let's try to get valid types:
            if ($script:__ValidConnectionTypes -eq $null) {
                $script:__ValidConnectionTypes = New-Object System.Collections.Generic.List[type]

                foreach ($ValidConnectionType in GetInheritedClasses -ParentType System.Data.Common.DbConnection -ExcludeAbstract) {
                    $script:__ValidConnectionTypes.Add($ValidConnectionType)
                }
            }

            $PotentialType = $script:__ValidConnectionTypes | Where-Object Name -eq $ConnectionType
            if (-not $PotentialType) {
                Write-Warning "Unable to find $ConnectionType in valid DB Connection types; searching all assemblies..."
                # Last ditch effort to try expensive call to GetInheritedClasses:
                $script:__ValidConnectionTypes.Clear()
                
                foreach ($ValidConnectionType in GetInheritedClasses -ParentType System.Data.Common.DbConnection -ExcludeAbstract -SearchAllAssemblies) {
                    $script:__ValidConnectionTypes.Add($ValidConnectionType)
                }
                $PotentialType = $script:__ValidConnectionTypes | Where-Object Name -eq $ConnectionType
            }

        }

        $ConnectionType = $PotentialType -as [type]

        if ($ConnectionType -eq $null) {
            Write-Error "Unknown connection type: $($CommandDbInformation['DbConnectionType'])"
            return
        }

        $CommandDbInformation.Remove('DbConnectionString')
        $DbConnectionParams.ConnectionString = $ConnectionString

        $CommandDbInformation.Remove('DbConnectionType')
        $DbConnectionParams.ConnectionType = $ConnectionType
    }
    else {
        Write-Error ("param() block for '$CommandName' is missing a database connection in the {0} attribute. You must either specify a 'DbConnection' scriptblock that returns a [System.Data.Common.DbConnection] object, or valid 'DbConnectionString' and 'DbConnectionType' strings that can be used to create a connection." -f $__FakeAttributes.DbCommandInfoAttributeName)
        return
    }

    $CommandDbInformation.DbConnectionParams = $DbConnectionParams

    if (-not $CommandDbInformation.Contains('FromClause')) {
        Write-Error ("param() block for '$CommandName' is missing a 'FromClause' in the {0} attribute ([{0}(FromClause='<FROM CLAUSE HERE>')] param())" -f $__FakeAttributes.DbCommandInfoAttributeName)
        return
    }
    else {
        $EvaluatedFromClause = $DefinitionParsedParamBlock.DbInfo['FromClause'] | 
            EvaluateAttributeArgumentValue -LimitAstToType StringConstantExpressionAst, ExpandableStringExpressionAst -DontEvaluateScriptBlocks -Verbose -LimitNumberOfElements 1 |
            Add-Member -MemberType ScriptProperty -Name FormattedStrings -Value {
            $FromString = if ($this -is [scriptblock]) {
                & $this
            }
            else {
                $this.ToString()
            }
        
            [string[]] $TrimmedLines = $FromString.Split("`n", [System.StringSplitOptions]::RemoveEmptyEntries).Trim()
            $TrimmedLines[0] = $TrimmedLines[0].TrimStart("FROM ")

            $TrimmedLines
        } -PassThru

        $CommandDbInformation['FromClause'] = $EvaluatedFromClause


        if ($CommandDbInformation.Contains('PSTypeName')) {
#            Write-Warning "need to sanitize PSTypeName"
        }
    }

    $CommandDbInformation.PropertyParameters = [ordered] @{}
    #region Generate param() block (with comment based help preserved)

    # First, check to see about CmdletBinding
    # DESIGN NOTE: For now, no merging of CmdletBinding properties. This is a simple if defintion contains it, use that, else
    #              if reference contains it, use that, else no CmdletBinding() at all...
    if ($DefinitionParsedParamBlock.CmdletBinding.Text) {
        $null = $NewCommandStringBuilder.AppendLine($DefinitionParsedParamBlock.CmdletBinding.Text)
    }
    elseif ($ReferenceCommandParsedParamBlock.CmdletBinding.Text) {
        $null = $NewCommandStringBuilder.AppendLine($ReferenceCommandParsedParamBlock.CmdletBinding.Text)
    }

    $null = $NewCommandStringBuilder.AppendLine('param(')

    # Now let's go through each parameter
    # DESIGN NOTE: No merging here, either. Think of this like processing group policy: Reference command properties are added
    #              to a hash table, keyed on the property name. If the definition contains a property of the same name, then
    #              that one is used. Consider it a best practice not to use positional parameters in the reference command (it
    #              would make whoever is trying to lay down params in a command definition have to know about those positions...)
    $FinalParameters = $DefinitionParsedParamBlock.Parameters
    foreach ($Parameter in $ReferenceCommandParsedParamBlock.Parameters.GetEnumerator()) {
        if (-not $FinalParameters.Contains($Parameter.Name)) {
            Write-Verbose "  ...adding $($Parameter.Name)"
            $FinalParameters[$Parameter.Name] = $Parameter.Value
        }
        else {
            Write-Verbose "  ...skipping adding $($Parameter.Name) b/c it's defined in the definition"
        }
    }

    # Need parameters in an array so we can join them with commas and do pretty tabbing...
    $AllParameters = New-Object System.Collections.Generic.List[string]
    foreach ($Parameter in $FinalParameters.GetEnumerator()) {

        # Parameters defined in param() block serve two purposes: to define the SELECT clause components, and to define the
        # WHERE clause components. Sometimes you may just want to use them to define the SELECT clause components and not
        # have them show up as valid parameters. In those instances, you'd use the 'NoParameter' argument to the attribute.
        # If that argument is used, the parameter text simply isn't added to the actual defined command's param() block, but
        # it is kept track of for SELECT, GROUP BY, and ORDER BY purposes.
        if ($Parameter.Value.FakeAttributes[$__FakeAttributes.DbColumnProperty] | Where-Object NoParameter -eq $true | Select-Object -first 1) {
            # Do nothing (maybe some verbose or debug output?). User doesn't want this parameter added to the command
        }
        else {
            $AllParameters.Add("`t{0}" -f ($Parameter.Value.Text.Trim("`n") -replace '\n', "`n`t"))
        }

Write-Debug 'Checking for fake attributes'
        if ($Parameter.Value.FakeAttributes.ContainsKey($__FakeAttributes.DbColumnProperty)) {
            # The fake attributes that were parsed out are just PSObjects, and there can potentially be
            # multiples (think about how you can have more than one [Parameter()] attribute on a parameter).
            # For the property information, though, we need very specific information, and we can't have more
            # than one (so for now, you can't have more than 1 column name defined). So, we'll go through
            # each object and add the info to a hashtable.
            # So, the language will allow multiple DB Property attributes (maybe it shouldn't), and it will
            # allow unknown/unhandled arguments to the DB property (again, maybe it shouldn't). This is the
            # part where the information is error checked and normalized. If multiples are defined, the
            # order will matter (last one wins)

            $KnownAttributes = @(
                'ColumnName'      # The name of the column (used in SELECT block)
                'ComparisonOperator'
                'ConditionalOperator'
                'QuoteString'
                'TransformArgument'
                'AllowWildcards'
                'PropertyName'
            )
            
            $DbPropertyInfo = @{
                FormatTableInfo = New-Object System.Collections.Generic.List[psobject]
            }
            foreach ($PropertyObject in $Parameter.Value.FakeAttributes[$__FakeAttributes.DbColumnProperty]) {
                foreach ($CurrentAttribute in $KnownAttributes) {
                    if ($PropertyObject.$CurrentAttribute -ne $null) {
                        $DbPropertyInfo[$CurrentAttribute] = $PropertyObject.$CurrentAttribute
                    }
                }
            }

            foreach ($FormatTableInfo in $Parameter.Value.FakeAttributes[$__FakeAttributes.DbFormatTableInfo]) {
                # Multiple format table infos allowed. If no ViewName is specified, use '__DefaultView'
                $ViewName = if ($FormatTableInfo.ViewName) {
                    $FormatTableInfo.ViewName
                }
                else {
                    '__DefaultView'
                }

                # Next, figure out if a property name was used:
                $PropertyInfo = @{
                    #Label = $Parameter.Name
                    #Expression = [scriptblock]::Create('$_.{0}' -f $Parameter.Name)  # Parameter name may differ from the PSObject's property name (think of datetime suffixes)
                    Label = $DbPropertyInfo.PropertyName
                    Expression = [scriptblock]::Create('$_.{0}' -f $DbPropertyInfo.PropertyName)
                    Alignment = 'left'
                }

                foreach ($InfoType in Write-Output Label, Expression, Width, Alignment) {
                    if ($FormatTableInfo.$InfoType) {
                        $PropertyInfo.$InfoType = $FormatTableInfo.$InfoType
                    }
                }

                # Another issue when datetime (or numeric values with right attribute) get split into two: both parameters get a formattable attribute if one was defined
                # for the parent? parameter in the param() block. We're going to walk all the defined FormatTable entries for this command for now, but this is kind of a
                # dumb way to do this. FIX THIS!!
if ($CommandDbInformation.PropertyParameters.Values.FormatTableInfo | Where-Object ViewName -eq $ViewName | ForEach-Object ColumnDefinition | ForEach-Object GetEnumerator | Where-Object Name -eq Label | Where-Object Value -eq $DbPropertyInfo.PropertyName) {
    # Already defined!
}
else {
                $DbPropertyInfo.FormatTableInfo.Add([PSCustomObject] @{ ViewName = $ViewName; ColumnDefinition = $PropertyInfo })
}
            }

            # Take care of a few default options that should happen if user didn't specify them. Things like strings and
            # dates should be quoted, strings need a comparison operator, etc
            if ($Parameter.Value.ScalarType -eq [string]) {
                # Strings get special wildcard and quotestring treatment (unless they were specified in the fake attribute)
                if (-not $DbPropertyInfo.Contains('AllowWildcards')) {
                    $DbPropertyInfo['AllowWildcards'] = $true
                    
                    if (-not $DbPropertyInfo.Contains('ComparisonOperator')) {
                        $DbPropertyInfo['ComparisonOperator'] = 'LIKE'
                    }
                }
                if (-not $DbPropertyInfo.Contains('QuoteString')) {
                    $DbPropertyInfo['QuoteString'] = "'"
                }
            }

            if ($Parameter.Value.ScalarType -eq [datetime]) {
                if (-not $DbPropertyInfo.Contains('QuoteString')) {
                    $DbPropertyInfo['QuoteString'] = "'"
                }

                $DateParametersThatNeedCompleter.Add($Parameter.Key)
            }

            $CommandDbInformation.PropertyParameters[$Parameter.Name] = $DbPropertyInfo
        }
    }

    # In debug mode, every command gets a -ReturnSqlQuery parameter that can be used for testing
    if ($DebugMode) {
        $AllParameters.Add("`t[switch] `$ReturnSqlQuery")
    }

    $null = $NewCommandStringBuilder.AppendLine($AllParameters -join ",`n")
    $null = $NewCommandStringBuilder.AppendLine(')')

<# THIS MIGHT BE A GOOD IDEA ONE DAY. FOR NOW, THOUGH, TURNING IT OFF

    # Execute statements in the begin, process and end blocks:
    foreach ($BlockKind in echo begin, process, end) {
        Write-Verbose "Executing statements in $BlockKind block..."
        foreach ($Statement in $Definition.Ast."${BlockKind}Block".Statements) {
            Invoke-Expression $Statement
        }
    }
#>
    #endregion

    # Add begin {} process {} and end {} blocks from the reference command. For now, those code blocks
    # are completely ignored if they are defined in the new defintion...
    foreach ($BlockKind in Write-Output Begin, Process, End) {
        $null = $NewCommandStringBuilder.AppendLine($ReferenceCommandScriptBlock.Ast."${BlockKind}Block".Extent.Text)
    }

    $FinalCommandScriptBlock = [scriptblock]::Create($NewCommandStringBuilder.ToString())

    # Bind it to the module
    $FinalCommandScriptBlock = (& { $PSCmdlet.MyInvocation.MyCommand.Module }).NewBoundScriptBlock($FinalCommandScriptBlock)
    
    $null = New-Item function: -Name script:$CommandName -Value $FinalCommandScriptBlock -Force 
    Export-ModuleMember $CommandName

    if ($TabExpansionAvailable) {
        foreach ($ParamName in Write-Output GroupBy, OrderBy, Negate) {
            Register-ArgumentCompleter -CommandName $CommandName -ParameterName $ParamName -ScriptBlock $BoundStandardCompleter
        }

        foreach ($ParamName in $DateParametersThatNeedCompleter) {
            Register-ArgumentCompleter -CommandName $CommandName -ParameterName $ParamName -ScriptBlock $BoundDateTimeCompleter
        }
    }

    # Get format information
    $PsTypeName = $CommandDbInformation.PsTypeName
    if ($PSTypeName) {
        $CommandDbInformation.PropertyParameters.Values.FormatTableInfo | Group-Object ViewName | ForEach-Object {
#            $TempFile = "$env:temp\{0}.ps1xml" -f [guid]::NewGuid()
            $TempFile = "$env:temp\db_reader_${pstypename}_format_file.ps1xml"
            New-TableFormatXml -MemberType $PsTypeName -ViewName $_.Name -TableInfo $_.Group.ColumnDefinition |
                Out-File -FilePath $TempFile -Force
            Update-FormatData -PrependPath $TempFile

            # For now, don't remove this. The type system gets really mad when it's updated again and the formatting
            # file is gone. Long term, though, truly random temp files can't hang around. What if a folder is created
            # in AppData for each module, and the formatting filename is generated based on the PSTypeName and a
            # hash of the Formatting Information? That way it can stick around for longer. Even if it is deleted,
            # that would be OK
#            Remove-Item $TempFile -Force
        }
    }

    # Stash the information in the module scope:
    $__CommandDeclarations[$CommandName] = $CommandDbInformation
}
#endregion

#region Low level helper commands
function InvokeReaderCommand {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ParameterSetName="ByConnectionString")]
        [string] $ConnectionString,
        [Parameter(Mandatory, ParameterSetName="ByConnectionString")]
# Might try to make just the short name work here if it's possible to find it based on being an inherited class of DbConnection...
        [type] $ConnectionType,
        [Parameter(Mandatory, Position=0, ParameterSetName="ByConnection")]
        [System.Data.Common.DbConnection] $Connection,
        [Parameter(Mandatory, Position=1)]
        [string] $Query,
        # Optional PSTypeNames to add to the objects that are output
        [string[]] $PSTypeName
    )


    process {
        switch ($PSCmdlet.ParameterSetName) {
            ByConnectionString {
                # Create the connection:
                try {
                    $Connection = New-Object -TypeName $ConnectionType $ConnectionString -ErrorAction Stop
                }
                catch {
                    Write-Error "Unable to open '$ConnectionType' connection with string '$ConnectionString': $_"
                    return
                }
            }
        }

        # Make sure the connection is open (if we created it in this function, it won't be). Also, if we open it,
        # we need to close it
        $NeedToClose = $false
        if ($Connection.State -ne "Open") {
            $Connection.Open()
            $NeedToClose = $true
        }

        $Command = $Connection.CreateCommand()
        $Command.Connection = $Connection
        $Command.CommandText = $Query

        try {
            $Reader = $Command.ExecuteReader()

            $RecordObjectProperties = [ordered] @{}
            while ($Reader.Read()) {
                $RecordObjectProperties.Clear()

    	        for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
                    $Name = $Reader.GetName($i)
                    $Value = $Reader.GetValue($i)

                    if ([System.DBNull]::Value.Equals($Value)) { $Value = $script:__OutputNullReplacementString }

                    if ($RecordObjectProperties.Contains($Name)) {
                        Write-Warning "$Name already exists. Property is going to be overwritten right now, but the InvokeReaderCommand function will be changed at some point so that a new Property will be created instead..."
                    }

                    $RecordObjectProperties[$Name] = $Value
    	        }
                $ReturnObject = [PSCustomObject] $RecordObjectProperties

                if ($PSBoundParameters.ContainsKey('PSTypeName')) {
                    foreach ($CurrentTypeName in $PSTypeName) {
                        $ReturnObject.pstypenames.Insert(0, $CurrentTypeName)
                    }
                }

                $ReturnObject
            }
        }
        catch {
            Write-Warning "Error executing query '$Query' on '$($Connection.ConnectionString)':"
            Write-Warning "    -> $_"
            return
        }
        finally {
            if ($Reader) {
                $Reader.Dispose()
            }

            if ($NeedToClose) {
                $Connection.Close()
            }
            if ($PSCmdlet.ParameterSetName -eq "ByConnectionString") {
                $Connection.Dispose()
            }
        }
    }
}


function DateTimeConverter {

    [CmdletBinding(DefaultParameterSetName='NormalConversion')]
    param(
        [Parameter(ValueFromPipeline, Mandatory, Position=0, ParameterSetName='NormalConversion')]
        [AllowNull()]
        $InputObject,
        [Parameter(Mandatory, ParameterSetName='ArgumentCompleterMode')]
        [AllowEmptyString()]
        [string] $wordToComplete
    )

    begin {
        $RegexInfo = @{
            Intervals = Write-Output Minute, Hour, Day, Week, Month, Year   # Regex would need to be redesigned if one of these can't be made plural with a simple 's' at the end
            Separators = Write-Output \., \s, _  #, '\|' # Bad separator in practice, but maybe good for an example of how easy it is to add a separator and then get command completion and argument conversion to work
            Adverbs = Write-Output Ago, FromNow
            GenerateRegex = {
                $Definition = $RegexInfo
                $Separator = '({0})?' -f ($Definition.Separators -join '|')   # ? makes separators optional
                $Adverbs = '(?<adverb>{0})' -f ($Definition.Adverbs -join '|')
                $Intervals = '((?<interval>{0})s?)' -f ($Definition.Intervals -join '|')
                $Number = '(?<number>-?\d+)'

                '^{0}{1}{2}{1}{3}$' -f $Number, $Separator, $Intervals, $Adverbs
            }
        }
        $DateTimeStringRegex = & $RegexInfo.GenerateRegex

        $DateTimeStringShortcuts = @{
            Now = { Get-Date }
            Today = { (Get-Date).ToShortDateString() }
            ThisMonth = { $Now = Get-Date; Get-Date -Month $Now.Month -Day 1 -Year $Now.Year }
            LastMonth = { $Now = Get-Date; (Get-Date -Month $Now.Month -Day 1 -Year $Now.Year).AddMonths(-1) }
            NextMonth = { $Now = Get-Date; (Get-Date -Month $Now.Month -Day 1 -Year $Now.Year).AddMonths(1) }
        }
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
        
            NormalConversion {
                if ($InputObject -eq $null) {
                    $InputObject = [System.DBNull]::Value
                }

                foreach ($DateString in $InputObject) {

                    if ($DateString -eq $null) {
                        # Let the DbReaderInfo transformer handle this
                        $null
                        continue
                    }
                    elseif ($DateString -as [datetime]) {
                        # No need to do any voodoo if it can already be coerced to a datetime
                        $DateString
                        continue
                    }

                    if ($DateString -match $DateTimeStringRegex) {
                        $Multiplier = 1  # Only changed if 'week' is used
                        switch ($Matches.interval) {
                            <#
                                Allowed intervals: minute, hour, day, week, month, year

                                Of those, only 'week' doesn't have a method, so handle it special. The
                                others can be handled in the default{} case
                            #>

                            week {
                                $Multiplier = 7
                                $MethodName = 'AddDays'
                            }

                            default {
                                $MethodName = "Add${_}s"
                            }

                        }

                        switch ($Matches.adverb) {
                            fromnow {
                                # No change needed
                            }

                            ago {
                                # Multiplier needs to be negated
                                $Multiplier *= -1
                            }
                        }

                        try {
                            (Get-Date).$MethodName.Invoke($Multiplier * $matches.number)
                            continue
                        }
                        catch {
                            Write-Error $_
                            return
                        }
                    }
                    elseif ($DateTimeStringShortcuts.ContainsKey($DateString)) {
                        (& $DateTimeStringShortcuts[$DateString]) -as [datetime]
                        continue
                    }
                    else {
                        # Just return what was originally input; if this is used as an argument transformation, the binder will
                        # throw it's localized error message
                        $DateString
                    }
                }

            }

            ArgumentCompleterMode {
                $CompletionResults = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

                # Check for any shortcut matches:
                foreach ($Match in ($DateTimeStringShortcuts.Keys -like "*${wordToComplete}*")) {
                    $EvaluatedValue = & $DateTimeStringShortcuts[$Match]
                    $CompletionResults.Add((NewCompletionResult -CompletionText $Match -ToolTip "$Match [$EvaluatedValue]"))
                }

                # Check to see if they've typed anything that could resemble valid friedly text
# Trim wildcards??
                if ($wordToComplete -match "^(-?\d+)(?<separator>$($RegexInfo.Separators -join '|'))?") {

                    $Length = $matches[1]
                    $Separator = " "
                    if ($matches.separator) {
                        $Separator = $matches.separator
                    }

                    $IntervalSuffix = 's'
                    if ($Length -eq '1') {
                        $IntervalSuffix = ''
                    }

                    foreach ($Interval in $RegexInfo.Intervals) {
                        foreach ($Adverb in $RegexInfo.Adverbs) {
#                            $CompletedText = $DisplayText = "${Length}${Separator}${Interval}${IntervalSuffix}${Separator}${Adverb}"
#                            if ($CompletedText -match '\s') {
#                                $CompletedText = "'$CompletedText'"
#                            }
                            $Text = "${Length}${Separator}${Interval}${IntervalSuffix}${Separator}${Adverb}"
                            if ($Text -like "*${wordToComplete}*") {
                                $CompletionResults.Add((NewCompletionResult -CompletionText $Text))
                            }
                        }
                    }
                }


                $CompletionResults
            }

            default {
                # Shouldn't happen. Just don't return anything for now...
            }
        }
    }
}

function NewCompletionResult {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $CompletionText,
        [string] $ListItemText,
        [System.Management.Automation.CompletionResultType] $ResultType = 'ParameterValue',
        [string] $ToolTip,
        [switch] $NoQuotes
    )

    process {

        if (-not $PSBoundParameters.ContainsKey('ListItemText')) {
            $ListItemText = $CompletionText
        }

        if (-not $PSBoundParameters.ContainsKey('ToolTip')) {
            $ToolTip = $CompletionText
        }

        # CHOOSING WHICH VARIABLE TO MATCH THIS TO MATTERS IN REGARDS TO BEHAVIOR OF COMMAND!!
        if ($ListItemText -notlike "${wordToComplete}*") { return }

        # Modified version of the check from TabExpansionPlusPlus (I added the single quote escaping)
        if ($ResultType -eq [System.Management.Automation.CompletionResultType]::ParameterValue -and -not $NoQuotes) {
            # Add single quotes for the caller in case they are needed.
            # We use the parser to robustly determine how it will treat
            # the argument.  If we end up with too many tokens, or if
            # the parser found something expandable in the results, we
            # know quotes are needed.

            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput("echo $CompletionText", [ref]$tokens, [ref]$null)
            if ($tokens.Length -ne 3 -or
                ($tokens[1] -is [System.Management.Automation.Language.StringExpandableToken] -and
                 $tokens[1].Kind -eq [System.Management.Automation.Language.TokenKind]::Generic))
            {
                $CompletionText = "'$($CompletionText -replace "'", "''")'"
            }
        }

        New-Object System.Management.Automation.CompletionResult $CompletionText, $ListItemText, $ResultType, $ToolTip
    }
}

function NewOrderByString {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('Expression', 'Value', 'Name', 'ColumnName')]
        [object] $Property,
        [switch] $Descending,
        [string[]] $ValidNames
    )

    process {
        foreach ($CurrentProperty in $Property) {
            if ($CurrentProperty -is [hashtable]) {
                try {
                    $Params = $CurrentProperty.Clone()
                    if ($Params.ContainsKey('ValidNames')) {
                        $Params.Remove('ValidNames')
                    }
                    (& $PSCmdlet.MyInvocation.MyCommand -ErrorAction Stop @Params)
                }
                catch {
                    throw $_
                }
            }
            else {

                $PropertyName = $CurrentProperty.ToString()
                $DescendingEnabled = $Descending

                try {

                    if ($ValidNames -notcontains $PropertyName) {
                        # This is a problem. A valid property wasn't specified. One last chance: does
                        # the string end with 'ASC' or 'DESC' or '!'?
                        if ($PropertyName -match "^(.*)((?<excmark>!)|\s+(?<orderstring>ASC|DESC))$") {
                            $PropertyName = $Matches[1]
                        
                            if ($Matches.orderstring -eq "DESC" -or $Matches.excmark -eq "!") {
                                $DescendingEnabled = $true
                            }
                            else {
                                $DescendingEnabled = $false
                            }

                            if ($ValidNames -notcontains $PropertyName) {
                                throw "Unknown"
                            }
                        }
                        else {
                            throw "Unknown"
                        }
                    }
                }
                catch {
                    Write-Warning "Unknown -OrderBy property '$PropertyName' will be ignored"
                    continue
                }

                # Quick way to make this match the case from the SELECT statement. Should be able to refactor
                # code above to do it without this last minute check
                $PropertyName = $ValidNames -eq $PropertyName | Select-Object -first 1
                "$PropertyName$(if ($DescendingEnabled) { " DESC" })"
            }
        }
    }
}
function ContainsMatch {
<#
Used mostly to figure out if a value is contained in a collection. Can't just use -contains because
the collection can have wildcards in it
#>
    param( 
        [string[]] $Collection,
        [string] $ValueToMatch
    )

    foreach ($Current in $Collection) {
        if ($ValueToMatch -like $Current) {
            return $true
        }
    }
    return $false
}

function PrepReaderInfoForSql {
<#
This gets a set of values ready for SQL format. It can replace PS wildcards with SQL wildcards, and it handles
quoting. It also
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject
    )

    process {
        if ($InputObject -is [string]) {
            # Add quotes
        }
    }
}

# Pretty much every argument this module generates will have a ROE.TransformParameter() attribute
# that calls this function to populate a side hashtable for each parameter in $PSBoundParameters.
# The side table contains a PSObject (one day a class, though) that contains DB relevant information,
# like whether or not the value should be negated, whether it was null, etc. It works with the
# NewDbReaderInfo function...

function AddDbReaderInfo {
<#

This function's job is to hide extra information in a strongly typed parameter, e.g.,
if you have an [int] named $Number that is a parameter for another function, this
function can be used in an argument transformation attribute to allow a hash table
to be passed in instead of just an [int], which opens the possibilty of negating a
parameter or changing the conditional operator used for joining multiple values
together (not applicable for [int], but would be for [int[]])

This function let's you do something like this:
function DemoAddDbReaderInfo {
    param(
        [ROE.TransformArgument({
            AddDbReaderInfo $_ -OutputType [int[]]
        })
        [int[]] $Id,
        [ROE.TransformArgument({
            AddDbReaderInfo $_ -OutputType [string[]]
        })
        [string[]] $Name,
        [ROE.TransformArgument({
            AddDbReaderInfo $_ -OutputType [datetime[]]
        })
        [datetime[]] $Date
    )

    $PSBoundParameters
}
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject,
        [type] $OutputType = [object[]],
        # This is used to look up the command declaration in module scope in order
        # to figure out the column name for the property that will hold the reader
        # info object
        [string] $CommandName,
        # Used with CommandName to figure out the DB column name
        [string] $ParameterName
    )

    begin {
        $CollectedReaderInfos = New-Object System.Collections.Generic.List[PSObject]

        $ParameterInformation = $__CommandDeclarations.$CommandName.PropertyParameters.$ParameterName
        if ($ParameterName -eq $null) {
            Write-Warning "Unable to find parameter information for '$ParameterName' parameter in '$CommandName' command"
        }
    }

    process {

        # Take any non-array and non-hashtable values and group them into their own array. That way, they will
        # be contained in a single DBReaderInfo
        $SimpleValues = New-Object System.Collections.Generic.List[object]
        $ComplexValues = New-Object System.Collections.Generic.List[object]
        
        if ($null -eq $InputObject) {
            # null is treated as a simple value
            $InputObject = @($null)
        }

        foreach ($var in $InputObject) {
            if ($var -is [array] -or $var -is [System.Collections.IDictionary]) { $ComplexValues.Add($var) }
            else { $SimpleValues.Add($var) }
        }

        if ($SimpleValues.Count) { $ComplexValues.Insert(0, $SimpleValues) }

        foreach ($CurrentInput in $ComplexValues) {

            if ($CurrentInput -is [System.Collections.IDictionary] -and -not [System.Collections.IDictionary].IsAssignableFrom($OutputType)) {
                if ($CurrentInput.Keys -contains 'ParameterInformation') { $CurrentInput.Remove('ParameterInformation') }  # User can't specify this
                $DbReaderInfo = NewDbReaderInfo @CurrentInput -OutputValueType $OutputType -ParameterInformation $ParameterInformation
            }
            else {
                # User passed simple data, i.e., no advanced hash table syntax was used
                $DbReaderInfo = NewDbReaderInfo -Value $CurrentInput -OutputValueType $OutputType -ParameterInformation $ParameterInformation
            }

            # Multiples are possible (think of $null and values being passed, or nested arrays, etc)
            foreach ($CurrentReaderInfo in $DbReaderInfo) {
                $CollectedReaderInfos.Add($CurrentReaderInfo)
            }
        }
    }

    end {
        # Attach helper function that converts all of the info contained in the DBReaderInfo object(s) to a string:
        $DbReaderInfoToString = {

            $AllConditions = foreach ($DbReaderInfo in $this.GetEnumerator()) {
                $Values = if ($DbReaderInfo.IsNull) {
                    'NULL'
                }
                else {
                    $DbReaderInfo.Value
                }


                $Values = foreach ($CurrentValue in $Values) {
                    if ($DbReaderInfo.AllowWildcards) {
                        # Translate wildcards to valid SQL (this currently assumes WildcardPattern
                        # can handle this w/o problem
                        $CurrentValue = (New-Object System.Management.Automation.WildcardPattern $CurrentValue).ToWql()
                    }

                    if ($DbReaderInfo.TransformArgument -is [scriptblock]) {
                        $CurrentValue = $CurrentValue | ForEach-Object $DbReaderInfo.TransformArgument
                    }

                    '{1}{0}{1}' -f $CurrentValue, $DbReaderInfo.QuoteString
                }

                $Conditions = foreach ($CurrentValue in $Values) {
                    '{0} {1} {2}' -f $DbReaderInfo.ColumnName, $DbReaderInfo.ComparisonOperator, $CurrentValue
                }

                '{0}({1})' -f $(if ($DbReaderInfo.Negate) { 'NOT ' }), ($Conditions -join " $($DbReaderInfo.ConditionalOperator) ")
            }

            $AllConditions -join ' OR ' # NEED TO MAKE OR CONFIGURABLE
        }
        Add-Member -InputObject $CollectedReaderInfos -MemberType ScriptMethod -Name ToWhereString -Value $DbReaderInfoToString

        # Populate the $PSBoundDbReaderInfos table in the function's scope.
        # NOTE: Hardcoding the scope isn't a good idea. We can make logic to walk the scope chain and figure out when
        #       it's found the right scope
        $PsBoundDbReaderInfos = try {
            Get-Variable -Scope 2 -Name $__DbReaderInfoTableName -ValueOnly -ErrorAction Stop
        }
        catch {
            @{}
        }

        $PsBoundDbReaderInfos[$ParameterName] = $CollectedReaderInfos
        Set-Variable -Name $__DbReaderInfoTableName -Scope 2 -Value $PsBoundDbReaderInfos
        
        # We need a valid value to return so that the PowerShell binder will be happy. To do that, we're going to look at
        # the .Value on each DBReaderInfo that we've generated/collected, and if we can't find a valid value there, we'll
        # write out a warning.
        # 
        # If $null was the only thing that came through, that value is @(), and a coercion attempt will be made. As long
        # as -OutputType is an array, it should work just fine.
        foreach ($CurrentReaderInfo in $CollectedReaderInfos.Value) {
            if (($ReturnValue = $CurrentReaderInfo -as $OutputType) -is [object]) {
                return , $ReturnValue
            }
        }
        
        Write-Warning "Unable to coerce a value to attach a DbReaderInfo to..."
    }
}

function NewDbReaderInfo {
<#
Helper function that is meant to allow a hash table to be splatted to it, which
allows for shorthand format like this:

$Params = @{V='Value'; N=$true}  # Value would be 'Value', and Negate would be $true
#>
    param(
        $Value,
        [switch] $Negate,
        [Alias('Operator')]
        [ValidateSet('AND','OR')]
        [string] $ConditionalOperator = 'OR',
        # This needs a validate set
        [string] $ComparisonOperator = '=',
        [type] $OutputValueType = [object[]],
        # Copy of the parameter information for the current parameter (provides default parameter information that
        # might have been defined in the command definition
        [System.Collections.IDictionary] $ParameterInformation,
        [string] $ColumnName,
#      [string] $PropertyName,
        # If OutputValueType is a string, this defaults to '
        [string] $QuoteString,
        [scriptblock] $TransformArgument,
        # If OutputValueType is a string, this defaults to true, otherwise false
        [switch] $AllowWildcards
    )

    $NullValue = $null

    $TypeToCoerce = $OutputValueType
    if ($OutputValueType.IsArray) {
        $TypeToCoerce = $OutputValueType.GetElementType()
    }

    foreach ($ParameterName in $MyInvocation.MyCommand.Parameters.Keys) {
        
        if ($ParameterName -in 'Value', 'ParameterInformation') {
            # User can't specify this information in the database reader parameter attribute (even though
            # defining a default value there might be kind of cool; more testing needed for that)
            continue
        }

Write-Debug "Default checker for parameter $ParameterName"
        if (-not $PSBoundParameters.ContainsKey($ParameterName) -and $ParameterInformation.Contains($ParameterName)) {
Write-Debug "  ..found default"
#            $PSBoundParameters[$ParameterName] = $ParameterInformation
            Set-Variable -Name $ParameterName -Value $ParameterInformation[$ParameterName] -Scope Local
        }
    }

    if ($Value.Count -eq 0 -and $Value -eq $null) {
        # This makes it so the foreach() block will execute once (there's logic
        # to handle nulls)
        $Value = @($null)
    }

    $NonNullValues = foreach ($CurrentValue in $Value) {
        if ($CurrentValue -in $null, [System.DBNull]::Value) {
            # This block of code won't emit anything to $NonNullValues, but
            # instead does some work setting up for the section below the
            # else {} block

            $NullFound = $true

            # This part looks a little weird. If the user passed $null, we have
            # to still give PowerShell something (remember, we're passing real
            # instances with synthetic properties). Let's try to let PS do its
            # type coercion, e.g., int would become 0 if $null was passed. We
            # do need to check for an array, though, b/c int[] (in our example)
            # wouldn't be coerced to 0 from $null
            #
            # NOTE: This section needs to be refactored since we don't attach
            #       DBReaderInfo to each parameter. AddDbReaderInfo still needs
            #       to be able to output a valid instance of the parameter type,
            #       though, so this will need some thought. When this goes to
            #       a real class, we'll handle it then

            # Some types coerce null into the right type, e.g., int makes it 0, string makes it empty string
            $NullValue = $null -as $TypeToCoerce

            if ($NullValue -eq $null) {
                # Couldn't coerce it...let's try to make it an empty array (AddDbReaderInfo needs something to attach the DbReaderInfo to)
                $NullValue = @() -as $OutputValueType
            }
        }
        else {
            # Output the current value. Dirty hack here where it checks for a datetime and gives it special treatment. It's not good b/c
            # datetime already gets special treatment during param() parsing when the TransformArgument attribute is added. Doing check
            # here helps for when the TransformArgument wasn't called...
            if ($TypeToCoerce -eq [datetime] -and $CurrentValue -isnot [datetime]) {
                DateTimeConverter -InputObject $CurrentValue
            }
            else {
                $CurrentValue
            }
        }
    }

    $DbReaderProps = @{
        Negate = $Negate -as [bool]
        ConditionalOperator = $ConditionalOperator
        ComparisonOperator = $ComparisonOperator
        IsNull = $false
        ColumnName = $ColumnName
        AllowWildcards = $AllowWildcards -as [bool]
        QuoteString = $QuoteString
        TransformArgument = $TransformArgument
    }

<#
    if ($PropertyName) {
        $DbReaderProps.PropertyName = $PropertyName
    }
#>
    if ($NonNullValues -ne $null) {
        $DbReaderProps.Value = $NonNullValues -as $OutputValueType
        [PSCustomObject] $DbReaderProps
    }
    if ($NullFound) {
        $DbReaderProps.Value = $NullValue
        $DbReaderProps.IsNull = $true
        
        if (-not $PSBoundParameters.ContainsKey('ComparisonOperator')) {
            # In the unlikely event that 'IS' is the wrong operator, the user can actually override it
            $DbReaderProps.ComparisonOperator = 'IS'
        }
        if (-not $PSBoundParameters.ContainsKey('QuoteString')) {
            $DbReaderProps.QuoteString = ''
        }
        [PSCustomObject] $DbReaderProps
    }
}

function GetValueFromAst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Management.Automation.Language.CommandElementAst] $AstNode
    )

    process {
        switch ($AstNode.GetType().Name) {
            #StringConstantExpressionAst {
            { $AstNode -is [System.Management.Automation.Language.ConstantExpressionAst] } {
                return $AstNode.Value
            }
            
            ScriptBlockExpressionAst {
                try {
# This one doesn't seem to work with variables that haven't been defined...
#                   $Scriptblock = $AstNode.ScriptBlock.GetScriptBlock()
                    $ScriptBlock = ([scriptblock]::Create($AstNode.ScriptBlock.ToString().Trim('{','}')))
                    
                    if ($EvaluateScriptBlock) {
                        return (& $ScriptBlock)
                    }
                    else {
                        return $ScriptBlock
                    }

                }
                catch {
                    Write-Warning "GetAstValue: Error executing scriptblock: $_"
                    return "[ERROR EXECUTING SCRIPTBLOCK: $_]"
                }
            }

            VariableExpressionAst {
                $GetVarParams = @{
                     ValueOnly = $true
                     Name = $AstNode.VariablePath.UserPath
                     ErrorAction = 'Stop'
                }

                if ($AstNode.IsGlobal) {
                    $GetVarParams.Scope = 'global'
                }
                elseif ($AstNode.IsScript) {
                    $GetVarParams.Scope = 'script'
                }

                try {
                    $ReturnValue = Get-Variable @GetVarParams 
                    return $ReturnValue
                }
                catch {
                    Write-Warning "Error getting value for `$$($GetVarParams.Name): ${_}"
                    return $null
                }
            }

            default {
Write-Debug "GetAstValue: Unsupported node type '$_'"
                Write-Warning "GetAstValue: Unsupported node type '$_', so returing '[UNKNOWN VALUE]'"
                return '[UNKNOWN VALUE]'
            }
        }
    }

}

function MergeHelpInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        # This is the starting help info. Any changes are made to this
        [System.Management.Automation.Language.CommentHelpInfo] $HelpInfo,
        [Parameter(Mandatory, ParameterSetName='TwoHelpInfos')]
        [System.Management.Automation.Language.CommentHelpInfo] $UpdatedHelpInfo,
        [Parameter(Mandatory, ParameterSetName='AttributeAst')]
        [System.Management.Automation.Language.AttributeAst] $HelpAttribute
    )

    process {
        Write-Verbose "In $($PSCmdlet.ParameterSetName) parameterset..."

        $UpdateMode = 'Overwrite'  # UpdateMode needs to be an enumeration; for now there are two modes: Overwrite and Merge

        switch ($PSCmdlet.ParameterSetName) {
            TwoHelpInfos {
                # No extra work needed. Function is set up to look at $UpdatedHelpInfo for stuff to 
                # add to original $HelpInfo...
                $GenericUpdatedHelpInfo = $UpdatedHelpInfo
            }

            AttributeAst {
                # Convert all named attributes into a PSObject (except 'UpdateMode', which will update the functions $UpdateMode)
                $HelpObject = @{}
                foreach ($Argument in $HelpAttribute.NamedArguments) {
                    if ($Argument.ArgumentName -eq 'UpdateMode') {
                        $UpdateMode = $Argument.Argument | GetValueFromAst
                        continue
                    }

                    $HelpObject[$Argument.ArgumentName] = $Argument.Argument | GetValueFromAst
                }
                $GenericUpdatedHelpInfo = [PSCustomObject] $HelpObject
            }

            default {
                throw "Unknown parameterset"
            }
        }

        # Should be pretty simple. Look through each property, and overwrite
        # $HelpInfo if the property is used (strings are checked for null, and
        # IEnumerables are checked for Count
        foreach ($PropertyInfo in [System.Management.Automation.Language.CommentHelpInfo].GetProperties()) {
            $PropertyName = $PropertyInfo.Name
            Write-Verbose "Current HelpInfo property: $PropertyName"
            if ($GenericUpdatedHelpInfo.$PropertyName -eq $null -or ($HelpInfo.$PropertyName -is [System.Collections.IEnumerable] -and $GenericUpdatedHelpInfo.$PropertyName.Count -eq 0)) {
#                Write-Verbose "  ...property not set, so skipping"
            }
            else {
                
                $HelpInfoValue = switch ($PropertyInfo.PropertyType.Name) {

                    ReadOnlyCollection``1 {
                        
                        $GenericType = $PropertyInfo.PropertyType.GenericTypeArguments[0]
                        $NewList = New-Object System.Collections.Generic.List[$GenericType]
                        if ($UpdateMode -eq 'Merge') {
                            # Put the originals in the list
                            foreach ($CurrentValue in $HelpInfo.$PropertyName) {
                                $null = $NewList.Add($CurrentValue)
                            }
                        }

                        foreach ($CurrentValue in $GenericUpdatedHelpInfo.$PropertyName) {
                            $null = $NewList.Add($CurrentValue)
                        }

                        try {
                            New-Object System.Collections.ObjectModel.ReadOnlyCollection[$GenericType] -ArgumentList (,$NewList) -ErrorAction Stop
                        }
                        catch {
                            "[ERROR CREATING OBJECT: $_]"
                        }
                    }

                    IDictionary``2 {
                        $GenericType = $PropertyInfo.PropertyType.GenericTypeArguments
                        $NewDict = New-Object "System.Collections.Generic.Dictionary[$($GenericType.Name -join ',')]"
                        if ($UpdateMode -eq 'Merge') {
                            # Put the originals in the list
                            $OldDict = $HelpInfo.$PropertyName
                            foreach ($CurrentKey in $OldDict.Keys) {
                                $null = $NewDict.Add($CurrentKey, $OldDict[$CurrentKey])
                            }
                        }

                        $UpdatedDict = $GenericUpdatedHelpInfo.$PropertyName
                        # This has to be a dictionary...
                        if ($UpdatedDict -isnot [System.Collections.IDictionary]) {
                            Write-Warning "Can't update '$PropertyName' because it should implement IDictionary and it doesn't..."
                            continue
                        }
                        foreach ($CurrentKey in $UpdatedDict.Keys) {
                            $UpdatedValue = $UpdatedDict[$CurrentKey]
                            
                            if ($NewDict.ContainsKey($CurrentKey) -and $UpdateMode -eq 'Merge') {
                                $UpdatedValue = $NewDict[$CurrentKey], $UpdatedValue -join "`n`n"
                            }
                            $null = $NewDict[$CurrentKey] = $UpdatedValue
                        }

                        $NewDict
                    }

                    string {
                        "{0}{1}`n`n" -f "$(if ($UpdateMode -eq 'Merge') {$HelpInfo.$PropertyName -replace "`\r?\n\r?\n$"})", $GenericUpdatedHelpInfo.$PropertyName
                    }

                    default {
                        Write-Warning "Unable to update '$PropertyName' in help info because it is of unknown type '$_'"
                    }
                }

                if ($HelpInfoValue -eq $null) { continue }

                Write-Verbose "  ...updating original CommentHelpInfo ($UpdateMode mode)"
                if ($HelpInfoValue -is $PropertyInfo.PropertyType) {
                    $PropertyInfo.SetValue($HelpInfo, $HelpInfoValue)
                }
                else {
                    Write-Warning "Can't set '$($PropertyInfo.Name)' for HelpInfo because it is of type '$($HelpInfoValue.GetType())' instead of '$($PropertyInfo.PropertyType)'"
                }
            }
        }

    }
}

function ParseParamBlock {
<#
    Parse a param block, separating 'fake' attributes and comments
#>

    [CmdletBinding()]
    param(
        [System.Management.Automation.Language.ParamBlockAst] $ParamBlockAst,
        [string] $CommandName,
        # Temporary switch used for testing the timing b/w re-tokenizing each parameter and not re-tokenizing
        [switch] $DontDoHelp
    )

    $ReturnHashtable = @{}

    $CmdletBinding = $ParamBlockAst.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } | Select-Object -first 1

    $ReturnHashTable.CmdletBinding = @{
        Ast = $CmdletBinding
        Text = $CmdletBinding.Extent.Text
    }

    $DbInfo = [ordered] @{}
    $ParamBlockAst.Attributes | Where-Object { $_.TypeName.Name -eq $__FakeAttributes.DbCommandInfoAttributeName } | Select-Object -first 1 | ForEach-Object {
        foreach ($NamedArg in $_.NamedArguments) {
            $DbInfo[$NamedArg.ArgumentName] = $NamedArg.Argument | GetValueFromAst
        }
    }
    $ReturnHashtable.DbInfo = $DbInfo

    $ReturnHashtable.HelpAttributes = $ParamBlockAst.Attributes | Where-Object { $_.TypeName.Name -eq $__FakeAttributes.HelpAttributeName }

    $ReturnHashtable.Parameters = [ordered] @{}

    # AST doesn't seem to care about comments for parameters, so we're going to use the tokenizer to get that info:
if (-not $DontDoHelp) {          # THIS IS FOR DEBUGGING PURPOSES FOR NOW
    $ParamComments = @{}
    $CurrentComments = New-Object System.Text.StringBuilder
    $TokensForComments = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($ParamBlockAst.Extent.Text, [ref] $TokensForComments, [ref] $null)
    foreach ($token in $TokensForComments) {
        switch ($token.Kind) {
            Variable {
                # Found a parameter name, so save the current comments and clear out
                # the stringbuilder
                if ($CurrentComments.Length) {
                    $ParamComments[$token.Name] = $CurrentComments.ToString()
                    $null = $CurrentComments.Clear()
                }
            }

            Comment {
                # Add it to the stringbuilder (we still don't know which parameter
                # it belongs to)
                $null = $CurrentComments.AppendLine($token.Text)
            }

            Param {
                # Not sure if comments can appear before the param keyword, but if they
                # can, this will clear any out
                $null = $CurrentComments.Clear()
            }
        }
    }
}

    $ParamText = New-Object System.Text.StringBuilder
    foreach ($ParamAst in $ParamBlockAst.Parameters) {
        
        $null = $ParamText.Clear()
        $FakeAttributes = @{}

        $ParamName = $ParamAst.Name.VariablePath.UserPath

        # Look through each attribute
        foreach ($ParamAttributeAst in $ParamAst.Attributes) {
            if ($ParamAttributeAst -isnot [System.Management.Automation.Language.AttributeAst]) {
                # Type constraint is of type [TypeConstraintAst], and would hit this
                # We can ignore that b/c we'll get the type constraint from the $ParamAst
                continue
            }

            $AttributeName = $ParamAttributeAst.TypeName.Name
            if ($AttributeName -in $__FakeAttributes.Values) {
                # Must be a fake attribute, so don't write it back out; instead store
                # it in the fake attrib hashtable
                
                $AttribArgs = @{}
                $AttribArgs["__UnnamedArgs"] = foreach ($PositionalArg in $ParamAttributeAst.PositionalArguments) {
                     $PositionalArg | GetValueFromAst
                }

                foreach ($NamedArg in $ParamAttributeAst.NamedArguments) {
                    $AttribArgs[$NamedArg.ArgumentName] = $NamedArg.Argument | GetValueFromAst
                }

                if (-not $FakeAttributes.ContainsKey($AttributeName)) {
                    $FakeAttributes[$AttributeName] = New-Object System.Collections.Generic.List[PSObject]
                }

                if ($AttributeName -eq $__FakeAttributes.DbColumnProperty) {
                    # This what the return object will call the property that this DB column info
                    # points to. We need to define it now b/c some parameters are split into to
                    # below.
                    if (-not $AttribArgs.ContainsKey('PropertyName')) {
                        $AttribArgs.PropertyName = $ParamName
                    }
                }

                $FakeAttributes[$AttributeName] += [PSCustomObject] $AttribArgs
            }
            else {
                # Assume this attribute to be a real one and write it back out
                $null = $ParamText.AppendLine($ParamAttributeAst.Extent.Text)
            }
        }


        # DbComparisonSuffixAttributeName is an option that will create two parameters instead of one. First shot at implementing it
        # is going to be ugly; will need to refactor this code to be cleaner. For now, take a snapshot of the $ParamText (both
        # parameters will share the same attributes). Then do a foreach for the potential parameter names and restart the process
        #
        # NOTE: I don't like the object array for the fake parameters. Think we might just make it so you can only have a single
        #       database reader attribute for a parameter. That would make this MUCH cleaner
        $ParamTextAttributes = $ParamText.ToString()
        $ParamHashTables = if ($FakeAttributes[$__FakeAttributes.DbComparisonSuffixAttributeName]) {

            if (-not ($GreaterThanSuffix = ($FakeAttributes[$__FakeAttributes.DbComparisonSuffixAttributeName] | Select-Object -last 1).GreaterThan)) {
                $GreaterThanSuffix = 'GreaterThan'    
            }

            if (-not ($LessThanSuffix = ($FakeAttributes[$__FakeAttributes.DbComparisonSuffixAttributeName] | Select-Object -last 1).LessThan)) {
                $LessThanSuffix = 'LessThan'    
            }

            $GtAttributes = $FakeAttributes.Clone()
            $GtAttributes[$__FakeAttributes.DbColumnProperty][-1] | Add-Member -NotePropertyName ComparisonOperator -NotePropertyValue '>' -Force
#            $FakeAttributes[$__FakeAttributes.DbColumnProperty][-1] | Add-Member -NotePropertyName ComparisonOperator -NotePropertyValue '>' -Force
            @{
                ParamName = "${ParamName}${GreaterThanSuffix}"
                BaseParamName = $ParamName
                FakeAttributes = $GtAttributes
#                FakeAttributes = $FakeAttributes
            }

#            $FakeAttributes[$__FakeAttributes.DbColumnProperty][-1] | Add-Member -NotePropertyName ComparisonOperator -NotePropertyValue '<' -Force
#            $FakeAttributes = $FakeAttributes.Clone()
            $FakeAttributes[$__FakeAttributes.DbColumnProperty] = $FakeAttributes[$__FakeAttributes.DbColumnProperty].Clone()
            $FakeAttributes[$__FakeAttributes.DbColumnProperty][-1] = $FakeAttributes[$__FakeAttributes.DbColumnProperty][-1].psobject.Copy()
            $FakeAttributes[$__FakeAttributes.DbColumnProperty][-1].ComparisonOperator = '<'
            @{
                ParamName = "${ParamName}${LessThanSuffix}"
                BaseParamName = $ParamName
                FakeAttributes = $FakeAttributes
            }
        }
        else {
            @{
                ParamName = $ParamName
                BaseParamName = $ParamName
                FakeAttributes = $FakeAttributes
            }
        }

        foreach ($CurrentParamTable in $ParamHashTables) {
            $CurrentParamName = $CurrentParamTable.ParamName
            $FakeAttributes = $CurrentParamTable.FakeAttributes
            $BaseParamName = $CurrentParamTable.BaseParamName

            if ($ParamComments.ContainsKey($BaseParamName)) {
                $null = $ParamText.Append($ParamComments[$BaseParamName])
            }

            $ParamType = $ParamAst.StaticType.FullName -as [type]
            $ScalarType = if ($ParamType.GetElementType()) { $ParamType.GetElementType() } else { $ParamType }

            if ($FakeAttributes.ContainsKey($__FakeAttributes.DbColumnProperty)) {
                # For now, all DBColumnProperty parameters are arrays. This is a limitation of
                # how DbReaderInfo is being snuck in, and hopefully can be removed at some point
                if (-not $ParamType.IsArray) {
                    $ParamType = ('{0}[]' -f $ParamType.FullName) -as [type]
                }
            }

            $null = $ParamText.AppendLine('[{0}]' -f $ParamType.FullName)

            if ($FakeAttributes.ContainsKey($__FakeAttributes.DbColumnProperty)) {
                # Split the check b/c type constraint needs to come before the transformation for v3/4 attribute order bug

                # Put DB Reader info tranformation in
                $null = $ParamText.AppendLine("[ROE.TransformParameter({ AddDbReaderInfo -InputObject `$_ -OutputType $ParamType -CommandName $CommandName -ParameterName $CurrentParamName })]")
            }

            # Add argument transform for datetime objects
            if ($ScalarType -eq [datetime]) {
                $null = $ParamText.AppendLine('[ROE.TransformParameter({ DateTimeConverter -InputObject $_ })]')
            }

            $null = $ParamText.AppendLine('${0}' -f $CurrentParamName) #$ParamAst.Name.Extent.Text)

            if ($ParamAst.DefaultValue) {
                $null = $ParamText.AppendFormat(" = ")
                $null = $ParamText.AppendFormat("{0}", $ParamAst.DefaultValue.Extent.Text)
            }

            $ReturnHashtable.Parameters[$CurrentParamName] = [PSCustomObject] @{
                Name = $CurrentParamName
                Text = $ParamText.ToString()
                ScalarType = $ScalarType
                FakeAttributes = $FakeAttributes
            }

            # Only matters if there's more params to build
            $ParamText.Clear()
            $ParamText.Append($ParamTextAttributes)
        }
    }
    
    $ReturnHashtable
}

function GetInheritedClasses {
    param(
        [object[]] $ParentType,
        [switch] $ExcludeAbstract,
        [switch] $ExcludeParentClass,
        [switch] $SearchAllAssemblies
    )

    begin {
        if ($SearchAllAssemblies) {
            $AllAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
        }
    }

    process {
        if (-not $ExcludeParentClass) {
            $ParentType
        }

        foreach ($CurrentType in $ParentType) {
            $Assemblies = if ($SearchAllAssemblies) {
                $AllAssemblies   
            }
            else {
                [System.Reflection.Assembly]::GetAssembly($CurrentType)
            }

            foreach ($Assembly in $Assemblies) {
                $Assembly.GetTypes() | Where-Object {
                    $_.IsSubclassOf($CurrentType) -and -not ($ExcludeAbstract -and $_.IsAbstract)
                }
            }
        }
    }
}

function EvaluateAttributeArgumentValue {
<#
This module is definitely not protected from SQL or PS injection attacks. Hopefully this function
can slightly help with the PS injection component (but I won't vouch for it). The thinking behind
it is that attribute values (which are limited to string constants or scriptblocks) can be fed
into this, and if a scriptblock was the input, this can be used to make sure only acceptable code
is executed, e.g., you might want to let an attribute receive a variable, but you'd have to put it
in a scriptblock. If you blindly execute the scriptblock, a command designer could put arbitrary
code in there that runs something and returns a string. If you don't want to allow that, hopefully
the -LimitAstToType parameter can be used to only allow VariableExpressionAst objects to be executed

Obviously, this thing is pretty crappy right now. If everything that needs to evaluate an argument
value goes through here, though, improvements made to it will propagate everywhere
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,
        [type[]] 
        [ROE.TransformParameterAttribute({
            foreach ($PotentialType in $_) {
                if (-not ($PotentialType -as [type])) {
                    # Maybe simple name passed. Try to get the actual type:
                    $PotentialType = GetInheritedClasses -ParentType ([System.Management.Automation.Language.Ast]) | Where-Object Name -eq $PotentialType
                }
                $PotentialType
            }
        })]
        $LimitAstToType = [System.Management.Automation.Language.Ast],
        [int] $LimitNumberOfElements,
        [type] $OutputAs = [object],
        # Some attribute arguments should actually store a SB that's executed each time.
        # If the inputobject is a scriptblock, this will return the new (probably not)
        # sanitized scriptblock
        [switch] $DontEvaluateScriptBlocks
    )

    process {
#        Write-Warning 'Evaluate function still needs lots of work!'
        $UncoercedOutput = switch ($InputObject.GetType().Name) {
            string {
                $InputObject
            }

            scriptblock {
Write-Verbose 'Scriptblock processing...'
                $OriginalScriptBlockAst = $InputObject.Ast.Copy()
                $NewSbBuilder = New-Object System.Text.StringBuilder

                Write-Warning "Slow here because AST classes need to be cached"
                $ValidAstTypes = GetInheritedClasses -ParentType $LimitAstToType | Select-Object -Unique

                foreach ($CurrentBlock in Write-Output ParamBlock, BeginBlock, ProcessBlock, DynamicParamBlock, EndBlock) {
Write-Verbose "Looking at $CurrentBlock"
                    if ($OriginalScriptBlockAst.$CurrentBlock) {
                        if ($CurrentBlock -ne 'EndBlock') {
                            Write-Error "$CurrentBlock isn't supported for attribute scriptblocks! This block will be ignored"
                            continue
                        }

                        $CurrentBlockText = $OriginalScriptBlockAst.$CurrentBlock.Extent.Text
                        $GroupedElements = $OriginalScriptBlockAst.$CurrentBlock.FindAll({$args[0].GetType() -in $ValidAstTypes}, $false) | Group-Object { '{0}{1}' -f $_.Extent.StartLineNumber, $_.Extent.Text }

                        if ($LimitNumberOfElements) {
                            $GroupedElements = $GroupedElements | Select-Object -First $LimitNumberOfElements
                        }
<#                        
                        $Elements | Add-Member -MemberType ScriptProperty -Name Depth -Value { 
                            $i = 0
                            $current = $this
                            while ($current.Parent -isnot [System.Management.Automation.Language.NamedBlockAst] -and $i -lt 100) { 
                                $i++
                                $current = $current.Parent 
                            } 
                            $i 
                        }
#>

                            Where-Object { $_.Parent -is [System.Management.Automation.Language.NamedBlockAst] }
#                            where { $_.Parent.Extent.Text -eq $CurrentBlockText }
Write-Debug "Filtered elements"

                        foreach ($Group in $GroupedElements) {
                            $null = $NewSbBuilder.AppendLine($Group.Group[-1].Extent.Text)
                        }
                    }
                }

                $NewScriptBlock = [scriptblock]::Create($NewSbBuilder.ToString())

                if ($OriginalScriptBlock.Module) {
Write-Verbose 'Binding new scriptblock to the same module as the reference one'
                    $NewScriptBlock = $OriginalScriptBlock.Module.NewBoundScriptBlock($NewScriptBlock)
                }
                
                if ($DontEvaluateScriptBlocks) {
                    # Return ScripBlock object
                    $NewScriptBlock
                }
                else {
                    # Evaluate SB
                    & $NewScriptBlock
                }
            }

            default {
                Write-Error "Unknown type provided as input: $_"
                return
            }
        }

        $UncoercedOutput -as $OutputAs
    }
}

function ConvertToSimpleXml {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [scriptblock] $InputObject,
        # Optional parameter used for spacing
        [int] $TabWidth = 0
    )

    process {
        $ParseErrors = $null
        $AstRoot = [System.Management.Automation.Language.Parser]::ParseInput(
            $InputObject, 
            [ref] $null,
            [ref] $ParseErrors
        )

        if ($ParseErrors) {
            Write-Error "Parse errors encountered!"
            return $ParseErrors
        }

        $LinePrefix = "    " * $TabWidth

        # Looking for CommandAst instances (top level only)
        $AstRoot.FindAll(
            {$args[0] -is [System.Management.Automation.Language.CommandAst]},
            $false
        ) | ForEach-Object {
            # Should only have 2 CommandElements: The 'Command Name', which we'll use to build an opening
            # and closing tag, and the scriptblock that defines any child elements -or- values (valid values
            # are very limited, too). One day, we'll add attributes

            $Command = $_

            # Other limitations: No variable for the TagName (yet), and no attributes for elements (yet)
            if ($Command.CommandElements.Count -ne 2) {
                Write-Warning 'Tags should only have a constant name and a scriptblock. Extra information in XML is not currently supported.'
                return
            }

            if ($Command.CommandElements[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $TagName = $Command.CommandElements[0]
            }
            else {
                Write-Warning "Skipping: $Command"
                return
            }

            $LastElement = $Command.CommandElements[1]
            if ($LastElement -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    # A scriptblock! That means we have child elements, so write the opening tag, call function
                    # recursively, and write the closing tag.
                    "${LinePrefix}<${TagName}>"
#                    $ExpandedScriptBlockText = $ExecutionContext.InvokeCommand.ExpandString($LastElement.ScriptBlock.EndBlock)
                    & $PSCmdlet.MyInvocation.MyCommand ([scriptblock]::Create($LastElement.ScriptBlock.EndBlock)) -TabWidth ($TabWidth + 1)
                    "${LinePrefix}</${TagName}>"
            }
            else { 
                $ExpandedElements = $LastElement | GetValueFromAst -WarningAction Stop -ErrorAction Stop
                foreach ($Element in $ExpandedElements) {
                    "${LinePrefix}<${TagName}>${Element}</${TagName}>"
                }
            }
        }
    }
}

function New-TableFormatXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $MemberType,
        [string] $ViewName,
        [object[]] $TableInfo
    )

    function NewFormatTableInfo {
        param(
            [Parameter(ValueFromPipeline)]
            [Alias('Name')]
            [object] $Label,
            [scriptblock] $Expression,
            [int] $Width,
            [string] $Alignment = 'left'
        )

        process {
            foreach ($CurrentLabel in $Label) {
                if ($CurrentLabel -is [hashtable]) {
                    try {
                        (& $PSCmdlet.MyInvocation.MyCommand @CurrentLabel -ErrorAction Stop)
                    }
                    catch {
                        throw $_
                    }
                }
                else {
                    $HeaderSb = New-Object System.Text.StringBuilder
                    $RowEntrySb = New-Object System.Text.StringBuilder

                    $null = $HeaderSb.AppendLine("Label $CurrentLabel")
                    $null = $HeaderSb.AppendLine("Alignment $Alignment")
                    if ($PsBoundParameters.ContainsKey('Width')) {
                        $null = $HeaderSb.AppendLine("Width $Width")
                    }

                    if ($PsBoundParameters.ContainsKey('Expression')) {
                        $null = $RowEntrySb.AppendLine("ScriptBlock '$Expression'")
                    }
                    else {
                        $null = $RowEntrySb.AppendLine("PropertyName $CurrentLabel")
                    }
                    [PSCustomObject] @{
                        Header = $HeaderSb.ToString()
                        RowEntry = $RowEntrySb.ToString()
                    }

                    #$HeaderSb.Clear()
                    #$RowEntrySb.Clear()
                }
            }
        }
    }

    $FtInfoObjects = $TableInfo | NewFormatTableInfo

    
    $SB = [scriptblock]::Create(@"
& Configuration {
ViewDefinitions {
    View {
        Name $ViewName
        ViewSelectedBy {
            TypeName $($MemberType -join ", ")
        }
        TableControl {
            TableHeaders {
$(
            foreach ($CurrentFtInfo in $FtInfoObjects) {
@"
                TableColumnHeader {{
                    {0}
                }}

"@ -f $CurrentFtInfo.Header
            }
)    
            }
            TableRowEntries {
                TableRowEntry {
                    TableColumnItems {
$(
                    foreach ($CurrentFtInfo in $FtInfoObjects) {
@"
                        TableColumnItem {{
                            {0}
                        }}

"@ -f $CurrentFtInfo.RowEntry
                    }
)
                    }
                }
            }
        }
    }
}
}
"@)

    ConvertToSimpleXml $SB
}

#endregion

#region C# Code

# Transformation attribute that let's us do magic stuff with parameters before they're bound
# Right now, this is really bad. Had a lot of problems with array unrolling and custom
# attributes not being removed. Trial and error got me here. It's probably not good for
# generic transforms right now, so will need to work on that. Might even make a custom
# transform attribute.
Add-Type @'
using System.Collections;    // Needed for IList
using System.Management.Automation;
using System.Collections.Generic;

namespace ROE {
	public sealed class TransformParameterAttribute : ArgumentTransformationAttribute {

        public string TransformScript {
            get { return _transformScript; }
            set { _transformScript = value; }
        }

        string _transformScript;
		public TransformParameterAttribute(string transformScript) {
            _transformScript = string.Format(@"
# Assign $_ variable
$_ = $args[0]

# The return value of this needs to match the C# return type so no coercion happens
$FinalResult = New-Object System.Collections.ObjectModel.Collection[psobject]

$ScriptResult = {0}

# Add the result and emit the collection
$FinalResult.Add((,$ScriptResult))  # (Nest result in one element array so it can survive the trip back out to PS environment)
$FinalResult", transformScript);
        }

		public override object Transform(EngineIntrinsics engineIntrinsics, object inputData) {

            var results = engineIntrinsics.InvokeCommand.InvokeScript(
                _transformScript,
                true,   // Run in its own scope
                System.Management.Automation.Runspaces.PipelineResultTypes.None,  // Just return as PSObject collection
                null,
                inputData
            );

            if (results.Count > 0) { 
                return results[0].ImmediateBaseObject;
            }
//            return inputData;  // No transformation
            return null;
        }
	}
}
'@

#endregion

Export-ModuleMember DbReaderCommand