Describe 'Framework Health' {
    It 'Doesn''t pollute its parent module' {
        # Right now this test has no way of passing. The goal is going to be to minimize the
        # amount of module scope pollution, but it will never make it down to 0

        $AllowedVariables = @(
            'DBRInfo' 
        )
        $AllowedCommands = @(
            'DbReaderCommand' 
        )

        $Module = New-Module {
            $__VariablesBefore = Get-Variable -Scope Script
            $__CommandsBefore = Get-Command

            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            $__VariablesAfter = Get-Variable -Scope Script | Where-Object Name -notin '__VariablesBefore', '__CommandsBefore'
            $__CommandsAfter = Get-Command

            Export-ModuleMember -Variable *
        }

        $NewVariables = Compare-Object $__VariablesBefore $__VariablesAfter -Property Name | 
            Where-Object SideIndicator -eq '=>' | 
            Where-Object Name -notin $AllowedVariables |
            ForEach-Object { 'Variable: {0}' -f $_.Name }

        $NewCommands = Compare-Object $__CommandsBefore $__CommandsAfter -Property Name | 
            Where-Object SideIndicator -eq '=>' | 
            Where-Object Name -notin $AllowedCommands | 
            ForEach-Object { 'Command: {0}' -f $_.Name }

        (@($NewVariables) + $NewCommands) -join "`n" | Should BeNullOrEmpty
    } 
}