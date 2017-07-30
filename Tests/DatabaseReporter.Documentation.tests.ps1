Describe "Documentation tests" {

    $MdFiles = Get-ChildItem $PSScriptRoot\..\docs *.md
    $ValidLinks = $MdFiles | ForEach-Object {
        $CurrentFile = $_.Name
        Write-Output $CurrentFile 

        # This regex isn't very flexible...that's fine, adding a bookmark doesn't
        # require many bells and whistles right now, and if it ever does, we can 
        # extend this then
        Select-String -InputObject $_ -Pattern '\<a name=(\''|\")(?<bookmark>[^\>]+)(\''|\")\s*\\?\>' | Select-Object -ExpandProperty Matches | ForEach-Object {
            Write-Output ('{0}#{1}' -f $CurrentFile, $_.Groups['bookmark'].Value)
        }
    }

    $ActiveLinks = $MdFiles | ForEach-Object {
        $CurrentFile = $_.Name
        Select-String -InputObject $_ -Pattern '\[(?<text>[^\[]+)\]\((?<link>[^\)\#]*)(?<bookmark>\#[^\)]+)?\)' | Select-Object -ExpandProperty Matches | ForEach-Object {
            # $Text = $_.Groups['text'].Value 
            $Link = $_.Groups['link'].Value
            $Bookmark = $_.Groups['bookmark'].Value

            if (-not $Link) { $Link = $CurrentFile }

            '{0}{1}' -f $Link, $Bookmark
        }
    }

    It 'All <attributename> properties are documented' {

    } 
    It 'All markdown files have at least one link' {
        Compare-Object $ActiveLinks $ValidLinks | Where-Object SideIndicator -eq '=>' | Where-Object InputObject -ne 'index.md' | Select-Object -ExpandProperty InputObject | Should BeNullOrEmpty
    }

    It 'All relative links are valid' {
        Compare-Object $ActiveLinks $ValidLinks | Where-Object SideIndicator -eq '<=' | Select-Object -ExpandProperty InputObject | Should BeNullOrEmpty
    }
}