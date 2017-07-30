## Database Reporter Framework Help System

Help for DbReaderCommand instances can be defined in two ways:
* [Comment Based Help](#commentbasedhelp)
* [Custom DatabaseReporter Attribute](#attribute)

<a name="commentbasedhelp"></a>
## Comment Based Help
Comment based help goes just inside the command definition and before the param() block definition:
  
```
DbReaderCommand TestCommand {
    <#
    .SYNOPSIS
        This will override the default .SYNOPSIS that is defined inside the DatabaseReporter.ps1 
        file's reference command. Any sections missing here that are defined in the reference
        command will still be present on the final 'TestCommand' that's being defined.
    

    .EXAMPLE
        Defining this example means that all examples from the DatabaseReporter.ps1 file's
        reference command are ignored.
    #>
    [MagicDbInfo(FromClause = 'TableName')]
    param(
        [MagicDbProp()]
        # Help for the -Column1 parameter goes here
        [string] $Column1
    )
}
```

Note that this is the same behavior as built-in comment based help in PowerShell. This is generally the recommended way to add help to your commands. 

<a name="attribute"></a>
## With a DatabaseReporter Attribute
A [[MagicPsHelp](MagicPsHelpAttribute.md)()] attribute placed before the param() block can also be used to define help for commands.

You normally wouldn't need to define help this way. The main reason to use it is if you have dynamic content that's needed at runtime (runtime here means the time that the module is imported, not when the command or help system is invoked). Here's an example:
```
DbReaderCommand TestCommand {
    [MagicPsHelp(
        Synopsis = 'Extra synopsis',
        UpdateMode = 'Merge',
        # This part is kind of important...notice that instead of using 'Example', we use 'Examples' and provide it a scriptblock for array
        Examples = { echo "Other Example 1", "Process id: $pid", "Notice how the previous example has dynamic content"},
        # Same as examples...when doing this, we need 'Parameters' (plural). Perhaps one day can expand this to allow single instances
        Parameters = {
            # This is SUPER clunky b/c I can only include strings or scriptblocks here...
            # Remember that you should be able to just do comment based help for parameters, so this method should be discouraged
            @{
                Column1 = 'This help for Column1 came from the dynamic command definition'
                NonExistentParam = "This param doesn't exist"
            }
        }
    )]
    [MagicPsHelp(  # Since UpdateMode isn't used here, it defaults to 'Overwrite'
        Description = 'Description goes here',
        Notes = 'Notes go here'
    )]
    [MagicDbInfo(FromClause = 'TableName')]
    param(
        [MagicDbProp()]
        [string] $Column1
    )
}
```