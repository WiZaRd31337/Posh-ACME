function Export-PAAccountKey {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position=0)]
        [ValidateScript({Test-ValidFriendlyName $_ -ThrowOnFail})]
        [Alias('Name')]
        [string]$ID,
        [Parameter(Mandatory)]
        [string]$OutputFile,
        [switch]$Force
    )

    Begin {
        # make sure we have a server configured
        if (-not (Get-PAServer)) {
            try { throw "No ACME server configured. Run Set-PAServer first." }
            catch { $PSCmdlet.ThrowTerminatingError($_) }
        }

        if ($Force) {
            $ConfirmPreference = 'None'
        }
    }

    Process {
        trap { $PSCmdlet.ThrowTerminatingError($PSItem) }

        # throw an error if there's no current account and no ID passed in
        if (-not $ID -and -not ($acct = Get-PAAccount)) {
            throw "No ACME account configured. Run New-PAAccount or specify an account ID."
        }

        # make sure the ID is valid if specified
        if ($ID -and -not ($acct = Get-PAAccount -ID $ID)) {
            throw "Invalid account ID: $ID"
        }

        # check if the output file exists
        $fileExists = Test-Path $OutputFile -PathType Leaf

        # confirm overwrite unless -Force was specified
        if ($fileExists -and -not $Force -and
            -not $PSCmdlet.ShouldContinue("Overwrite?","File already exists: $OutputFile"))
        {
            Write-Verbose "Export account key aborted."
            return
        }

        Write-Verbose "Exporting account $($acct.id) ($($acct.KeyLength)) to $OutputFile"

        # convert the JWK to a BC keypair
        $keypair = $acct.key | ConvertFrom-Jwk -AsBC

        # export it
        Export-Pem $keypair $OutputFile

    }


    <#
    .SYNOPSIS
        Export an ACME account private key.

    .DESCRIPTION
        The account key is saved as an unencrypted Base64 encoded PEM file.

    .PARAMETER ID
        The ACME account ID value.

    .PARAMETER OutputFile
        The path to the file to write the key data to.

    .PARAMETER Force
        If specified and the output file already exists, it will be overwritten. Without the switch, a confirmation prompt will be presented.

    .EXAMPLE
        Export-PAAccountKey -OutputFile .\mykey.pem

        Exports the current ACME account's key to the specified file.

    .EXAMPLE
        Export-PAAccountKey 12345 -OutputFile .\mykey.pem -Force

        Exports the specified ACME account's key to the specified file and overwrites it if necessary.

    .EXAMPLE
        $fldr = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AcmeAccountKeys'
        PS C:\>New-Item -ItemType Directory -Force -Path $fldr | Out-Null
        PS C:\>Get-PAAccount -List | %{
        PS C:\>    Export-PAAccountKey $_.ID -OutputFile "$fldr\$($_.ID).key" -Force
        PS C:\>}

        Backup all account keys for this ACME server to a folder on the desktop.

    .LINK
        Project: https://github.com/rmbolger/Posh-ACME

    .LINK
        Get-PAAccount

    #>
}
