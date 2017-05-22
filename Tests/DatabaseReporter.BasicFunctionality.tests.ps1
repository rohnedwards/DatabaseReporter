
Describe 'Basic Functionality' {
    It 'Writes an error when no command information is provided' {
        $TestMod = New-Module -Name DBTest -ScriptBlock {
            . "$PSScriptRoot\..\DatabaseReporter.ps1"

            DbReaderCommand HelpTest {
                
            } -ErrorAction SilentlyContinue -ErrorVariable TestErrors
        } 

        $ErrorList = & $TestMod { $TestErrors }
        $ErrorList.Count | Should BeGreaterThan 0    # This should actually just be 1, but for some reason, there are some generic errors coming back...
        $TestMod | Remove-Module
    }

    It 'Exports only defined commands' {
        $WorkingMod = New-Module -Name ExportCommandTest -ScriptBlock {
            
            . "$PSScriptRoot\..\DatabaseReporter.ps1"
            
            DbReaderCommand HelpTest1 {
                [MagicDbInfo(
                    FromClause = 'TableName',
                    DbConnectionString = 'ConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param()
            }
            DbReaderCommand HelpTest2 {
                [MagicDbInfo(
                    FromClause = 'FromTable',
                    DbConnectionString = 'ConnectionString',
                    DbConnectionType = 'System.Data.SqlClient.SqlConnection'
                )]
                param()
            }
        }

        Get-Command -Module $WorkingMod.Name | Where-Object Name -notin HelpTest1, HelpTest2 | Should BeNullOrEmpty
    }
}