@{
    # Workspace-local PSScriptAnalyzer settings.
    # If you re-enable script analysis, VS Code PowerShell extension will use this file.

    Severity = @('Error', 'Warning')

    # Keep the experience quiet for small scripts and tooling files.
    # Add/remove rules here as you prefer.
    ExcludeRules = @(
        # Commented out by default; keep here if you ever want to relax verb policing.
        # 'PSUseApprovedVerbs'
    )
}
