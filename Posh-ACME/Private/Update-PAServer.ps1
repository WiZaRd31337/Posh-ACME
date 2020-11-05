function Update-PAServer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position=0,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateScript({Test-ValidDirUrl $_ -ThrowOnFail})]
        [Alias('location')]
        [string]$DirectoryUrl,
        [switch]$NonceOnly,
        [switch]$SkipCertificateCheck,
        [switch]$DisableTelemetry
    )

    Process {

        # grab the directory url from explicit parameters or the current memory copy
        if (-not $DirectoryUrl) {
            if (-not $script:Dir) {
                throw "No ACME server configured. Run Set-PAServer or specify a DirectoryUrl."
            }
            $DirectoryUrl = $script:Dir.location
            $UpdatingCurrent = $true
        } else {
            # even if they specified the directory url explicitly, we may still be updating the
            # "current" server. So figure that out and set a flag for later.
            if ($script:Dir -and $script:Dir.location -eq $DirectoryUrl) {
                $UpdatingCurrent = $true
            } else {
                $UpdatingCurrent = $false
            }
        }

        # determine the directory folder/file
        $dirFolder = ConvertTo-DirFolder $DirectoryUrl
        $dirFile = Join-Path $dirFolder 'dir.json'

        # Full refresh
        if (-not $NonceOnly -or -not (Test-Path $dirFile -PathType Leaf)) {

            # If the caller asked for a NonceOnly refresh but there's no existing dir.json,
            # we'll just do a full refresh with a warning.
            if ($NonceOnly) {
                Write-Warning "Performing full update instead of NonceOnly because existing server details missing."
            }

            # make the request
            Write-Debug "Updating directory info from $DirectoryUrl"
            try {
                $response = Invoke-WebRequest $DirectoryUrl -EA Stop -Verbose:$false @script:UseBasic
            } catch { throw }
            $dirObj = $response.Content | ConvertFrom-Json

            # process the response
            if ($dirObj -is [pscustomobject] -and 'newAccount' -in $dirObj.PSObject.Properties.name) {

                # create the directory folder if necessary
                if (-not (Test-Path $dirFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $dirFolder -Force -EA Stop | Out-Null
                }

                # add location, nonce, and type to the returned directory object
                $dirObj | Add-Member -NotePropertyMembers @{
                    location = $DirectoryUrl
                    nonce = $null
                    SkipCertificateCheck = $SkipCertificateCheck.IsPresent
                    DisableTelemetry = $DisableTelemetry.IsPresent
                }
                $dirObj.PSObject.TypeNames.Insert(0,'PoshACME.PAServer')

                # update the nonce value
                if ($response.Headers.ContainsKey($script:HEADER_NONCE)) {
                    $dirObj.nonce = $response.Headers[$script:HEADER_NONCE] | Select-Object -First 1
                } else {
                    $dirObj.nonce = Get-Nonce $dirObj.newNonce
                }

                # save to disk
                Write-Debug "Saving PAServer to disk"
                $dirObj | ConvertTo-Json | Out-File $dirFile -Force -EA Stop

                # overwrite the in-memory copy if we're actually updating the current one
                if ($UpdatingCurrent) { $script:Dir = $dirObj }

            } else {
                Write-Debug ($dirObj | ConvertTo-Json)
                throw "Unexpected ACME response querying directory. Check with -Debug."
            }

        # Nonce only refresh
        } else {

            # grab a reference to the object we'll be updating
            if ($UpdatingCurrent) {
                $dirObj = $script:Dir
            } else {
                $dirObj = Get-PAServer $DirectoryUrl
            }

            # update the nonce value
            $dirObj.nonce = Get-Nonce $dirObj.newNonce

            # save to disk
            Write-Debug "Saving PAServer to disk"
            $dirObj | ConvertTo-Json | Out-File $dirFile -Force -EA Stop

        }

    }

}
