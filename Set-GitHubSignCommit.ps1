function Set-GitHubSignLatestCommit {
    param (
        [Parameter(Mandatory = $true)][string]$RepositoryName,
        [Parameter(Mandatory = $true)][string]$BranchName,
        [Parameter(Mandatory = $true)][PSCustomObject]$GitHubTokenInstance,
        [Parameter()][string]$OwnerName = "DivyaGhai"
    )

    $headers = @{
        Authorization = "Bearer $($GitHubTokenInstance.token)"
        Accept        = "application/vnd.github+json"
        "User-Agent"  = "PowerShell-GitHubClient"
    }

    $branchUrl = "https://api.github.com/repos/$OwnerName/$RepositoryName/branches/$BranchName"
    $branch = Invoke-RestMethod -Uri $branchUrl -Headers $headers

    $commitSha = $branch.commit.sha
    $commitData = Invoke-RestMethod -Uri $branch.commit.url -Headers $headers

    $commitTree = $commitData.commit.tree.sha
    $parentSha = $commitData.parents[0].sha
    $author = $commitData.commit.author
    $committer = $commitData.commit.committer

    $commitTextLines = @(
        "tree $commitTree",
        "parent $parentSha",
        "author $($author.name) <$($author.email)> $(Get-Date $author.date -UFormat %s) -0000",
        "committer $($committer.name) <$($committer.email)> $(Get-Date $committer.date -UFormat %s) -0000",
        "",
        "$($commitData.commit.message)"
    )

    $commitText = ($commitTextLines -join "`n") + "`n"

    $tempPath = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tempPath, $commitText)
    $signature = & gpg --armor --sign --default-key $author.email --detach-sign --output - $tempPath
    Remove-Item $tempPath

    $signedCommit = @{
        message    = $commitData.commit.message
        tree       = $commitTree
        parents    = @($parentSha)
        author     = $author
        committer  = $committer
        signature  = ($signature -join "`n") + "`n"
    }

    $createUrl = "https://api.github.com/repos/$OwnerName/$RepositoryName/git/commits"
    $newCommit = Invoke-RestMethod -Uri $createUrl -Method POST -Headers $headers `
        -Body ($signedCommit | ConvertTo-Json -Depth 10 -Compress) `
        -ContentType "application/json"

    # Now move the branch to point to new commit
    $updateRefUrl = "https://api.github.com/repos/$OwnerName/$RepositoryName/git/refs/heads/$BranchName"
    $updatePayload = @{ sha = $newCommit.sha; force = $true } | ConvertTo-Json
   $response = Invoke-RestMethod -Uri $updateRefUrl -Method POST -Headers $headers -Body $updatePayload -ContentType "application/json"

   
$response | ConvertTo-Json -Depth 12 | Write-Host
# Just the “Verified” badge info
$verified   = $response.data.createCommitOnBranch.commit.verification.verified
$reason     = $response.data.createCommitOnBranch.commit.verification.reason
$commitUrl  = $response.data.createCommitOnBranch.commit.url
$commitSha  = $response.data.createCommitOnBranch.commit.oid

Write-Host "Commit: $commitSha"
Write-Host "URL   : $commitUrl"
Write-Host "Signed: $verified  ($reason)"
    Write-Host "✅ Signed and updated branch to commit: $($newCommit.sha)"
 Write-Host "✅ response here: $($response)"
}
