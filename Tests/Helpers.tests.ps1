. $PSScriptRoot\Helpers.ps1

Describe 'Helper functions' {
    It 'Test-DictionaryMatch' {
        $Dict1 = [ordered] @{
            Key = 'Value'
            1 = 1
            '@ParamName' = 2
        }
        $Dict2 = @{
            Key = 'Value'
            1 = 1
            '@ParamName' = 2
        } 
        
        $Dict1 | Test-DictionaryMatch $Dict2 | Should Be $true

        $Dict1['Key'] = 'Different Value'
        $Dict1 | Test-DictionaryMatch $Dict2 | Should Be $false

        $Dict2['Key'] = 'Different Value'
        $Dict2 | Test-DictionaryMatch $Dict1 | Should Be $true
    }

    It 'Test-QueryMatch' {
        $Query1 = "SELECT * FROM Table1     "
        $Query2 = "
        SELECT
            *
        FROM
            Table1
        "

        $Query3 = "SELECT * FROM Table2"

        $Query1 | Test-QueryMatch $Query2 | Should Be $true
        $Query1 | Test-QueryMatch $Query3 | Should Be $false
    }
}

