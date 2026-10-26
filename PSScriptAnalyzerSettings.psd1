@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # twindesk.ps1 has its own --dry-run and confirmation model, identical to the
        # Bash version, instead of -WhatIf/-Confirm on internal helper functions.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
