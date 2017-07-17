. "$PSScriptRoot\Helpers.ps1"

Describe 'DB Reporter DBConnection handling' {
    It 'AsDbConnectionType works with <description>' {
        param(
            [object] $InputType
        )

        $Module = New-Module -Name AsDbConnectionTest {
            . "$PSScriptRoot\..\DatabaseReporter.ps1"
        } 

        & $Module { $args[0] | AsDbConnectionType } $InputType | Should Not BeNullOrEmpty
    } -TestCases @{
        Description = 'SqlConnection'
        InputType = 'SqlConnection' 
    }, @{
        Description = 'System.Data.SqlClient.SqlConnection'
        InputType = 'System.Data.SqlClient.SqlConnection'
    }, @{
        Description = '[System.Data.SqlClient.SqlConnection]'
        InputType = [System.Data.SqlClient.SqlConnection]
    }, @{
        Description = 'OdbcConnection'
        InputType = 'OdbcConnection'
    }

    It 'DbConnection at [MagicDbInfo()] level takes precedence over other 2 methods' {

    }

    It 'DbConnectionString and Type at [MagicDbInfo()] level takes precedence over module setting' {
        
    }

    It 'Module leve DbConnection works' {
        
    }
}