@{
    # Rules that do not fit an interactive, admin-only optimization toolkit:
    #   PSAvoidUsingWriteHost      - the scripts are console UIs; coloured output is the point.
    #   PSUseShouldProcessForStateChangingFunctions
    #                              - Undo-All-Changes.ps1 implements its own -WhatIf switch, and
    #                                Set-*Safe always writes a restorable backup record instead.
    #   PSAvoidGlobalVars          - Common-Functions.ps1 exists only to re-publish the module's
    #                                catalog under the old $Global:* names for backward compatibility.
    #   PSAvoidOverwritingBuiltInCmdlets
    #                              - Write-Log only collides with a PowerShell 6 Core built-in;
    #                                this toolkit targets Windows PowerShell 5.1.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidGlobalVars',
        'PSAvoidOverwritingBuiltInCmdlets'
    )
}
